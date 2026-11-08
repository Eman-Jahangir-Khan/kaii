import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../auth_repository.dart';
import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'requests_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String _myUid = authRepo.currentUser!.uid;
  final _searchCtrl = TextEditingController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _ready = false;
  bool _failed = false;
  String _query = '';
  int _seq = 0;
  int _pendingCount = 0;

  // ---- PIN: selection state ----
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _sub = chatRepo.chatsStream().listen(
      _onSnapshot,
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _failed = true;
          _ready = true;
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _otherUidOf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final participants = List<String>.from(d.data()['participants'] as List);
    return participants.firstWhere((u) => u != _myUid, orElse: () => _myUid);
  }

  // ---- PIN: helpers ----
  bool _isPinned(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final p = d.data()['pinnedBy'];
    return p is List && p.contains(_myUid);
  }

  /// Maine ye chat delete ki ho aur uske baad koi naya message na aaya ho
  bool _isDeletedForMe(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final del = m['deletedAt'];
    if (del is! Map || !del.containsKey(_myUid)) return false;
    final cut = del[_myUid] as Timestamp?;
    if (cut == null) return true; // delete abhi likha ja raha hai
    final last = m['lastMessageAt'] as Timestamp?;
    if (last == null) return false; // naya message abhi likha ja raha hai
    return last.compareTo(cut) <= 0;
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _togglePin() async {
    final messenger = ScaffoldMessenger.of(context);
    final chosen = _docs.where((d) => _selected.contains(d.id)).toList();
    final unpin = chosen.every(_isPinned);

    if (!unpin) {
      final already = _docs.where(_isPinned).length;
      final fresh = chosen.where((d) => !_isPinned(d)).length;
      if (already + fresh > 3) {
        messenger.showSnackBar(
          const SnackBar(content: Text('You can pin up to 3 chats')),
        );
        return;
      }
    }

    setState(_selected.clear);
    try {
      await Future.wait(
        chosen.map((d) => chatRepo.setPinned(d.id, !unpin)),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update pin. Try again.')),
      );
    }
  }

  // ---- DELETE: selected chats delete karo (confirmation ke baad) ----
  Future<void> _deleteSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final ids = _selected.toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: softCardColor,
        title: Text(
          ids.length == 1 ? 'Delete chat?' : 'Delete ${ids.length} chats?',
          style: const TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'This chat will be removed from your list and its messages deleted for you only. The other person will still keep their copy.',
          style: TextStyle(color: AppColors.brown700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(_selected.clear);
    try {
      await Future.wait(ids.map(chatRepo.deleteChatForMe));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete chat. Try again.')),
      );
    }
  }

  /// Search ke liye samne walon ke naam pehle se load kar lo (cache mein)
  Future<void> _prefetchUsers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final uids = docs
        .map(_otherUidOf)
        .toSet()
        .where((u) => chatRepo.cachedUser(u) == null);
    await Future.wait(
      uids.map((u) => chatRepo.getUser(u).then((_) {}, onError: (_) {})),
    );
  }

  Future<void> _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    final id = ++_seq;
    // Sirf accepted chats list mein; incoming pending requests ki ginti alag
    final docs = snap.docs.where((d) {
      final s = d.data()['status'] as String?;
      return (s == null || s == 'accepted') && !_isDeletedForMe(d);
    }).toList();
    final pending = snap.docs.where((d) {
      final m = d.data();
      return m['status'] == 'pending' && m['requestedBy'] != _myUid;
    }).length;

    if (!_ready) {
      // pehli baar: naam load hone tak ruko taake list ek saath aaye
      await _prefetchUsers(docs);
    } else {
      // baad mein: list foran dikhao, naye users background mein load hon
      _prefetchUsers(docs).then((_) {
        if (mounted) setState(() {});
      });
    }

    if (!mounted || id != _seq) return;
    setState(() {
      _docs = docs;
      _pendingCount = pending;
      _ready = true;
      _failed = false;
    });
  }

  /// Username ya naam mein search wala text ho to chat dikhao
  /// Pinned chats hamesha upar
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visible {
    final list = _query.isEmpty
        ? _docs
        : _docs.where((d) {
      final u = chatRepo.cachedUser(_otherUidOf(d));
      final username = ((u?['username'] as String?) ?? '').toLowerCase();
      final name = ((u?['name'] as String?) ?? '').toLowerCase();
      return username.contains(_query) || name.contains(_query);
    }).toList();
    return [
      ...list.where(_isPinned),
      ...list.where((d) => !_isPinned(d)),
    ];
  }

  bool _isMarkedUnread(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()['markedUnread'];
    return m is List && m.contains(_myUid);
  }

  Future<void> _toggleMarkUnread() async {
    final messenger = ScaffoldMessenger.of(context);
    final chosen = _docs.where((d) => _selected.contains(d.id)).toList();
    final mark = !chosen.every(_isMarkedUnread);

    setState(_selected.clear);
    try {
      await Future.wait(
        chosen.map((d) => chatRepo.setMarkedUnread(d.id, mark)),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update chat. Try again.')),
      );
    }
  }

  bool _isBlockedByMe(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final b = d.data()['blockedBy'];
    return b is List && b.contains(_myUid);
  }

  Future<void> _toggleBlock() async {
    final messenger = ScaffoldMessenger.of(context);
    final chosen = _docs.where((d) => _selected.contains(d.id)).toList();
    final count = chosen.length;
    final block = !chosen.every(_isBlockedByMe);

    if (block) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: softCardColor,
          title: Text(
            count == 1 ? 'Block user?' : 'Block $count users?',
            style: const TextStyle(
              color: AppColors.brown900,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Blocked users cannot message you, and you cannot message them until you unblock.',
            style: TextStyle(color: AppColors.brown700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(_selected.clear);
    try {
      await Future.wait(
        chosen.map((d) => chatRepo.setBlocked(d.id, block)),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            block
                ? (count == 1 ? 'User blocked' : '$count users blocked')
                : (count == 1 ? 'User unblocked' : '$count users unblocked'),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update block. Try again.')),
      );
    }
  }

  Widget _searchBar() {
    return Container(
      decoration: BoxDecoration(
        color: softCardColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.brown900.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        cursorColor: AppColors.gold700,
        style: const TextStyle(
          color: AppColors.brown900,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Search chats',
          hintStyle: TextStyle(
            color: AppColors.brown700.withValues(alpha: 0.7),
          ),
          prefixIcon: const Icon(Icons.search, color: AppColors.gold700),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
            icon: const Icon(Icons.close, color: AppColors.brown700),
            onPressed: () {
              _searchCtrl.clear();
              setState(() => _query = '');
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _body() {
    if (_failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load chats',
        subtitle:
        'Check your internet. If it keeps happening, create the Firestore index from the link in the debug console.',
      );
    }
    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold700),
      );
    }
    if (_docs.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No chats yet',
        subtitle: 'Tap the button below to find someone and say hi.',
      );
    }
    final docs = _visible;
    if (docs.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No chats found',
        subtitle: 'No chat matches "$_query".',
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final d = docs[i];
        return _ChatTile(
          key: ValueKey(d.id),
          data: d.data(),
          myUid: _myUid,
          pinned: _isPinned(d),
          selected: _selected.contains(d.id),
          onLongPress: () => _toggleSelect(d.id),
          onTap: _selecting ? () => _toggleSelect(d.id) : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        floatingActionButton: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.gold500, AppColors.gold700],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold700.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewChatScreen()),
              ),
              child: const Icon(
                Icons.add_comment_outlined,
                color: AppColors.cream,
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            GradientHeader(
              title: _selecting ? '${_selected.length} selected' : 'Kaii',
              titleStyle: _selecting
                  ? const TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              )
                  : const TextStyle(
                color: Colors.black,
                fontFamily: 'PlaywriteITTrad',
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
              actions: _selecting
                  ? [
                IconButton(
                  tooltip: 'Pin',
                  icon: Icon(
                    _docs
                        .where((d) => _selected.contains(d.id))
                        .every(_isPinned)
                        ? Icons.push_pin_outlined
                        : Icons.push_pin,
                    color: Colors.black,
                  ),
                  onPressed: _togglePin,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.black),
                  onPressed: _deleteSelected,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.black),
                  color: softCardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (v) {
                    if (v == 'unread') {
                      _toggleMarkUnread();
                    } else if (v == 'block') {
                      _toggleBlock();
                    }
                  },
                  itemBuilder: (_) {
                    final allMarked = _docs
                        .where((d) => _selected.contains(d.id))
                        .every(_isMarkedUnread);
                    final allBlocked = _docs
                        .where((d) => _selected.contains(d.id))
                        .every(_isBlockedByMe);
                    return [
                      PopupMenuItem(
                        value: 'unread',
                        child: Row(
                          children: [
                            Icon(
                              allMarked
                                  ? Icons.mark_chat_read_outlined
                                  : Icons.mark_chat_unread_outlined,
                              color: AppColors.gold700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              allMarked
                                  ? 'Mark as read'
                                  : 'Mark as unread',
                              style: const TextStyle(
                                color: AppColors.brown900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(
                              allBlocked
                                  ? Icons.check_circle_outline
                                  : Icons.block,
                              color: AppColors.gold700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              allBlocked ? 'Unblock user' : 'Block user',
                              style: const TextStyle(
                                color: AppColors.brown900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              ]
                  : [
                PopupMenuButton<String>(
                  icon: Badge(
                    isLabelVisible: _pendingCount > 0,
                    label: Text(
                        _pendingCount > 99 ? '99+' : '$_pendingCount'),
                    backgroundColor: AppColors.brown900,
                    textColor: AppColors.cream,
                    child:
                    const Icon(Icons.more_vert, color: Colors.black),
                  ),
                  color: softCardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onSelected: (v) {
                    if (v == 'requests') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RequestsScreen()),
                      );
                    } else if (v == 'logout') {
                      authRepo.logout();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'requests',
                      child: Row(
                        children: [
                          const Icon(Icons.mark_email_unread_outlined,
                              color: AppColors.gold700),
                          const SizedBox(width: 12),
                          const Text(
                            'Message requests',
                            style: TextStyle(
                              color: AppColors.brown900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_pendingCount > 0) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.gold700,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _pendingCount > 99
                                    ? '99+'
                                    : '$_pendingCount',
                                style: const TextStyle(
                                  color: AppColors.cream,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: AppColors.gold700),
                          SizedBox(width: 12),
                          Text(
                            'Log out',
                            style: TextStyle(
                              color: AppColors.brown900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _searchBar(),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final String myUid;
  final bool pinned;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ChatTile({
    super.key,
    required this.data,
    required this.myUid,
    this.pinned = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends State<_ChatTile> {
  late final String _otherUid;
  late final Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    final participants = List<String>.from(widget.data['participants'] as List);
    _otherUid = participants.firstWhere(
          (u) => u != widget.myUid,
      orElse: () => widget.myUid,
    );
    _future = chatRepo.getUser(_otherUid);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final lastMessage = (data['lastMessage'] as String?) ?? '';
    final mine = data['lastSenderId'] == widget.myUid;
    final time = (data['lastMessageAt'] as Timestamp?)?.toDate();
    final unreadMap = (data['unread'] as Map?) ?? const {};
    final unread = (unreadMap[widget.myUid] as num?)?.toInt() ?? 0;

    final marked = data['markedUnread'] is List &&
        (data['markedUnread'] as List).contains(widget.myUid);
    final isUnread = unread > 0 || marked;
    final blocked = data['blockedBy'] is List &&
        (data['blockedBy'] as List).contains(widget.myUid);

    final clearedMap = data['clearedAt'];
    var isCleared = false;
    if (clearedMap is Map && clearedMap.containsKey(widget.myUid)) {
      final cut = clearedMap[widget.myUid] as Timestamp?;
      final last = data['lastMessageAt'] as Timestamp?;
      isCleared = cut == null || (last != null && last.compareTo(cut) <= 0);
    }
    var previewText = lastMessage;
    var previewMine = mine;
    final myPrevMap = data['myPreview'];
    if (myPrevMap is Map) {
      final p = myPrevMap[widget.myUid];
      if (p is Map && p['base'] == data['lastMessageAt']) {
        previewText = (p['text'] as String?) ?? '';
        previewMine = p['senderId'] == widget.myUid;
      }
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      initialData: chatRepo.cachedUser(_otherUid),
      builder: (context, snap) {
        final user = snap.data;
        final username = (user?['username'] as String?) ??
            (snap.connectionState == ConnectionState.done
                ? 'Unknown user'
                : '...');
        final photo = (user?['photoUrl'] as String?) ?? '';

        return Container(
          decoration: BoxDecoration(
            color: widget.selected ? AppColors.gold200 : softCardColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.brown900.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onLongPress: widget.onLongPress,
              onTap: widget.onTap ??
                      () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        otherUid: _otherUid,
                        username: username,
                        photoUrl: photo,
                      ),
                    ),
                  ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    UserAvatar(username: username, photoUrl: photo, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brown900,
                                  ),
                                ),
                              ),
                              if (blocked)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.brown900
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.block,
                                          size: 12,
                                          color: AppColors.brown700),
                                      SizedBox(width: 3),
                                      Text(
                                        'Blocked',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.brown700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isCleared || previewText.isEmpty
                                ? ''
                                : (previewMine
                                ? 'You: $previewText'
                                : previewText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.brown700,
                              fontWeight:
                              isUnread ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(time),
                          style: TextStyle(
                            fontSize: 12,
                            color: isUnread
                                ? AppColors.gold700
                                : AppColors.brown700,
                            fontWeight:
                            isUnread ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.pinned)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.push_pin,
                                  size: 16,
                                  color: AppColors.brown700,
                                ),
                              ),
                            if (unread > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold700,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  unread > 99 ? '99+' : '$unread',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.cream,
                                  ),
                                ),
                              )
                            else if (marked)
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: AppColors.gold700,
                                  shape: BoxShape.circle,
                                ),
                              )
                            else if (!widget.pinned)
                                const SizedBox(height: 20),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _formatTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  if (diff == 0) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
  }
  if (diff == 1) return 'Yesterday';
  return '${two(t.day)}/${two(t.month)}/${two(t.year % 100)}';
}
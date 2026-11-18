import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'group_info_screen.dart';
import '../chat_repository.dart';
import '../group_repository.dart';
import '../message_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';

/// MainShell ko batata hai ke Groups mein selection chal rahi hai (back dabane par Home par na jaye)
final ValueNotifier<bool> groupsSelecting = ValueNotifier<bool>(false);

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  // last message bhejne walon ke live user docs
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _userSubs = {};
  final Map<String, Map<String, dynamic>> _liveUsers = {};
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loaded = false;
  bool _failed = false;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    chatRepo.contactNames.addListener(_onNames);
    _sub = groupRepo.groupsStream().listen(
          (snap) {
        if (!mounted) return;
        setState(() {
          _docs = snap.docs;
          _loaded = true;
          _failed = false;
        });
        _watchSenders(snap.docs);
      },
      onError: (e) {
        debugPrint('GROUPS STREAM ERROR: $e'); // index ka link yahin milega
        if (!mounted) return;
        setState(() {
          _failed = true;
          _loaded = true;
        });
      },
    );
  }

  @override
  void dispose() {
    chatRepo.contactNames.removeListener(_onNames);
    for (final sub in _userSubs.values) {
      sub.cancel();
    }
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
    groupsSelecting.value = false;
  }

  void _onNames() {
    if (mounted) setState(() {});
  }

  void _watchSenders(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    for (final d in docs) {
      final g = d.data();
      final ids = <String>{(g['lastSenderId'] as String?) ?? ''};
      final mp = g['myPreview'];
      final mine = mp is Map ? mp[_myUid] : null;
      if (mine is Map) ids.add((mine['senderId'] as String?) ?? '');
      for (final u in ids) {
        if (u.isEmpty || u == _myUid || _userSubs.containsKey(u)) continue;
        _userSubs[u] = chatRepo.userStream(u).listen((s) {
          final data = s.data();
          if (!mounted || data == null) return;
          setState(() => _liveUsers[u] = data);
        }, onError: (_) {});
      }
    }
  }

  /// Mera save kiya naam > nickname > username > (group doc mein likha purana naam)
  String _nameOf(String uid, {String fallback = ''}) => chatRepo.displayName(
    uid,
    _liveUsers[uid] ?? chatRepo.cachedUser(uid),
    fallback: fallback,
  );

  void _create() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
  }

  bool _isMember(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      List<String>.from(d.data()['members'] ?? const []).contains(_myUid);

  bool _isPinned(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final p = d.data()['pinnedBy'];
    return p is List && p.contains(_myUid);
  }

  bool _isMarkedUnread(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()['markedUnread'];
    return m is List && m.contains(_myUid);
  }

  /// Maine ye group delete kiya ho (member hoon to naya message aane par wapis aa jata hai,
  /// chhodne wale ke liye wapis nahi aata)
  bool _isDeletedForMe(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final del = data['deletedAt'];
    if (del is! Map || !del.containsKey(_myUid)) return false;
    if (!_isMember(d)) return true;
    final cut = del[_myUid] as Timestamp?;
    if (cut == null) return true;
    final last = data['lastMessageAt'] as Timestamp?;
    if (last == null) return false;
    return last.compareTo(cut) <= 0;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _chosen =>
      _docs.where((d) => _selected.contains(d.id)).toList();

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
    groupsSelecting.value = _selected.isNotEmpty;
  }

  void _clearSelection() {
    setState(_selected.clear);
    // MainShell ka back-handler isi frame mein chalta hai, isliye flag baad mein girao
    WidgetsBinding.instance
        .addPostFrameCallback((_) => groupsSelecting.value = false);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: softCardColor,
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(body, style: const TextStyle(color: AppColors.brown700)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _togglePin() async {
    final chosen = _chosen;
    final unpin = chosen.every(_isPinned);
    if (!unpin) {
      final already =
          _docs.where((d) => !_isDeletedForMe(d) && _isPinned(d)).length;
      final fresh = chosen.where((d) => !_isPinned(d)).length;
      if (already + fresh > 3) {
        _snack('You can pin up to 3 groups');
        return;
      }
    }
    _clearSelection();
    try {
      await Future.wait(chosen.map((d) => groupRepo.setPinned(d.id, !unpin)));
    } catch (_) {
      _snack('Could not update pin. Try again.');
    }
  }

  Future<void> _toggleMarkUnread() async {
    final chosen = _chosen;
    final mark = !chosen.every(_isMarkedUnread);
    _clearSelection();
    try {
      await Future.wait(
        chosen.map((d) => groupRepo.setMarkedUnread(d.id, mark)),
      );
    } catch (_) {
      _snack('Could not update group. Try again.');
    }
  }

  Future<void> _deleteSelected() async {
    final chosen = _chosen;
    if (chosen.any(_isMember)) {
      _snack('Leave the group first, then you can delete it');
      return;
    }
    final ok = await _confirm(
      title: chosen.length == 1 ? 'Delete group?' : 'Delete ${chosen.length} groups?',
      body: 'The group will be removed from your list and its messages deleted for you.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    _clearSelection();
    try {
      await Future.wait(chosen.map((d) => groupRepo.deleteGroupForMe(d.id)));
    } catch (_) {
      _snack('Could not delete group. Try again.');
    }
  }

  Future<void> _leaveSelected() async {
    final groups = _chosen.where(_isMember).toList();
    if (groups.isEmpty) {
      _snack('You have already left');
      return;
    }
    final ok = await _confirm(
      title: groups.length == 1 ? 'Leave group?' : 'Leave ${groups.length} groups?',
      body: "You won't receive new messages. The old chat stays in your list until you delete it.",
      action: 'Leave',
    );
    if (!ok || !mounted) return;
    _clearSelection();
    try {
      await Future.wait(groups.map((d) => groupRepo.leaveGroup(d.id)));
    } catch (_) {
      _snack('Could not leave the group. Try again.');
    }
  }

  Timestamp? _leftTime(Map<String, dynamic> g) {
    final m = g['leftAt'];
    final t = m is Map ? m[_myUid] : null;
    return t is Timestamp ? t : null;
  }

  String _preview(Map<String, dynamic> g, bool isMember) {
    if (!isMember) {
      final by = g['leftBy'];
      final who = by is Map ? ((by[_myUid] as String?) ?? '') : '';
      return who.isEmpty ? 'You left' : 'You were removed by $who';
    }
    // delete for me ke baad meri apni preview (jab tak koi naya message na aaye)
    final mp = g['myPreview'];
    if (mp is Map) {
      final p = mp[_myUid];
      if (p is Map && p['base'] == g['lastMessageAt']) {
        final text = (p['text'] as String?) ?? '';
        final sid = (p['senderId'] as String?) ?? '';
        final sname = (p['senderName'] as String?) ?? '';
        if (text.isEmpty) return '';
        if (sid.isEmpty) return text;
        if (sid == _myUid) return 'You: $text';
        final shown = _nameOf(sid, fallback: sname);
        return shown.isEmpty ? text : '$shown: $text';
      }
    }
    final msg = (g['lastMessage'] as String?) ?? '';
    final senderId = (g['lastSenderId'] as String?) ?? '';
    final senderName = (g['lastSenderName'] as String?) ?? '';
    if (senderId.isEmpty) return msg; // system message
    if (senderId == _myUid) return 'You: $msg';
    final shown = _nameOf(senderId, fallback: senderName);
    return shown.isEmpty ? msg : '$shown: $msg';
  }

  String _time(Timestamp? ts) {
    if (ts == null) return '';
    final t = ts.toDate();
    return sameDay(t, DateTime.now()) ? hhmm(t) : dayLabel(t);
  }

  void _showPhoto(String groupId, String name, String photo, bool isMember) {
    final size = MediaQuery.of(context).size.width * 0.75;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: size,
              color: softCardColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    // photo par tap: poori screen par khulti hai
                    onTap: photo.isEmpty
                        ? null
                        : () => _openFullPhoto(name, photo),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: size,
                          height: size,
                          child: photo.isEmpty
                              ? Container(
                            color:
                            AppColors.gold500.withValues(alpha: 0.2),
                            alignment: Alignment.center,
                            child: UserAvatar(
                              username: name,
                              photoUrl: '',
                              size: size * 0.5,
                            ),
                          )
                              : CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.gold700,
                              ),
                            ),
                            errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding:
                            const EdgeInsets.fromLTRB(14, 12, 14, 24),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black54, Colors.transparent],
                              ),
                            ),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Message',
                        icon: const Icon(Icons.chat_bubble_outline,
                            color: AppColors.gold700),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GroupChatScreen(
                              groupId: groupId,
                              name: name,
                              photoUrl: photo,
                            ),
                          ));
                        },
                      ),
                      if (isMember)
                        IconButton(
                          tooltip: 'Call',
                          icon: const Icon(Icons.call_outlined,
                              color: AppColors.gold700),
                          onPressed: () {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Calls are coming soon')),
                            );
                          },
                        ),
                      if (isMember)
                        IconButton(
                          tooltip: 'Group info',
                          icon: const Icon(Icons.info_outline,
                              color: AppColors.gold700),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  GroupInfoScreen(groupId: groupId),
                            ));
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullPhoto(String name, String photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
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
          hintText: 'Search groups',
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
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold700),
      );
    }
    if (_failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load groups',
        subtitle: 'Check your internet and try again.',
      );
    }
    final visible = _docs.where((d) => !_isDeletedForMe(d)).toList();
    if (visible.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'No groups yet',
        subtitle: 'Tap + to create a group with your contacts.',
      );
    }
    final filtered = _query.isEmpty
        ? visible
        : visible
        .where((d) => ((d.data()['name'] as String?) ?? '')
        .toLowerCase()
        .contains(_query))
        .toList();
    if (filtered.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No groups found',
        subtitle: 'No group matches "$_query".',
      );
    }
    // pin kiye hue upar
    final list = [
      ...filtered.where(_isPinned),
      ...filtered.where((d) => !_isPinned(d)),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final d = list[i];
        final g = d.data();
        final name = (g['name'] as String?) ?? '';
        final photo = (g['photoUrl'] as String?) ?? '';
        final isMember =
        List<String>.from(g['members'] ?? const []).contains(_myUid);
        final unreadMap = g['unread'];
        final unread = !isMember
            ? 0
            : (unreadMap is Map
            ? ((unreadMap[_myUid] as num?)?.toInt() ?? 0)
            : 0);
        final pinned = _isPinned(d);
        final marked = _isMarkedUnread(d);
        final selected = _selected.contains(d.id);

        return Container(
          decoration: BoxDecoration(
            color: selected ? AppColors.gold200 : softCardColor,
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
              onLongPress: () => _toggleSelect(d.id),
              onTap: _selecting
                  ? () => _toggleSelect(d.id)
                  : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupChatScreen(
                    groupId: d.id,
                    name: name,
                    photoUrl: photo,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _selecting
                          ? () => _toggleSelect(d.id)
                          : () => _showPhoto(d.id, name, photo, isMember),
                      child:
                      UserAvatar(username: name, photoUrl: photo, size: 52),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brown900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _preview(g, isMember),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.brown700,
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
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
                          _time(isMember
                              ? g['lastMessageAt'] as Timestamp?
                              : _leftTime(g)),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread > 0
                                ? AppColors.gold700
                                : AppColors.brown700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (pinned)
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
                                    horizontal: 7, vertical: 2),
                                constraints:
                                const BoxConstraints(minWidth: 22),
                                decoration: BoxDecoration(
                                  color: AppColors.gold700,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Text(
                                  unread > 99 ? '99+' : '$unread',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.cream,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
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
                            else if (!pinned)
                                const SizedBox(height: 22),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
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
              onTap: _create,
              child: const Icon(
                Icons.group_add_outlined,
                color: AppColors.cream,
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            GradientHeader(
              title: _selecting ? '${_selected.length} selected' : 'Groups',
              titleStyle: _selecting
                  ? const TextStyle(
                color: Colors.black,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              )
                  : null,
              actions: _selecting
                  ? [
                IconButton(
                  tooltip: 'Pin',
                  icon: Icon(
                    _chosen.every(_isPinned)
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
                    } else if (v == 'leave') {
                      _leaveSelected();
                    }
                  },
                  itemBuilder: (_) {
                    final allMarked = _chosen.every(_isMarkedUnread);
                    final anyMember = _chosen.any(_isMember);
                    PopupMenuItem<String> item(
                        String v, IconData icon, String label) {
                      return PopupMenuItem(
                        value: v,
                        child: Row(
                          children: [
                            Icon(icon, color: AppColors.gold700),
                            const SizedBox(width: 12),
                            Text(
                              label,
                              style: const TextStyle(
                                color: AppColors.brown900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return [
                      item(
                        'unread',
                        allMarked
                            ? Icons.mark_chat_read_outlined
                            : Icons.mark_chat_unread_outlined,
                        allMarked ? 'Mark as read' : 'Mark as unread',
                      ),
                      if (anyMember)
                        item('leave', Icons.logout, 'Leave group'),
                    ];
                  },
                ),
              ]
                  : const [],
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
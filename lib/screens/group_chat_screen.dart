import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../chat_repository.dart';
import '../cloudinary_service.dart';
import '../group_repository.dart';
import '../message_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'group_info_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String name;
  final String photoUrl;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.name,
    this.photoUrl = '',
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  static const _reactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  final _controller = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  late String _name = widget.name;
  late String _photoUrl = widget.photoUrl;
  Map<String, dynamic> _group = {};
  bool _isMember = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _groupSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _msgSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loaded = false;
  bool _failed = false;

  final Set<String> _selected = {};
  Map<String, dynamic>? _replyTo;
  String? _editingId;
  String _editDraft = '';
  String? _editOriginal;

  bool _uploading = false;
  bool _hasText = false;
  bool _marking = false;

  bool _typing = false;
  Timer? _typingTimer;
  Timer? _tick;

  final Map<String, GlobalKey> _keys = {};
  String? _flashId;
  Timer? _flashTimer;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _groupSub = groupRepo.groupDocStream(widget.groupId).listen(
      _onGroup,
      onError: (e) {
        if (!mounted) return;
        if (e is FirebaseException && e.code == 'permission-denied') {
          _msgSub?.cancel();
          setState(() {
            _isMember = false;
            _loaded = true;
          });
        } else {
          setState(() {
            _failed = true;
            _loaded = true;
          });
        }
      },
    );
    // "typing..." purani na rahe, isliye thori thori der baad header dobara banao
    _tick = Timer.periodic(const Duration(seconds: 4), (_) {
      final t = _group['typing'];
      if (mounted && t is Map && t.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _stopTyping();
    _typingTimer?.cancel();
    _tick?.cancel();
    _flashTimer?.cancel();
    _groupSub?.cancel();
    _msgSub?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onGroup(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final data = snap.data();
    if (data == null) {
      _msgSub?.cancel();
      _msgSub = null;
      setState(() {
        _isMember = false;
        _loaded = true;
      });
      return;
    }

    final members = List<String>.from(data['members'] ?? const []);
    final member = members.contains(_myUid);
    setState(() {
      _group = data;
      _name = (data['name'] as String?) ?? _name;
      _photoUrl = (data['photoUrl'] as String?) ?? _photoUrl;
      _isMember = member;
    });

    if (!member) {
      _msgSub?.cancel();
      _msgSub = null;
      setState(() => _loaded = true);
      return;
    }

    _ensureUsers(members);
    _startMessages();

    // naya message aaya aur screen khuli hai: padha hua mark karo
    final unread = data['unread'];
    final mine = unread is Map ? ((unread[_myUid] as num?)?.toInt() ?? 0) : 0;
    if (mine > 0 && !_marking) {
      _marking = true;
      groupRepo
          .markRead(widget.groupId)
          .catchError((_) {})
          .whenComplete(() => _marking = false);
    }
  }

  void _startMessages() {
    if (_msgSub != null) return;
    _msgSub = groupRepo.messagesStream(widget.groupId).listen(
          (snap) {
        if (!mounted) return;
        setState(() {
          _docs = snap.docs;
          _loaded = true;
          _failed = false;
        });
      },
      onError: (e) {
        debugPrint('GROUP MESSAGES ERROR: $e');
        if (!mounted) return;
        setState(() {
          _failed = true;
          _loaded = true;
        });
      },
    );
  }

  /// Typing / naam dikhane ke liye members ke usernames cache mein le aao
  void _ensureUsers(List<String> members) {
    final missing = members.where((u) => chatRepo.cachedUser(u) == null);
    if (missing.isEmpty) return;
    Future.wait(
      missing.map((u) => chatRepo.getUser(u).then((_) {}, onError: (_) {})),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  // -------------------------------------------------------------------------
  // Group data helpers
  // -------------------------------------------------------------------------

  List<String> get _members =>
      List<String>.from(_group['members'] ?? const []);

  bool get _amAdmin =>
      List<String>.from(_group['admins'] ?? const []).contains(_myUid);

  bool get _selecting => _selected.isNotEmpty;

  String get _headerStatus {
    final names = <String>[];
    final t = _group['typing'];
    if (t is Map) {
      final now = DateTime.now();
      t.forEach((uid, ts) {
        if (uid == _myUid || ts is! Timestamp) return;
        if (now.difference(ts.toDate()).inSeconds > 8) return;
        final n = chatRepo.cachedUser(uid as String)?['username'] as String?;
        if (n != null && n.isNotEmpty) names.add(n);
      });
    }
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length > 1) return '${names.join(', ')} are typing…';
    final n = _members.length;
    return n == 1 ? '1 member' : '$n members';
  }

  /// Meri join hone ki tareekh se pehle ke messages aur meri taraf se delete kiye hue na dikhao
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visible {
    final j = _group['joinedAt'];
    final joined = j is Map ? j[_myUid] : null;
    return _docs.where((d) {
      final m = d.data();
      final del = m['deletedFor'];
      if (del is List && del.contains(_myUid)) return false;
      if (joined is Timestamp) {
        final c = m['createdAt'];
        if (c is Timestamp && c.compareTo(joined) < 0) return false;
      }
      return true;
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _selectedDocs =>
      _visible.where((d) => _selected.contains(d.id)).toList();

  /// Baqi sab members ne ye message dekh liya?
  bool _seenByAll(Timestamp? created) {
    if (created == null) return false;
    final lr = _group['lastRead'];
    if (lr is! Map) return false;
    final others = _members.where((m) => m != _myUid).toList();
    if (others.isEmpty) return false;
    for (final m in others) {
      final t = lr[m];
      if (t is! Timestamp || t.compareTo(created) < 0) return false;
    }
    return true;
  }

  bool _isMine(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      d.data()['senderId'] == _myUid;

  bool _within(
      QueryDocumentSnapshot<Map<String, dynamic>> d, Duration limit) {
    final c = d.data()['createdAt'];
    if (c is! Timestamp) return true;
    return DateTime.now().difference(c.toDate()) <= limit;
  }

  // -------------------------------------------------------------------------
  // Typing
  // -------------------------------------------------------------------------

  void _onTextChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    if (_editingId != null || !_isMember) return;

    if (has) {
      if (!_typing) {
        _typing = true;
        groupRepo.setTyping(widget.groupId, true).catchError((_) {});
      }
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
    } else {
      _stopTyping();
    }
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (!_typing) return;
    _typing = false;
    groupRepo.setTyping(widget.groupId, false).catchError((_) {});
  }

  // -------------------------------------------------------------------------
  // Send / reply / edit
  // -------------------------------------------------------------------------

  void _scrollToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _send() {
    if (!_isMember) return;
    if (_editingId != null) {
      _submitEdit();
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo;
    _controller.clear();
    _stopTyping();
    if (reply != null) setState(() => _replyTo = null);

    groupRepo
        .sendMessage(
      groupId: widget.groupId,
      members: _members,
      text: text,
      replyTo: reply,
    )
        .catchError((_) {
      if (!mounted) return;
      if (_controller.text.isEmpty) _controller.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be sent')),
      );
    });
    _scrollToBottom();
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_uploading || !_isMember) return;
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (picked == null) return;

    final reply = _replyTo;
    setState(() {
      _uploading = true;
      _replyTo = null;
    });

    try {
      final r = await cloudinary.uploadImage(File(picked.path));
      await groupRepo.sendImage(
        groupId: widget.groupId,
        members: _members,
        imageUrl: r['url'] as String,
        width: (r['width'] as num?)?.toInt(),
        height: (r['height'] as num?)?.toInt(),
        replyTo: reply,
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('GROUP IMAGE SEND ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image could not be sent')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showAttachSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openImage(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(child: CachedNetworkImage(imageUrl: url)),
        ),
      ),
    ));
  }

  void _startReply(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    if (_editingId != null || !_isMember) return;
    final m = d.data();
    if (m['deletedForAll'] == true || m['type'] == 'system') return;
    final text = m['type'] == 'image'
        ? '📷 Photo'
        : ((m['text'] as String?) ?? '');
    setState(() {
      _replyTo = {
        'id': d.id,
        'text': text.length > 200 ? text.substring(0, 200) : text,
        'senderId': m['senderId'],
        'senderName': m['senderName'] ?? '',
      };
    });
    _inputFocus.requestFocus();
  }

  void _startEdit() {
    final docs = _selectedDocs;
    if (docs.length != 1) return;
    final d = docs.first;
    final text = (d.data()['text'] as String?) ?? '';
    _clearSelection();
    _editDraft = _controller.text;
    _editOriginal = text;
    setState(() {
      _replyTo = null;
      _editingId = d.id;
    });
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _inputFocus.requestFocus();
  }

  void _cancelEdit() {
    if (_editingId == null) return;
    setState(() => _editingId = null);
    _controller.text = _editDraft;
    _controller.selection =
        TextSelection.collapsed(offset: _editDraft.length);
    _editDraft = '';
    _editOriginal = null;
  }

  Future<void> _submitEdit() async {
    final id = _editingId;
    if (id == null) return;
    final newText = _controller.text.trim();
    if (newText.isEmpty) return;
    if (newText == _editOriginal) {
      _cancelEdit();
      return;
    }
    final isLast = _docs.isNotEmpty && _docs.first.id == id;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _editingId = null);
    _controller.text = _editDraft;
    _controller.selection =
        TextSelection.collapsed(offset: _editDraft.length);
    _editDraft = '';
    _editOriginal = null;

    try {
      await groupRepo.editMessage(
        groupId: widget.groupId,
        messageId: id,
        newText: newText,
        updateLastMessage: isLast,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not edit message. Try again.')),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Selection / actions
  // -------------------------------------------------------------------------

  void _toggleMsg(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  Future<void> _copySelected() async {
    final texts = _selectedDocs.reversed
        .where((d) => d.data()['deletedForAll'] != true)
        .map((d) => (d.data()['text'] as String?) ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    _clearSelection();
    if (texts.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: texts.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }

  Future<void> _reactToSelected(String emoji) async {
    final messenger = ScaffoldMessenger.of(context);
    final docs = _selectedDocs;
    if (docs.length != 1) return;
    final d = docs.first;
    final r = d.data()['reactions'];
    final mine = r is Map ? r[_myUid] : null;

    _clearSelection();
    try {
      await groupRepo.setReaction(
        groupId: widget.groupId,
        messageId: d.id,
        emoji: mine == emoji ? null : emoji,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not react. Try again.')),
      );
    }
  }

  Future<void> _deleteDialog() async {
    final docs = _selectedDocs;
    if (docs.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    final canAll = docs.every((d) =>
    d.data()['deletedForAll'] != true &&
        d.data()['type'] != 'system' &&
        (_isMine(d) || _amAdmin));

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(docs.length == 1
            ? 'Delete message?'
            : 'Delete ${docs.length} messages?'),
        actions: [
          if (canAll)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('Delete for everyone'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'me'),
            child: const Text('Delete for me'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    final ids = docs.map((d) => d.id).toList();
    final isLast = _docs.isNotEmpty && ids.contains(_docs.first.id);
    _clearSelection();

    try {
      if (choice == 'all') {
        await groupRepo.deleteMessagesForEveryone(
          groupId: widget.groupId,
          messageIds: ids,
          updateLastMessage: isLast,
        );
      } else {
        await groupRepo.deleteMessagesForMe(
          groupId: widget.groupId,
          messageIds: ids,
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete. Try again.')),
      );
    }
  }

  Future<void> _jumpTo(String id) async {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message is too far up')),
      );
      return;
    }
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
    );
    if (!mounted) return;
    setState(() => _flashId = id);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  Future<void> _openInfo() async {
    final left = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GroupInfoScreen(groupId: widget.groupId),
      ),
    );
    if (left == true && mounted) Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  List<Widget> _msgActions() {
    final docs = _selectedDocs;
    if (docs.isEmpty) return const [];
    final single = docs.length == 1 ? docs.first : null;
    final canEdit = single != null &&
        _isMine(single) &&
        single.data()['type'] == 'text' &&
        single.data()['deletedForAll'] != true &&
        _within(single, const Duration(minutes: 15));
    final hasText = docs.any((d) =>
    d.data()['deletedForAll'] != true &&
        ((d.data()['text'] as String?) ?? '').isNotEmpty);

    return [
      if (hasText)
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_outlined, color: Colors.black),
          onPressed: _copySelected,
        ),
      if (canEdit && _isMember)
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined, color: Colors.black),
          onPressed: _startEdit,
        ),
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline, color: Colors.black),
        onPressed: _deleteDialog,
      ),
    ];
  }

  Widget _reactionBar() {
    final sel = _selectedDocs;
    final r = sel.length == 1 ? sel.first.data()['reactions'] : null;
    final mineReaction = r is Map ? r[_myUid] : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: softCardColor,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppColors.brown900.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in _reactions)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _reactToSelected(e),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: mineReaction == e
                      ? const BoxDecoration(
                    color: AppColors.gold200,
                    shape: BoxShape.circle,
                  )
                      : null,
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting && _editingId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSelection();
        } else if (_editingId != null) {
          _cancelEdit();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            GestureDetector(
              onTap: (_selecting || !_isMember) ? null : _openInfo,
              child: GradientHeader(
                title: _selecting ? '${_selected.length} selected' : _name,
                subtitle: _selecting || !_isMember ? null : _headerStatus,
                titleStyle:
                const TextStyle(fontSize: 18, color: Colors.black),
                showBack: !_selecting,
                leading: _selecting
                    ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: _clearSelection,
                )
                    : UserAvatar(
                  username: _name,
                  photoUrl: _photoUrl,
                  size: 40,
                ),
                actions: _selecting ? _msgActions() : const [],
              ),
            ),
            Expanded(child: _messages()),
            _isMember ? _inputBar() : _cantSendBar(),
          ],
        ),
      ),
    );
  }

  Widget _messages() {
    if (!_isMember && _loaded) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'You are no longer a member',
        subtitle: "You can't see or send messages in this group.",
      );
    }
    if (_failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load messages',
        subtitle: 'Check your internet and try again.',
      );
    }
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold700),
      );
    }

    final msgs = _visible;
    if (msgs.isEmpty) {
      return const EmptyState(
        icon: Icons.waving_hand_outlined,
        title: 'Say hi to the group',
        subtitle: 'Send a message to start the conversation.',
      );
    }

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: msgs.length,
      itemBuilder: (_, i) {
        final doc = msgs[i];
        final m = doc.data();
        final created = (m['createdAt'] as Timestamp?)?.toDate();
        final older = i + 1 < msgs.length ? msgs[i + 1].data() : null;
        final olderTime = (older?['createdAt'] as Timestamp?)?.toDate();
        final showDate =
            created != null && (olderTime == null || !sameDay(olderTime, created));

        if (m['type'] == 'system') {
          return Column(
            key: ValueKey(doc.id),
            children: [
              if (showDate) DateChip(label: dayLabel(created)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DateChip(label: (m['text'] as String?) ?? ''),
              ),
            ],
          );
        }

        final mine = m['senderId'] == _myUid;
        final showSender = !mine &&
            (older == null ||
                older['type'] == 'system' ||
                older['senderId'] != m['senderId'] ||
                showDate);
        final deleted = m['deletedForAll'] == true;
        final reply = m['replyTo'];
        final createdTs = m['createdAt'] as Timestamp?;

        return Column(
          key: ValueKey(doc.id),
          children: [
            if (showDate) DateChip(label: dayLabel(created)),
            KeyedSubtree(
              key: _keys.putIfAbsent(doc.id, () => GlobalKey()),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _toggleMsg(doc.id),
                onTap: _selecting ? () => _toggleMsg(doc.id) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  color: _selected.contains(doc.id)
                      ? AppColors.gold400.withValues(alpha: 0.3)
                      : (doc.id == _flashId
                      ? AppColors.gold400.withValues(alpha: 0.45)
                      : AppColors.gold400.withValues(alpha: 0.0)),
                  child: Column(
                    children: [
                      if (_selected.length == 1 &&
                          _selected.contains(doc.id) &&
                          !deleted &&
                          _isMember)
                        Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _reactionBar(),
                        ),
                      SwipeToReply(
                        enabled: !_selecting && !deleted && _isMember,
                        onReply: () => _startReply(doc),
                        child: MessageBubble(
                          data: m,
                          mine: mine,
                          pending:
                          doc.metadata.hasPendingWrites || created == null,
                          seen: mine && _seenByAll(createdTs),
                          time: created,
                          showSender: showSender,
                          onImageTap: _openImage,
                          replyName: reply is Map
                              ? (reply['senderId'] == _myUid
                              ? 'You'
                              : ((reply['senderName'] as String?) ?? ''))
                              : '',
                          onReplyTap: reply is Map
                              ? () => _jumpTo(reply['id'] as String)
                              : null,
                        ),
                      ),
                      if (m['reactions'] is Map &&
                          (m['reactions'] as Map).isNotEmpty &&
                          !deleted)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ReactionPill(
                              reactions: m['reactions'] as Map,
                              myUid: _myUid,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _cantSendBar() {
    return Container(
      color: AppColors.cream,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.block, size: 18, color: AppColors.brown700),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  "You can't send messages to this group",
                  style: TextStyle(
                    color: AppColors.brown700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required String title,
    String? body,
    required VoidCallback onClose,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.gold500.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.gold700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.gold700,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (body != null)
                  Text(
                    body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.brown900, fontSize: 13),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close,
                size: 18, color: AppColors.brown700),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    final reply = _replyTo;
    return Container(
      color: AppColors.cream,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_uploading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: LinearProgressIndicator(
                    color: AppColors.gold700,
                    minHeight: 3,
                  ),
                ),
              if (reply != null)
                _banner(
                  icon: Icons.reply,
                  title: reply['senderId'] == _myUid
                      ? 'Replying to yourself'
                      : 'Replying to ${reply['senderName']}',
                  body: (reply['text'] as String?) ?? '',
                  onClose: () => setState(() => _replyTo = null),
                ),
              if (_editingId != null)
                _banner(
                  icon: Icons.edit_outlined,
                  title: 'Editing message',
                  onClose: _cancelEdit,
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    onPressed: (_editingId != null || _uploading)
                        ? null
                        : _showAttachSheet,
                    icon: const Icon(Icons.attach_file,
                        color: AppColors.brown700),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: softCardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brown900.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: AppColors.gold700,
                        style: const TextStyle(
                          color: AppColors.brown900,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            color: AppColors.brown700.withValues(alpha: 0.7),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: _hasText ? 1 : 0.55,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.gold500, AppColors.gold700],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold700.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _hasText ? _send : null,
                          child: Icon(
                            _editingId != null
                                ? Icons.check_rounded
                                : Icons.send_rounded,
                            color: AppColors.cream,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
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
import 'group_message_info_screen.dart';
import 'forward_to_screen.dart';

class _ChatBg {
  final String key;
  final String name;
  final Color color;
  const _ChatBg(this.key, this.name, this.color);
}

// chat_screen.dart wali hi list (keys same rakhna)
const _chatBgs = [
  _ChatBg('default', 'Default', AppColors.cream),
  _ChatBg('sand', 'Sand', Color(0xFFF1E4C3)),
  _ChatBg('peach', 'Peach', Color(0xFFFBE0D2)),
  _ChatBg('blush', 'Blush', Color(0xFFF8DCE4)),
  _ChatBg('mint', 'Mint', Color(0xFFDDEFDF)),
  _ChatBg('sky', 'Sky', Color(0xFFDCEAF7)),
  _ChatBg('lavender', 'Lavender', Color(0xFFE6DFF3)),
  _ChatBg('grey', 'Grey', Color(0xFFEDEDED)),
];

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
  // members ke live user docs (nickname badle to foran nazar aaye)
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>
  _userSubs = {};
  final Map<String, Map<String, dynamic>> _liveUsers = {};
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
  String _leftBy = ''; // '' = khud chhoda, warna remove karne wale ka naam
  Timestamp? _msgBefore;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pinSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pinnedRaw = [];
  int _pinIndex = 0;

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

  // ---- search ----
  bool _searching = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  int _matchIndex = 0;

  // ---- chat theme (group doc mein: chatTheme.<uid>) ----
  String? get _themeKey {
    final t = _group['chatTheme'];
    return t is Map ? t[_myUid] as String? : null;
  }

  Color get _chatBg {
    for (final b in _chatBgs) {
      if (b.key == _themeKey) return b.color;
    }
    return AppColors.cream;
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    chatRepo.contactNames.addListener(_onNames);
    _controller.addListener(_onTextChanged);
    _groupSub = groupRepo.groupDocStream(widget.groupId).listen(
      _onGroup,
      onError: (e) {
        if (!mounted) return;
        if (e is FirebaseException && e.code == 'permission-denied') {
          _msgSub?.cancel();
          _pinSub?.cancel();
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
    chatRepo.contactNames.removeListener(_onNames);
    for (final sub in _userSubs.values) {
      sub.cancel();
    }
    _stopTyping();
    _typingTimer?.cancel();
    _tick?.cancel();
    _flashTimer?.cancel();
    _groupSub?.cancel();
    _msgSub?.cancel();
    _pinSub?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onGroup(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final data = snap.data();
    if (data == null) {
      _msgSub?.cancel();
      _msgSub = null;
      setState(() {
        _failed = true;
        _loaded = true;
      });
      return;
    }

    final members = List<String>.from(data['members'] ?? const []);
    final member = members.contains(_myUid);
    final leftAtMap = data['leftAt'];
    final leftByMap = data['leftBy'];
    final leftAt = leftAtMap is Map ? leftAtMap[_myUid] : null;

    setState(() {
      _group = data;
      _name = (data['name'] as String?) ?? _name;
      _photoUrl = (data['photoUrl'] as String?) ?? _photoUrl;
      _isMember = member;
      _leftBy = (!member && leftByMap is Map)
          ? ((leftByMap[_myUid] as String?) ?? '')
          : '';
    });

    if (!member) {
      // access khatam, par purani chat dikhti rahe (chhodne ke waqt tak)
      if (leftAt is Timestamp) _startMessages(before: leftAt);
      _pinSub?.cancel();
      _pinSub = null;
      if (_pinnedRaw.isNotEmpty) setState(() => _pinnedRaw = []);
      return;
    }

    _ensureUsers(members);
    _startMessages();
    _startPins();

    // naya message aaya aur screen khuli hai: padha hua mark karo
    final unread = data['unread'];
    final mine = unread is Map ? ((unread[_myUid] as num?)?.toInt() ?? 0) : 0;
    final mk = data['markedUnread'];
    final marked = mk is List && mk.contains(_myUid);
    if ((mine > 0 || marked) && !_marking) {
      _marking = true;
      groupRepo
          .markRead(widget.groupId)
          .catchError((_) {})
          .whenComplete(() => _marking = false);
    }
  }

  void _startMessages({Timestamp? before}) {
    if (_msgSub != null && _msgBefore == before) return;
    _msgSub?.cancel();
    _msgBefore = before;
    _msgSub = groupRepo.messagesStream(widget.groupId, before: before).listen(
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

  void _startPins() {
    if (_pinSub != null) return;
    _pinSub = groupRepo.pinnedStream(widget.groupId).listen(
          (snap) {
        if (mounted) setState(() => _pinnedRaw = snap.docs);
      },
      onError: (_) {},
    );
  }



  /// Typing / naam dikhane ke liye members ke usernames cache mein le aao
  void _onNames() {
    if (mounted) setState(() {});
  }

  /// Mera save kiya naam > nickname > username > (message mein likha purana naam)
  String _nameOf(String uid, {String fallback = ''}) => chatRepo.displayName(
    uid,
    _liveUsers[uid] ?? chatRepo.cachedUser(uid),
    fallback: fallback,
  );

  /// Message ka senderName dikhane se pehle sahi naam se badal do
  Map<String, dynamic> _withName(Map<String, dynamic> m) {
    final sid = m['senderId'];
    if (sid is! String || sid == _myUid) return m;
    return {
      ...m,
      'senderName': _nameOf(sid, fallback: (m['senderName'] as String?) ?? ''),
    };
  }

  void _ensureUsers(List<String> members) {
    for (final u in members) {
      if (u == _myUid || _userSubs.containsKey(u)) continue;
      _userSubs[u] = chatRepo.userStream(u).listen((s) {
        final data = s.data();
        if (!mounted || data == null) return;
        setState(() => _liveUsers[u] = data);
      }, onError: (_) {});
    }
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
        final n = _nameOf(uid as String);
        if (n.isNotEmpty) names.add(n);
      });
    }
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length > 1) return '${names.join(', ')} are typing…';
    final n = _members.length;
    return n == 1 ? '1 member' : '$n members';
  }

  /// Meri join hone ki tareekh se pehle ke messages aur meri taraf se delete kiye hue na dikhao
  /// Jo messages meri membership ke dauran ke hain wahi dikhao:
  /// pehli join se pehle ke aur chhodne-se-dobara-add-hone ke beech ke nahi
  bool _canSee(Map<String, dynamic> m) {
    final del = m['deletedFor'];
    if (del is List && del.contains(_myUid)) return false;

    final c = m['createdAt'];
    if (c is! Timestamp) return true;

    // join hone se pehle ke messages nahi
    final j = _group['joinedAt'];
    final joined = j is Map ? j[_myUid] : null;
    if (joined is Timestamp && c.compareTo(joined) < 0) return false;

    // maine group delete kiya ho to uske baad ke messages hi dikhao
    final dl = _group['deletedAt'];
    final deletedAt = dl is Map ? dl[_myUid] : null;
    if (deletedAt is Timestamp && c.compareTo(deletedAt) <= 0) return false;

    // maine chat clear ki ho to uske baad ke messages hi dikhao
    final cl = _group['clearedAt'];
    final clearedAt = cl is Map ? cl[_myUid] : null;
    if (clearedAt is Timestamp && c.compareTo(clearedAt) <= 0) return false;

    // chhodne se dobara add hone ke beech ka gap
    final g = _group['gaps'];
    if (g is Map && g[_myUid] is Map) {
      for (final e in (g[_myUid] as Map).entries) {
        final from = int.tryParse(e.key.toString());
        final to = e.value;
        if (from != null &&
            to is Timestamp &&
            c.millisecondsSinceEpoch > from &&
            c.compareTo(to) < 0) {
          return false;
        }
      }
    }
    return true;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _visible =>
      _docs.where((d) => _canSee(d.data())).toList();

  /// Pin kiye hue messages (naya pehle, delete hue nahi)
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _pinned {
    final list = _pinnedRaw.where((d) {
      final m = d.data();
      return m['pinned'] == true &&
          m['deletedForAll'] != true &&
          _canSee(m);
    }).toList();
    list.sort((a, b) {
      final ta = a.data()['pinnedAt'] as Timestamp?;
      final tb = b.data()['pinnedAt'] as Timestamp?;
      if (ta == null) return -1;
      if (tb == null) return 1;
      return tb.compareTo(ta);
    });
    return list;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _selectedDocs =>
      _visible.where((d) => _selected.contains(d.id)).toList();

  bool _seenByAll(Timestamp? created) {
    if (created == null) return false;
    final lr = _group['lastRead'];
    if (lr is! Map) return false;
    final j = _group['joinedAt'];
    var counted = 0;
    for (final m in _members) {
      if (m == _myUid) continue;
      // jo member message ke baad join hua, uska hisaab nahi
      final joined = j is Map ? j[m] : null;
      if (joined is Timestamp && joined.compareTo(created) > 0) continue;
      counted++;
      final t = lr[m];
      if (t is! Timestamp || t.compareTo(created) < 0) return false;
    }
    return counted > 0;
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

  String _previewText(Map<String, dynamic>? m) {
    if (m == null) return '';
    if (m['deletedForAll'] == true) return 'This message was deleted';
    if (m['type'] == 'image') return '📷 Photo';
    return (m['text'] as String?) ?? '';
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
        // delete se pehle dekh lo: sab se naya (mujhe nazar aane wala) message delete ho raha hai?
        final vis = _visible; // naye pehle
        final base = _group['lastMessageAt'] as Timestamp?;
        final newestDeleted = vis.isNotEmpty && ids.contains(vis.first.id);
        final remaining = vis.where((d) => !ids.contains(d.id)).toList();

        await groupRepo.deleteMessagesForMe(
          groupId: widget.groupId,
          messageIds: ids,
        );

        if (newestDeleted && base != null) {
          final next = remaining.isEmpty ? null : remaining.first.data();
          await groupRepo.setMyPreview(
            groupId: widget.groupId,
            base: base,
            text: _previewText(next),
            senderId: (next == null || next['type'] == 'system')
                ? ''
                : ((next['senderId'] as String?) ?? ''),
            senderName: (next?['senderName'] as String?) ?? '',
          );
        }
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

  Widget _groupMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.black),
      color: softCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      onSelected: _onMenuSelected,
      itemBuilder: (_) => [
        _menuItem('info', Icons.info_outline, 'Group info'),
        _menuItem('theme', Icons.palette_outlined, 'Chat theme'),
        _menuItem('search', Icons.search, 'Search'),
        _menuItem('clear', Icons.delete_sweep_outlined, 'Clear chat'),
        // chhodne ke baad "Exit group" nahi dikhega
        if (_isMember)
          _menuItem('exit', Icons.exit_to_app, 'Exit group'),
      ],
    );
  }

  void _onMenuSelected(String v) {
    switch (v) {
      case 'info':
        _openInfo();
        break;
      case 'theme':
        _openThemePicker();
        break;
      case 'search':
        setState(() => _searching = true);
        break;
      case 'clear':
        _clearChat();
        break;
      case 'exit':
        _exitGroup();
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  /// Jin messages mein search wala lafz hai un ki ids (naya pehle)
  List<String> _matchIds() {
    if (_searchQuery.isEmpty) return const [];
    return _visible.where((d) {
      final m = d.data();
      if (m['type'] == 'system' || m['deletedForAll'] == true) return false;
      return ((m['text'] as String?) ?? '')
          .toLowerCase()
          .contains(_searchQuery);
    }).map((d) => d.id).toList();
  }

  /// Maujooda match tak scroll karo (1 second flash bhi hoga)
  void _jumpToMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ids = _matchIds();
      if (ids.isEmpty) return;
      _jumpTo(ids[_matchIndex.clamp(0, ids.length - 1)]);
    });
  }

  /// delta +1 = purana match, -1 = naya match
  void _stepMatch(int delta) {
    final n = _matchIds().length;
    if (n == 0) return;
    setState(() => _matchIndex = (_matchIndex + delta + n) % n);
    _jumpToMatch();
  }

  void _closeSearch() {
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _searchQuery = '';
      _matchIndex = 0;
    });
  }

  Widget _searchField() {
    final n = _matchIds().length;
    final pos = n == 0 ? 0 : _matchIndex.clamp(0, n - 1) + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
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
          autofocus: true,
          onChanged: (v) {
            setState(() {
              _searchQuery = v.trim().toLowerCase();
              _matchIndex = 0;
            });
            _jumpToMatch();
          },
          cursorColor: AppColors.gold700,
          style: const TextStyle(
            color: AppColors.brown900,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Search messages',
            hintStyle: TextStyle(
              color: AppColors.brown700.withValues(alpha: 0.7),
            ),
            prefixIcon: const Icon(Icons.search, color: AppColors.gold700),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searchQuery.isNotEmpty)
                  Text(
                    '$pos/$n',
                    style: const TextStyle(
                      color: AppColors.brown700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                  const BoxConstraints(minWidth: 34, minHeight: 40),
                  icon: const Icon(Icons.keyboard_arrow_up,
                      color: AppColors.brown700),
                  onPressed: n == 0 ? null : () => _stepMatch(1),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                  const BoxConstraints(minWidth: 34, minHeight: 40),
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: AppColors.brown700),
                  onPressed: n == 0 ? null : () => _stepMatch(-1),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                  const BoxConstraints(minWidth: 34, minHeight: 40),
                  icon: const Icon(Icons.close, color: AppColors.brown700),
                  onPressed: _closeSearch,
                ),
              ],
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Theme
  // -------------------------------------------------------------------------

  void _openThemePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: softCardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chat theme',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brown900,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [for (final b in _chatBgs) _themeDot(ctx, b)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themeDot(BuildContext ctx, _ChatBg b) {
    final selected = (_themeKey ?? 'default') == b.key;
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _setTheme(b.key);
      },
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: b.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? AppColors.gold700
                    : AppColors.brown700.withValues(alpha: 0.25),
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: AppColors.gold700)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            b.name,
            style: const TextStyle(fontSize: 12, color: AppColors.brown900),
          ),
        ],
      ),
    );
  }

  Future<void> _setTheme(String key) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await groupRepo.setChatTheme(
        widget.groupId,
        key == 'default' ? null : key,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change theme. Try again.')),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Exit group
  // -------------------------------------------------------------------------

  Future<void> _exitGroup() async {
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: softCardColor,
        title: const Text(
          'Exit group?',
          style: TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          "You won't be able to send or receive new messages in $_name.",
          style: const TextStyle(color: AppColors.brown700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await groupRepo.leaveGroup(widget.groupId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not exit group. Try again.')),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Clear chat
  // -------------------------------------------------------------------------

  Future<void> _clearChat() async {
    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: softCardColor,
        title: const Text(
          'Clear chat?',
          style: TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'All messages will be cleared for you only. Other members will still keep their copy.',
          style: TextStyle(color: AppColors.brown700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await groupRepo.clearChatForMe(widget.groupId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Chat cleared')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not clear chat. Try again.')),
      );
    }
  }

  PopupMenuItem<String> _menuItem(String v, IconData icon, String label) {
    return PopupMenuItem(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.brown900),
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

  List<Widget> _msgActions() {
    final docs = _selectedDocs;
    if (docs.isEmpty) return const [];
    final single = docs.length == 1 ? docs.first : null;

    final canEdit = single != null &&
        _isMember &&
        _isMine(single) &&
        single.data()['type'] == 'text' &&
        single.data()['deletedForAll'] != true &&
        _within(single, const Duration(minutes: 15));
    final canInfo = single != null &&
        _isMember &&
        _isMine(single) &&
        single.data()['type'] != 'system' &&
        single.data()['deletedForAll'] != true;
    final hasText = docs.any((d) =>
    d.data()['deletedForAll'] != true &&
        ((d.data()['text'] as String?) ?? '').isNotEmpty);
    final allPinned = docs.every((d) => d.data()['pinned'] == true);

    final menu = <PopupMenuItem<String>>[
      if (hasText) _menuItem('forward', Icons.forward, 'Forward'),
      if (canEdit) _menuItem('edit', Icons.edit_outlined, 'Edit'),
      if (canInfo) _menuItem('info', Icons.info_outline, 'Info'),
    ];

    return [
      if (hasText)
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_outlined, color: Colors.black),
          onPressed: _copySelected,
        ),
      if (_isMember)
        IconButton(
          tooltip: allPinned ? 'Unpin' : 'Pin',
          icon: Icon(
            allPinned ? Icons.push_pin : Icons.push_pin_outlined,
            color: Colors.black,
          ),
          onPressed: _togglePinSelected,
        ),
      if (_isMember)
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline, color: Colors.black),
          onPressed: _deleteDialog,
        ),
      if (menu.isNotEmpty)
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.black),
          color: softCardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onSelected: (v) {
            switch (v) {
              case 'forward':
                _forwardSelected();
                break;
              case 'edit':
                _startEdit();
                break;
              case 'info':
                _openMessageInfo();
                break;
            }
          },
          itemBuilder: (_) => menu,
        ),
    ];
  }

  void _openMessageInfo() {
    final docs = _selectedDocs;
    if (docs.length != 1) return;
    final data = docs.first.data();
    _clearSelection();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GroupMessageInfoScreen(groupId: widget.groupId, data: data),
      ),
    );
  }

  Future<void> _forwardSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    // _docs naye pehle hain, forward ke liye purane pehle chahiye
    final texts = _selectedDocs.reversed
        .where((d) =>
    d.data()['deletedForAll'] != true && d.data()['type'] == 'text')
        .map((d) => (d.data()['text'] as String?) ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();

    if (texts.isEmpty) {
      _clearSelection();
      messenger.showSnackBar(
        const SnackBar(content: Text('Only text messages can be forwarded')),
      );
      return;
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ForwardToScreen(texts: texts)),
    );
    if (!mounted) return;
    if (sent == true) {
      _clearSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(texts.length == 1
              ? 'Message forwarded'
              : '${texts.length} messages forwarded'),
        ),
      );
    }
  }

  Future<void> _togglePinSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final docs = _selectedDocs;
    if (docs.isEmpty) return;

    final unpin = docs.every((d) => d.data()['pinned'] == true);
    if (!unpin) {
      if (docs.any((d) =>
      d.data()['deletedForAll'] == true || d.data()['type'] == 'system')) {
        _clearSelection();
        messenger.showSnackBar(
          const SnackBar(content: Text("You can't pin this message")),
        );
        return;
      }
      final fresh = docs.where((d) => d.data()['pinned'] != true).length;
      if (_pinned.length + fresh > 3) {
        messenger.showSnackBar(
          const SnackBar(content: Text('You can pin up to 3 messages')),
        );
        return;
      }
    }

    final ids = docs.map((d) => d.id).toList();
    _clearSelection();
    try {
      await groupRepo.setMessagesPinned(
        groupId: widget.groupId,
        messageIds: ids,
        pinned: !unpin,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(unpin
              ? (ids.length == 1 ? 'Message unpinned' : 'Messages unpinned')
              : (ids.length == 1 ? 'Message pinned' : 'Messages pinned')),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update pin. Try again.')),
      );
    }
  }

  Future<void> _jumpToPinned(String id, int count) async {
    await _jumpTo(id);
    if (!mounted) return;
    if (count > 1) setState(() => _pinIndex = (_pinIndex + 1) % count);
  }

  Widget _pinBar() {
    final pins = _pinned;
    final i = _pinIndex.clamp(0, pins.length - 1);
    final m = pins[i].data();
    final body =
    m['type'] == 'image' ? '📷 Photo' : ((m['text'] as String?) ?? '');
    final pinSid = (m['senderId'] as String?) ?? '';
    final storedName = (m['senderName'] as String?) ?? '';
    final sender = pinSid.isEmpty || pinSid == _myUid
        ? storedName
        : _nameOf(pinSid, fallback: storedName);
    final text = sender.isEmpty ? body : '$sender: $body';

    return Material(
      color: softCardColor,
      child: InkWell(
        onTap: () => _jumpToPinned(pins[i].id, pins.length),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 18, color: AppColors.gold700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brown900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (pins.length > 1)
                Text(
                  '${i + 1}/${pins.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.brown700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
      canPop: !_searching && !_selecting && _editingId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _clearSelection();
        } else if (_editingId != null) {
          _cancelEdit();
        } else {
          _closeSearch();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            GestureDetector(
              onTap: _selecting ? null : _openInfo,
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
                actions: _selecting ? _msgActions() : [_groupMenu()],
              ),
            ),
            if (_searching) _searchField(),
            if (_isMember && _pinned.isNotEmpty) _pinBar(),
            Expanded(
              child: Container(
                color: _chatBg,
                child: _messages(),
              ),
            ),
            if (!_searching) _isMember ? _inputBar() : _cantSendBar(),
          ],
        ),
      ),
    );
  }

  Widget _messages() {

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
      cacheExtent: _searching ? 100000 : null,
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
                          data: _withName(m),
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
                              : _nameOf(
                            (reply['senderId'] as String?) ?? '',
                            fallback:
                            (reply['senderName'] as String?) ?? '',
                          ))
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
    final text = _leftBy.isEmpty
        ? 'You left this group'
        : 'You were removed by $_leftBy';
    return Container(
      color: AppColors.cream,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 18, color: AppColors.brown700),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: const TextStyle(
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
                      : 'Replying to ${_nameOf(
                    (reply['senderId'] as String?) ?? '',
                    fallback: (reply['senderName'] as String?) ?? '',
                  )}',
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
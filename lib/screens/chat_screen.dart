import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../cloudinary_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_repository.dart';
import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'contact_screen.dart';
import 'forward_to_screen.dart';
import '../status_repository.dart';
import 'status_viewer_screen.dart';

class _ChatBg {
  final String key;
  final String name;
  final Color color;
  const _ChatBg(this.key, this.name, this.color);
}

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

/// Self-destruct ke options (duration null = off)
class _DestructOption {
  final String label;
  final Duration? duration;
  const _DestructOption(this.label, this.duration);
}

const _destructOptions = <_DestructOption>[
  _DestructOption('Off', null),
  _DestructOption('10 seconds', Duration(seconds: 10)),
  _DestructOption('1 minute', Duration(minutes: 1)),
  _DestructOption('1 hour', Duration(hours: 1)),
  _DestructOption('24 hours', Duration(hours: 24)),
];

class ChatScreen extends StatefulWidget {
  final String otherUid;
  final String username;
  final String photoUrl;

  const ChatScreen({
    super.key,
    required this.otherUid,
    required this.username,
    this.photoUrl = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String _myUid = authRepo.currentUser!.uid;
  late final String _chatId = chatRepo.chatIdWith(widget.otherUid);

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Timer? _ticker;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loaded = false;
  bool _failed = false;
  bool _hasText = false;
  bool _marking = false;
  _DestructOption _destruct = _destructOptions.first;
  final _picker = ImagePicker();
  bool _uploading = false;

  /// Jin expired messages ka delete call ja chuka hai
  final Set<String> _deleting = {};

  /// Jab maine ye chat delete ki thi (us se pehle ke messages nahi dikhane)
  Timestamp? _deletedAt;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _chatSub;
  bool _blockedByMe = false;
  bool _blockedByOther = false;
  bool _searching = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  int _matchIndex = 0;
  String? _themeKey;

  Color get _chatBg {
    for (final b in _chatBgs) {
      if (b.key == _themeKey) return b.color;
    }
    return AppColors.cream;
  }
  final Map<String, GlobalKey> _keys = {};
  String? _selectedMsgId;
  final Set<String> _selectedMsgs = {};
  Timestamp? _lastMessageAt;
  String? _editingId;
  Map<String, dynamic>? _replyTo;
  String? _flashId;
  Timer? _flashTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _presenceSub;
  bool _otherOnlineFlag = false;
  DateTime? _otherLastSeen;
  bool _otherHidesPresence = false;
  // ---- typing ----
  // meri taraf (likhne wala)
  bool _iAmTyping = false;
  DateTime? _lastTypingWrite;
  Timer? _typingIdle;
  String _lastTypedText = '';
  // samne wale ki taraf (dekhne wala)
  Object? _lastTypingStamp;
  bool _typingPrimed = false;
  DateTime? _otherTypingUntil;
  String _shownStatus = '';

  bool get _otherOnline {
    final seen = _otherLastSeen;
    return _otherOnlineFlag &&
        seen != null &&
        DateTime.now().difference(seen).inSeconds < 90;
  }

  /// Header ke neeche dikhane wala text. Block ho to kuch nahi dikhega
  String get _presenceText {
    if (_blockedByMe || _blockedByOther || _otherHidesPresence) return '';
    if (_otherOnline) return 'online';
    final seen = _otherLastSeen;
    if (seen == null) return '';
    final now = DateTime.now();
    if (_sameDay(seen, now)) return 'last seen today at ${_hhmm(seen)}';
    if (_sameDay(seen, now.subtract(const Duration(days: 1)))) {
      return 'last seen yesterday at ${_hhmm(seen)}';
    }
    return 'last seen ${_dayLabel(seen)}';
  }

  bool get _otherTyping {
    final until = _otherTypingUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Header ke neeche: typing ho to wo, warna online / last seen
  String get _headerStatus {
    if (_blockedByMe || _blockedByOther) return '';
    if (_otherTyping) return 'typing...';
    return _presenceText;
  }


  String _editDraft = '';
  final _inputFocus = FocusNode();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pinSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pinned = [];
  int _pinIndex = 0;
  bool _jumping = false;
  final Set<String> _unreadIds = {};
  final DateTime _openedAt = DateTime.now();
  String? _firstUnreadId;
  int _unreadCount = 0;
  bool _unreadScrolled = false;

  @override
  void initState() {
    super.initState();

    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      _onTypingChanged();
    });

    _start();

    // Har second countdown refresh + expired messages saaf
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _start() async {
    try {
      _deletedAt = await chatRepo.deletedAtFor(_chatId);
    } catch (_) {}
    chatRepo.setMarkedUnread(_chatId, false).catchError((_) {});
    if (!mounted) return;
    _chatSub = chatRepo.chatDocStream(_chatId).listen((doc) {
      final b = doc.data()?['blockedBy'];
      final list = b is List ? b : const [];
      final t = doc.data()?['chatTheme'];
      final themeKey = t is Map ? t[_myUid] as String? : null;
      final lastAt = doc.data()?['lastMessageAt'] as Timestamp?;
      final tm = doc.data()?['typing'];
      final tStamp = tm is Map ? tm[widget.otherUid] : null;
      if (!mounted) return;
      setState(() {
        _blockedByMe = list.contains(_myUid);
        _blockedByOther = list.contains(widget.otherUid);
        _themeKey = themeKey;
        _lastMessageAt = lastAt;

        if (tStamp == null) {
          _otherTypingUntil = null;
        } else if (_typingPrimed && tStamp != _lastTypingStamp) {
          // naya typing signal aaya: 5 second tak "typing..." dikhao
          _otherTypingUntil = DateTime.now().add(const Duration(seconds: 5));
        }
        _lastTypingStamp = tStamp;
        _typingPrimed = true; // pehla snapshot purana ho sakta hai, usay ignore
      });
    }, onError: (_) {});
    _presenceSub = chatRepo.userStream(widget.otherUid).listen((doc) {
      final d = doc.data();
      if (!mounted) return;
      setState(() {
        _otherOnlineFlag = d?['online'] == true;
        _otherLastSeen = (d?['lastSeen'] as Timestamp?)?.toDate();
        _otherHidesPresence = d?['hidePresence'] == true;
      });
    }, onError: (_) {});
    _sub = chatRepo.messagesStream(_chatId).listen(
      _onSnapshot,
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _failed = true;
          _loaded = true;
        });
      },
    );
    _pinSub = chatRepo.pinnedStream(_chatId).listen((snap) {
      final list = snap.docs
          .where(_afterDelete)
          .where((d) => d.data()['deletedForAll'] != true)
          .toList();
      // naya pin pehle
      list.sort((a, b) {
        final ta = a.data()['pinnedAt'] as Timestamp?;
        final tb = b.data()['pinnedAt'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return -1;
        if (tb == null) return 1;
        return tb.compareTo(ta);
      });
      if (!mounted) return;
      setState(() {
        _pinned = list;
        if (_pinIndex >= list.length) _pinIndex = 0;
      });
    }, onError: (_) {});
  }

  /// Delete / clear ke baad ke messages dikhao, aur jo maine "delete for me"
  /// kiye hain wo chhupa do
  bool _afterDelete(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final df = data['deletedFor'];
    if (df is List && df.contains(_myUid)) return false;

    final cut = _deletedAt;
    if (cut == null) return true;
    final t = data['createdAt'] as Timestamp?;
    return t == null || t.compareTo(cut) > 0;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _chatSub?.cancel();
    _searchCtrl.dispose();
    _inputFocus.dispose();
    _pinSub?.cancel();
    _ticker?.cancel();
    _stopTyping(); // chat se bahar jate hi typing band
    _controller.dispose();
    _flashTimer?.cancel();
    _presenceSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Data handling
  // -------------------------------------------------------------------------

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final docs = snap.docs.where(_afterDelete).toList();

    // Chat khulne ke pehle 2 second mein jo messages unread the unhein yaad rakho
    if (DateTime.now().difference(_openedAt) < const Duration(seconds: 2)) {
      for (final d in docs) {
        final m = d.data();
        if (m['type'] != 'system' &&
            m['senderId'] == widget.otherUid &&
            m['readAt'] == null) {
          _unreadIds.add(d.id);
        }
      }
    }
    // docs naye pehle hain, sab se purana unread dhoondo
    String? firstUnread;
    for (final d in docs.reversed) {
      if (_unreadIds.contains(d.id)) {
        firstUnread = d.id;
        break;
      }
    }
    final unreadCount = docs.where((d) => _unreadIds.contains(d.id)).length;

    setState(() {
      _docs = docs;
      _loaded = true;
      _failed = false;
      _firstUnreadId = firstUnread;
      _unreadCount = unreadCount;
    });
    _sweepExpired();
    _markRead(docs);

    // Bohat saare unread hon to banner tak scroll karo (sirf ek baar)
    if (firstUnread != null && unreadCount > 6 && !_unreadScrolled) {
      _unreadScrolled = true;
      _scrollToFirstUnread();
    }
  }

  /// Samne wale ke unread messages hon to read mark karo
  Future<void> _markRead(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    if (_marking) return;
    final hasUnread = docs.any((d) {
      final m = d.data();
      return m['senderId'] == widget.otherUid &&
          m['readAt'] == null &&
          !d.metadata.hasPendingWrites;
    });
    if (!hasUnread) return;

    _marking = true;
    try {
      await chatRepo.markChatRead(
        chatId: _chatId,
        otherUid: widget.otherUid,
        after: _deletedAt,
      );
    } catch (_) {
      // agli snapshot par dobara koshish ho jayegi
    } finally {
      _marking = false;
    }
  }

  /// Likhte waqt typing bhejo (har 3 second mein ek baar se zyada nahi)
  void _onTypingChanged() {
    // sirf cursor hila ho, text na badla ho to kuch nahi
    if (_controller.text == _lastTypedText) return;
    _lastTypedText = _controller.text;

    if (_editingId != null) return; // edit karte waqt typing nahi dikhani
    if (_controller.text.trim().isEmpty) {
      _stopTyping();
      return;
    }

    final now = DateTime.now();
    if (!_iAmTyping ||
        _lastTypingWrite == null ||
        now.difference(_lastTypingWrite!).inSeconds >= 3) {
      _iAmTyping = true;
      _lastTypingWrite = now;
      chatRepo.setTyping(_chatId, true).catchError((_) {});
    }
    // 4 second kuch na likhein to typing band
    _typingIdle?.cancel();
    _typingIdle = Timer(const Duration(seconds: 4), _stopTyping);
  }

  void _stopTyping() {
    _typingIdle?.cancel();
    if (!_iAmTyping) return;
    _iAmTyping = false;
    chatRepo.setTyping(_chatId, false).catchError((_) {});
  }

  void _tick() {
    if (!mounted) return;

    // typing / online ka text badla ho (expire hua) to hi rebuild
    final status = _headerStatus;
    if (status != _shownStatus) {
      setState(() => _shownStatus = status);
    }

    final hasExpiring = _docs.any((d) => d.data()['expiresAt'] != null);
    if (!hasExpiring) return;
    setState(() {}); // countdown refresh
    _sweepExpired();
  }

  /// Expire ho chuke messages Firestore se delete karo
  void _sweepExpired() {
    final now = DateTime.now();
    for (final d in _docs) {
      final exp = (d.data()['expiresAt'] as Timestamp?)?.toDate();
      if (exp == null || exp.isAfter(now)) continue;
      if (!_deleting.add(d.id)) continue;
      chatRepo
          .deleteMessage(chatId: _chatId, messageId: d.id)
          .catchError((_) {});
    }
  }

  void _send() {
    if (_editingId != null) {
      _submitEdit();
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final reply = _replyTo;
    _controller.clear();
    if (reply != null) setState(() => _replyTo = null);

    chatRepo
        .sendMessage(
      otherUid: widget.otherUid,
      text: text,
      destructAfter: _destruct.duration,
      replyTo: reply,
    )
        .catchError((_) {
      if (!mounted) return;
      if (_controller.text.isEmpty) _controller.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be sent')),
      );
    });

    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_uploading) return;
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 70, // compress, free quota bachane ke liye
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
      await chatRepo.sendImage(
        otherUid: widget.otherUid,
        imageUrl: r['url'] as String,
        width: (r['width'] as num?)?.toInt(),
        height: (r['height'] as num?)?.toInt(),
        destructAfter: _destruct.duration,
        replyTo: reply,
      );
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('IMAGE SEND ERROR: $e');
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
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: url),
          ),
        ),
      ),
    ));
  }

  Future<void> _pickDestruct() async {
    final picked = await showModalBottomSheet<_DestructOption>(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Disappearing messages',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brown900,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'New messages will be deleted after this time.',
                  style: TextStyle(color: AppColors.brown700, fontSize: 13),
                ),
              ),
              for (final o in _destructOptions)
                ListTile(
                  title: Text(
                    o.label,
                    style: const TextStyle(
                      color: AppColors.brown900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: o.label == _destruct.label
                      ? const Icon(Icons.check, color: AppColors.gold700)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(o),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _destruct = picked);
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------


  Widget _chatMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.black),
      color: softCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      onSelected: _onMenuSelected,
      itemBuilder: (_) => [
        _menuItem('contact', Icons.person_outline, 'View contact'),
        _menuItem('theme', Icons.palette_outlined, 'Chat theme'),
        _menuItem(
          'block',
          _blockedByMe ? Icons.check_circle_outline : Icons.block,
          _blockedByMe ? 'Unblock user' : 'Block user',
        ),
        _menuItem('search', Icons.search, 'Search'),
        _menuItem('clear', Icons.delete_sweep_outlined, 'Clear chat'),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _selectedDocs =>
      _docs.where((d) => _selectedMsgs.contains(d.id)).toList();

  bool get _msgSelecting => _selectedDocs.isNotEmpty;

  void _clearMsgSelection() => setState(_selectedMsgs.clear);

  void _toggleMsg(String id) {
    setState(() {
      if (!_selectedMsgs.remove(id)) _selectedMsgs.add(id);
    });
  }

  bool _isMine(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
      d.data()['senderId'] == _myUid;

  bool _within(QueryDocumentSnapshot<Map<String, dynamic>> d, Duration limit) {
    final t = (d.data()['createdAt'] as Timestamp?)?.toDate();
    return t != null && DateTime.now().difference(t) < limit;
  }

  static const _reactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  /// Ek message select ho to header ke neeche emoji ki bar
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

  Future<void> _reactToSelected(String emoji) async {
    final messenger = ScaffoldMessenger.of(context);
    final docs = _selectedDocs;
    if (docs.length != 1) return;
    final d = docs.first;

    final r = d.data()['reactions'];
    final mine = r is Map ? r[_myUid] : null;

    _clearMsgSelection();
    try {
      await chatRepo.setReaction(
        chatId: _chatId,
        messageId: d.id,
        emoji: mine == emoji ? null : emoji, // wahi emoji dobara = hata do
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not react. Try again.')),
      );
    }
  }

  /// Message select hone par header ke buttons
  List<Widget> _msgActions() {
    final docs = _selectedDocs;
    if (docs.isEmpty) return const [];
    final canEdit = docs.length == 1 &&
        _isMine(docs.first) &&
        docs.first.data()['deletedForAll'] != true &&
        _within(docs.first, const Duration(minutes: 15));

    return [
      IconButton(
        tooltip: 'Copy',
        icon: const Icon(Icons.copy_outlined, color: Colors.black),
        onPressed: _copyMessage,
      ),
      IconButton(
        tooltip: docs.every((d) => d.data()['pinned'] == true)
            ? 'Unpin'
            : 'Pin',
        icon: Icon(
          docs.every((d) => d.data()['pinned'] == true)
              ? Icons.push_pin
              : Icons.push_pin_outlined,
          color: Colors.black,
        ),
        onPressed: _togglePinSelected,
      ),
      IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline, color: Colors.black),
        onPressed: _deleteMessageDialog,
      ),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.black),
        color: softCardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        onSelected: _onMsgMenu,
        itemBuilder: (_) => [
          _menuItem('forward', Icons.forward, 'Forward'),
          if (canEdit) _menuItem('edit', Icons.edit_outlined, 'Edit'),
        ],
      ),
    ];
  }

  void _onMsgMenu(String v) {
    switch (v) {
      case 'forward':
        _forwardSelected();
        break;
      case 'edit':
        _startEdit();
        break;
    }
  }

  Future<void> _copyMessage() async {
    // _docs naye pehle hain, copy ke liye purane pehle chahiye
    final docs = _selectedDocs.reversed.toList();
    if (docs.isEmpty) return;
    final text = docs
        .map((d) => (d.data()['text'] as String?) ?? '')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _clearMsgSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          docs.length == 1 ? 'Message copied' : '${docs.length} messages copied',
        ),
      ),
    );
  }
  void _startEdit() {
    final docs = _selectedDocs;
    if (docs.length != 1) return;
    final d = docs.first;
    if (!_isMine(d) ||
        d.data()['type'] == 'image' ||
        d.data()['deletedForAll'] == true ||
        !_within(d, const Duration(minutes: 15))) {
      _clearMsgSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Edit time is over')),
      );
      return;
    }

    final text = (d.data()['text'] as String?) ?? '';
    setState(() {
      _editingId = d.id;
      _replyTo = null;
      _editDraft = _controller.text; // jo likh rahi thi wo wapis ke liye
      _selectedMsgs.clear();
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
  }

  void _startReply(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    if (_editingId != null) return;
    final m = d.data();
    if (m['deletedForAll'] == true || m['type'] == 'system') return;
    final text = (m['text'] as String?) ?? '';
    setState(() {
      _replyTo = {
        'id': d.id,
        'text': text.length > 200 ? text.substring(0, 200) : text,
        'senderId': m['senderId'],
      };
    });
    _inputFocus.requestFocus();
  }

  void _cancelReply() {
    if (_replyTo == null) return;
    setState(() => _replyTo = null);
  }

  Future<void> _openStatusFromReply(String statusId) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final item = await statusRepo.getActive(statusId);
    if (!mounted) return;
    if (item == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This status is no longer available')),
      );
      return;
    }
    final mine = item.ownerId == _myUid;
    nav.push(
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          ownerIds: [item.ownerId],
          groups: {item.ownerId: [item]},
          isMine: mine,
        ),
      ),
    );
  }

  /// Quote par tap karne par original message tak scroll + 1 second highlight
  Future<void> _jumpToMessage(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _jumping = true);
    await WidgetsBinding.instance.endOfFrame;

    final ctx = _keys[id]?.currentContext;
    var found = false;
    if (ctx != null && ctx.mounted) {
      found = true;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;
    setState(() {
      _jumping = false;
      if (found) _flashId = id;
    });

    if (found) {
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() => _flashId = null);
      });
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('This message is too old to show here')),
      );
    }
  }

  Future<void> _submitEdit() async {
    final id = _editingId;
    if (id == null) return;
    final newText = _controller.text.trim();
    if (newText.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    QueryDocumentSnapshot<Map<String, dynamic>>? doc;
    for (final d in _docs) {
      if (d.id == id) doc = d;
    }

    // Message nahi mila ya 15 minute guzar gaye
    if (doc == null || !_within(doc, const Duration(minutes: 15))) {
      _cancelEdit();
      messenger.showSnackBar(
        const SnackBar(content: Text('Edit time is over')),
      );
      return;
    }
    // Kuch badla hi nahi
    if (((doc.data()['text'] as String?) ?? '') == newText) {
      _cancelEdit();
      return;
    }

    final last = _lastMessageAt;
    final isLast = last != null && doc.data()['createdAt'] == last;

    _cancelEdit();
    try {
      await chatRepo.editMessage(
        chatId: _chatId,
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

  String _systemLabel(Map<String, dynamic> m) {
    final who = m['senderId'] == _myUid ? 'You' : widget.username;
    final n = (m['count'] as num?)?.toInt() ?? 1;
    return n == 1 ? '$who pinned a message' : '$who pinned $n messages';
  }

  Future<void> _scrollToFirstUnread() async {
    final id = _firstUnreadId;
    if (id == null) return;
    setState(() => _jumping = true);
    await WidgetsBinding.instance.endOfFrame;

    final ctx = _keys[id]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    if (!mounted) return;
    setState(() => _jumping = false);
  }

  Future<void> _forwardSelected() async {
    final messenger = ScaffoldMessenger.of(context);

    // _docs naye pehle hain, forward ke liye purane pehle chahiye
    final texts = _selectedDocs.reversed
        .where((d) => d.data()['deletedForAll'] != true)
        .map((d) => (d.data()['text'] as String?) ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList();

    if (texts.isEmpty) {
      _clearMsgSelection();
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to forward')),
      );
      return;
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ForwardToScreen(texts: texts)),
    );
    if (!mounted) return;

    if (sent == true) {
      _clearMsgSelection();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            texts.length == 1
                ? 'Message forwarded'
                : '${texts.length} messages forwarded',
          ),
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
      if (docs.any((d) => d.data()['deletedForAll'] == true)) {
        _clearMsgSelection();
        messenger.showSnackBar(
          const SnackBar(content: Text("You can't pin a deleted message")),
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
    _clearMsgSelection();
    try {
      await chatRepo.setMessagesPinned(
        chatId: _chatId,
        messageIds: ids,
        pinned: !unpin,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            unpin
                ? (ids.length == 1 ? 'Message unpinned' : 'Messages unpinned')
                : (ids.length == 1 ? 'Message pinned' : 'Messages pinned'),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update pin. Try again.')),
      );
    }
  }

  /// Pin kiye hue message tak scroll karo
  Future<void> _jumpToPinned(
      QueryDocumentSnapshot<Map<String, dynamic>> d,
      ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _jumping = true);
    await WidgetsBinding.instance.endOfFrame;

    final ctx = _keys[d.id]?.currentContext;
    var found = false;
    if (ctx != null && ctx.mounted) {
      found = true;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (!mounted) return;
    setState(() {
      _jumping = false;
      if (_pinned.length > 1) _pinIndex = (_pinIndex + 1) % _pinned.length;
    });
    if (!found) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This message is too old to show here')),
      );
    }
  }

  Widget _pinBar() {
    final d = _pinned[_pinIndex.clamp(0, _pinned.length - 1)];
    final text = (d.data()['text'] as String?) ?? '';
    return Material(
      color: softCardColor,
      child: InkWell(
        onTap: () => _jumpToPinned(d),
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
              if (_pinned.length > 1)
                Text(
                  '${_pinIndex.clamp(0, _pinned.length - 1) + 1}/${_pinned.length}',
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

  Future<void> _deleteForEveryone(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ids = docs.map((d) => d.id).toList();

    // Kya in mein chat ka aakhri message bhi hai?
    final last = _lastMessageAt;
    final deletesLast =
        last != null && docs.any((d) => d.data()['createdAt'] == last);

    _clearMsgSelection();
    try {
      await chatRepo.deleteMessagesForEveryone(
        chatId: _chatId,
        messageIds: ids,
        updateLastMessage: deletesLast,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ids.length == 1
                ? 'Message deleted for everyone'
                : '${ids.length} messages deleted for everyone',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete. Try again.')),
      );
    }
  }

  Future<void> _deleteMessageDialog() async {
    final docs = _selectedDocs;
    if (docs.isEmpty) return;
    final canEveryone = docs.every(
          (d) =>
      _isMine(d) &&
          _within(d, const Duration(hours: 1)) &&
          d.data()['deletedForAll'] != true,
    );

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: softCardColor,
        title: Text(
          docs.length == 1
              ? 'Delete message?'
              : 'Delete ${docs.length} messages?',
          style: const TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          if (canEveryone)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'everyone'),
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

    if (!mounted) return;
    if (choice == 'me') {
      await _deleteForMe(docs);
    } else if (choice == 'everyone') {
      await _deleteForEveryone(docs);
    }
  }

  Future<void> _deleteForMe(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ids = docs.map((d) => d.id).toList();

    // Delete se pehle hi dekh lo ke sab se naya message delete ho raha hai ya nahi
    final visible =
    _docs.where((d) => d.data()['type'] != 'system').toList(); // naye pehle
    final newestDeleted = visible.isNotEmpty && ids.contains(visible.first.id);
    final remaining = visible.where((d) => !ids.contains(d.id)).toList();
    final base = _lastMessageAt;

    _clearMsgSelection();
    try {
      await chatRepo.deleteMessagesForMe(chatId: _chatId, messageIds: ids);

      if (newestDeleted && base != null) {
        final next = remaining.isEmpty ? null : remaining.first.data();
        await chatRepo.setMyPreview(
          chatId: _chatId,
          base: base,
          text: (next?['text'] as String?) ?? '',
          senderId: (next?['senderId'] as String?) ?? '',
        );
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ids.length == 1
                ? 'Message deleted'
                : '${ids.length} messages deleted',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete. Try again.')),
      );
    }
  }



  void _openContact() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactScreen(
          uid: widget.otherUid,
          username: widget.username,
          photoUrl: widget.photoUrl,
        ),
      ),
    );
  }

  void _onMenuSelected(String v) {
    switch (v) {
      case 'contact':
        _openContact();
        break;
      case 'theme':
        _openThemePicker();
        break;
      case 'block':
        _toggleBlock();
        break;
      case 'search':
        setState(() => _searching = true);
        break;
      case 'clear':
        _clearChat();
        break;
    }
  }

  /// Jin messages mein search wala lafz hai un ki ids (naya pehle)
  List<String> _matchIds() {
    if (_searchQuery.isEmpty) return const [];
    final now = DateTime.now();
    return _docs.where((d) {
      final m = d.data();
      final exp = (m['expiresAt'] as Timestamp?)?.toDate();
      if (exp != null && !exp.isAfter(now)) return false;
      return ((m['text'] as String?) ?? '')
          .toLowerCase()
          .contains(_searchQuery);
    }).map((d) => d.id).toList();
  }

  /// Maujooda match tak scroll karo
  void _jumpToMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ids = _matchIds();
      if (ids.isEmpty) return;
      final id = ids[_matchIndex.clamp(0, ids.length - 1)];
      final ctx = _keys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
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
                  icon:
                  const Icon(Icons.close, color: AppColors.brown700),
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
      await chatRepo.setChatTheme(_chatId, key == 'default' ? null : key);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Send a message first to change the theme'),
        ),
      );
    }
  }

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
          'All messages will be cleared for you only. The other person will still keep their copy.',
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
      await chatRepo.clearChatForMe(_chatId);
      _deletedAt = await chatRepo.deletedAtFor(_chatId);
      if (!mounted) return;
      setState(() {
        _docs = _docs.where(_afterDelete).toList();
        _pinned = _pinned.where(_afterDelete).toList();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Chat cleared')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not clear chat. Try again.')),
      );
    }
  }

  Future<void> _toggleBlock() async {
    final messenger = ScaffoldMessenger.of(context);
    final block = !_blockedByMe;

    if (block) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: softCardColor,
          title: const Text(
            'Block user?',
            style: TextStyle(
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

    try {
      await chatRepo.setBlocked(_chatId, block);
      messenger.showSnackBar(
        SnackBar(content: Text(block ? 'User blocked' : 'User unblocked')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update block. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_searching && !_msgSelecting && _editingId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_msgSelecting) {
          _clearMsgSelection();
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
              onTap: _msgSelecting ? null : _openContact,
              child: GradientHeader(
                title: _msgSelecting
                    ? '${_selectedDocs.length} selected'
                    : widget.username,
                subtitle: _msgSelecting ? null : _headerStatus,
                titleStyle:
                const TextStyle(fontSize: 18, color: Colors.black),
                showBack: !_msgSelecting,
                leading: _msgSelecting
                    ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: _clearMsgSelection,
                )
                    : UserAvatar(
                  username: widget.username,
                  photoUrl: widget.photoUrl,
                  size: 40,
                ),
                actions: _msgSelecting ? _msgActions() : [_chatMenu()],
              ),
            ),
            if (_searching) _searchField(),
            if (_pinned.isNotEmpty) _pinBar(),
            Expanded(
              child: Container(
                color: _chatBg,
                child: _messages(),
              ),
            ),
            if (!_searching)
              _blockedByMe
                  ? _blockedBar()
                  : _blockedByOther
                  ? _cantSendBar()
                  : _inputBar(),
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

    // Expired messages screen se foran chhupa do
    final now = DateTime.now();
    var msgs = _docs.where((d)  {
      final exp = (d.data()['expiresAt'] as Timestamp?)?.toDate();
      return exp == null || exp.isAfter(now);
    }).toList();



    if (msgs.isEmpty) {
      return EmptyState(
        icon: Icons.waving_hand_outlined,
        title: 'Say hi to ${widget.username}',
        subtitle: 'Send a message to start the chat.',
      );
    }

    final matchIds = _matchIds();
    final currentId = matchIds.isEmpty
        ? null
        : matchIds[_matchIndex.clamp(0, matchIds.length - 1)];

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      cacheExtent: (_searching || _jumping) ? 100000 : null,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: msgs.length,
      itemBuilder: (_, i) {
        final doc = msgs[i];
        final m = doc.data();
        final created = (m['createdAt'] as Timestamp?)?.toDate();
        final older = i + 1 < msgs.length
            ? (msgs[i + 1].data()['createdAt'] as Timestamp?)?.toDate()
            : null;
        final showDate =
            created != null && (older == null || !_sameDay(older, created));

        return Column(
          key: ValueKey(doc.id),
          children: [
            if (showDate) _DateChip(label: _dayLabel(created)),
            if (doc.id == _firstUnreadId) _UnreadBanner(count: _unreadCount),
            if (m['type'] == 'system')
              _DateChip(label: _systemLabel(m))
            else
            KeyedSubtree(
              key: _keys.putIfAbsent(doc.id, () => GlobalKey()),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _toggleMsg(doc.id),
                onTap: _msgSelecting ? () => _toggleMsg(doc.id) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  color: _selectedMsgs.contains(doc.id)
                      ? AppColors.gold400.withValues(alpha: 0.3)
                      : (doc.id == _flashId
                      ? AppColors.gold400.withValues(alpha: 0.45)
                      : AppColors.gold400.withValues(alpha: 0.0)),
                  child: Column(
                    children: [
                      if (_selectedMsgs.length == 1 &&
                          _selectedMsgs.contains(doc.id) &&
                          m['deletedForAll'] != true)
                        Align(
                          alignment: m['senderId'] == _myUid
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: _reactionBar(),
                        ),
                      _SwipeToReply(
                        enabled: !_msgSelecting && m['deletedForAll'] != true,
                        onReply: () => _startReply(doc),
                        child: _Bubble(
                          onImageTap: _openImage,
                          data: m,
                          mine: m['senderId'] == _myUid,
                          pending: doc.metadata.hasPendingWrites || created == null,
                          time: created,
                          expiresAt: (m['expiresAt'] as Timestamp?)?.toDate(),
                          now: now,
                          highlight: _searchQuery,
                          current: doc.id == currentId,
                          replyName: (m['replyTo'] is Map &&
                              (m['replyTo'] as Map)['isStatus'] == true)
                              ? 'Status'
                              : (m['replyTo'] is Map &&
                              (m['replyTo'] as Map)['senderId'] == _myUid)
                              ? 'You'
                              : widget.username,
                          onReplyTap: m['replyTo'] is! Map
                              ? null
                              : (m['replyTo'] as Map)['isStatus'] == true
                              ? () => _openStatusFromReply(
                              (m['replyTo'] as Map)['id'] as String)
                              : () => _jumpToMessage(
                              (m['replyTo'] as Map)['id'] as String),
                        ),
                      ),
                      if (m['reactions'] is Map &&
                          (m['reactions'] as Map).isNotEmpty &&
                          m['deletedForAll'] != true)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Align(
                            alignment: m['senderId'] == _myUid
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: _ReactionPill(
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
                  "You can't send messages to this user",
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

  Widget _blockedBar() {
    return Container(
      color: AppColors.cream,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.block, color: AppColors.brown700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'You blocked this user',
                  style: TextStyle(
                    color: AppColors.brown700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    chatRepo.setBlocked(_chatId, false).catchError((_) {}),
                child: const Text('Unblock'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    final active = _destruct.duration != null;
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
              if (_replyTo != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gold500.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 18, color: AppColors.gold700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _replyTo!['senderId'] == _myUid
                                  ? 'Replying to yourself'
                                  : 'Replying to ${widget.username}',
                              style: const TextStyle(
                                color: AppColors.gold700,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              (_replyTo!['text'] as String?) ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.brown900, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _cancelReply,
                        child: const Icon(Icons.close,
                            size: 18, color: AppColors.brown700),
                      ),
                    ],
                  ),
                ),
              if (_editingId != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gold500.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined,
                          size: 16, color: AppColors.gold700),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Editing message',
                          style: TextStyle(
                            color: AppColors.brown900,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _cancelEdit,
                        child: const Icon(Icons.close,
                            size: 18, color: AppColors.brown700),
                      ),
                    ],
                  ),
                ),
              if (active)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.gold500.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 16, color: AppColors.gold700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Messages disappear after ${_destruct.label}',
                          style: const TextStyle(
                            color: AppColors.brown900,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _destruct = _destructOptions.first),
                        child: const Icon(Icons.close,
                            size: 18, color: AppColors.brown700),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Disappearing messages',
                    onPressed: _pickDestruct,
                    icon: Icon(
                      active ? Icons.timer : Icons.timer_outlined,
                      color: active ? AppColors.gold700 : AppColors.brown700,
                    ),
                  ),
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

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool mine;
  final bool pending;
  final DateTime? time;
  final DateTime? expiresAt;
  final DateTime now;
  final String highlight;
  final bool current;
  final String replyName;
  final VoidCallback? onReplyTap;
  final void Function(String url)? onImageTap;

  const _Bubble({
    required this.data,
    required this.mine,
    required this.pending,
    required this.time,
    required this.expiresAt,
    required this.now,
    this.highlight = '',
    this.current = false,
    this.replyName = '',
    this.onReplyTap,
    this.onImageTap,
  });



  List<TextSpan> _spans(String text) {
    final q = highlight;
    if (q.isEmpty) return [TextSpan(text: text)];
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final i = lower.indexOf(q, start);
      if (i < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (i > start) spans.add(TextSpan(text: text.substring(start, i)));
      spans.add(
        TextSpan(
          text: text.substring(i, i + q.length),
          style: TextStyle(
            backgroundColor: current ? AppColors.gold400 : AppColors.gold200,
            color: AppColors.brown900,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = i + q.length;
    }
    return spans;
  }


  @override
  Widget build(BuildContext context) {
    final text = data['type'] == 'image'
        ? '📷 Photo'
        : ((data['text'] as String?) ?? '');
    final read = data['readAt'] != null;
    final fg = mine ? AppColors.cream : AppColors.brown900;
    final meta =
    mine ? AppColors.cream.withValues(alpha: 0.78) : AppColors.brown700;
    final maxW = MediaQuery.of(context).size.width * 0.78;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? null : softCardColor,
            gradient: mine
                ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gold500, AppColors.gold700],
            )
                : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brown900.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data['forwarded'] == true && data['deletedForAll'] != true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forward, size: 13, color: meta),
                        const SizedBox(width: 4),
                        Text(
                          'Forwarded',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: meta,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (data['replyTo'] is Map && data['deletedForAll'] != true)
                  GestureDetector(
                    onTap: onReplyTap,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    replyName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: mine ? AppColors.cream : AppColors.gold700,
                                    ),
                                  ),
                                  Text(
                                    ((data['replyTo'] as Map)['text'] as String?) ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: meta),
                                  ),
                                ],
                              ),
                            ),
                            if ((((data['replyTo'] as Map)['thumb']) as String?)
                                ?.isNotEmpty ??
                                false) ...[
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: (data['replyTo'] as Map)['thumb'] as String,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                  const SizedBox(width: 42, height: 42),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (data['deletedForAll'] == true)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 15, color: meta),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'This message was deleted',
                          style: TextStyle(
                            color: meta,
                            fontSize: 14.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  if (data['type'] == 'image' && data['imageUrl'] is String)
                    GestureDetector(
                      onTap: () => onImageTap?.call(data['imageUrl'] as String),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: (data['width'] is num &&
                              data['height'] is num &&
                              (data['height'] as num) > 0)
                              ? (data['width'] as num) / (data['height'] as num)
                              : 1,
                          child: CachedNetworkImage(
                            imageUrl: data['imageUrl'] as String,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  if (text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                          top: data['type'] == 'image' ? 6 : 0),
                      child: Text.rich(
                        TextSpan(children: _spans(text)),
                        style:
                        TextStyle(color: fg, fontSize: 15.5, height: 1.3),
                      ),
                    ),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (expiresAt != null) ...[
                        Icon(Icons.timer_outlined, size: 12, color: meta),
                        const SizedBox(width: 2),
                        Text(
                          _remaining(expiresAt!, now),
                          style: TextStyle(fontSize: 11, color: meta),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (data['pinned'] == true &&
                          data['deletedForAll'] != true) ...[
                        Icon(Icons.push_pin, size: 12, color: meta),
                        const SizedBox(width: 4),
                      ],
                      if (data['edited'] == true &&
                          data['deletedForAll'] != true) ...[
                        Text(
                          'edited',
                          style: TextStyle(
                            fontSize: 11,
                            color: meta,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        _hhmm(time),
                        style: TextStyle(fontSize: 11, color: meta),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          pending
                              ? Icons.access_time
                              : (read ? Icons.done_all : Icons.done),
                          size: 14,
                          color: read && !pending ? Colors.white : meta,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  const _SwipeToReply({
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _trigger = 60.0;
  static const _maxDrag = 80.0;

  late final AnimationController _ctrl;
  Animation<double>? _anim;
  double _dx = 0;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
      final a = _anim;
      if (a != null) setState(() => _dx = a.value);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    _ctrl.stop();
    final next = (_dx + d.delta.dx).clamp(0.0, _maxDrag);
    if (!_fired && next >= _trigger) {
      _fired = true;
      HapticFeedback.lightImpact();
    }
    setState(() => _dx = next);
  }

  void _onEnd() {
    if (_fired) widget.onReply();
    _fired = false;
    _anim = Tween<double>(begin: _dx, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: (_) => _onEnd(),
      onHorizontalDragCancel: _onEnd,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: p,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * p,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold500.withValues(alpha: 0.25),
                    ),
                    child: const Icon(Icons.reply,
                        size: 18, color: AppColors.brown700),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  final Map reactions;
  final String myUid;
  const _ReactionPill({required this.reactions, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final e in reactions.values) {
      if (e is String) counts[e] = (counts[e] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final emojis = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final iReacted = reactions[myUid] is String;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: softCardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iReacted ? AppColors.gold700 : AppColors.gold200,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brown900.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emojis.take(3).map((e) => e.key).join(),
            style: const TextStyle(fontSize: 14),
          ),
          if (total > 1) ...[
            const SizedBox(width: 4),
            Text(
              '$total',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.brown700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnreadBanner extends StatelessWidget {
  final int count;
  const _UnreadBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      color: AppColors.gold500.withValues(alpha: 0.2),
      child: Text(
        count == 1 ? '1 UNREAD MESSAGE' : '$count UNREAD MESSAGES',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: AppColors.brown700,
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.gold500.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.brown700,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');

String _hhmm(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  return '$h:${_two(t.minute)} $suffix';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_two(t.day)}/${_two(t.month)}/${t.year}';
}

String _remaining(DateTime exp, DateTime now) {
  final s = exp.difference(now).inSeconds;
  if (s < 60) return '${s < 0 ? 0 : s}s';
  if (s < 3600) return '${(s / 60).ceil()}m';
  if (s < 86400) return '${(s / 3600).ceil()}h';
  return '${(s / 86400).ceil()}d';
}
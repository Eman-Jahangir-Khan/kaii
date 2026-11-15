import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../chat_repository.dart';
import '../status_repository.dart';
import '../theme.dart';
import '../widgets.dart';

const _imageSeconds = 5;

DateTime _timeOf(StatusItem i) =>
    i.createdAt ?? i.expiresAt.subtract(statusLifetime);

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  final h = d.inHours;
  return '$h ${h == 1 ? 'hour' : 'hours'} ago';
}

/// Ek contact (ya apne) ke statuses ek ke baad ek full screen mein
class StatusViewerScreen extends StatefulWidget {
  /// Pehla = jis se shuru karna hai, baaqi us ke baad khud chalte hain
  final List<String> ownerIds;
  final Map<String, List<StatusItem>> groups;
  final bool isMine;

  const StatusViewerScreen({
    super.key,
    required this.ownerIds,
    required this.groups,
    required this.isMine,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  final String _me = FirebaseAuth.instance.currentUser!.uid;
  late final AnimationController _anim = AnimationController(vsync: this);
  late final List<String> _queue = widget.ownerIds;
  late Map<String, List<StatusItem>> _byOwner;
  late String _ownerId;
  int _ownerIdx = 0;
  late List<StatusItem> _items;
  StreamSubscription<List<StatusItem>>? _sub;
  VideoPlayerController? _video;

  int _index = 0;
  int _token = 0; // purane async kaam ko ignore karne ke liye
  bool _ready = false; // media tayar, progress chal sakta hai
  bool _paused = false;
  final Set<String> _marked = {};
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _sendingReply = false;

  @override
  void initState() {
    super.initState();
    _byOwner = {
      for (final e in widget.groups.entries)
        e.key: [...e.value]..sort((a, b) => _timeOf(a).compareTo(_timeOf(b))),
    };
    _ownerId = _queue.first;
    _items = _byOwner[_ownerId] ?? [];

    // dusron ka status: pehla na dekha hua; apna: pehla
    if (!widget.isMine) {
      final firstUnseen = _items.indexWhere((i) => !i.viewedByMe(_me));
      _index = firstUnseen < 0 ? 0 : firstUnseen;
    }

    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });

    // reply likhte waqt status ruk jaye, baad mein dobara chale
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _pause();
      } else {
        _resume();
      }
    });

    // likes / views live update hote rahen
    final source = widget.isMine ? statusRepo.myStream() : statusRepo.feedStream();
    _sub = source.listen(_onUpdate, onError: (e) {
      debugPrint('viewer stream error: $e');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(_index);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _anim.dispose();
    _video?.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _onUpdate(List<StatusItem> all) {
    if (!mounted) return;
    // sab owners ka data update (merge), taake agla contact bhi taaza rahe
    final map = <String, List<StatusItem>>{};
    for (final i in all) {
      map.putIfAbsent(i.ownerId, () => []).add(i);
    }
    for (final e in map.entries) {
      e.value.sort((a, b) => _timeOf(a).compareTo(_timeOf(b)));
      _byOwner[e.key] = e.value;
    }

    final list = map[_ownerId];
    if (list == null || list.isEmpty) return;

    final curId = _items[_index].id;
    final idx = list.indexWhere((i) => i.id == curId);
    if (idx >= 0) {
      setState(() {
        _items = list;
        _index = idx;
      });
    } else {
      // jo status chal raha tha wo delete ho gaya
      _items = list;
      _load(math.min(_index, list.length - 1));
    }
  }

  // ---------------- playback ----------------

  Future<void> _load(int i) async {
    final token = ++_token;
    _anim.stop();
    _anim.value = 0;

    final old = _video;
    setState(() {
      _index = i;
      _ready = false;
      _video = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());

    final item = _items[i];

    if (!widget.isMine && !item.viewedByMe(_me) && _marked.add(item.id)) {
      statusRepo.markViewed(item.id).catchError((Object e) {
        debugPrint('markViewed error: $e');
      });
    }

    if (!item.isVideo) {
      try {
        await precacheImage(CachedNetworkImageProvider(item.mediaUrl), context);
      } catch (_) {}
      if (!mounted || token != _token) return;
      _anim.duration = const Duration(seconds: _imageSeconds);
      setState(() => _ready = true);
      if (!_paused) _anim.forward(from: 0);
      return;
    }

    final c = VideoPlayerController.networkUrl(Uri.parse(item.mediaUrl));
    try {
      await c.initialize();
    } catch (e) {
      debugPrint('viewer video error: $e');
      c.dispose();
      if (mounted && token == _token) _next();
      return;
    }
    if (!mounted || token != _token) {
      c.dispose();
      return;
    }
    await c.setLooping(false);
    _video = c;
    final d = c.value.duration;
    _anim.duration = d > Duration.zero ? d : const Duration(seconds: _imageSeconds);
    setState(() => _ready = true);
    if (!_paused) {
      c.play();
      _anim.forward(from: 0);
    }
  }

  void _next() {
    if (!mounted) return;
    if (_index < _items.length - 1) {
      _load(_index + 1);
    } else {
      _nextOwner();
    }
  }

  void _prev() {
    if (_index > 0) {
      _load(_index - 1);
    } else {
      _prevOwner();
    }
  }

  void _switchOwner(int idx, int startIndex) {
    _ownerIdx = idx;
    _ownerId = _queue[idx];
    _items = _byOwner[_ownerId]!;
    _load(startIndex);
  }

  /// Is contact ke statuses khatam: agle contact ke (na dekhe hue se) shuru
  void _nextOwner() {
    for (var i = _ownerIdx + 1; i < _queue.length; i++) {
      final list = _byOwner[_queue[i]];
      if (list != null && list.isNotEmpty) {
        final firstUnseen = list.indexWhere((x) => !x.viewedByMe(_me));
        _switchOwner(i, firstUnseen < 0 ? 0 : firstUnseen);
        return;
      }
    }
    Navigator.of(context).maybePop();
  }

  /// Pehle status par left tap: pichle contact ka aakhri status
  void _prevOwner() {
    for (var i = _ownerIdx - 1; i >= 0; i--) {
      final list = _byOwner[_queue[i]];
      if (list != null && list.isNotEmpty) {
        _switchOwner(i, list.length - 1);
        return;
      }
    }
    _load(0);
  }

  void _pause() {
    _paused = true;
    _anim.stop();
    _video?.pause();
  }

  void _resume() {
    _paused = false;
    if (_ready) {
      _anim.forward();
      _video?.play();
    }
  }

  Future<void> _openSheet(WidgetBuilder builder) async {
    _pause();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: builder,
    );
    if (mounted) _resume();
  }

  void _openSeenBy(StatusItem item) =>
      _openSheet((_) => _SeenBySheet(item: item));

  /// Chat mein quote ke liye chhota thumbnail (Cloudinary transformation)
  String _thumbOf(StatusItem i) {
    var url = i.mediaUrl.replaceFirst('/upload/', '/upload/w_160,h_160,c_fill/');
    if (i.isVideo) url = url.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '.jpg');
    return url;
  }

  /// Status ka reply status ke malik ko chat (inbox) mein jata hai
  Future<void> _sendReply(StatusItem item) async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sendingReply) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sendingReply = true);
    try {
      await chatRepo.sendMessage(
        otherUid: _ownerId,
        text: text,
        replyTo: {
          'id': item.id,
          'text': item.caption.isNotEmpty
              ? item.caption
              : (item.isVideo ? '🎥 Video' : '📷 Photo'),
          'senderId': _ownerId,
          'isStatus': true,
          'thumb': _thumbOf(item),
        },
      );
      _replyCtrl.clear();
      _replyFocus.unfocus();
      messenger.showSnackBar(const SnackBar(content: Text('Reply sent')));
    } catch (e) {
      debugPrint('status reply error: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send reply.')),
      );
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Future<void> _delete(StatusItem item) async {
    _pause();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        title: const Text('Delete status?'),
        content: const Text('This status will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      _resume();
      return;
    }
    try {
      final last = _items.length == 1;
      await statusRepo.delete(item.id);
      if (!mounted) return;
      if (last) {
        Navigator.of(context).maybePop();
      } else {
        _paused = false; // stream naye status par le jayegi
      }
    } catch (e) {
      debugPrint('delete status error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete status.')),
      );
      _resume();
    }
  }

  // ---------------- UI ----------------

  Widget _media(StatusItem item) {
    if (!_ready) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold400),
      );
    }
    if (item.isVideo) {
      final v = _video;
      if (v == null) return const SizedBox.shrink();
      return Center(
        child: AspectRatio(
          aspectRatio: v.value.aspectRatio,
          child: VideoPlayer(v),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: item.mediaUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white54, size: 48),
      ),
    );
  }

  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          return Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        value: i < _index
                            ? 1
                            : i == _index
                            ? _anim.value
                            : 0,
                        backgroundColor: Colors.white24,
                        valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(StatusItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          _UserBuilder(
            uid: _ownerId,
            builder: (context, username, photo) {
              return Row(
                children: [
                  UserAvatar(username: username, photoUrl: photo, size: 36),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isMine ? 'My status' : username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _ago(_timeOf(item)),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text, VoidCallback onTap,
      {Color color = Colors.white}) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            if (text.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(StatusItem item) {
    if (widget.isMine) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            _pill(Icons.visibility_outlined, '${item.viewedBy.length}',
                    () => _openSeenBy(item)),
            const Spacer(),
            _pill(Icons.delete_outline, '', () => _delete(item)),
          ],
        ),
      );
    }

    final liked = item.likedBy(_me);
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: c),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _replyCtrl,
              focusNode: _replyFocus,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Reply...',
                hintStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.black38,
                isDense: true,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: border(Colors.white38),
                enabledBorder: border(Colors.white38),
                focusedBorder: border(Colors.white70),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _replyCtrl,
            builder: (context, v, _) {
              final hasText = v.text.trim().isNotEmpty;
              return hasText
                  ? _pill(Icons.send_rounded, '', () => _sendReply(item),
                  color: AppColors.gold400)
                  : _pill(
                liked ? Icons.favorite : Icons.favorite_border,
                '',
                    () => statusRepo.setLike(item.id, !liked),
                color: liked ? Colors.redAccent : Colors.white,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _scrim({required bool top}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Container(
          height: top ? 140 : 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [Colors.black54, Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _items[_index];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (_replyFocus.hasFocus) {
                  _replyFocus.unfocus();
                  return;
                }
                final w = MediaQuery.of(context).size.width;
                d.localPosition.dx < w / 3 ? _prev() : _next();
              },
              onLongPressStart: (_) => _pause(),
              onLongPressEnd: (_) => _resume(),
              child: _media(item),
            ),
            _scrim(top: true),
            _scrim(top: false),
            SafeArea(
              child: Column(
                children: [
                  _progress(),
                  _header(item),
                  const Spacer(),
                  if (item.caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        item.caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.3,
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: _bottomBar(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seen by (sirf apne status par)
// ---------------------------------------------------------------------------

class _SeenBySheet extends StatelessWidget {
  final StatusItem item;
  const _SeenBySheet({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: statusRepo.viewsStream(item.id),
        builder: (context, snap) {
          if (snap.hasError) debugPrint('views error: ${snap.error}');
          final docs = [...(snap.data?.docs ?? const [])];
          docs.sort((a, b) {
            final ta = (a.data()['viewedAt'] as Timestamp?)?.toDate();
            final tb = (b.data()['viewedAt'] as Timestamp?)?.toDate();
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Viewed by ${docs.length}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brown900,
                        ),
                      ),
                    ),
                    const Icon(Icons.favorite,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${item.likes.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brown900,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? const Center(
                  child: Text('No views yet',
                      style: TextStyle(color: AppColors.brown700)),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final time =
                    (d.data()['viewedAt'] as Timestamp?)?.toDate();
                    return _UserBuilder(
                      uid: d.id,
                      builder: (context, username, photo) => ListTile(
                        leading: UserAvatar(
                            username: username, photoUrl: photo, size: 40),
                        title: Text(
                          username,
                          style: const TextStyle(
                            color: AppColors.brown900,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          _ago(time),
                          style:
                          const TextStyle(color: AppColors.brown700),
                        ),
                        trailing: item.likes.contains(d.id)
                            ? const Icon(Icons.favorite,
                            color: Colors.redAccent)
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// uid se username + photo la kar builder ko deta hai (cache pehle)
class _UserBuilder extends StatefulWidget {
  final String uid;
  final Widget Function(BuildContext context, String username, String photoUrl)
  builder;
  const _UserBuilder({required this.uid, required this.builder});

  @override
  State<_UserBuilder> createState() => _UserBuilderState();
}

class _UserBuilderState extends State<_UserBuilder> {
  late Future<Map<String, dynamic>?> _future = chatRepo.getUser(widget.uid);

  @override
  void didUpdateWidget(covariant _UserBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // uid badle (agla contact) to naya user load ho
    if (oldWidget.uid != widget.uid) {
      _future = chatRepo.getUser(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey(widget.uid), // purana naam/photo na bachay
      future: _future,
      initialData: chatRepo.cachedUser(widget.uid),
      builder: (context, snap) {
        final user = snap.data;
        final username = (user?['username'] as String?) ??
            (snap.connectionState == ConnectionState.done
                ? 'Unknown user'
                : '...');
        final photo = (user?['photoUrl'] as String?) ?? '';
        return widget.builder(context, username, photo);
      },
    );
  }
}
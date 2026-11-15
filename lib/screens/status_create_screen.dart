import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../chat_repository.dart';
import '../cloudinary_service.dart';
import '../status_repository.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Vis { contacts, only, except }

const _maxVideoSeconds = 30;

Widget _sheetTile(BuildContext ctx, IconData icon, String label, String value) {
  return ListTile(
    leading: Icon(icon, color: AppColors.gold700),
    title: Text(
      label,
      style: const TextStyle(
        color: AppColors.brown900,
        fontWeight: FontWeight.w700,
      ),
    ),
    onTap: () => Navigator.pop(ctx, value),
  );
}

/// Status tab ke + button se call karo:
/// pehle media chuno (photo / video), phir create screen khulti hai.
Future<void> startNewStatus(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _sheetTile(ctx, Icons.photo_library_outlined, 'Photo from gallery',
              'photo_gallery'),
          _sheetTile(
              ctx, Icons.photo_camera_outlined, 'Take a photo', 'photo_camera'),
          _sheetTile(ctx, Icons.video_library_outlined, 'Video from gallery',
              'video_gallery'),
          _sheetTile(
              ctx, Icons.videocam_outlined, 'Record a video', 'video_camera'),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final isVideo = choice.startsWith('video');
  final source =
  choice.endsWith('camera') ? ImageSource.camera : ImageSource.gallery;

  XFile? picked;
  try {
    final picker = ImagePicker();
    picked = isVideo
        ? await picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: _maxVideoSeconds),
    )
        : await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
  } catch (e) {
    debugPrint('startNewStatus pick error: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the picker.')),
      );
    }
    return;
  }
  if (picked == null || !context.mounted) return;

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          CreateStatusScreen(file: File(picked!.path), isVideo: isVideo),
    ),
  );
}

class CreateStatusScreen extends StatefulWidget {
  final File file;
  final bool isVideo;
  const CreateStatusScreen({
    super.key,
    required this.file,
    required this.isVideo,
  });

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final _caption = TextEditingController();
  VideoPlayerController? _video;
  bool _tooLong = false;
  bool _loading = false;

  _Vis _vis = _Vis.contacts;
  List<Map<String, String>> _contacts = [];
  bool _contactsReady = false;
  Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
    _loadContacts();
  }

  @override
  void dispose() {
    _caption.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(widget.file);
    _video = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.play();
      if (!mounted) return;
      setState(() {
        // gallery se chuni hui video maxDuration se lambi ho sakti hai
        _tooLong = c.value.duration > const Duration(seconds: _maxVideoSeconds + 1);
      });
    } catch (e) {
      debugPrint('video init error: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadContacts() async {
    try {
      final uids = await statusRepo.contactUids();
      final users = await Future.wait(uids.map((u) async {
        final d = await chatRepo.getUser(u);
        return <String, String>{
          'uid': u,
          'username': (d?['username'] as String?) ?? 'user',
          'photoUrl': (d?['photoUrl'] as String?) ?? '',
        };
      }));
      users.sort((a, b) => a['username']!.compareTo(b['username']!));
      if (!mounted) return;
      setState(() {
        _contacts = users;
        _contactsReady = true;
      });
    } catch (e) {
      debugPrint('load contacts error: $e');
      if (mounted) setState(() => _contactsReady = true);
    }
  }

  Future<void> _chooseContacts() async {
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ContactPicker(
        contacts: _contacts,
        initial: _picked,
        title: _vis == _Vis.only ? 'Share with' : 'Hide from',
      ),
    );
    if (res != null && mounted) setState(() => _picked = res);
  }

  Future<void> _post() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    if (_contacts.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add some contacts first.')),
      );
      return;
    }
    if (_vis != _Vis.contacts && _picked.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Choose at least one contact.')),
      );
      return;
    }

    final all = _contacts.map((c) => c['uid']!).toList();
    final List<String> visibleTo;
    switch (_vis) {
      case _Vis.contacts:
        visibleTo = all;
      case _Vis.only:
        visibleTo = all.where(_picked.contains).toList();
      case _Vis.except:
        visibleTo = all.where((u) => !_picked.contains(u)).toList();
    }
    if (visibleTo.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nobody would be able to see this status.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final up = widget.isVideo
          ? await cloudinary.uploadVideo(widget.file)
          : await cloudinary.uploadImage(widget.file);

      await statusRepo.post(
        mediaUrl: up['url'] as String,
        mediaType: widget.isVideo ? 'video' : 'image',
        visibleTo: visibleTo,
        caption: _caption.text,
        width: (up['width'] as num?)?.toInt(),
        height: (up['height'] as num?)?.toInt(),
      );

      nav.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Status posted')),
      );
    } catch (e, st) {
      debugPrint('post status error: $e\n$st');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not post status. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _preview() {
    Widget content;
    if (!widget.isVideo) {
      content = Image.file(widget.file, fit: BoxFit.contain);
    } else {
      final v = _video;
      if (v != null && v.value.isInitialized) {
        content = GestureDetector(
          onTap: () => setState(() {
            v.value.isPlaying ? v.pause() : v.play();
          }),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: v.value.aspectRatio,
                child: VideoPlayer(v),
              ),
              if (!v.value.isPlaying)
                const Icon(Icons.play_circle_fill_rounded,
                    size: 64, color: Colors.white70),
            ],
          ),
        );
      } else {
        content = const CircularProgressIndicator(color: AppColors.gold400);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 380,
        width: double.infinity,
        color: Colors.black,
        alignment: Alignment.center,
        child: content,
      ),
    );
  }

  Widget _visTile(_Vis v, String title, String subtitle) {
    final selected = _vis == v;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => setState(() => _vis = v),
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        color: selected ? AppColors.gold700 : AppColors.brown700,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.brown900,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.brown700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPost = !_loading && !_tooLong && _contactsReady;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(title: 'New status', showBack: true),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _preview(),
                if (_tooLong)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Video must be $_maxVideoSeconds seconds or shorter.',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _caption,
                  maxLines: 2,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: AppColors.brown900),
                  decoration: InputDecoration(
                    hintText: 'Add a caption...',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Who can see this?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brown900,
                  ),
                ),
                const SizedBox(height: 4),
                _visTile(_Vis.contacts, 'My contacts',
                    'Everyone you have added'),
                _visTile(_Vis.only, 'Only share with...',
                    'Pick the contacts who can see it'),
                _visTile(_Vis.except, 'My contacts except...',
                    'Hide it from some contacts'),
                if (_vis != _Vis.contacts)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: OutlinedButton.icon(
                      onPressed: _contacts.isEmpty ? null : _chooseContacts,
                      icon: const Icon(Icons.people_alt_outlined),
                      label: Text(
                        _picked.isEmpty
                            ? 'Choose contacts'
                            : 'Choose contacts (${_picked.length})',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gold700,
                        side: const BorderSide(color: AppColors.gold700),
                      ),
                    ),
                  ),
                if (_contactsReady && _contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'You have no contacts yet. Add someone from Chats first.',
                      style: TextStyle(color: AppColors.brown700),
                    ),
                  ),
                const SizedBox(height: 20),
                PillButton(
                  label: 'Post status',
                  loading: _loading,
                  onPressed: canPost ? _post : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contacts ki checklist (bottom sheet)
class _ContactPicker extends StatefulWidget {
  final List<Map<String, String>> contacts;
  final Set<String> initial;
  final String title;
  const _ContactPicker({
    required this.contacts,
    required this.initial,
    required this.title,
  });

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  late final Set<String> _sel = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brown900,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.contacts.length,
                itemBuilder: (_, i) {
                  final c = widget.contacts[i];
                  final uid = c['uid']!;
                  return CheckboxListTile(
                    activeColor: AppColors.gold700,
                    value: _sel.contains(uid),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _sel.add(uid);
                      } else {
                        _sel.remove(uid);
                      }
                    }),
                    secondary: UserAvatar(
                      username: c['username']!,
                      photoUrl: c['photoUrl']!,
                      size: 40,
                    ),
                    title: Text(
                      c['username']!,
                      style: const TextStyle(
                        color: AppColors.brown900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: PillButton(
                label: 'Done (${_sel.length})',
                onPressed: () => Navigator.pop(context, _sel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
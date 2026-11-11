import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../cloudinary_service.dart';
import '../group_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _contacts = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _failed = false;
  bool _creating = false;
  XFile? _photo;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final c = await groupRepo.loadContacts();
      if (!mounted) return;
      setState(() {
        _contacts = c;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final p = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (p != null && mounted) setState(() => _photo = p);
  }

  bool get _canCreate =>
      !_creating && _name.text.trim().isNotEmpty && _selected.isNotEmpty;

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _creating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var photoUrl = '';
      if (_photo != null) {
        final r = await cloudinary.uploadImage(File(_photo!.path));
        photoUrl = r['url'] as String;
      }
      final name = _name.text.trim();
      final id = await groupRepo.createGroup(
        name: name,
        photoUrl: photoUrl,
        memberUids: _selected.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            groupId: id,
            name: name,
            photoUrl: photoUrl,
          ),
        ),
      );
    } catch (e) {
      debugPrint('CREATE GROUP ERROR: $e');
      if (!mounted) return;
      setState(() => _creating = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create group. Try again.')),
      );
    }
  }

  Widget _photoPicker() {
    return GestureDetector(
      onTap: _creating ? null : _pickPhoto,
      child: Stack(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.gold500.withValues(alpha: 0.2),
              image: _photo == null
                  ? null
                  : DecorationImage(
                image: FileImage(File(_photo!.path)),
                fit: BoxFit.cover,
              ),
            ),
            child: _photo == null
                ? const Icon(Icons.groups_rounded,
                size: 30, color: AppColors.gold700)
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.gold700,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt,
                  size: 13, color: AppColors.cream),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactList() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold700),
      );
    }
    if (_failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load contacts',
        subtitle: 'Check your internet and try again.',
      );
    }
    if (_contacts.isEmpty) {
      return const EmptyState(
        icon: Icons.person_add_alt_outlined,
        title: 'No contacts yet',
        subtitle: 'Start a chat with someone first, then add them to a group.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      itemCount: _contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final u = _contacts[i];
        final uid = u['uid'] as String;
        final username = (u['username'] as String?) ?? '';
        final name = (u['name'] as String?) ?? '';
        final on = _selected.contains(uid);
        return Container(
          decoration: BoxDecoration(
            color: softCardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? AppColors.gold700 : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _creating
                  ? null
                  : () => setState(() {
                on ? _selected.remove(uid) : _selected.add(uid);
              }),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    UserAvatar(
                      username: username,
                      photoUrl: (u['photoUrl'] as String?) ?? '',
                      size: 44,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brown900,
                            ),
                          ),
                          if (name.isNotEmpty)
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                              const TextStyle(color: AppColors.brown700),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      on ? Icons.check_circle : Icons.circle_outlined,
                      color: on ? AppColors.gold700 : AppColors.brown700,
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
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          GradientHeader(
            title: 'New group',
            showBack: true,
            subtitle: _selected.isEmpty
                ? 'Select members'
                : '${_selected.length} selected',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _photoPicker(),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: softCardColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: _name,
                      enabled: !_creating,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.words,
                      cursorColor: AppColors.gold700,
                      style: const TextStyle(
                        color: AppColors.brown900,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Group name',
                        counterText: '',
                        hintStyle: TextStyle(
                          color: AppColors.brown700.withValues(alpha: 0.7),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _contactList()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: PillButton(
                label: 'Create group',
                loading: _creating,
                onPressed: _canCreate ? _create : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
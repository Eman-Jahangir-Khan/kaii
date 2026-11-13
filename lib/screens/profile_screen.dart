import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_repository.dart';
import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import '../cloudinary_service.dart';
import '../image_helper.dart';
import '../photo_viewer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  late final String _uid = _user?.uid ?? '';
  late final Future<Map<String, dynamic>?> _future = chatRepo.getUser(_uid);

  bool? _showPresence; // null = Firestore ki value use hogi
  String? _photoOverride; // nayi photo ('' = hata di gayi)
  bool _uploading = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changePhoto(ImageSource source) async {
    final path = await pickSquareImage(source: source);
    if (path == null) return;
    setState(() => _uploading = true);
    try {
      final r = await cloudinary.uploadImage(File(path));
      final url = r['url'] as String;
      await chatRepo.setMyPhoto(url);
      if (mounted) setState(() => _photoOverride = url);
    } catch (e) {
      debugPrint('PROFILE PHOTO ERROR: $e');
      _snack('Could not update photo. Try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _uploading = true);
    try {
      await chatRepo.setMyPhoto('');
      if (mounted) setState(() => _photoOverride = '');
    } catch (_) {
      _snack('Could not remove photo. Try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _photoSheet(bool hasPhoto) {
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
                _changePhoto(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _changePhoto(ImageSource.camera);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePresence(bool show) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _showPresence = show);
    try {
      await chatRepo.setHidePresence(!show);
    } catch (_) {
      if (!mounted) return;
      setState(() => _showPresence = !show);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update. Try again.')),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        title: const Text(
          'Log out?',
          style: TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'You will need to sign in again.',
          style: TextStyle(color: AppColors.brown700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.brown700),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log out',
              style: TextStyle(
                color: AppColors.gold700,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) authRepo.logout();
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(title: 'Profile'),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _future,
              initialData: chatRepo.cachedUser(_uid),
              builder: (context, snap) {
                final data = snap.data;
                final loading =
                    snap.connectionState != ConnectionState.done &&
                        data == null;
                final username = (data?['username'] as String?) ?? '';
                final name = (data?['name'] as String?) ?? '';
                final photo =
                    _photoOverride ?? ((data?['photoUrl'] as String?) ?? '');
                final shownName = name.isNotEmpty ? name : username;
                final showPresence =
                    _showPresence ?? (data?['hidePresence'] != true);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: photo.isEmpty
                                ? null
                                : () => openFullPhoto(
                              context,
                              title: shownName,
                              photoUrl: photo,
                            ),
                            child: UserAvatar(
                              username: shownName,
                              photoUrl: photo,
                              size: 110,
                            ),
                          ),
                          if (_uploading)
                            Positioned.fill(
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black38,
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.cream,
                                    strokeWidth: 3,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onTap: (_uploading || loading)
                                  ? null
                                  : () => _photoSheet(photo.isNotEmpty),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: AppColors.gold700,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt,
                                    size: 18, color: AppColors.cream),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        loading
                            ? '...'
                            : (shownName.isEmpty ? 'Unknown' : shownName),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brown900,
                        ),
                      ),
                    ),
                    if (username.isNotEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '@$username',
                            style: const TextStyle(color: AppColors.brown700),
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'SIGNED IN AS',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold700,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: softCardColor,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brown900.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.alternate_email,
                            label: 'Username',
                            value: username.isEmpty ? '-' : username,
                          ),
                          _divider(),
                          _InfoRow(
                            icon: Icons.person_outline,
                            label: 'Name',
                            value: name.isEmpty ? '-' : name,
                          ),
                          _divider(),
                          _InfoRow(
                            icon: Icons.mail_outline,
                            label: 'Email',
                            value: email.isEmpty ? '-' : email,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: softCardColor,
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
                        child: SwitchListTile(
                          value: showPresence,
                          onChanged: loading ? null : _togglePresence,
                          secondary: const Icon(Icons.visibility_outlined,
                              color: AppColors.gold700),
                          title: const Text(
                            'Online status & last seen',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brown900,
                            ),
                          ),
                          subtitle: const Text(
                            "When off, others can't see if you're online or when you were last seen.",
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.brown700,
                            ),
                          ),
                          thumbColor: WidgetStateProperty.resolveWith(
                                (s) => s.contains(WidgetState.selected)
                                ? AppColors.cream
                                : AppColors.brown700,
                          ),
                          trackColor: WidgetStateProperty.resolveWith(
                                (s) => s.contains(WidgetState.selected)
                                ? AppColors.gold700
                                : AppColors.gold200,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Log out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brown900,
                        side: const BorderSide(
                          color: AppColors.gold700,
                          width: 1.5,
                        ),
                        shape: const StadiumBorder(),
                        minimumSize: const Size.fromHeight(52),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
    height: 1,
    thickness: 1,
    indent: 50,
    color: AppColors.gold700.withValues(alpha: 0.2),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold700, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.brown700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brown900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
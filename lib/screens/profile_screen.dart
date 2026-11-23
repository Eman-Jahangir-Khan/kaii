import 'dart:io';
import 'dart:async';

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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

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
  String? _nameOverride; // naya naam (nickname)
  String? _usernameOverride;
  DateTime? _usernameChangedOverride; // abhi badla to cooldown foran lag jaye
  bool _savingUsername = false;
  bool _savingName = false;

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

  Future<void> _editUsername(String current, DateTime? changedAt) async {
    if (_savingUsername) return;

    // 7 din ka gap
    if (changedAt != null) {
      final allowedAt = changedAt.add(AuthRepository.usernameCooldown);
      if (DateTime.now().isBefore(allowedAt)) {
        _snack(UsernameCooldownException(allowedAt).toString());
        return;
      }
    }

    final c = TextEditingController(text: current);
    String? error;
    String status = 'idle'; // idle | checking | available | unavailable
    Timer? debounce;
    bool closed = false;

    Widget statusWidget() {
      switch (status) {
        case 'checking':
          return const Row(children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Checking...'),
          ]);
        case 'available':
          return const Row(children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 6),
            Text('Available',
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w700)),
          ]);
        case 'unavailable':
          return const Row(children: [
            Icon(Icons.cancel, size: 16, color: Colors.red),
            SizedBox(width: 6),
            Text('Unavailable',
                style:
                TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ]);
        default:
          return const Text('6-20 characters: small letters, numbers, _ and .');
      }
    }

    void onChanged(String raw, StateSetter setD) {
      debounce?.cancel();
      final v = raw.trim().toLowerCase();
      error = null;
      // apna hi username ya abhi adhoora/ghalat format: check nahi karna
      if (v == current || validateUsername(v) != null) {
        setD(() => status = 'idle');
        return;
      }
      setD(() => status = 'checking');
      debounce = Timer(const Duration(milliseconds: 500), () async {
        bool free;
        try {
          free = await authRepo.isUsernameAvailable(v);
        } catch (_) {
          if (!closed) setD(() => status = 'idle');
          return;
        }
        if (closed || c.text.trim().toLowerCase() != v) return;
        setD(() => status = free ? 'available' : 'unavailable');
      });
    }

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.cream,
          title: const Text(
            'Change username',
            style: TextStyle(
              color: AppColors.brown900,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                maxLength: 20,
                onChanged: (t) => onChanged(t, setD),
                inputFormatters: [
                  TextInputFormatter.withFunction(
                        (oldValue, newValue) =>
                        newValue.copyWith(text: newValue.text.toLowerCase()),
                  ),
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_.]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                decoration: InputDecoration(
                  prefixText: '@',
                  errorText: error,
                  helper: statusWidget(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can change your username only once every 7 days.',
                style: TextStyle(fontSize: 12.5, color: AppColors.brown700),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                closed = true;
                debounce?.cancel();
                Navigator.pop(ctx);
              },
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.brown700)),
            ),
            TextButton(
              onPressed: () async {
                final v = c.text.trim().toLowerCase();
                final err = validateUsername(v) ??
                    (v == current ? 'This is already your username' : null);
                if (err != null) {
                  setD(() => error = err);
                  return;
                }
                // abhi tak check nahi hua (ya jaldi dabaya) to pehle check
                if (status != 'available') {
                  debounce?.cancel();
                  setD(() => status = 'checking');
                  bool free;
                  try {
                    free = await authRepo.isUsernameAvailable(v);
                  } catch (_) {
                    free = true; // aakhri faisla transaction karega
                  }
                  if (closed) return;
                  if (!free) {
                    setD(() => status = 'unavailable');
                    return;
                  }
                }
                closed = true;
                debounce?.cancel();
                if (ctx.mounted) Navigator.pop(ctx, v);
              },
              child: const Text('Next',
                  style: TextStyle(
                      color: AppColors.gold700, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    closed = true;
    debounce?.cancel();
    if (newName == null || !mounted) return;

    // strict rule hai, isliye ek baar confirm
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        title: Text(
          'Change to @$newName?',
          style: const TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: const Text(
          'You will not be able to change your username again for 7 days. '
              'Your old username becomes available to other people.',
          style: TextStyle(color: AppColors.brown700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.brown700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Change',
                style: TextStyle(
                    color: AppColors.gold700, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _savingUsername = true);
    try {
      await authRepo.changeUsername(newName);
      chatRepo.patchCachedUser(_uid, {'username': newName});
      if (mounted) {
        setState(() {
          _usernameOverride = newName;
          _usernameChangedOverride = DateTime.now();
        });
      }
      _snack('Username updated.');
    } catch (e) {
      debugPrint('USERNAME ERROR: $e');
      _snack(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _savingUsername = false);
    }
  }

  Future<void> _editName(String current) async {
    if (_savingName) return;
    final c = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        title: const Text(
          'Edit name',
          style: TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.brown700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save',
                style: TextStyle(
                    color: AppColors.gold700, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (newName == null || newName == current) return;

    setState(() => _savingName = true);
    try {
      await chatRepo.setMyName(newName);
      if (mounted) setState(() => _nameOverride = newName);
      _snack('Name updated.');
    } catch (e) {
      debugPrint('NAME ERROR: $e');
      _snack('Could not update name. Try again.');
    } finally {
      if (mounted) setState(() => _savingName = false);
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
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    if (_deleting) return;
    final isGoogle =
        _user?.providerData.any((p) => p.providerId == 'google.com') ?? false;
    final c = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cream,
        title: const Text(
          'Delete account?',
          style: TextStyle(
            color: AppColors.brown900,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isGoogle
                  ? 'This is permanent. You will be asked to confirm with Google.'
                  : 'This is permanent. Enter your password to confirm.',
              style: const TextStyle(color: AppColors.brown700),
            ),
            if (!isGoogle)
              TextField(
                controller: c,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.brown700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      await authRepo.deleteAccount(password: isGoogle ? null : c.text.trim());
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      debugPrint('DELETE ACCOUNT ERROR: $e');
      _snack(authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
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
                final username =
                    _usernameOverride ?? ((data?['username'] as String?) ?? '');
                final usernameChangedAt = _usernameChangedOverride ??
                    (data?['usernameChangedAt'] as Timestamp?)?.toDate();
                final name =
                    _nameOverride ?? ((data?['name'] as String?) ?? '');
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
                            onEdit: loading
                                ? null
                                : () => _editUsername(username, usernameChangedAt),
                          ),
                          _divider(),
                          _InfoRow(
                            icon: Icons.person_outline,
                            label: 'Name',
                            value: name.isEmpty ? '-' : name,
                            onEdit: loading ? null : () => _editName(name),
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
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _deleting ? null : _confirmDelete,
                      icon: _deleting
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.red),
                      )
                          : const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text('Delete account',
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w700)),
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
  final VoidCallback? onEdit;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
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
          if (onEdit != null)
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined,
                  size: 20, color: AppColors.gold700),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}
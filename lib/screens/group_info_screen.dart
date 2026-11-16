import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import '../chat_repository.dart';
import '../cloudinary_service.dart';
import '../group_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import '../image_helper.dart';

/// Pop result: true = main ne group chhod diya (chat screen bhi band ho jaye)
class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  const GroupInfoScreen({super.key, required this.groupId});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;


  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Map<String, dynamic> _group = {};
  bool _loaded = false;
  bool _busy = false;
  bool _isMember = true;

  @override
  void initState() {
    super.initState();
    _sub = groupRepo.groupDocStream(widget.groupId).listen(
          (snap) {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) {
          if (!_busy) Navigator.of(context).pop(true);
          return;
        }
        final member =
        List<String>.from(data['members'] ?? const []).contains(_myUid);

        // chhodne / remove hone ke baad: us waqt ki saved copy dikhao
        var shown = data;
        if (!member) {
          final snaps = data['leftSnapshot'];
          final mine = snaps is Map ? snaps[_myUid] : null;
          if (mine is Map) {
            shown = {...data, ...Map<String, dynamic>.from(mine)};
          }
        }
        setState(() {
          _group = shown;
          _isMember = member;
          _loaded = true;
        });
        _ensureUsers();
      },
      onError: (_) {
        if (mounted && !_busy) Navigator.of(context).pop(true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<String> get _members =>
      List<String>.from(_group['members'] ?? const []);
  List<String> get _admins => List<String>.from(_group['admins'] ?? const []);
  bool get _amAdmin => _isMember && _admins.contains(_myUid);

  void _ensureUsers() {
    final missing = _members.where((u) => chatRepo.cachedUser(u) == null);
    if (missing.isEmpty) return;
    Future.wait(
      missing.map((u) => chatRepo.getUser(u).then((_) {}, onError: (_) {})),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  String _username(String uid) =>
      (chatRepo.cachedUser(uid)?['username'] as String?) ?? '';

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, String error) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      debugPrint('GROUP INFO ERROR: $e');
      _snack(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _leftNote() {
    final lb = _group['leftBy'];
    final by = lb is Map ? ((lb[_myUid] as String?) ?? '') : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold500.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.gold700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              by.isEmpty
                  ? 'You left this group. This is how it looked when you left.'
                  : 'You were removed by $by. This is how it looked when you were removed.',
              style: const TextStyle(color: AppColors.brown900),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ edit

  Future<void> _rename() async {
    final c = TextEditingController(text: (_group['name'] as String?) ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Group name'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty || name == _group['name']) return;
    await _run(
          () => groupRepo.updateInfo(groupId: widget.groupId, name: name),
      'Could not change the name.',
    );
  }

  Future<void> _changePhoto() async {
    final path = await pickSquareImage();
    if (path == null) return;
    await _run(() async {
      final r = await cloudinary.uploadImage(File(path));
      await groupRepo.updateInfo(
        groupId: widget.groupId,
        photoUrl: r['url'] as String,
      );
    }, 'Could not change the photo.');
  }

  // --------------------------------------------------------------- members

  Future<void> _addMembers() async {
    final picked = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute(
        builder: (_) => _AddMembersScreen(existing: _members),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    await _run(
          () => groupRepo.addMembers(groupId: widget.groupId, users: picked),
      'Could not add members.',
    );
  }

  void _memberMenu(String uid) {
    if (!_amAdmin || uid == _myUid) return;
    final isAdmin = _admins.contains(uid);
    final name = _username(uid);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(isAdmin
                  ? Icons.remove_moderator_outlined
                  : Icons.admin_panel_settings_outlined),
              title: Text(isAdmin ? 'Remove as admin' : 'Make admin'),
              onTap: () {
                Navigator.pop(ctx);
                _run(
                      () => groupRepo.setAdmin(
                    groupId: widget.groupId,
                    uid: uid,
                    username: name,
                    admin: !isAdmin,
                  ),
                  'Could not update admin.',
                );
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.person_remove_outlined, color: Colors.red),
              title: Text('Remove $name',
                  style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _run(
                      () => groupRepo.removeMember(
                    groupId: widget.groupId,
                    uid: uid,
                    username: name,
                  ),
                  'Could not remove member.',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text("You won't receive messages from this group anymore."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await groupRepo.leaveGroup(widget.groupId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('LEAVE GROUP ERROR: $e');
      if (mounted) setState(() => _busy = false);
      _snack('Could not leave the group.');
    }
  }

  // -------------------------------------------------------------------- UI

  Widget _memberTile(String uid) {
    final u = chatRepo.cachedUser(uid);
    final username = (u?['username'] as String?) ?? '';
    final photo = (u?['photoUrl'] as String?) ?? '';
    final about = (u?['about'] as String?) ?? '';
    final isAdmin = _admins.contains(uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: softCardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _memberMenu(uid),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                UserAvatar(username: username, photoUrl: photo, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uid == _myUid ? 'You' : username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brown900,
                        ),
                      ),
                      if (about.isNotEmpty)
                        Text(
                          about,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.brown700),
                        ),
                    ],
                  ),
                ),
                if (isAdmin)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold500.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (_group['name'] as String?) ?? '';
    final photo = (_group['photoUrl'] as String?) ?? '';

    // admins pehle, phir baqi (naam ke hisab se); main sab se upar
    final sorted = [..._members]..sort((a, b) {
      if (a == _myUid) return -1;
      if (b == _myUid) return 1;
      final aa = _admins.contains(a) ? 0 : 1;
      final bb = _admins.contains(b) ? 0 : 1;
      if (aa != bb) return aa - bb;
      return _username(a).compareTo(_username(b));
    });

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(title: 'Group info', showBack: true),
          if (_busy)
            const LinearProgressIndicator(
                color: AppColors.gold700, minHeight: 3),
          Expanded(
            child: !_loaded
                ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold700),
            )
                : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _amAdmin && !_busy ? _changePhoto : null,
                    child: Stack(
                      children: [
                        UserAvatar(
                            username: name, photoUrl: photo, size: 96),
                        if (_amAdmin)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppColors.gold700,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  size: 16, color: AppColors.cream),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brown900,
                        ),
                      ),
                    ),
                    if (_amAdmin)
                      IconButton(
                        tooltip: 'Edit name',
                        icon: const Icon(Icons.edit_outlined,
                            size: 20, color: AppColors.gold700),
                        onPressed: _busy ? null : _rename,
                      ),
                  ],
                ),
                Center(
                  child: Text(
                    'Group · ${_members.length} members',
                    style: const TextStyle(color: AppColors.brown700),
                  ),
                ),
                const SizedBox(height: 24),
                if (_amAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppColors.gold500.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _busy ? null : _addMembers,
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Icon(Icons.person_add_alt_1_outlined,
                                  color: AppColors.gold700),
                              SizedBox(width: 12),
                              Text(
                                'Add members',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brown900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_isMember) _leftNote(),
                for (final uid in sorted) _memberTile(uid),
                const SizedBox(height: 14),
                if (_isMember)
                  TextButton.icon(
                  onPressed: _busy ? null : _leave,
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    'Leave group',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
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

// ---------------------------------------------------------------------------
// Add members picker
// ---------------------------------------------------------------------------

class _AddMembersScreen extends StatefulWidget {
  final List<String> existing;
  const _AddMembersScreen({required this.existing});

  @override
  State<_AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<_AddMembersScreen> {
  List<Map<String, dynamic>> _contacts = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await groupRepo.loadContacts();
      if (!mounted) return;
      setState(() {
        _contacts =
            all.where((u) => !widget.existing.contains(u['uid'])).toList();
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

  Widget _body() {
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
        icon: Icons.groups_outlined,
        title: 'Nobody left to add',
        subtitle: 'All your contacts are already in this group.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: _contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final u = _contacts[i];
        final uid = u['uid'] as String;
        final on = _selected.contains(uid);
        final username = (u['username'] as String?) ?? '';
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
              onTap: () => setState(() {
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
            title: 'Add members',
            showBack: true,
            subtitle: _selected.isEmpty ? null : '${_selected.length} selected',
          ),
          Expanded(child: _body()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: PillButton(
                label: 'Add',
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                  _contacts
                      .where((u) => _selected.contains(u['uid']))
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
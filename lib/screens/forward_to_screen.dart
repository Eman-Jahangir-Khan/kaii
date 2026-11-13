import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../chat_repository.dart';
import '../group_repository.dart';
import '../theme.dart';
import '../widgets.dart';

/// Messages ko groups aur contacts mein forward karo.
/// Bhejne par `true` ke saath pop hota hai (purane ForwardScreen jaisa).
class ForwardToScreen extends StatefulWidget {
  final List<String> texts;
  const ForwardToScreen({super.key, required this.texts});

  @override
  State<ForwardToScreen> createState() => _ForwardToScreenState();
}

class _ForwardToScreenState extends State<ForwardToScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  final _searchCtrl = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _groups = [];
  List<Map<String, dynamic>> _contacts = [];
  final Set<String> _selGroups = {};
  final Set<String> _selUsers = {};
  String _query = '';
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;

  int get _count => _selGroups.length + _selUsers.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        groupRepo.groupsStream().first,
        groupRepo.loadContacts(),
      ]);
      final snap = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final contacts = results[1] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        // sirf wo groups jin mein main abhi member hoon
        _groups = snap.docs
            .where((d) => List<String>.from(d.data()['members'] ?? const [])
            .contains(_myUid))
            .toList();
        _contacts = contacts;
        _loading = false;
      });
    } catch (e) {
      debugPrint('FORWARD LOAD ERROR: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _send() async {
    if (_count == 0 || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    var ok = 0;
    var failed = 0;

    for (final d in _groups.where((d) => _selGroups.contains(d.id))) {
      try {
        final members = List<String>.from(d.data()['members'] ?? const []);
        for (final t in widget.texts) {
          await groupRepo.sendMessage(
            groupId: d.id,
            members: members,
            text: t,
            forwarded: true,
          );
        }
        ok++;
      } catch (e) {
        debugPrint('FORWARD GROUP ERROR: $e');
        failed++;
      }
    }

    for (final uid in _selUsers) {
      try {
        for (final t in widget.texts) {
          await chatRepo.sendMessage(
            otherUid: uid,
            text: t,
            forwarded: true,
          );
        }
        ok++;
      } catch (e) {
        debugPrint('FORWARD CHAT ERROR: $e');
        failed++;
      }
    }

    if (!mounted) return;
    if (failed > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok == 0
              ? 'Could not forward. Try again.'
              : 'Could not forward to $failed chat(s)'),
        ),
      );
    }
    if (ok > 0) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _sending = false);
    }
  }

  // ------------------------------------------------------------------ UI

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
          hintText: 'Search',
          hintStyle: TextStyle(
            color: AppColors.brown700.withValues(alpha: 0.7),
          ),
          prefixIcon: const Icon(Icons.search, color: AppColors.gold700),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 12, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: AppColors.gold700,
        ),
      ),
    );
  }

  Widget _row({
    required String name,
    required String photo,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: softCardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.gold700 : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _sending ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                UserAvatar(username: name, photoUrl: photo, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
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
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? AppColors.gold700 : AppColors.brown700,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        title: 'Could not load chats',
        subtitle: 'Check your internet and try again.',
      );
    }

    final groups = _groups
        .where((d) => ((d.data()['name'] as String?) ?? '')
        .toLowerCase()
        .contains(_query))
        .toList();
    final contacts = _contacts.where((u) {
      final n = ((u['username'] as String?) ?? '').toLowerCase();
      final nm = ((u['name'] as String?) ?? '').toLowerCase();
      return n.contains(_query) || nm.contains(_query);
    }).toList();

    if (groups.isEmpty && contacts.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: _query.isEmpty ? 'Nowhere to forward' : 'No results',
        subtitle: _query.isEmpty
            ? 'Start a chat or join a group first.'
            : 'Nothing matches "$_query".',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      children: [
        if (groups.isNotEmpty) _label('GROUPS'),
        for (final d in groups)
          _row(
            name: (d.data()['name'] as String?) ?? '',
            photo: (d.data()['photoUrl'] as String?) ?? '',
            selected: _selGroups.contains(d.id),
            onTap: () => setState(() {
              if (!_selGroups.remove(d.id)) _selGroups.add(d.id);
            }),
          ),
        if (contacts.isNotEmpty) _label('CONTACTS'),
        for (final u in contacts)
          _row(
            name: (u['username'] as String?) ?? '',
            photo: (u['photoUrl'] as String?) ?? '',
            selected: _selUsers.contains(u['uid']),
            onTap: () => setState(() {
              final uid = u['uid'] as String;
              if (!_selUsers.remove(uid)) _selUsers.add(uid);
            }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          GradientHeader(
            title: 'Forward to',
            showBack: true,
            subtitle: _count == 0 ? null : '$_count selected',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _searchBar(),
          ),
          Expanded(child: _body()),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: PillButton(
                label:  _count == 0 ? 'Send' : 'Send ($_count)',
                loading: _sending,
                onPressed: _count == 0 ? null : _send,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
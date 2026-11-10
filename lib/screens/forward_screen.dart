import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../auth_repository.dart';
import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';

class _Target {
  final String uid;
  final String username;
  final String photoUrl;
  final bool blocked;
  const _Target({
    required this.uid,
    required this.username,
    required this.photoUrl,
    required this.blocked,
  });
}

class ForwardScreen extends StatefulWidget {
  /// Forward hone wale messages ka text, purane se naye ke order mein
  final List<String> texts;
  const ForwardScreen({super.key, required this.texts});

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  static const _maxPick = 5;

  final String _myUid = authRepo.currentUser!.uid;
  final _searchCtrl = TextEditingController();

  List<_Target> _targets = [];
  final Set<String> _picked = {};
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;
  String _query = '';

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

  /// Meri taraf se delete ki hui chat (jo home par nahi dikhti)
  bool _hiddenForMe(Map<String, dynamic> m) {
    final del = m['deletedAt'];
    if (del is! Map || !del.containsKey(_myUid)) return false;
    final cut = del[_myUid] as Timestamp?;
    if (cut == null) return true;
    final last = m['lastMessageAt'] as Timestamp?;
    if (last == null) return false;
    return last.compareTo(cut) <= 0;
  }

  Future<void> _load() async {
    try {
      final snap = await chatRepo.chatsStream().first;
      final docs = snap.docs.where((d) {
        final m = d.data();
        final s = m['status'] as String?;
        return (s == null || s == 'accepted') && !_hiddenForMe(m);
      });

      final targets = await Future.wait(docs.map((d) async {
        final m = d.data();
        final participants = List<String>.from(m['participants'] as List);
        final other = participants.firstWhere(
              (u) => u != _myUid,
          orElse: () => _myUid,
        );
        final user = await chatRepo.getUser(other);
        final b = m['blockedBy'];
        return _Target(
          uid: other,
          username: (user?['username'] as String?) ?? 'Unknown user',
          photoUrl: (user?['photoUrl'] as String?) ?? '',
          blocked: b is List && b.isNotEmpty,
        );
      }));

      if (!mounted) return;
      setState(() {
        _targets = targets.where((t) => t.uid != _myUid).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _toggle(String uid) {
    if (!_picked.contains(uid) && _picked.length >= _maxPick) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can forward to up to 5 chats')),
      );
      return;
    }
    setState(() {
      if (!_picked.remove(uid)) _picked.add(uid);
    });
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      for (final uid in _picked) {
        for (final text in widget.texts) {
          await chatRepo.sendMessage(
            otherUid: uid,
            text: text,
            forwarded: true,
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not forward. Try again.')),
      );
    }
  }

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
          hintText: 'Search chats',
          hintStyle: TextStyle(
            color: AppColors.brown700.withValues(alpha: 0.7),
          ),
          prefixIcon: const Icon(Icons.search, color: AppColors.gold700),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
            icon: const Icon(Icons.close, color: AppColors.brown700),
            onPressed: () {
              _searchCtrl.clear();
              setState(() => _query = '');
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _tile(_Target t) {
    final picked = _picked.contains(t.uid);
    return Opacity(
      opacity: t.blocked ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: picked ? AppColors.gold200 : softCardColor,
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
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: t.blocked ? null : () => _toggle(t.uid),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  UserAvatar(
                    username: t.username,
                    photoUrl: t.photoUrl,
                    size: 46,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brown900,
                          ),
                        ),
                        if (t.blocked)
                          const Text(
                            'Blocked',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.brown700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    picked
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: picked ? AppColors.gold700 : AppColors.brown700,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(List<_Target> list) {
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
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: 'No chats',
        subtitle: _query.isEmpty
            ? 'Start a chat first to forward messages.'
            : 'No chat matches "$_query".',
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _tile(list[i]),
    );
  }

  Widget _sendBar() {
    final names = _targets
        .where((t) => _picked.contains(t.uid))
        .map((t) => t.username)
        .join(', ');
    return Container(
      color: softCardColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  names,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brown900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold700,
                  foregroundColor: AppColors.cream,
                ),
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.cream,
                  ),
                )
                    : const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _targets
        .where((t) => _query.isEmpty || t.username.toLowerCase().contains(_query))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          GradientHeader(
            title: 'Forward to',
            titleStyle: const TextStyle(fontSize: 18, color: Colors.black),
            showBack: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _searchBar(),
          ),
          Expanded(child: _body(list)),
          if (_picked.isNotEmpty) _sendBar(),
        ],
      ),
    );
  }
}
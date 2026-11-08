import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  bool _loading = false;
  bool _failed = false;
  List<Map<String, dynamic>> _results = [];
  Map<String, ChatLink> _links = {};
  final Set<String> _busy = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim().toLowerCase();
    setState(() => _query = q);

    if (q.length < 2) {
      setState(() {
        _results = [];
        _loading = false;
        _failed = false;
      });
      return;
    }

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    try {
      final r = await chatRepo.searchUsers(q);
      final links = await chatRepo
          .linksFor(r.map((u) => u['uid'] as String).toList());
      if (!mounted || q != _query) return;
      setState(() {
        _results = r;
        _links = links;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || q != _query) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _open(Map<String, dynamic> user) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUid: user['uid'] as String,
          username: (user['username'] as String?) ?? '',
          photoUrl: (user['photoUrl'] as String?) ?? '',
        ),
      ),
    );
  }


  Future<void> _onUserTap(Map<String, dynamic> user) async {
    final uid = user['uid'] as String;
    final link = _links[uid] ?? ChatLink.none;

    if (link == ChatLink.accepted) {
      _open(user);
      return;
    }
    if (link != ChatLink.none && link != ChatLink.requestReceived) return;
    if (_busy.contains(uid)) return;

    setState(() => _busy.add(uid));
    try {
      final result = await chatRepo.sendRequest(uid);
      if (!mounted) return;
      setState(() {
        _links[uid] = result;
        _busy.remove(uid);
      });
      if (result == ChatLink.accepted) {
        _open(user);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request sent to ${user['username']}')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy.remove(uid));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send request. Try again.')),
      );
    }
  }


  Widget _trailing(String uid) {
    if (_busy.contains(uid)) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.gold700,
        ),
      );
    }
    Widget pill(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.gold700,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.cream,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget muted(String label) => Text(
      label,
      style: const TextStyle(
        color: AppColors.brown700,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );

    switch (_links[uid] ?? ChatLink.none) {
      case ChatLink.accepted:
        return const Icon(Icons.chevron_right, color: AppColors.gold700);
      case ChatLink.none:
        return pill('Request');
      case ChatLink.requestReceived:
        return pill('Accept');
      case ChatLink.requestSent:
        return muted('Requested');
      case ChatLink.declined:
        return muted('Declined');
    }
  }

  Widget _body() {
    if (_query.length < 2) {
      return const EmptyState(
        icon: Icons.person_search_outlined,
        title: 'Find people',
        subtitle: 'Type at least 2 letters of a username.',
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold700),
      );
    }
    if (_failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Search failed',
        subtitle: 'Check your internet and try again.',
      );
    }
    if (_results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'No users found',
        subtitle: 'Check the spelling of the username.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final u = _results[i];
        final username = (u['username'] as String?) ?? '';
        final photo = (u['photoUrl'] as String?) ?? '';
        final name = (u['name'] as String?) ?? '';
        final uid = u['uid'] as String;
        return Container(
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
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _onUserTap(u),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    UserAvatar(username: username, photoUrl: photo, size: 48),
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
                          if (name.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.brown700),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _trailing(uid),
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
            title: 'New chat',
            showBack: true,
            bottom: Container(
              decoration: BoxDecoration(
                color: softCardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                cursorColor: AppColors.gold700,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_.]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                style: const TextStyle(
                  color: AppColors.brown900,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by username',
                  hintStyle: TextStyle(
                    color: AppColors.brown700.withValues(alpha: 0.7),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.gold700,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }


}
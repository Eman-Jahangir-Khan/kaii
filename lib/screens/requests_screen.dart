import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../auth_repository.dart';
import '../chat_repository.dart';
import '../theme.dart';
import '../widgets.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final String _myUid = authRepo.currentUser!.uid;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
  chatRepo.chatsStream();

  String _otherUidOf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final p = List<String>.from(d.data()['participants'] as List);
    return p.firstWhere((u) => u != _myUid, orElse: () => _myUid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(title: 'Message requests', showBack: true),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load requests',
                    subtitle: 'Check your internet and try again.',
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.gold700,
                    ),
                  );
                }
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  return m['status'] == 'pending' &&
                      m['requestedBy'] != _myUid;
                }).toList();

                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.mark_email_unread_outlined,
                    title: 'No requests',
                    subtitle: 'Requests from other people will show up here.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _RequestTile(
                    key: ValueKey(docs[i].id),
                    otherUid: _otherUidOf(docs[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatefulWidget {
  final String otherUid;
  const _RequestTile({super.key, required this.otherUid});

  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  late final Future<Map<String, dynamic>?> _future =
  chatRepo.getUser(widget.otherUid);
  bool _busy = false;

  Future<void> _act(bool accept, String username) async {
    setState(() => _busy = true);
    try {
      if (accept) {
        await chatRepo.acceptRequest(widget.otherUid);
      } else {
        await chatRepo.rejectRequest(widget.otherUid);
      }
      if (!mounted) return;
      if (accept) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You can now chat with $username')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      initialData: chatRepo.cachedUser(widget.otherUid),
      builder: (context, snap) {
        final user = snap.data;
        final username = (user?['username'] as String?) ?? '...';
        final name = (user?['name'] as String?) ?? '';
        final photo = (user?['photoUrl'] as String?) ?? '';

        return Container(
          padding: const EdgeInsets.all(12),
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
              Row(
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
                        if (name.isNotEmpty)
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.brown700),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _act(false, username),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brown900,
                        side: const BorderSide(color: AppColors.gold700),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _act(true, username),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold700,
                        foregroundColor: AppColors.cream,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
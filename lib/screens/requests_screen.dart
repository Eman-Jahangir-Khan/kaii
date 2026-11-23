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

                final pending = snap.data!.docs
                    .where((d) => d.data()['status'] == 'pending')
                    .toList();
                final received = pending
                    .where((d) => d.data()['requestedBy'] != _myUid)
                    .toList();
                final sent = pending
                    .where((d) => d.data()['requestedBy'] == _myUid)
                    .toList();

                if (received.isEmpty && sent.isEmpty) {
                  return const EmptyState(
                    icon: Icons.mark_email_unread_outlined,
                    title: 'No requests',
                    subtitle:
                    'Requests you receive or send will show up here.',
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _SectionHeader(title: 'Received', count: received.length),
                    if (received.isEmpty)
                      const _SectionEmpty(text: 'No requests received')
                    else
                      for (final d in received)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RequestTile(
                            key: ValueKey('r_${d.id}'),
                            otherUid: _otherUidOf(d),
                            docId: d.id,
                            sent: false,
                          ),
                        ),
                    const SizedBox(height: 14),
                    _SectionHeader(title: 'Sent', count: sent.length),
                    if (sent.isEmpty)
                      const _SectionEmpty(text: 'No requests sent')
                    else
                      for (final d in sent)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RequestTile(
                            key: ValueKey('s_${d.id}'),
                            otherUid: _otherUidOf(d),
                            docId: d.id,
                            sent: true,
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.brown900,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.gold500.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brown900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  final String text;
  const _SectionEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.brown700, fontSize: 13.5),
      ),
    );
  }
}

class _RequestTile extends StatefulWidget {
  final String otherUid;
  final String docId;
  final bool sent; // true = maine bheji hai, false = mujhe aayi hai
  const _RequestTile({
    super.key,
    required this.otherUid,
    required this.docId,
    required this.sent,
  });

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

  /// Bheji hui request wapas lo (RequestButton wala hi tareeqa: chat doc delete)
  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.docId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request cancelled')),
      );
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
                  if (widget.sent)
                    const Text(
                      'Pending',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.gold700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (widget.sent)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _cancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brown900,
                      side: const BorderSide(color: AppColors.gold700),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Cancel request'),
                  ),
                )
              else
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
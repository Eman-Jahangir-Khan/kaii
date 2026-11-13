import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../chat_repository.dart';
import '../group_repository.dart';
import '../message_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// Group message ki info: kis ne padh liya aur kis ne nahi
class GroupMessageInfoScreen extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> data; // message ka data

  const GroupMessageInfoScreen({
    super.key,
    required this.groupId,
    required this.data,
  });

  @override
  State<GroupMessageInfoScreen> createState() =>
      _GroupMessageInfoScreenState();
}

class _GroupMessageInfoScreenState extends State<GroupMessageInfoScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Map<String, dynamic> _group = {};
  bool _loaded = false;

  Timestamp? get _created => widget.data['createdAt'] as Timestamp?;

  @override
  void initState() {
    super.initState();
    _sub = groupRepo.groupDocStream(widget.groupId).listen((snap) {
      if (!mounted) return;
      setState(() {
        _group = snap.data() ?? {};
        _loaded = true;
      });
      _ensureUsers();
    }, onError: (_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<String> get _members =>
      List<String>.from(_group['members'] ?? const []);

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

  /// Ye member is message ko dekh sakta tha? (baad mein join hua ya gap mein tha to nahi)
  bool _couldSee(String uid, Timestamp created) {
    final j = _group['joinedAt'];
    final joined = j is Map ? j[uid] : null;
    if (joined is Timestamp && joined.compareTo(created) > 0) return false;

    final g = _group['gaps'];
    if (g is Map && g[uid] is Map) {
      for (final e in (g[uid] as Map).entries) {
        final from = int.tryParse(e.key.toString());
        final to = e.value;
        if (from != null &&
            to is Timestamp &&
            created.millisecondsSinceEpoch > from &&
            created.compareTo(to) < 0) {
          return false;
        }
      }
    }
    return true;
  }

  Widget _section(String title, IconData icon, Color color, List<String> uids,
      String emptyText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                '$title (${uids.length})',
                style: const TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.gold700,
                ),
              ),
            ],
          ),
        ),
        if (uids.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              emptyText,
              style: const TextStyle(color: AppColors.brown700),
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                for (var i = 0; i < uids.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 66,
                      color: AppColors.gold700.withValues(alpha: 0.2),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        UserAvatar(
                          username: _username(uids[i]),
                          photoUrl: (chatRepo.cachedUser(uids[i])?['photoUrl']
                          as String?) ??
                              '',
                          size: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _username(uids[i]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brown900,
                            ),
                          ),
                        ),
                        Icon(icon, size: 18, color: color),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _body() {
    final created = _created;
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold700),
      );
    }
    if (created == null) {
      return const EmptyState(
        icon: Icons.access_time,
        title: 'Message is being sent',
        subtitle: 'Info will be available in a moment.',
      );
    }

    final lr = _group['lastRead'];
    final read = <String>[];
    final unread = <String>[];
    for (final m in _members) {
      if (m == _myUid || !_couldSee(m, created)) continue;
      final t = lr is Map ? lr[m] : null;
      if (t is Timestamp && t.compareTo(created) >= 0) {
        read.add(m);
      } else {
        unread.add(m);
      }
    }
    int byName(String a, String b) => _username(a).compareTo(_username(b));
    read.sort(byName);
    unread.sort(byName);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        MessageBubble(
          data: widget.data,
          mine: true,
          pending: false,
          seen: false,
          time: created.toDate(),
        ),
        const SizedBox(height: 12),
        _section('READ BY', Icons.done_all, AppColors.gold700, read,
            'Nobody has read this yet.'),
        _section('NOT READ YET', Icons.done, AppColors.brown700, unread,
            'Everyone has read this.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Column(
        children: [
          const GradientHeader(title: 'Message info', showBack: true),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
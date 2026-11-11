import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../group_repository.dart';
import '../message_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loaded = false;
  bool _failed = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _sub = groupRepo.groupsStream().listen(
          (snap) {
        if (!mounted) return;
        setState(() {
          _docs = snap.docs;
          _loaded = true;
          _failed = false;
        });
      },
      onError: (e) {
        debugPrint('GROUPS STREAM ERROR: $e'); // index ka link yahin milega
        if (!mounted) return;
        setState(() {
          _failed = true;
          _loaded = true;
        });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _create() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
  }

  String _preview(Map<String, dynamic> g) {
    final msg = (g['lastMessage'] as String?) ?? '';
    final senderId = (g['lastSenderId'] as String?) ?? '';
    final senderName = (g['lastSenderName'] as String?) ?? '';
    if (senderId.isEmpty) return msg; // system message
    if (senderId == _myUid) return 'You: $msg';
    return senderName.isEmpty ? msg : '$senderName: $msg';
  }

  String _time(Timestamp? ts) {
    if (ts == null) return '';
    final t = ts.toDate();
    return sameDay(t, DateTime.now()) ? hhmm(t) : dayLabel(t);
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
          hintText: 'Search groups',
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

  Widget _body() {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold700),
      );
    }
    if (_failed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load groups',
        subtitle: 'Check your internet and try again.',
      );
    }
    if (_docs.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'No groups yet',
        subtitle: 'Tap + to create a group with your contacts.',
      );
    }
    final list = _query.isEmpty
        ? _docs
        : _docs
        .where((d) => ((d.data()['name'] as String?) ?? '')
        .toLowerCase()
        .contains(_query))
        .toList();
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No groups found',
        subtitle: 'No group matches "$_query".',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final d = list[i];
        final g = d.data();
        final name = (g['name'] as String?) ?? '';
        final photo = (g['photoUrl'] as String?) ?? '';
        final unreadMap = g['unread'];
        final unread =
        unreadMap is Map ? ((unreadMap[_myUid] as num?)?.toInt() ?? 0) : 0;

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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupChatScreen(
                    groupId: d.id,
                    name: name,
                    photoUrl: photo,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    UserAvatar(username: name, photoUrl: photo, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brown900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _preview(g),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.brown700,
                              fontWeight: unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _time(g['lastMessageAt'] as Timestamp?),
                          style: TextStyle(
                            fontSize: 12,
                            color: unread > 0
                                ? AppColors.gold700
                                : AppColors.brown700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 22),
                            decoration: BoxDecoration(
                              color: AppColors.gold700,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.cream,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 22),
                      ],
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
    return Column(
      children: [
        GradientHeader(
          title: 'Groups',
          actions: [
            IconButton(
              tooltip: 'New group',
              icon: const Icon(Icons.add_rounded, color: Colors.black),
              onPressed: _create,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: _searchBar(),
        ),
        Expanded(child: _body()),
      ],
    );
  }
}
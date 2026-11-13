import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'group_info_screen.dart';
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

  Timestamp? _leftTime(Map<String, dynamic> g) {
    final m = g['leftAt'];
    final t = m is Map ? m[_myUid] : null;
    return t is Timestamp ? t : null;
  }

  String _preview(Map<String, dynamic> g, bool isMember) {
    if (!isMember) {
      final by = g['leftBy'];
      final who = by is Map ? ((by[_myUid] as String?) ?? '') : '';
      return who.isEmpty ? 'You left' : 'You were removed by $who';
    }
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

  void _showPhoto(String groupId, String name, String photo, bool isMember) {
    final size = MediaQuery.of(context).size.width * 0.75;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: size,
              color: softCardColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    // photo par tap: poori screen par khulti hai
                    onTap: photo.isEmpty
                        ? null
                        : () => _openFullPhoto(name, photo),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: size,
                          height: size,
                          child: photo.isEmpty
                              ? Container(
                            color:
                            AppColors.gold500.withValues(alpha: 0.2),
                            alignment: Alignment.center,
                            child: UserAvatar(
                              username: name,
                              photoUrl: '',
                              size: size * 0.5,
                            ),
                          )
                              : CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.gold700,
                              ),
                            ),
                            errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding:
                            const EdgeInsets.fromLTRB(14, 12, 14, 24),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black54, Colors.transparent],
                              ),
                            ),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        tooltip: 'Message',
                        icon: const Icon(Icons.chat_bubble_outline,
                            color: AppColors.gold700),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GroupChatScreen(
                              groupId: groupId,
                              name: name,
                              photoUrl: photo,
                            ),
                          ));
                        },
                      ),
                      if (isMember)
                        IconButton(
                          tooltip: 'Call',
                          icon: const Icon(Icons.call_outlined,
                              color: AppColors.gold700),
                          onPressed: () {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Calls are coming soon')),
                            );
                          },
                        ),
                      if (isMember)
                        IconButton(
                          tooltip: 'Group info',
                          icon: const Icon(Icons.info_outline,
                              color: AppColors.gold700),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  GroupInfoScreen(groupId: groupId),
                            ));
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openFullPhoto(String name, String photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
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
        final isMember =
        List<String>.from(g['members'] ?? const []).contains(_myUid);
        final unreadMap = g['unread'];
        final unread = !isMember
            ? 0
            : (unreadMap is Map
            ? ((unreadMap[_myUid] as num?)?.toInt() ?? 0)
            : 0);

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
                    GestureDetector(
                      onTap: () => _showPhoto(d.id, name, photo, isMember),
                      child:
                      UserAvatar(username: name, photoUrl: photo, size: 52),
                    ),
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
                            _preview(g, isMember),
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
                          _time(isMember
                              ? g['lastMessageAt'] as Timestamp?
                              : _leftTime(g)),
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
    return Scaffold(
      backgroundColor: AppColors.cream,
      floatingActionButton: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.gold500, AppColors.gold700],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold700.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _create,
            child: const Icon(
              Icons.group_add_outlined,
              color: AppColors.cream,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const GradientHeader(title: 'Groups'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _searchBar(),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
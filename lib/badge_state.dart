import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'chat_repository.dart';
import 'group_repository.dart';
import 'status_repository.dart';

/// Tamam chats ke total unread messages
final ValueNotifier<int> chatsUnread = ValueNotifier<int>(0);

/// Tamam groups ke total unread messages
final ValueNotifier<int> groupsUnread = ValueNotifier<int>(0);

/// Dusron ke un-dekhe status updates (sirf dot dikhane ke liye)
final ValueNotifier<int> statusUnseen = ValueNotifier<int>(0);

/// Background mein teeno streams sunti hai taake tab khuli na ho tab bhi badge bane
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupsSub;
  StreamSubscription<List<StatusItem>>? _statusSub;
  Timer? _tick;
  List<StatusItem> _lastFeed = const [];
  String? _uid;

  void start() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == _uid) return;
    stop();
    _uid = uid;

    _chatsSub = chatRepo.chatsStream().listen(
          (snap) => chatsUnread.value = _countChats(snap, uid),
      onError: (e) => debugPrint('BADGE chats error: $e'),
    );
    _groupsSub = groupRepo.groupsStream().listen(
          (snap) => groupsUnread.value = _countGroups(snap, uid),
      onError: (e) => debugPrint('BADGE groups error: $e'),
    );
    _statusSub = statusRepo.feedStream().listen(
          (items) {
        _lastFeed = items;
        statusUnseen.value = _countStatus(items, uid);
      },
      onError: (e) => debugPrint('BADGE status error: $e'),
    );
    // status expire hone par bina naye event ke bhi badge hat jaye
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      statusUnseen.value = _countStatus(_lastFeed, uid);
    });
  }

  void stop() {
    _chatsSub?.cancel();
    _groupsSub?.cancel();
    _statusSub?.cancel();
    _tick?.cancel();
    _chatsSub = null;
    _groupsSub = null;
    _statusSub = null;
    _tick = null;
    _lastFeed = const [];
    _uid = null;
    chatsUnread.value = 0;
    groupsUnread.value = 0;
    statusUnseen.value = 0;
  }

  /// Maine ye chat/group delete ki ho aur uske baad naya message na aaya ho
  bool _deletedForMe(Map<String, dynamic> m, String me) {
    final del = m['deletedAt'];
    if (del is! Map || !del.containsKey(me)) return false;
    final cut = del[me] as Timestamp?;
    if (cut == null) return true;
    final last = m['lastMessageAt'] as Timestamp?;
    if (last == null) return false;
    return last.compareTo(cut) <= 0;
  }

  /// unread number, warna "mark as unread" ho to 1
  int _unreadOf(Map<String, dynamic> m, String me) {
    final um = m['unread'];
    final n = um is Map ? ((um[me] as num?)?.toInt() ?? 0) : 0;
    if (n > 0) return n;
    final marked = m['markedUnread'];
    return (marked is List && marked.contains(me)) ? 1 : 0;
  }

  int _countChats(QuerySnapshot<Map<String, dynamic>> snap, String me) {
    var total = 0;
    for (final d in snap.docs) {
      final m = d.data();
      final s = m['status'] as String?;
      if (!(s == null || s == 'accepted')) continue; // pending requests nahi
      if (_deletedForMe(m, me)) continue;
      total += _unreadOf(m, me);
    }
    return total;
  }

  int _countGroups(QuerySnapshot<Map<String, dynamic>> snap, String me) {
    var total = 0;
    for (final d in snap.docs) {
      final m = d.data();
      final members = List<String>.from(m['members'] ?? const []);
      if (!members.contains(me)) continue;
      if (_deletedForMe(m, me)) continue;
      total += _unreadOf(m, me);
    }
    return total;
  }

  int _countStatus(List<StatusItem> items, String me) {
    return items
        .where((i) => !i.isExpired && i.ownerId != me && !i.viewedByMe(me))
        .length;
  }
}
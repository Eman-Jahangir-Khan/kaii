import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../call_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'call_screen.dart';

class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Column(
      children: [
        const GradientHeader(title: 'Calls'),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: callRepo.historyStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const EmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load calls',
                  subtitle: 'Check your internet and try again.',
                );
              }
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.gold700),
                );
              }

              // Sirf khatam ho chuki calls, naye pehle
              final docs = snap.data!.docs
                  .where((d) => d.data()['status'] != 'ringing')
                  .toList()
                ..sort((a, b) {
                  final ta = a.data()['createdAt'] as Timestamp?;
                  final tb = b.data()['createdAt'] as Timestamp?;
                  if (ta == null) return -1;
                  if (tb == null) return 1;
                  return tb.compareTo(ta);
                });

              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.call_outlined,
                  title: 'No calls yet',
                  subtitle: 'Your call history will appear here.',
                );
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) => _CallTile(data: docs[i].data(), myUid: myUid),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CallTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String myUid;
  const _CallTile({required this.data, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final outgoing = data['callerId'] == myUid;
    final status = (data['status'] as String?) ?? '';
    final video = data['type'] == 'video';
    final missed = !outgoing && (status == 'missed' || status == 'cancelled');

    final otherUid = (outgoing ? data['calleeId'] : data['callerId']) as String;
    final name =
        ((outgoing ? data['calleeName'] : data['callerName']) as String?) ?? '';
    final photo =
        ((outgoing ? data['calleePhoto'] : data['callerPhoto']) as String?) ??
            '';

    final created = (data['createdAt'] as Timestamp?)?.toDate();
    final answered = (data['answeredAt'] as Timestamp?)?.toDate();
    final ended = (data['endedAt'] as Timestamp?)?.toDate();

    String label;
    if (status == 'ended' && answered != null && ended != null) {
      final s = ended.difference(answered).inSeconds;
      label = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    } else if (status == 'declined') {
      label = 'Declined';
    } else if (missed) {
      label = 'Missed';
    } else if (status == 'missed') {
      label = 'No answer';
    } else {
      label = 'Cancelled';
    }

    return ListTile(
      leading: UserAvatar(username: name, photoUrl: photo, size: 46),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: missed ? Colors.red : AppColors.brown900,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(
            outgoing ? Icons.call_made : Icons.call_received,
            size: 14,
            color: missed ? Colors.red : AppColors.brown700,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label  ·  ${_when(created)}',
              style: const TextStyle(color: AppColors.brown700),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(
          video ? Icons.videocam_outlined : Icons.call_outlined,
          color: AppColors.gold700,
        ),
        onPressed: () => placeCall(
          context,
          otherUid: otherUid,
          otherName: name,
          otherPhoto: photo,
          video: video,
        ),
      ),
    );
  }

  String _when(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final time =
        '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    return '${t.day}/${t.month}/${t.year}, $time';
  }
}
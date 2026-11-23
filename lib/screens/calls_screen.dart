import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../call_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'call_screen.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  /// Select ki hui calls ki ids (khali ho to selection mode band)
  final Set<String> _selected = {};

  /// Abhi screen par nazar aa rahi saari calls (Select all ke liye)
  List<String> _visibleIds = [];

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _visibleIds.length) {
        _selected.clear(); // sab select the, to sab hata do
      } else {
        _selected
          ..clear()
          ..addAll(_visibleIds);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ids.length == 1 ? 'Delete call?' : 'Delete ${ids.length} calls?'),
        content: const Text('This only removes them from your call history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await callRepo.deleteForMe(ids);
      if (mounted) setState(() => _selected.clear());
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return PopScope(
      // Selection mode mein back dabane par sirf selection band ho
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selected.clear());
      },
      child: Column(
        children: [
          const GradientHeader(title: 'Calls'),
          if (_selecting) _selectionBar(),
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

                // Khatam ho chuki calls, jo maine delete nahi ki, naye pehle
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  if (m['status'] == 'ringing') return false;
                  final deletedFor = (m['deletedFor'] as List?) ?? const [];
                  return !deletedFor.contains(myUid);
                }).toList()
                  ..sort((a, b) {
                    final ta = a.data()['createdAt'] as Timestamp?;
                    final tb = b.data()['createdAt'] as Timestamp?;
                    if (ta == null) return -1;
                    if (tb == null) return 1;
                    return tb.compareTo(ta);
                  });

                _visibleIds = docs.map((d) => d.id).toList();
                // Jo call ab list mein nahi (delete ho gayi) usay selection se hatao
                _selected.removeWhere((id) => !_visibleIds.contains(id));

                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.call_outlined,
                    title: 'No calls yet',
                    subtitle: 'Your call history will appear here.',
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    return _CallTile(
                      data: d.data(),
                      myUid: myUid,
                      selecting: _selecting,
                      selected: _selected.contains(d.id),
                      onToggle: () => _toggle(d.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionBar() {
    final allSelected =
        _visibleIds.isNotEmpty && _selected.length == _visibleIds.length;
    return Material(
      color: AppColors.brown900,
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _selected.clear()),
            ),
            Expanded(
              child: Text(
                '${_selected.length} selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: allSelected ? 'Unselect all' : 'Select all',
              icon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
                color: Colors.white,
              ),
              onPressed: _selectAll,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _deleteSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String myUid;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;

  const _CallTile({
    required this.data,
    required this.myUid,
    required this.selecting,
    required this.selected,
    required this.onToggle,
  });

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
      selected: selected,
      selectedTileColor: AppColors.gold700.withValues(alpha: 0.14),
      // Lamba dabane se selection shuru, phir tap se select / unselect
      onLongPress: onToggle,
      onTap: selecting ? onToggle : null,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          UserAvatar(username: name, photoUrl: photo, size: 46),
          if (selected)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.gold700,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
            ),
        ],
      ),
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
          color: selecting ? AppColors.brown700 : AppColors.gold700,
        ),
        // Selection mode mein call button band
        onPressed: selecting
            ? null
            : () => placeCall(
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
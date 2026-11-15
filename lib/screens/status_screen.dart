import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../chat_repository.dart';
import '../status_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'status_create_screen.dart';
import 'status_viewer_screen.dart';

DateTime _timeOf(StatusItem i) =>
    i.createdAt ?? i.expiresAt.subtract(statusLifetime);

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) {
    final m = d.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  final h = d.inHours;
  return '$h ${h == 1 ? 'hour' : 'hours'} ago';
}

/// Ek contact ke saare active statuses (purana pehle)
class _Group {
  final String ownerId;
  final List<StatusItem> items;
  _Group(this.ownerId, this.items);

  DateTime get latest => _timeOf(items.last);
  bool hasUnseen(String me) => items.any((i) => !i.viewedByMe(me));
}

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final String _me = FirebaseAuth.instance.currentUser!.uid;
  late final Stream<List<StatusItem>> _feed = statusRepo.feedStream();
  late final Stream<List<StatusItem>> _mine = statusRepo.myStream();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // har minute "x minutes ago" aur expiry dobara check
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _soon([String what = 'Coming soon']) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(what)));
  }

  void _openMine(List<StatusItem> items) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          ownerIds: [_me],
          groups: {_me: items},
          isMine: true,
        ),
      ),
    );
  }

  /// Is contact se shuru, phir list ke baaqi contacts khud chalte hain
  void _openGroups(List<_Group> ordered, _Group start) {
    final from = ordered.indexOf(start);
    final queue = ordered.sublist(from < 0 ? 0 : from);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          ownerIds: [for (final g in queue) g.ownerId],
          groups: {for (final g in queue) g.ownerId: g.items},
          isMine: false,
        ),
      ),
    );
  }

  // ---------------- UI pieces ----------------

  Widget _card({required Widget child, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
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
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: AppColors.brown700,
        ),
      ),
    );
  }

  Widget _titleSubtitle(String title, String subtitle) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
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
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.brown700),
          ),
        ],
      ),
    );
  }

  /// Sab se upar: mera apna status
  Widget _myTile(List<StatusItem> mine) {
    final has = mine.isNotEmpty;
    return _UserBuilder(
      uid: _me,
      builder: (context, username, photo) {
        return _card(
          onTap: has ? () => _openMine(mine) : () => startNewStatus(context),
          child: Row(
            children: [
              _StatusRing(
                // apne statuses ki ring hamesha "unseen" rang mein
                seen: [for (final _ in mine) false],
                username: username,
                photoUrl: photo,
                badge: has
                    ? null
                    : Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold700,
                    border: Border.all(color: softCardColor, width: 2),
                  ),
                  child: const Icon(Icons.add,
                      size: 14, color: AppColors.cream),
                ),
              ),
              const SizedBox(width: 12),
              _titleSubtitle(
                'My status',
                has
                    ? '${mine.length} ${mine.length == 1 ? 'update' : 'updates'} · ${_ago(_timeOf(mine.last))}'
                    : 'Tap to add status update',
              ),
              if (has)
                IconButton(
                  tooltip: 'Add status',
                  icon: const Icon(Icons.add_circle_outline,
                      color: AppColors.gold700),
                  onPressed: () => startNewStatus(context),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Kisi contact ka status
  Widget _contactTile(_Group g, List<_Group> ordered) {
    return _UserBuilder(
      uid: g.ownerId,
      builder: (context, username, photo) {
        return _card(
          onTap: () => _openGroups(ordered, g),
          child: Row(
            children: [
              _StatusRing(
                seen: [for (final i in g.items) i.viewedByMe(_me)],
                username: username,
                photoUrl: photo,
              ),
              const SizedBox(width: 12),
              _titleSubtitle(username, _ago(g.latest)),
            ],
          ),
        );
      },
    );
  }

  Widget _newStatusButton() {
    return Container(
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
          onTap: () => startNewStatus(context),
          child: const Icon(Icons.camera_alt_outlined, color: AppColors.cream),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String text) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold700),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.brown900,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.black),
      color: softCardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (_) => _soon(),
      itemBuilder: (_) => [
        _menuItem('privacy', Icons.lock_outline, 'Status privacy'),
        _menuItem('settings', Icons.settings_outlined, 'Settings'),
      ],
    );
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      floatingActionButton: _newStatusButton(),
      body: Column(
        children: [
          GradientHeader(title: 'Status', actions: [_menu()]),
          Expanded(
            child: StreamBuilder<List<StatusItem>>(
              stream: _mine,
              builder: (context, mineSnap) {
                if (mineSnap.hasError) debugPrint('my status error: ${mineSnap.error}');
                final mine = (mineSnap.data ?? const <StatusItem>[])
                    .where((i) => !i.isExpired)
                    .toList()
                  ..sort((a, b) => _timeOf(a).compareTo(_timeOf(b)));

                return StreamBuilder<List<StatusItem>>(
                  stream: _feed,
                  builder: (context, feedSnap) {
                    if (feedSnap.hasError) {
                      // pehli baar yahan index ka link console mein aayega
                      debugPrint('status feed error: ${feedSnap.error}');
                    }

                    final items = (feedSnap.data ?? const <StatusItem>[])
                        .where((i) => !i.isExpired && i.ownerId != _me)
                        .toList();

                    final byOwner = <String, List<StatusItem>>{};
                    for (final i in items) {
                      byOwner.putIfAbsent(i.ownerId, () => []).add(i);
                    }
                    final groups = byOwner.entries.map((e) {
                      final l = e.value
                        ..sort((a, b) => _timeOf(a).compareTo(_timeOf(b)));
                      return _Group(e.key, l);
                    }).toList()
                      ..sort((a, b) => b.latest.compareTo(a.latest));

                    final recent =
                    groups.where((g) => g.hasUnseen(_me)).toList();
                    final viewed =
                    groups.where((g) => !g.hasUnseen(_me)).toList();
                    final ordered = [...recent, ...viewed];

                    final loading = feedSnap.connectionState ==
                        ConnectionState.waiting &&
                        !feedSnap.hasData;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      children: [
                        _myTile(mine),
                        if (feedSnap.hasError)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Could not load updates. Please try again later.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.brown700),
                            ),
                          ),
                        if (recent.isNotEmpty) ...[
                          _section('Recent updates'),
                          for (final g in recent) _contactTile(g, ordered),
                        ],
                        if (viewed.isNotEmpty) ...[
                          _section('Viewed updates'),
                          for (final g in viewed) _contactTile(g, ordered),
                        ],
                        if (groups.isEmpty && !loading && !feedSnap.hasError)
                          const SizedBox(
                            height: 320,
                            child: EmptyState(
                              icon: Icons.donut_large_rounded,
                              title: 'No updates yet',
                              subtitle:
                              'Status updates from your contacts will appear here.',
                            ),
                          ),
                      ],
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
}

/// uid se username + photo la kar builder ko deta hai (cache pehle)
class _UserBuilder extends StatefulWidget {
  final String uid;
  final Widget Function(BuildContext context, String username, String photoUrl)
  builder;
  const _UserBuilder({required this.uid, required this.builder});

  @override
  State<_UserBuilder> createState() => _UserBuilderState();
}

class _UserBuilderState extends State<_UserBuilder> {
  late Future<Map<String, dynamic>?> _future = chatRepo.getUser(widget.uid);

  @override
  void didUpdateWidget(covariant _UserBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _future = chatRepo.getUser(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      key: ValueKey(widget.uid),
      future: _future,
      initialData: chatRepo.cachedUser(widget.uid),
      builder: (context, snap) {
        final user = snap.data;
        final username = (user?['username'] as String?) ??
            (snap.connectionState == ConnectionState.done
                ? 'Unknown user'
                : '...');
        final photo = (user?['photoUrl'] as String?) ?? '';
        return widget.builder(context, username, photo);
      },
    );
  }
}

/// Avatar ke gird ring: har status ka ek hissa, dekha hua = halka, nahi dekha = gold
class _StatusRing extends StatelessWidget {
  final List<bool> seen; // purana pehle; true = dekh liya
  final String username;
  final String photoUrl;
  final Widget? badge;

  const _StatusRing({
    required this.seen,
    required this.username,
    required this.photoUrl,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _RingPainter(seen))),
          Center(
            child: UserAvatar(username: username, photoUrl: photoUrl, size: 50),
          ),
          if (badge != null) Positioned(right: 0, bottom: 0, child: badge!),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final List<bool> seen;
  _RingPainter(this.seen);

  @override
  void paint(Canvas canvas, Size size) {
    if (seen.isEmpty) return;
    const stroke = 3.0;
    final rect = const Offset(stroke / 2, stroke / 2) &
    Size(size.width - stroke, size.height - stroke);

    final n = seen.length;
    final gap = n == 1 ? 0.0 : 0.16; // segments ke beech khali jagah (radian)
    final sweep = 2 * math.pi / n;

    for (var i = 0; i < n; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = seen[i]
            ? AppColors.brown700.withValues(alpha: 0.35)
            : AppColors.gold500;
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep + gap / 2,
        sweep - gap,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => !listEquals(old.seen, seen);
}
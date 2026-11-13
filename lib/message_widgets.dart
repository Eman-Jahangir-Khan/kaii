import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Helpers (public, taake chat aur group dono use kar saken)
// ---------------------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime? t) {
  if (t == null) return '';
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final suffix = t.hour < 12 ? 'AM' : 'PM';
  return '$h:${_two(t.minute)} $suffix';
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_two(t.day)}/${_two(t.month)}/${t.year}';
}

/// Group mein har sender ka apna rang (uid se tay hota hai)
const _senderColors = <Color>[
  Color(0xFF8E3B2F),
  Color(0xFF2F6B4F),
  Color(0xFF3B5B8E),
  Color(0xFF7A4E9B),
  Color(0xFF9B6A12),
  Color(0xFF1F7A7A),
  Color(0xFFA33C6B),
  Color(0xFF5B6B2F),
];

Color senderColor(String uid) {
  var h = 0;
  for (final c in uid.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _senderColors[h % _senderColors.length];
}

// ---------------------------------------------------------------------------
// Message bubble
// ---------------------------------------------------------------------------

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool mine;
  final bool pending;

  /// sab members ne padh liya (double tick)
  final bool seen;
  final DateTime? time;

  /// group mein doosron ke message par sender ka naam dikhao
  final bool showSender;
  final String replyName;
  final VoidCallback? onReplyTap;
  final void Function(String url)? onImageTap;

  const MessageBubble({
    super.key,
    required this.data,
    required this.mine,
    required this.pending,
    required this.time,
    this.seen = false,
    this.showSender = false,
    this.replyName = '',
    this.onReplyTap,
    this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final deleted = data['deletedForAll'] == true;
    final isImage = data['type'] == 'image' && data['imageUrl'] is String;
    final text = (data['text'] as String?) ?? '';
    final fg = mine ? AppColors.cream : AppColors.brown900;
    final meta =
    mine ? AppColors.cream.withValues(alpha: 0.78) : AppColors.brown700;
    final maxW = MediaQuery.of(context).size.width * 0.78;
    final senderId = (data['senderId'] as String?) ?? '';
    final senderName = (data['senderName'] as String?) ?? '';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? null : softCardColor,
            gradient: mine
                ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gold500, AppColors.gold700],
            )
                : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brown900.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSender && !mine && senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: senderColor(senderId),
                      ),
                    ),
                  ),
                if (data['forwarded'] == true && !deleted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forward, size: 13, color: meta),
                        const SizedBox(width: 4),
                        Text(
                          'Forwarded',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: meta,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (data['replyTo'] is Map && !deleted)
                  GestureDetector(
                    onTap: onReplyTap,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                          decoration: BoxDecoration(
                            color: (mine ? Colors.black : AppColors.gold500)
                                .withValues(alpha: 0.15),
                            border: Border(
                              left: BorderSide(
                                color:
                                mine ? AppColors.cream : AppColors.gold700,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                replyName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: mine
                                      ? AppColors.cream
                                      : AppColors.gold700,
                                ),
                              ),
                              Text(
                                ((data['replyTo'] as Map)['text']
                                as String?) ??
                                    '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: meta),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (deleted)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 15, color: meta),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'This message was deleted',
                          style: TextStyle(
                            color: meta,
                            fontSize: 14.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  if (isImage)
                    GestureDetector(
                      onTap: () => onImageTap?.call(data['imageUrl'] as String),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: (data['width'] is num &&
                              data['height'] is num &&
                              (data['height'] as num) > 0)
                              ? (data['width'] as num) /
                              (data['height'] as num)
                              : 1,
                          child: CachedNetworkImage(
                            imageUrl: data['imageUrl'] as String,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  if (text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: isImage ? 6 : 0),
                      child: Text(
                        text,
                        style:
                        TextStyle(color: fg, fontSize: 15.5, height: 1.3),
                      ),
                    ),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (data['edited'] == true && !deleted) ...[
                        Text(
                          'edited',
                          style: TextStyle(
                            fontSize: 11,
                            color: meta,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        hhmm(time),
                        style: TextStyle(fontSize: 11, color: meta),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          pending
                              ? Icons.access_time
                              : (seen ? Icons.done_all : Icons.done),
                          size: 14,
                          color: seen && !pending ? Colors.white : meta,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Swipe to reply
// ---------------------------------------------------------------------------

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _trigger = 60.0;
  static const _maxDrag = 80.0;

  late final AnimationController _ctrl;
  Animation<double>? _anim;
  double _dx = 0;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
      final a = _anim;
      if (a != null) setState(() => _dx = a.value);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    _ctrl.stop();
    final next = (_dx + d.delta.dx).clamp(0.0, _maxDrag);
    if (!_fired && next >= _trigger) {
      _fired = true;
      HapticFeedback.lightImpact();
    }
    setState(() => _dx = next);
  }

  void _onEnd() {
    if (_fired) widget.onReply();
    _fired = false;
    _anim = Tween<double>(begin: _dx, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: (_) => _onEnd(),
      onHorizontalDragCancel: _onEnd,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: p,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * p,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.gold500.withValues(alpha: 0.25),
                    ),
                    child: const Icon(Icons.reply,
                        size: 18, color: AppColors.brown700),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reaction pill, date chip
// ---------------------------------------------------------------------------

class ReactionPill extends StatelessWidget {
  final Map reactions;
  final String myUid;
  const ReactionPill({super.key, required this.reactions, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final e in reactions.values) {
      if (e is String) counts[e] = (counts[e] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final emojis = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final iReacted = reactions[myUid] is String;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: softCardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iReacted ? AppColors.gold700 : AppColors.gold200,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brown900.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emojis.take(3).map((e) => e.key).join(),
            style: const TextStyle(fontSize: 14),
          ),
          if (total > 1) ...[
            const SizedBox(width: 4),
            Text(
              '$total',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.brown700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DateChip extends StatelessWidget {
  final String label;
  const DateChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.gold500.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.brown700,
          ),
        ),
      ),
    );
  }
}
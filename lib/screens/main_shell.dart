import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../badge_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'calls_screen.dart';
import 'groups_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'status_screen.dart';

/// 5 tabs + animated bottom bar
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _pageCtrl = PageController();

  // tab par aakar "dekh liya" wali ginti (badge = value - seen)
  int _seenChats = 0;
  int _seenGroups = 0;
  int _seenStatus = 0;

  @override
  void initState() {
    super.initState();
    BadgeService.instance.start();
    chatsUnread.addListener(_onBadgeSource);
    groupsUnread.addListener(_onBadgeSource);
    statusUnseen.addListener(_onBadgeSource);
    _syncSeen();
  }

  @override
  void dispose() {
    chatsUnread.removeListener(_onBadgeSource);
    groupsUnread.removeListener(_onBadgeSource);
    statusUnseen.removeListener(_onBadgeSource);
    BadgeService.instance.stop();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onBadgeSource() {
    if (!mounted) return;
    setState(_syncSeen);
  }

  /// Jo tab abhi khuli hai uska badge saaf, baqi tabs ke liye seen ko
  /// value se upar nahi jane dete (taake count kam ho kar dobara barhe to dikhe)
  void _syncSeen() {
    _seenChats = _index == 0
        ? chatsUnread.value
        : math.min(_seenChats, chatsUnread.value);
    _seenGroups = _index == 1
        ? groupsUnread.value
        : math.min(_seenGroups, groupsUnread.value);
    _seenStatus = _index == 2
        ? statusUnseen.value
        : math.min(_seenStatus, statusUnseen.value);
  }

  int _badgeFor(int tab) {
    if (tab == _index) return 0;
    switch (tab) {
      case 0:
        return math.max(0, chatsUnread.value - _seenChats);
      case 1:
        return math.max(0, groupsUnread.value - _seenGroups);
      case 2:
        return math.max(0, statusUnseen.value - _seenStatus);
      default:
        return 0;
    }
  }

  void _goTo(int i) {
    if (i == _index) return;
    if ((i - _index).abs() == 1) {
      _pageCtrl.animateToPage(
        i,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageCtrl.jumpToPage(i); // door wali tab par beech ke pages nahi guzarte
    }
  }

  Widget _tab(int i, Widget child) => _TabFade(
    controller: _pageCtrl,
    index: i,
    child: _KeepAlive(child: child),
  );

  static const _icons = <IconData>[
    Icons.chat_bubble_outline_rounded,
    Icons.groups_outlined,
    Icons.donut_large_rounded,
    Icons.call_outlined,
    Icons.person_outline_rounded,
  ];
  static const _labels = <String>[
    'Chats',
    'Groups',
    'Status',
    'Calls',
    'Profile',
  ];

  // kin tabs par number dikhana hai (false = sirf dot)
  static const _showCount = <bool>[true, true, false, false, false];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;

    final badges = <int>[for (int i = 0; i < _icons.length; i++) _badgeFor(i)];

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (groupsSelecting.value) return;
        _goTo(0);
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Stack(
          children: [
            // header ke peeche fixed gradient (header ki unchai = status bar + 72)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: media.padding.top + 72,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFFA67917), Color(0xFFE8B84A)],
                  ),
                ),
              ),
            ),
            PageView(
              controller: _pageCtrl,
              onPageChanged: (i) => setState(() {
                _index = i;
                _syncSeen();
              }),
              children: [
                _tab(0, const HomeScreen()),
                _tab(1, const GroupsScreen()),
                _tab(2, const StatusScreen()),
                _tab(3, const CallsScreen()),
                _tab(4, const ProfileScreen()),
              ],
            ),
          ],
        ),
        // keyboard khulne par bar chhupa do taake jagah na ghire
        bottomNavigationBar: keyboardOpen
            ? null
            : Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 10 + media.padding.bottom),
          child: AnimatedNavBar(
            index: _index,
            icons: _icons,
            labels: _labels,
            badges: badges,
            showCount: _showCount,
            onTap: _goTo,
          ),
        ),
      ),
    );
  }
}

class _TabFade extends StatelessWidget {
  final PageController controller;
  final int index;
  final Widget child;
  const _TabFade({
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        double page = index.toDouble();
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? page;
        }
        final t = (1 - (page - index).abs()).clamp(0.0, 1.0);
        return Opacity(opacity: t, child: child);
      },
    );
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ---------------------------------------------------------------------------
// Animated bottom bar
// ---------------------------------------------------------------------------

class AnimatedNavBar extends StatelessWidget {
  final int index;
  final List<IconData> icons;
  final List<String> labels;
  final List<int> badges; // har tab ka badge count (0 = koi badge nahi)
  final List<bool> showCount; // true = number, false = sirf dot
  final ValueChanged<int> onTap;

  const AnimatedNavBar({
    super.key,
    required this.index,
    required this.icons,
    required this.labels,
    required this.badges,
    required this.showCount,
    required this.onTap,
  });

  static const double _barH = 68; // bar ki unchai
  static const double _overhang = 6; // circle bar se kitna upar nikle
  static const double _sidePad = 20; // bar ke andar left/right gap
  static const double _circle = 46; // circle ka size

  @override
  Widget build(BuildContext context) {
    final n = icons.length;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final itemW = (w - _sidePad * 2) / n;

        return TweenAnimationBuilder<double>(
          // index badalte hi purani position se nayi tak slide hota hai
          tween: Tween<double>(end: index.toDouble()),
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          builder: (context, pos, _) {
            final cx = _sidePad + itemW * (pos + 0.5);

            return SizedBox(
              height: _barH + _overhang,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // dark bar (notch ke saath)
                  Positioned(
                    top: _overhang,
                    left: 0,
                    right: 0,
                    height: _barH,
                    child: CustomPaint(
                      painter: _NavBarPainter(
                        cx: cx,
                        color: AppColors.brown900,
                      ),
                    ),
                  ),
                  // icons + badges
                  Positioned(
                    top: _overhang,
                    left: _sidePad,
                    right: _sidePad,
                    height: _barH,
                    child: Row(
                      children: [
                        for (int i = 0; i < n; i++)
                          Expanded(
                            child: Semantics(
                              label: labels[i],
                              button: true,
                              selected: i == index,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onTap(i),
                                child: Center(
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      Opacity(
                                        opacity:
                                        math.min(1.0, (pos - i).abs()),
                                        child: Icon(
                                          icons[i],
                                          size: 24,
                                          color: AppColors.cream
                                              .withValues(alpha: 0.75),
                                        ),
                                      ),
                                      if (badges[i] > 0 && i != index)
                                        Positioned(
                                          top: -6,
                                          right: -8,
                                          child: _NavBadge(
                                            count: badges[i],
                                            showCount: showCount[i],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // sliding gold circle
                  Positioned(
                    left: cx - _circle / 2,
                    top: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: _circle,
                        height: _circle,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.gold500, AppColors.gold700],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold700.withValues(alpha: 0.5),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          icons[math.max(0, math.min(n - 1, pos.round()))],
                          size: 24,
                          color: AppColors.brown900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NavBadge extends StatelessWidget {
  final int count;
  final bool showCount;
  const _NavBadge({required this.count, required this.showCount});

  static const _red = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    if (!showCount) {
      // status: sirf dot
      return Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: _red,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.brown900, width: 1.5),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _red,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.brown900, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _NavBarPainter extends CustomPainter {
  final double cx; // notch ka center (x)
  final Color color;

  _NavBarPainter({required this.cx, required this.color});

  static const double _r = 18; // bar ke konay
  static const double _depth = 45; // notch kitna gehra
  static const double _half = 36; // notch upar se kitna chora (aadha) - 5 tabs ke liye chhota

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // kinaray ke bohat qareeb notch ho to thora tang kar do
    final half = math.min(_half, math.min(cx, w - cx) - _r);
    final k = half / _half;

    final path = Path()
      ..moveTo(0, _r)
      ..quadraticBezierTo(0, 0, _r, 0)
      ..lineTo(cx - half, 0)
      ..cubicTo(cx - 27 * k, 0, cx - 19 * k, _depth, cx, _depth)
      ..cubicTo(cx + 19 * k, _depth, cx + 27 * k, 0, cx + half, 0)
      ..lineTo(w - _r, 0)
      ..quadraticBezierTo(w, 0, w, _r)
      ..lineTo(w, h - _r)
      ..quadraticBezierTo(w, h, w - _r, h)
      ..lineTo(_r, h)
      ..quadraticBezierTo(0, h, 0, h - _r)
      ..close();

    canvas.drawShadow(path, Colors.black, 8, true);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _NavBarPainter old) =>
      old.cx != cx || old.color != color;
}
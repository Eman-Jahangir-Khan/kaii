import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'groups_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

/// 4 tabs + animated bottom bar
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
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

  static const _icons = <IconData>[
    Icons.chat_bubble_outline_rounded,
    Icons.groups_outlined,
    Icons.donut_large_rounded,
    Icons.person_outline_rounded,
  ];
  static const _labels = <String>['Chats', 'Groups', 'Status', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;

    return PopScope(
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _goTo(0);
        },
        child: Scaffold(
      backgroundColor: AppColors.cream,
      // IndexedStack: tab badalne par purani tab ki halat (search wagaira) bani rehti hai
      body: PageView(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          _KeepAlive(child: HomeScreen()),
          _KeepAlive(child: GroupsScreen()),
          _KeepAlive(
            child: _ComingSoonTab(
                title: 'Status', icon: Icons.donut_large_rounded),
          ),
          _KeepAlive(child: ProfileScreen()),
        ],
      ),
      // keyboard khulne par bar chhupa do taake jagah na ghire
      bottomNavigationBar: keyboardOpen
          ? null
          : Padding(
        padding:
        EdgeInsets.fromLTRB(16, 4, 16, 10 + media.padding.bottom),
        child: AnimatedNavBar(
          index: _index,
          icons: _icons,
          labels: _labels,
          onTap: _goTo,
        ),
      ),
        ), );
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

class _ComingSoonTab extends StatelessWidget {
  final String title;
  final IconData icon;
  const _ComingSoonTab({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GradientHeader(title: title),
        Expanded(
          child: EmptyState(
            icon: icon,
            title: 'Coming soon',
            subtitle: '$title will be added after the chat section is done.',
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Animated bottom bar
// ---------------------------------------------------------------------------

class AnimatedNavBar extends StatelessWidget {
  final int index;
  final List<IconData> icons;
  final List<String> labels;
  final ValueChanged<int> onTap;

  const AnimatedNavBar({
    super.key,
    required this.index,
    required this.icons,
    required this.labels,
    required this.onTap,
  });

  static const double _barH = 68; // bar ki unchai
  static const double _overhang = 6; // circle bar se kitna upar nikle
  static const double _sidePad = 28; // bar ke andar left/right gap
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
                  // icons (jo tab chuni ho uska icon circle ke andar chala jata hai)
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
                                  child: Opacity(
                                    opacity: math.min(1.0, (pos - i).abs()),
                                    child: Icon(
                                      icons[i],
                                      size: 24,
                                      color: AppColors.cream
                                          .withValues(alpha: 0.75),
                                    ),
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

class _NavBarPainter extends CustomPainter {
  final double cx; // notch ka center (x)
  final Color color;

  _NavBarPainter({required this.cx, required this.color});

  static const double _r = 18; // bar ke konay
  static const double _depth = 45; // notch kitna gehra
  static const double _half = 46; // notch upar se kitna chora (aadha)

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
      ..cubicTo(cx - 34 * k, 0, cx - 24 * k, _depth, cx, _depth)
      ..cubicTo(cx + 24 * k, _depth, cx + 34 * k, 0, cx + half, 0)
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
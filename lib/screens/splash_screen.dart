import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets.dart';

/// Splash: naya logo scale + fade ke sath aata hai, phir `next` screen par
/// fade ke sath chala jata hai (jaise AuthGate).
class SplashScreen extends StatefulWidget {
  final Widget next;
  final Duration duration;

  const SplashScreen({
    super.key,
    required this.next,
    this.duration = const Duration(milliseconds: 2400),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
  );
  late final Animation<double> _logoScale = Tween<double>(begin: 0.6, end: 1)
      .animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
  ));
  late final Animation<double> _textFade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
  );
  late final Animation<Offset> _textSlide = Tween<Offset>(
    begin: const Offset(0, 0.4),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _c,
    curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
  ));

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeRoute(widget.next));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.brown900,
                AppColors.brown700,
                AppColors.gold700,
              ],
            ),
          ),
          child: Stack(
            children: [
              // halki si decoration circle (auth header jaisi)
              Positioned(
                top: -110,
                right: -80,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold500.withValues(alpha: 0.16),
                  ),
                ),
              ),
              Positioned(
                bottom: -120,
                left: -90,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold500.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                top: 90,
                left: 24,
                child: DotGrid(
                  rows: 5,
                  cols: 5,
                  color: AppColors.gold200.withValues(alpha: 0.25),
                ),
              ),
              Positioned(
                bottom: 90,
                right: 24,
                child: DotGrid(
                  rows: 5,
                  cols: 5,
                  color: AppColors.gold200.withValues(alpha: 0.25),
                ),
              ),

              // logo + naam
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const KaiiLogo(size: 130),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeTransition(
                      opacity: _textFade,
                      child: SlideTransition(
                        position: _textSlide,
                        child: const Text(
                          'kaii',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                            color: AppColors.cream,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // neeche chhota loader
              Positioned(
                left: 0,
                right: 0,
                bottom: 48,
                child: FadeTransition(
                  opacity: _textFade,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.gold200,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
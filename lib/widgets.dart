import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'theme.dart';

/// Final logo: gold card + do "i" (code se bana hua, koi asset nahi)
class KaiiLogo extends StatelessWidget {
  final double size;
  final bool showShadow;
  const KaiiLogo({super.key, this.size = 80, this.showShadow = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(showShadow: showShadow)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool showShadow;
  const _LogoPainter({required this.showShadow});

  // Design 1024x1024 canvas par bana hai, visible hissa 90..926 hai
  static const double _origin = 90;
  static const double _span = 836;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _span);
    canvas.translate(-_origin, -_origin);

    const cardRadius = Radius.circular(110);

    if (showShadow) {
      canvas.drawRRect(
        RRect.fromLTRBR(126, 126, 926, 926, cardRadius),
        Paint()..color = const Color(0xFFA6A6A6),
      );
    }

    const cardRect = Rect.fromLTRB(90, 90, 890, 890);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardRect, cardRadius),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9E7400), Color(0xFFF2B400)],
        ).createShader(cardRect),
    );

    _drawI(canvas, centerX: 390, color: const Color(0xFFFFE75C));
    _drawI(canvas, centerX: 590, color: const Color(0xFF5C4811));

    canvas.restore();
  }

  void _drawI(Canvas canvas, {required double centerX, required Color color}) {
    final paint = Paint()..color = color;
    canvas.drawCircle(Offset(centerX, 315), 55, paint);
    canvas.drawRRect(
      RRect.fromLTRBR(
        centerX - 50,
        385,
        centerX + 50,
        725,
        const Radius.circular(50),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) =>
      old.showShadow != showShadow;
}

/// Neeche se halka sa slide + fade hoke aata hai (delay ke sath)
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double offset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.delay = Duration.zero,
    this.offset = 24,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
  AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _anim =
  CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(
        opacity: _anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _anim.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Fade wala page transition (screens badalte waqt jhatka na lage)
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) =>
      FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 250),
);

/// Form ke items ek ek karke aate hain (index jitna bara, utni der se)
Widget stagger(int index, Widget child) => FadeSlideIn(
  delay: Duration(milliseconds: 300 + index * 90),
  duration: const Duration(milliseconds: 500),
  offset: 18,
  child: child,
);

// ---------------------------------------------------------------------------
// Form widgets
// ---------------------------------------------------------------------------

/// Cream ke upar halka sa white mix, taake fields card alag nazar aaye
Color get _fieldCardColor =>
    Color.alphaBlend(Colors.white.withValues(alpha: 0.65), AppColors.cream);



/// FieldGroup ke andar wali borderless field (chhota label upar, value neeche)
/// Fields ki list, har field ke beech gap (har field ki apni alag card hai)
class FieldGroup extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  const FieldGroup({super.key, required this.children, this.gap = 14});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}

/// Apni alag rounded card wali field (chhota label upar, value neeche)
class CardField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final List<TextInputFormatter>? inputFormatters;
  final String? helper;
  final String? Function(String?)? validator;

  const CardField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.inputFormatters,
    this.helper,
    this.validator,
  });

  static const _error = Color(0xFFB3261E);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _fieldCardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.brown900.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            inputFormatters: inputFormatters,
            validator: validator,
            cursorColor: AppColors.gold700,
            style: const TextStyle(
              color: AppColors.brown900,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: label,
              errorStyle: const TextStyle(color: _error, fontSize: 11),
              labelStyle: const TextStyle(color: AppColors.brown700),
              floatingLabelStyle: const TextStyle(
                color: AppColors.gold700,
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: Icon(icon, color: AppColors.gold700, size: 20),
              suffixIcon: suffix,
              filled: false,
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
            ),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 6),
            child: Text(
              helper!,
              style: const TextStyle(
                color: AppColors.brown700,
                fontSize: 11.5,
              ),
            ),
          ),
      ],
    );
  }
}

/// Full width gradient pill button
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.65,
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gold500, AppColors.gold700],
          ),
          borderRadius: BorderRadius.circular(30),
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
            borderRadius: BorderRadius.circular(30),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.cream,
                ),
              )
                  : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cream,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Decoration helpers
// ---------------------------------------------------------------------------

/// Chhote chhote dots ka grid (reference wali dotted decoration)
class DotGrid extends StatelessWidget {
  final int rows;
  final int cols;
  final double gap;
  final double radius;
  final Color color;

  const DotGrid({
    super.key,
    this.rows = 6,
    this.cols = 6,
    this.gap = 14,
    this.radius = 2,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size((cols - 1) * gap + radius * 2, (rows - 1) * gap + radius * 2),
      painter: _DotPainter(rows, cols, gap, radius, color),
    );
  }
}

class _DotPainter extends CustomPainter {
  final int rows;
  final int cols;
  final double gap;
  final double radius;
  final Color color;

  _DotPainter(this.rows, this.cols, this.gap, this.radius, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(radius + c * gap, radius + r * gap),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) =>
      old.rows != rows ||
          old.cols != cols ||
          old.gap != gap ||
          old.radius != radius ||
          old.color != color;
}

/// Header ke neeche ka wave. flip = true par wave ulta hota hai (signup)
class _WaveClipper extends CustomClipper<Path> {
  final bool flip;
  const _WaveClipper({required this.flip});

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()..moveTo(0, 0);
    if (flip) {
      path
        ..lineTo(0, h - 40)
        ..cubicTo(w * 0.35, h - 110, w * 0.7, h + 10, w, h - 70);
    } else {
      path
        ..lineTo(0, h - 70)
        ..cubicTo(w * 0.3, h + 10, w * 0.65, h - 110, w, h - 40);
    }
    path
      ..lineTo(w, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant _WaveClipper old) => old.flip != flip;
}

// ---------------------------------------------------------------------------
// Auth screens ka common look
// ---------------------------------------------------------------------------

/// Login aur Signup dono ka common UI: upar wave wala gradient header,
/// beech mein form, neeche switch link. Logic apni apni screen mein rehta hai.
class AuthShell extends StatelessWidget {
  final bool isLogin;
  final String title;
  final String subtitle;
  final String footerText;
  final String footerAction;
  final VoidCallback onSwitch;
  final bool showBack;
  final Widget child;

  const AuthShell({
    super.key,
    required this.isLogin,
    required this.title,
    required this.subtitle,
    required this.footerText,
    required this.footerAction,
    required this.onSwitch,
    required this.child,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final headerH = keyboardOpen
        ? 220.0
        : (media.size.height * 0.34).clamp(250.0, 330.0);
    final canGoBack = showBack && Navigator.of(context).canPop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Column(
          children: [
            // ---------- header ----------
            ClipPath(
              clipper: _WaveClipper(flip: !isLogin),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                height: headerH,
                width: double.infinity,
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
                    // halki si decoration circle
                    Positioned(
                      top: -90,
                      right: isLogin ? -70 : null,
                      left: isLogin ? null : -70,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.6, end: 1),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, child) => Opacity(
                          opacity: ((v - 0.6) / 0.4).clamp(0.0, 1.0),
                          child: Transform.scale(scale: v, child: child),
                        ),
                        child: Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.gold500.withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                    ),
                    // dotted decoration
                    Positioned(
                      top: 60,
                      left: isLogin ? 18 : null,
                      right: isLogin ? null : 18,
                      child: DotGrid(
                        rows: 5,
                        cols: 5,
                        color: AppColors.gold200.withValues(alpha: 0.28),
                      ),
                    ),
                    // back button + logo
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            canGoBack
                                ? GestureDetector(
                              onTap: () => Navigator.of(context).maybePop(),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.cream
                                      .withValues(alpha: 0.2),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new,
                                  size: 16,
                                  color: AppColors.cream,
                                ),
                              ),
                            )
                                : const SizedBox(width: 36, height: 36),
                            AnimatedOpacity(
                              opacity: keyboardOpen ? 0 : 1,
                              duration: const Duration(milliseconds: 200),
                              child: const KaiiLogo(size: 48),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // title + subtitle
                    Positioned(
                      left: 28,
                      right: 28,
                      bottom: keyboardOpen ? 44 : 70,
                      child: FadeSlideIn(
                        offset: -20,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 32,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cream,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.gold200,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---------- body ----------
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    bottom: 16,
                    left: 10,
                    child: DotGrid(
                      rows: 6,
                      cols: 6,
                      color: AppColors.gold700.withValues(alpha: 0.16),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        28,
                        8,
                        28,
                        12 + media.padding.bottom,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: c.maxHeight - 8 - 12 - media.padding.bottom,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              child,
                              const Spacer(),
                              const SizedBox(height: 16),
                              _footer(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          footerText,
          style: const TextStyle(color: AppColors.brown700, fontSize: 13),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSwitch,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              footerAction,
              style: const TextStyle(
                color: AppColors.gold700,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chat UI helpers
// ---------------------------------------------------------------------------

/// Fields wale card jaisa halka sa white mix, list tiles ke liye
Color get softCardColor =>
    Color.alphaBlend(Colors.white.withValues(alpha: 0.65), AppColors.cream);

/// Photo ho to photo, warna username ka pehla harf gold circle mein
class UserAvatar extends StatelessWidget {
  final String username;
  final String photoUrl;
  final double size;

  const UserAvatar({
    super.key,
    required this.username,
    this.photoUrl = '',
    this.size = 50,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.isNotEmpty;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.gold500, AppColors.gold700],
        ),
        image: hasPhoto
            ? DecorationImage(image: NetworkImage(photoUrl), fit: BoxFit.cover)
            : null,
      ),
      child: hasPhoto
          ? null
          : Text(
        username.isEmpty ? '?' : username[0].toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          color: AppColors.cream,
        ),
      ),
    );
  }
}

/// Upar ka gradient header (neeche se rounded), chat screens ke liye
/// Upar ka halka gradient header (chat screens ke liye)
class GradientHeader extends StatelessWidget {
  final String title;
  final TextStyle? titleStyle;
  final bool showBack;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;
  final String? subtitle;

  const GradientHeader({
    super.key,
    required this.title,
    this.titleStyle,
    this.showBack = false,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // halke background par status bar ke icons gehre hone chahiye
      value: SystemUiOverlayStyle.dark,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFA67917), Color(0xFFE8B84A)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        if (showBack)
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 18,
                          color: Colors.black,
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ).merge(titleStyle),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.black87,
                              ),
                            ),
                        ],
                      ),
                    ),
                        ...actions,
                      ],
                    ),
                ),
                if (bottom != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: bottom!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Khali list / error / loading ke baad ka message
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold500.withValues(alpha: 0.18),
              ),
              child: Icon(icon, size: 44, color: AppColors.gold700),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.brown900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.brown700, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// "or" wali patli line
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(
        thickness: 1,
        color: AppColors.gold700.withValues(alpha: 0.35),
      ),
    );
    return Row(
      children: [
        line,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(color: AppColors.brown700, fontSize: 13),
          ),
        ),
        line,
      ],
    );
  }
}

/// Google wala outlined button
class GoogleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const GoogleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brown900,
          backgroundColor: softCardColor,
          side: const BorderSide(color: AppColors.gold700, width: 1.5),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: loading
            ? const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.gold700,
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.g_mobiledata,
                size: 34, color: AppColors.gold700),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}


class RequestButton extends StatelessWidget {
  const RequestButton({
    super.key,
    required this.otherUid,
    required this.onOpenChat, // yahan apni ChatScreen kholo
  });

  final String otherUid;
  final VoidCallback onOpenChat;

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final ids = [me, otherUid]..sort(); // rules mein participants[0]_participants[1]
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc('${ids[0]}_${ids[1]}');

    Widget filled(String label, VoidCallback onTap) =>
        ElevatedButton(onPressed: onTap, child: Text(label));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 48);
        final data = snap.data!.data();
        final status = data == null ? null : (data['status'] ?? 'accepted');
        final requestedBy = data?['requestedBy'];

        void sendRequest() => data == null
            ? ref.set({
          'participants': ids,
          'status': 'pending',
          'requestedBy': me,
          'createdAt': FieldValue.serverTimestamp(),
        })
            : ref.update({'status': 'pending', 'requestedBy': me});

        if (status == null) return filled('Request', sendRequest);
        if (status == 'accepted') return filled('Message', onOpenChat);

        if (status == 'pending') {
          if (requestedBy == me) {
            return OutlinedButton(
              onPressed: () => ref.delete(),
              child: const Text('Cancel request'),
            );
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              filled('Accept', () => ref.update({'status': 'accepted'})),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => ref.update({'status': 'rejected'}),
                child: const Text('Reject'),
              ),
            ],
          );
        }

        // rejected
        return requestedBy == me
            ? const Text('Request declined')
            : filled('Request', sendRequest);
      },
    );
  }
}
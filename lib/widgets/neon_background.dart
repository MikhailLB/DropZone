import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme.dart';

/// Animated neon "burst of rays" background, drawn entirely in code so there
/// is no baked-in text. Used behind the menu and other static screens.
class NeonBackground extends StatefulWidget {
  final Widget? child;
  const NeonBackground({super.key, this.child});

  @override
  State<NeonBackground> createState() => _NeonBackgroundState();
}

class _NeonBackgroundState extends State<NeonBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Very long duration so the loop boundary is never visible in a session.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 100000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _NeonPainter(_controller),
          isComplex: true,
          willChange: true,
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _NeonPainter extends CustomPainter {
  final Animation<double> anim;
  _NeonPainter(this.anim) : super(repaint: anim);

  static const _rayColors = [
    DZColors.red,
    DZColors.blue,
    DZColors.green,
    DZColors.yellow,
    DZColors.cyan,
    DZColors.purple,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 100000; // seconds elapsed
    final rect = Offset.zero & size;

    // Base gradient.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.2,
          colors: [Color(0xFF20204A), DZColors.bg],
        ).createShader(rect),
    );

    final center = Offset(size.width * 0.5, size.height * 0.42);

    // Soft central glow.
    canvas.drawCircle(
      center,
      size.width * 0.36,
      Paint()
        ..color = DZColors.cyan.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );

    // Rotating, pulsing rays.
    const rayCount = 16;
    final maxLen = size.height * 0.75;
    final rot = t * 0.06;
    for (int i = 0; i < rayCount; i++) {
      final base = (i / rayCount) * math.pi * 2 + rot;
      final color = _rayColors[i % _rayColors.length];
      final pulse = 0.55 + 0.45 * math.sin(t * 1.1 + i * 0.9);
      final len = maxLen * (0.45 + 0.55 * pulse);
      final inner = size.width * 0.06;

      final p1 = center + Offset(math.cos(base), math.sin(base)) * inner;
      final p2 = center + Offset(math.cos(base), math.sin(base)) * len;

      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.width * (0.012 + 0.01 * pulse)
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0.55 * pulse),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromPoints(p1, p2))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawLine(p1, p2, paint);
    }

    // Floating sparkle particles drifting upward.
    final rng = math.Random(99);
    final spark = Paint();
    for (int i = 0; i < 36; i++) {
      final bx = rng.nextDouble() * size.width;
      final speed = 8 + rng.nextDouble() * 22;
      final by = (size.height - (t * speed + rng.nextDouble() * size.height) %
              (size.height + 40));
      final tw = 0.5 + 0.5 * math.sin(t * 2 + i);
      final c = _rayColors[i % _rayColors.length];
      spark
        ..color = c.withValues(alpha: 0.10 + 0.25 * tw)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(Offset(bx, by), 1.4 + 1.6 * tw, spark);
    }
  }

  @override
  bool shouldRepaint(covariant _NeonPainter oldDelegate) => true;
}

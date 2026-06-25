import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../theme.dart';
import 'engine.dart';
import 'sprites.dart';

class GamePainter extends CustomPainter {
  final DropZoneEngine engine;
  final GameSprites sprites;
  final double time;

  GamePainter({
    required this.engine,
    required this.sprites,
    required this.time,
  });

  static const _zoneColors = DZColors.ballColors;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawZones(canvas);
    _drawObstacles(canvas);
    _drawTrails(canvas);
    _drawBalls(canvas);
    _drawEffects(canvas);
    _drawLauncher(canvas);
    _drawPopups(canvas);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.3),
        radius: 1.1,
        colors: [Color(0xFF1A1A3A), DZColors.bg],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    // Subtle drifting stars.
    final star = Paint()..color = Colors.white.withValues(alpha: 0.25);
    final rng = math.Random(7);
    for (int i = 0; i < 40; i++) {
      final bx = rng.nextDouble() * size.width;
      final by = (rng.nextDouble() * size.height + time * 8) % size.height;
      final tw = 0.5 + 0.5 * math.sin(time * 2 + i);
      star.color = Colors.white.withValues(alpha: 0.06 + 0.10 * tw);
      canvas.drawCircle(Offset(bx, by), 1.1, star);
    }
  }

  void _drawZones(Canvas canvas) {
    final top = engine.zoneTop;
    final h = engine.height - top;
    for (final z in engine.zones) {
      final color = _zoneColors[z.colorIndex];
      final r = Rect.fromLTRB(z.left + 3, top + 3, z.right - 3, engine.height - 3);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));

      final fill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.10 + 0.18 * z.pulse),
            color.withValues(alpha: 0.30 + 0.30 * z.pulse),
          ],
        ).createShader(r);
      canvas.drawRRect(rr, fill);

      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = color.withValues(alpha: 0.85)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 3 + 6 * z.pulse.clamp(0, 1));
      canvas.drawRRect(rr, border);

      // Target rings in the center of each zone.
      final cx = z.center;
      final cy = top + h * 0.5;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.5);
      canvas.drawCircle(Offset(cx, cy), h * 0.28, ring);
      canvas.drawCircle(Offset(cx, cy), h * 0.16, ring);
    }
  }

  void _drawObstacles(Canvas canvas) {
    for (final o in engine.obstacles) {
      final ui.Image? img;
      switch (o.type) {
        case ObstacleType.splitter2:
          img = sprites.images['splitter2'];
          break;
        case ObstacleType.splitter3:
          img = sprites.images['splitter3'];
          break;
        case ObstacleType.mirror:
          img = sprites.images['mirror'];
          break;
      }
      if (img == null) continue;
      final r = o.radius * 1.45;
      final dst = Rect.fromCenter(center: o.center, width: r * 2, height: r * 2);
      _drawImageFit(canvas, img, dst, opacity: 1.0);
    }
  }

  void _drawTrails(Canvas canvas) {
    for (final b in engine.balls) {
      if (b.trail.length < 2) continue;
      final color = _zoneColors[b.colorIndex];
      for (int i = 0; i < b.trail.length; i++) {
        final f = i / b.trail.length;
        final p = Paint()
          ..color = color.withValues(alpha: 0.04 + 0.18 * f)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(b.trail[i], b.radius * (0.4 + 0.5 * f), p);
      }
    }
  }

  void _drawBalls(Canvas canvas) {
    for (final b in engine.balls) {
      final img = sprites.ball(b.colorIndex);
      final color = _zoneColors[b.colorIndex];
      final glow = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.radius * 0.8);
      canvas.drawCircle(b.pos, b.radius * 1.1, glow);
      if (img != null) {
        final dst = Rect.fromCenter(
            center: b.pos, width: b.radius * 2.6, height: b.radius * 2.6);
        _drawImageFit(canvas, img, dst);
      }
    }
  }

  void _drawEffects(Canvas canvas) {
    final img = sprites.images['explode'];
    for (final e in engine.effects) {
      final color = _zoneColors[e.colorIndex];
      final t = e.t;
      final scale = e.success ? (0.3 + t * 1.2) : (0.2 + t * 0.9);
      final opacity = (1 - t).clamp(0.0, 1.0);
      if (img != null && e.success) {
        final s = e.size * scale;
        final dst = Rect.fromCenter(center: e.pos, width: s, height: s);
        _drawImageFit(canvas, img, dst, opacity: opacity);
      } else {
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t)
          ..color = color.withValues(alpha: opacity * 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(e.pos, e.size * scale, ring);
      }
    }
  }

  void _drawLauncher(Canvas canvas) {
    if (engine.state != RoundState.aiming) return;
    final x = engine.launcherX;
    final yTop = engine.launchY;
    final color = _zoneColors[engine.launcherColor];

    // Dashed aim guide.
    final dash = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    double y = yTop + engine.ballRadius * 2;
    final end = engine.zoneTop;
    while (y < end) {
      canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 14, end)), dash);
      y += 26;
    }

    // Launcher housing.
    final housing = Paint()
      ..color = DZColors.bgPanelLight
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, yTop - engine.ballRadius * 0.4),
            width: engine.ballRadius * 3.4, height: engine.ballRadius * 2.4),
        const Radius.circular(8),
      ),
      housing,
    );

    // Preview ball.
    final img = sprites.ball(engine.launcherColor);
    final glow = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, engine.ballRadius);
    canvas.drawCircle(Offset(x, yTop), engine.ballRadius * 1.1, glow);
    if (img != null) {
      final dst = Rect.fromCenter(
          center: Offset(x, yTop),
          width: engine.ballRadius * 2.6,
          height: engine.ballRadius * 2.6);
      _drawImageFit(canvas, img, dst);
    }
  }

  void _drawPopups(Canvas canvas) {
    for (final p in engine.popups) {
      final color = _zoneColors[p.colorIndex];
      final opacity = (1 - p.t).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            fontSize: p.matched ? 22 : 15,
            fontWeight: FontWeight.w900,
            color: (p.matched ? color : DZColors.textDim)
                .withValues(alpha: opacity),
            shadows: [
              Shadow(color: color.withValues(alpha: opacity * 0.8), blurRadius: 10),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.pos.dx - tp.width / 2, p.pos.dy - tp.height));
    }
  }

  void _drawImageFit(Canvas canvas, ui.Image img, Rect dst,
      {double opacity = 1.0}) {
    final src = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble());
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Colors.white.withValues(alpha: opacity);
    canvas.drawImageRect(img, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}

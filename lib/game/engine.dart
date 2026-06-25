import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ObstacleType { splitter2, splitter3, mirror }

enum RoundState { aiming, won, lost }

class Ball {
  Offset pos;
  Offset vel;
  int colorIndex;
  double radius;
  int splitBudget;

  /// Id of the splitter this ball just emerged from (to avoid instant re-split).
  int ignoreSplitterId = -1;
  double ignoreTimer = 0;
  bool alive = true;

  /// Recent positions for the neon motion trail.
  final List<Offset> trail = [];

  Ball({
    required this.pos,
    required this.vel,
    required this.colorIndex,
    required this.radius,
    required this.splitBudget,
  });
}

class Obstacle {
  final int id;
  final ObstacleType type;
  Offset center;
  double radius;
  double cooldown = 0;
  double spin;

  Obstacle({
    required this.id,
    required this.type,
    required this.center,
    required this.radius,
    this.spin = 0,
  });
}

class Zone {
  final double left;
  final double right;
  final int colorIndex;
  double pulse = 0;
  Zone(this.left, this.right, this.colorIndex);

  double get center => (left + right) / 2;
}

/// Visual-only effect (split spark / zone explosion).
class Fx {
  Offset pos;
  double age = 0;
  final double life;
  final int colorIndex;
  final double size;
  final bool success;
  Fx({
    required this.pos,
    required this.life,
    required this.colorIndex,
    required this.size,
    required this.success,
  });

  double get t => (age / life).clamp(0.0, 1.0);
}

/// Floating "+score" popup.
class ScorePopup {
  Offset pos;
  double age = 0;
  final double life;
  final String text;
  final int colorIndex;
  final bool matched;
  ScorePopup({
    required this.pos,
    required this.life,
    required this.text,
    required this.colorIndex,
    required this.matched,
  });

  double get t => (age / life).clamp(0.0, 1.0);
}

/// The full physics + scoring simulation for one level.
class DropZoneEngine {
  // Field dimensions (play area in logical px).
  double width = 0;
  double height = 0;
  bool built = false;

  // Level / progression inputs.
  final int level;
  final int targetScore;
  final int totalBalls;
  final int zoneCount;
  final int splitterCount;
  final int mirrorCount;
  final int splitBudget;
  final double scoreMultiplier;
  final int coinsPerMatch;
  final double magnetStrength;

  // Runtime state.
  final List<Ball> balls = [];
  final List<Obstacle> obstacles = [];
  final List<Zone> zones = [];
  final List<Fx> effects = [];
  final List<ScorePopup> popups = [];

  int ballsLeft;
  int score = 0;
  int coinsEarned = 0;
  int combo = 0;
  int bestCombo = 0;
  RoundState state = RoundState.aiming;

  double launcherX = 0;
  int launcherColor = 0;
  double dropCooldown = 0;
  double zoneTop = 0;

  // Callbacks for sound / haptics.
  void Function(bool matched)? onCapture;
  void Function()? onSplit;
  void Function(bool won)? onRoundEnd;

  final math.Random _rng;
  int _nextObstacleId = 0;

  DropZoneEngine({
    required this.level,
    required this.targetScore,
    required this.totalBalls,
    required this.zoneCount,
    required this.splitterCount,
    required this.mirrorCount,
    required this.splitBudget,
    required this.scoreMultiplier,
    required this.coinsPerMatch,
    required this.magnetStrength,
  })  : ballsLeft = totalBalls,
        _rng = math.Random(level * 7919 + 13) {
    launcherColor = _rng.nextInt(4);
  }

  double get gravity => 2.15 * height;
  double get ballRadius => 0.030 * width;
  double get obstacleRadius => 0.052 * width;
  double get launchY => 0.085 * height;

  void build(Size size) {
    if (built && size.width == width && size.height == height) return;
    width = size.width;
    height = size.height;
    launcherX = width / 2;
    final zoneHeight = 0.085 * height;
    zoneTop = height - zoneHeight;

    _buildZones();
    _buildObstacles();
    // Start with a color that actually has a zone on the board.
    if (!activeZoneColors.contains(launcherColor)) {
      launcherColor = zones.first.colorIndex;
    }
    built = true;
  }

  void _buildZones() {
    zones.clear();
    final seg = width / zoneCount;
    // Choose a color layout: ensure variety, allow repeats for larger counts.
    final colors = <int>[];
    final pool = [0, 1, 2, 3]..shuffle(_rng);
    for (int i = 0; i < zoneCount; i++) {
      colors.add(pool[i % 4]);
    }
    colors.shuffle(_rng);
    for (int i = 0; i < zoneCount; i++) {
      zones.add(Zone(i * seg, (i + 1) * seg, colors[i]));
    }
  }

  void _buildObstacles() {
    obstacles.clear();
    final topBound = 0.20 * height;
    final bottomBound = zoneTop - obstacleRadius * 2.2;
    final minDist = obstacleRadius * 2.4;

    int placed = 0;
    int attempts = 0;
    final total = splitterCount + mirrorCount;
    while (placed < total && attempts < 2000) {
      attempts++;
      final x = obstacleRadius * 1.5 +
          _rng.nextDouble() * (width - obstacleRadius * 3);
      final y = topBound + _rng.nextDouble() * (bottomBound - topBound);
      final c = Offset(x, y);
      bool ok = true;
      for (final o in obstacles) {
        if ((o.center - c).distance < minDist) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;

      final isSplitter = placed < splitterCount;
      ObstacleType type;
      if (isSplitter) {
        type = _rng.nextBool() ? ObstacleType.splitter3 : ObstacleType.splitter2;
      } else {
        type = ObstacleType.mirror;
      }
      obstacles.add(Obstacle(
        id: _nextObstacleId++,
        type: type,
        center: c,
        radius: obstacleRadius,
        spin: (_rng.nextDouble() - 0.5) * 0.8,
      ));
      placed++;
    }
  }

  void moveLauncher(double x) {
    launcherX = x.clamp(ballRadius * 1.5, width - ballRadius * 1.5);
  }

  void setLauncherColor(int colorIndex) {
    launcherColor = colorIndex.clamp(0, 3);
  }

  /// Colors that currently have at least one matching zone.
  Set<int> get activeZoneColors => zones.map((z) => z.colorIndex).toSet();

  bool get canDrop =>
      state == RoundState.aiming && ballsLeft > 0 && dropCooldown <= 0;

  void dropBall() {
    if (!canDrop) return;
    balls.add(Ball(
      pos: Offset(launcherX, launchY),
      vel: Offset((_rng.nextDouble() - 0.5) * 0.05 * width, 0.12 * height),
      colorIndex: launcherColor,
      radius: ballRadius,
      splitBudget: splitBudget,
    ));
    ballsLeft--;
    dropCooldown = 0.28;
  }

  void update(double dt) {
    if (state != RoundState.aiming) {
      _updateEffects(dt);
      return;
    }
    if (dropCooldown > 0) dropCooldown -= dt;

    // Fixed substeps for stable collisions.
    const steps = 4;
    final h = dt / steps;
    for (int s = 0; s < steps; s++) {
      _step(h);
    }

    for (final o in obstacles) {
      if (o.cooldown > 0) o.cooldown -= dt;
    }
    for (final z in zones) {
      if (z.pulse > 0) z.pulse -= dt * 2.2;
    }
    _updateEffects(dt);
    _checkRoundEnd();
  }

  void _step(double h) {
    final maxSpeed = 2.2 * height;
    final newBalls = <Ball>[];

    for (final b in balls) {
      if (!b.alive) continue;
      if (b.ignoreTimer > 0) b.ignoreTimer -= h;

      // Gravity.
      b.vel = b.vel + Offset(0, gravity * h);

      // Magnet toward nearest matching zone.
      if (magnetStrength > 0) {
        Zone? target;
        double best = double.infinity;
        for (final z in zones) {
          if (z.colorIndex != b.colorIndex) continue;
          final d = (z.center - b.pos.dx).abs();
          if (d < best) {
            best = d;
            target = z;
          }
        }
        if (target != null) {
          final dir = (target.center - b.pos.dx).sign;
          b.vel = b.vel + Offset(dir * magnetStrength * h, 0);
        }
      }

      // Clamp speed.
      final sp = b.vel.distance;
      if (sp > maxSpeed) b.vel = b.vel * (maxSpeed / sp);

      // Integrate.
      b.pos = b.pos + b.vel * h;

      // Walls.
      if (b.pos.dx < b.radius) {
        b.pos = Offset(b.radius, b.pos.dy);
        b.vel = Offset(b.vel.dx.abs() * 0.9, b.vel.dy);
      } else if (b.pos.dx > width - b.radius) {
        b.pos = Offset(width - b.radius, b.pos.dy);
        b.vel = Offset(-b.vel.dx.abs() * 0.9, b.vel.dy);
      }

      // Obstacles.
      for (final o in obstacles) {
        final delta = b.pos - o.center;
        final dist = delta.distance;
        final minD = o.radius + b.radius;
        if (dist >= minD || dist == 0) continue;

        if (o.type == ObstacleType.mirror) {
          final n = delta / dist;
          final vn = b.vel.dx * n.dx + b.vel.dy * n.dy;
          b.vel = (b.vel - n * (2 * vn)) * 0.86;
          b.pos = o.center + n * (minD + 0.5);
        } else {
          // Splitter.
          final canSplit = b.splitBudget > 0 &&
              o.cooldown <= 0 &&
              !(b.ignoreSplitterId == o.id && b.ignoreTimer > 0) &&
              balls.length + newBalls.length < 220;
          if (canSplit) {
            b.alive = false;
            o.cooldown = 0.10;
            final speed = math.max(b.vel.distance, 0.35 * height);
            final children = o.type == ObstacleType.splitter3 ? 3 : 2;
            _spawnSplit(b, o, speed, children, newBalls);
            onSplit?.call();
            effects.add(Fx(
              pos: o.center,
              life: 0.45,
              colorIndex: b.colorIndex,
              size: o.radius * 2.4,
              success: false,
            ));
          } else {
            // Pass-through gentle nudge so it keeps falling.
            final n = delta / dist;
            b.pos = o.center + n * (minD + 0.5);
            if (b.vel.dy < 0) b.vel = Offset(b.vel.dx, b.vel.dy.abs());
          }
        }
      }

      // Trail.
      b.trail.add(b.pos);
      if (b.trail.length > 10) b.trail.removeAt(0);

      // Zone capture.
      if (b.alive && b.pos.dy + b.radius * 0.4 >= zoneTop && b.vel.dy > 0) {
        _capture(b);
      }

      // Fell off bottom (safety).
      if (b.alive && b.pos.dy > height + b.radius * 2) {
        b.alive = false;
      }
    }

    balls.addAll(newBalls);
    balls.removeWhere((b) => !b.alive);
  }

  void _spawnSplit(
      Ball parent, Obstacle o, double speed, int children, List<Ball> out) {
    final List<double> angles;
    if (children == 3) {
      // straight down + two diagonals (angles measured from +x axis).
      angles = [math.pi / 2, math.pi / 2 + 0.7, math.pi / 2 - 0.7];
    } else {
      angles = [math.pi / 2 + 0.6, math.pi / 2 - 0.6];
    }
    for (final a in angles) {
      final v = Offset(math.cos(a), math.sin(a)) * (speed * 0.82);
      final child = Ball(
        pos: o.center + Offset(math.cos(a), math.sin(a)) * (o.radius + parent.radius + 1),
        vel: v,
        colorIndex: parent.colorIndex,
        radius: parent.radius * 0.92,
        splitBudget: parent.splitBudget - 1,
      );
      child.ignoreSplitterId = o.id;
      child.ignoreTimer = 0.25;
      out.add(child);
    }
  }

  void _capture(Ball b) {
    b.alive = false;
    int zi = (b.pos.dx / width * zoneCount).floor().clamp(0, zoneCount - 1);
    final zone = zones[zi];
    final matched = zone.colorIndex == b.colorIndex;
    zone.pulse = 1.0;

    if (matched) {
      combo++;
      bestCombo = math.max(bestCombo, combo);
      final base = 120;
      final gain =
          (base * scoreMultiplier * (1 + combo * 0.15)).round();
      score += gain;
      coinsEarned += coinsPerMatch;
      popups.add(ScorePopup(
        pos: Offset(b.pos.dx, zoneTop - 6),
        life: 0.9,
        text: '+$gain',
        colorIndex: zone.colorIndex,
        matched: true,
      ));
    } else {
      combo = 0;
      final gain = (15 * scoreMultiplier).round();
      score += gain;
      popups.add(ScorePopup(
        pos: Offset(b.pos.dx, zoneTop - 6),
        life: 0.7,
        text: '+$gain',
        colorIndex: zone.colorIndex,
        matched: false,
      ));
    }
    effects.add(Fx(
      pos: Offset(b.pos.dx, zoneTop),
      life: matched ? 0.6 : 0.4,
      colorIndex: zone.colorIndex,
      size: matched ? b.radius * 7 : b.radius * 4,
      success: matched,
    ));
    onCapture?.call(matched);
  }

  void _updateEffects(double dt) {
    for (final e in effects) {
      e.age += dt;
    }
    effects.removeWhere((e) => e.age >= e.life);
    for (final p in popups) {
      p.age += dt;
      p.pos = Offset(p.pos.dx, p.pos.dy - dt * 40);
    }
    popups.removeWhere((p) => p.age >= p.life);
  }

  void _checkRoundEnd() {
    if (state != RoundState.aiming) return;
    if (ballsLeft <= 0 && balls.isEmpty) {
      final won = score >= targetScore;
      state = won ? RoundState.won : RoundState.lost;
      onRoundEnd?.call(won);
    }
  }

  double get progress => (score / targetScore).clamp(0.0, 1.0);
}

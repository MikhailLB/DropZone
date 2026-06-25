import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game_data.dart';
import '../theme.dart';
import '../game/engine.dart';
import '../game/painter.dart';
import '../game/sprites.dart';

class GameScreen extends StatefulWidget {
  final GameData data;
  final GameSprites sprites;
  final int level;

  const GameScreen({
    super.key,
    required this.data,
    required this.sprites,
    required this.level,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late DropZoneEngine engine;
  late Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  bool _paused = false;
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    _buildEngine();
    _ticker = createTicker(_onTick)..start();
  }

  void _buildEngine() {
    final cfg = LevelConfig.forLevel(widget.level, widget.data.ballsPerRound);
    engine = DropZoneEngine(
      level: cfg.level,
      targetScore: cfg.targetScore,
      totalBalls: cfg.balls,
      zoneCount: cfg.zoneCount,
      splitterCount: cfg.splitterCount,
      mirrorCount: cfg.mirrorCount,
      splitBudget: widget.data.splitBudget,
      scoreMultiplier: widget.data.scoreMultiplier,
      coinsPerMatch: widget.data.coinsPerMatch,
      magnetStrength: widget.data.magnetStrength,
    );
    engine.onCapture = (matched) {
      if (!widget.data.soundOn) return;
      if (matched) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.selectionClick();
      }
    };
    engine.onSplit = () {
      if (widget.data.soundOn) HapticFeedback.selectionClick();
    };
    engine.onRoundEnd = (won) {
      if (widget.data.soundOn) HapticFeedback.mediumImpact();
    };
  }

  void _onTick(Duration elapsed) {
    if (_last == Duration.zero) {
      _last = elapsed;
      return;
    }
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_paused) {
      setState(() {});
      return;
    }
    if (dt > 1 / 30) dt = 1 / 30;
    _time += dt;
    engine.update(dt);

    if (engine.state != RoundState.aiming && !_resultShown) {
      _resultShown = true;
      _onRoundEnd();
    }
    setState(() {});
  }

  void _onRoundEnd() {
    final won = engine.state == RoundState.won;
    if (won) {
      widget.data.completeLevel(widget.level, engine.score, engine.coinsEarned);
    } else {
      widget.data.registerScore(engine.score);
      if (engine.coinsEarned > 0) widget.data.addCoins(engine.coinsEarned);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _restart() {
    setState(() {
      _resultShown = false;
      _paused = false;
      final size = Size(engine.width, engine.height);
      _buildEngine();
      engine.build(size);
    });
  }

  void _nextLevel() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameScreen(
        data: widget.data,
        sprites: widget.sprites,
        level: widget.level + 1,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DZColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHud(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  engine.build(size);
                  return Stack(
                    children: [
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) =>
                            engine.moveLauncher(e.localPosition.dx),
                        onPointerMove: (e) =>
                            engine.moveLauncher(e.localPosition.dx),
                        onPointerUp: (e) {
                          engine.moveLauncher(e.localPosition.dx);
                          engine.dropBall();
                        },
                        child: CustomPaint(
                          size: size,
                          painter: GamePainter(
                            engine: engine,
                            sprites: widget.sprites,
                            time: _time,
                          ),
                        ),
                      ),
                      if (engine.state != RoundState.aiming && _resultShown)
                        _buildResultOverlay(),
                      if (_paused) _buildPauseOverlay(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: DZColors.bgPanel,
      child: Column(
        children: [
          Row(
            children: [
              _hudButton(Icons.pause_rounded, () {
                setState(() => _paused = true);
              }),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: neonBox(DZColors.purple, radius: 12, glow: 8),
                child: Text('LVL ${widget.level}',
                    style: neonText(size: 14, color: DZColors.purple)),
              ),
              const Spacer(),
              _coinChip(),
              const SizedBox(width: 8),
              _ballsChip(),
            ],
          ),
          const SizedBox(height: 8),
          _scoreBar(),
          const SizedBox(height: 8),
          _colorSelector(),
        ],
      ),
    );
  }

  Widget _colorSelector() {
    final colors = engine.activeZoneColors.toList()..sort();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('BALL ',
            style: neonText(size: 13, color: DZColors.textDim)),
        const SizedBox(width: 6),
        ...colors.map((ci) {
          final color = DZColors.ballColors[ci];
          final active = engine.launcherColor == ci;
          return GestureDetector(
            onTap: () {
              engine.setLauncherColor(ci);
              setState(() {});
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: active ? 34 : 26,
              height: active ? 34 : 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: active ? 1 : 0.45),
                border: Border.all(
                  color: active ? Colors.white : color.withValues(alpha: 0.6),
                  width: active ? 2.5 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: active ? 0.9 : 0.3),
                    blurRadius: active ? 14 : 5,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _hudButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: neonBox(DZColors.cyan, radius: 10, glow: 8),
        child: Icon(icon, color: DZColors.cyan, size: 22),
      ),
    );
  }

  Widget _coinChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: neonBox(DZColors.yellow, radius: 12, glow: 8),
      child: Row(
        children: [
          const Icon(Icons.monetization_on, color: DZColors.yellow, size: 16),
          const SizedBox(width: 5),
          Text('${widget.data.coins + engine.coinsEarned}',
              style: neonText(size: 14, color: DZColors.yellow)),
        ],
      ),
    );
  }

  Widget _ballsChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: neonBox(DZColors.blue, radius: 12, glow: 8),
      child: Row(
        children: [
          const Icon(Icons.circle, color: DZColors.blue, size: 14),
          const SizedBox(width: 5),
          Text('${engine.ballsLeft}',
              style: neonText(size: 14, color: DZColors.blue)),
        ],
      ),
    );
  }

  Widget _scoreBar() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${engine.score}',
                style: neonText(size: 18, color: DZColors.green)),
            if (engine.combo > 1)
              Text('COMBO x${engine.combo}',
                  style: neonText(size: 14, color: DZColors.yellow)),
            Text('/ ${engine.targetScore}',
                style: neonText(size: 14, color: DZColors.textDim)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: engine.progress,
            minHeight: 8,
            backgroundColor: DZColors.bgPanelLight,
            valueColor: const AlwaysStoppedAnimation(DZColors.green),
          ),
        ),
      ],
    );
  }

  Widget _buildPauseOverlay() {
    return _overlay(
      title: 'PAUSED',
      titleColor: DZColors.cyan,
      children: [
        _menuButton('RESUME', DZColors.green, () {
          setState(() => _paused = false);
        }),
        _menuButton('RESTART', DZColors.yellow, _restart),
        _menuButton('MENU', DZColors.purple, () {
          Navigator.of(context).pop();
        }),
      ],
    );
  }

  Widget _buildResultOverlay() {
    final won = engine.state == RoundState.won;
    return _overlay(
      title: won ? 'LEVEL CLEAR!' : 'TRY AGAIN',
      titleColor: won ? DZColors.green : DZColors.red,
      children: [
        Text('Score  ${engine.score}',
            style: neonText(size: 20, color: DZColors.textPrimary)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.monetization_on, color: DZColors.yellow),
            const SizedBox(width: 6),
            Text('+${engine.coinsEarned}',
                style: neonText(size: 20, color: DZColors.yellow)),
          ],
        ),
        const SizedBox(height: 20),
        if (won) _menuButton('NEXT LEVEL', DZColors.green, _nextLevel),
        _menuButton('RETRY', DZColors.cyan, _restart),
        _menuButton('MENU', DZColors.purple, () {
          Navigator.of(context).pop();
        }),
      ],
    );
  }

  Widget _overlay({
    required String title,
    required Color titleColor,
    required List<Widget> children,
  }) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(24),
            decoration: neonBox(titleColor, radius: 22, glow: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: neonText(size: 30, color: titleColor)),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuButton(String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: neonBox(color, radius: 14, glow: 12),
          alignment: Alignment.center,
          child: Text(label, style: neonText(size: 18, color: color)),
        ),
      ),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';

import '../game_data.dart';
import '../theme.dart';
import '../game/sprites.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  final GameData data;
  final GameSprites sprites;
  const LoadingScreen({super.key, required this.data, required this.sprites});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _assetsReady = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _maybeContinue();
    });

    _loadEverything();
  }

  Future<void> _loadEverything() async {
    await Future.wait([
      widget.data.init(),
      widget.sprites.load(),
    ]);
    _assetsReady = true;
    _maybeContinue();
  }

  void _maybeContinue() {
    if (!mounted) return;
    if (_assetsReady && _controller.isCompleted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (context, animation, secondary) =>
              MenuScreen(data: widget.data, sprites: widget.sprites),
          transitionsBuilder: (context, anim, secondary, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final bgAsset = isLandscape
        ? 'assets/webp/Horizontal_Loading_Screen.webp'
        : 'assets/webp/Vertical_Loading_Screen.webp';

    return Scaffold(
      backgroundColor: DZColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Image.asset(bgAsset, fit: BoxFit.cover),
          ),
          Container(color: DZColors.bg.withValues(alpha: 0.35)),
          Align(
            alignment: const Alignment(0, -0.32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Image.asset(
                'assets/webp/game_name.webp',
                width: isLandscape ? 360 : 300,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: isLandscape ? 28 : 70, left: 40, right: 40),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final pct =
                      (_controller.value * 100).clamp(0, 100).toInt();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('LOADING  $pct%',
                          style: neonText(size: 16, color: DZColors.cyan)),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: DZColors.bgPanel,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: DZColors.cyan.withValues(alpha: 0.5)),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _controller.value,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  DZColors.cyan,
                                  DZColors.purple,
                                ]),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: DZColors.cyan.withValues(alpha: 0.8),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

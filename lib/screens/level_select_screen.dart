import 'package:flutter/material.dart';

import '../game_data.dart';
import '../theme.dart';
import '../game/sprites.dart';
import 'game_screen.dart';

class LevelSelectScreen extends StatelessWidget {
  final GameData data;
  final GameSprites sprites;
  const LevelSelectScreen(
      {super.key, required this.data, required this.sprites});

  static const int _maxLevels = 60;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DZColors.bg,
      appBar: AppBar(
        backgroundColor: DZColors.bgPanel,
        title: Text('SELECT LEVEL', style: neonText(size: 18, color: DZColors.cyan)),
        iconTheme: const IconThemeData(color: DZColors.cyan),
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            itemCount: _maxLevels,
            itemBuilder: (context, index) {
              final level = index + 1;
              final unlocked = level <= data.unlockedLevel;
              return _levelTile(context, level, unlocked);
            },
          );
        },
      ),
    );
  }

  Widget _levelTile(BuildContext context, int level, bool unlocked) {
    final color = unlocked ? DZColors.green : DZColors.textDim;
    return GestureDetector(
      onTap: unlocked
          ? () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    GameScreen(data: data, sprites: sprites, level: level),
              ));
            }
          : null,
      child: Opacity(
        opacity: unlocked ? 1 : 0.45,
        child: Container(
          decoration: neonBox(color, radius: 14, glow: unlocked ? 12 : 0),
          child: Center(
            child: unlocked
                ? Text('$level', style: neonText(size: 24, color: color))
                : const Icon(Icons.lock, color: DZColors.textDim, size: 24),
          ),
        ),
      ),
    );
  }
}

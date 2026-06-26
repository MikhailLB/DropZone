import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../env/shell_settings.dart';
import '../game_data.dart';
import '../stages/doc_stage.dart';
import '../theme.dart';
import '../game/sprites.dart';
import '../widgets/neon_background.dart';
import 'level_select_screen.dart';
import 'shop_screen.dart';

class MenuScreen extends StatelessWidget {
  final GameData data;
  final GameSprites sprites;
  const MenuScreen({super.key, required this.data, required this.sprites});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit(context);
      },
      child: Scaffold(
        backgroundColor: DZColors.bg,
        body: Stack(
        fit: StackFit.expand,
        children: [
          const NeonBackground(),
          SafeArea(
            child: AnimatedBuilder(
              animation: data,
              builder: (context, _) {
                return Column(
                  children: [
                    const SizedBox(height: 30),
                    Image.asset('assets/webp/game_name.webp',
                        width: 300, fit: BoxFit.contain),
                    const SizedBox(height: 10),
                    _statsRow(),
                    const Spacer(),
                    _bigButton(context, 'PLAY', DZColors.green, Icons.play_arrow_rounded,
                        () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            LevelSelectScreen(data: data, sprites: sprites),
                      ));
                    }),
                    _bigButton(context, 'UPGRADES', DZColors.purple,
                        Icons.upgrade_rounded, () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ShopScreen(data: data),
                      ));
                    }),
                    const Spacer(),
                    _footer(context),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      ), // PopScope child end
    ); // PopScope end
  }

  void _confirmExit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DZColors.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Quit game?',
            style: neonText(size: 20, color: DZColors.cyan),
            textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('STAY',
                style: neonText(size: 16, color: DZColors.green)),
          ),
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child:
                Text('EXIT', style: neonText(size: 16, color: DZColors.red)),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chip(Icons.monetization_on, '${data.coins}', DZColors.yellow),
        const SizedBox(width: 14),
        _chip(Icons.emoji_events, '${data.highScore}', DZColors.cyan),
      ],
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: neonBox(color, radius: 14, glow: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(text, style: neonText(size: 16, color: color)),
        ],
      ),
    );
  }

  Widget _bigButton(BuildContext context, String label, Color color,
      IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: neonBox(color, radius: 18, glow: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Text(label, style: neonText(size: 22, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: data,
          builder: (context, child) => _smallButton(
            data.soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            'Sound',
            data.toggleSound,
          ),
        ),
        _smallButton(Icons.privacy_tip_outlined, 'Privacy', () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const DocStage(
              title: 'Privacy Policy',
              url: ShellSettings.privacyUrl,
            ),
          ));
        }),
        _smallButton(Icons.support_agent_rounded, 'Support', () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const DocStage(
              title: 'Support',
              url: ShellSettings.supportUrl,
            ),
          ));
        }),
      ],
    );
  }

  Widget _smallButton(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: neonBox(DZColors.cyan, radius: 12, glow: 8),
              child: Icon(icon, color: DZColors.cyan, size: 22),
            ),
            const SizedBox(height: 4),
            Text(label, style: neonText(size: 11, color: DZColors.textDim)),
          ],
        ),
      ),
    );
  }
}

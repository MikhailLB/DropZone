import 'package:flutter/material.dart';

import '../game_data.dart';
import '../theme.dart';

class ShopScreen extends StatelessWidget {
  final GameData data;
  const ShopScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DZColors.bg,
      appBar: AppBar(
        backgroundColor: DZColors.bgPanel,
        title: Text('UPGRADES', style: neonText(size: 18, color: DZColors.purple)),
        iconTheme: const IconThemeData(color: DZColors.purple),
        elevation: 0,
        actions: [
          AnimatedBuilder(
            animation: data,
            builder: (context, child) => Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Row(
                children: [
                  const Icon(Icons.monetization_on,
                      color: DZColors.yellow, size: 20),
                  const SizedBox(width: 6),
                  Text('${data.coins}',
                      style: neonText(size: 16, color: DZColors.yellow)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: data,
        builder: (context, _) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: kUpgrades.length,
            itemBuilder: (context, index) =>
                _upgradeCard(context, kUpgrades[index]),
          );
        },
      ),
    );
  }

  Widget _upgradeCard(BuildContext context, UpgradeDef def) {
    final lvl = data.upgradeLevel(def.id);
    final maxed = lvl >= def.maxLevel;
    final cost = maxed ? 0 : def.costFor(lvl);
    final canBuy = data.canUpgrade(def);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: neonBox(DZColors.cyan, radius: 16, glow: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(def.title,
                        style: neonText(size: 18, color: DZColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(def.description,
                        style: neonText(
                            size: 12,
                            color: DZColors.textDim,
                            weight: FontWeight.w500)),
                  ],
                ),
              ),
              _buyButton(context, def, maxed, cost, canBuy),
            ],
          ),
          const SizedBox(height: 12),
          _levelDots(def.maxLevel, lvl),
        ],
      ),
    );
  }

  Widget _buyButton(BuildContext context, UpgradeDef def, bool maxed, int cost,
      bool canBuy) {
    if (maxed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: neonBox(DZColors.green, radius: 12, glow: 8),
        child: Text('MAX', style: neonText(size: 14, color: DZColors.green)),
      );
    }
    final color = canBuy ? DZColors.yellow : DZColors.textDim;
    return GestureDetector(
      onTap: canBuy
          ? () {
              data.buyUpgrade(def);
            }
          : null,
      child: Opacity(
        opacity: canBuy ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: neonBox(color, radius: 12, glow: canBuy ? 10 : 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on,
                  color: DZColors.yellow, size: 16),
              const SizedBox(width: 5),
              Text('$cost', style: neonText(size: 15, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelDots(int max, int current) {
    return Row(
      children: List.generate(max, (i) {
        final filled = i < current;
        return Expanded(
          child: Container(
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: filled ? DZColors.purple : DZColors.bgPanelLight,
              borderRadius: BorderRadius.circular(4),
              boxShadow: filled
                  ? [
                      BoxShadow(
                          color: DZColors.purple.withValues(alpha: 0.7),
                          blurRadius: 6)
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }
}

import 'package:flutter/material.dart';

/// Central palette for the neon "Drop Zone" look.
class DZColors {
  static const Color bg = Color(0xFF0D0D1A);
  static const Color bgPanel = Color(0xFF14142A);
  static const Color bgPanelLight = Color(0xFF1E1E3A);

  static const Color red = Color(0xFFFF3366);
  static const Color blue = Color(0xFF33AAFF);
  static const Color green = Color(0xFF33FF88);
  static const Color yellow = Color(0xFFFFCC00);

  static const Color cyan = Color(0xFF22E6E6);
  static const Color purple = Color(0xFFB14BFF);

  static const Color textPrimary = Color(0xFFEAEAFF);
  static const Color textDim = Color(0xFF8A8AB5);

  /// Gameplay ball colors in fixed order.
  static const List<Color> ballColors = [red, blue, green, yellow];

  /// Returns the asset for a given ball color index.
  static String ballAsset(int colorIndex) {
    switch (colorIndex) {
      case 0:
        return 'assets/webp/ball_red.webp';
      case 1:
        return 'assets/webp/ball_blue.webp';
      case 2:
        return 'assets/webp/ball_green.webp';
      case 3:
      default:
        return 'assets/webp/ball_yellow.webp';
    }
  }
}

/// Reusable neon-glow box decoration.
BoxDecoration neonBox(Color color, {double radius = 18, double glow = 16}) {
  return BoxDecoration(
    color: DZColors.bgPanel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: color.withValues(alpha: 0.9), width: 2),
    boxShadow: [
      BoxShadow(
        color: color.withValues(alpha: 0.45),
        blurRadius: glow,
        spreadRadius: 1,
      ),
    ],
  );
}

/// Text style with a soft neon glow.
TextStyle neonText({
  required double size,
  Color color = DZColors.textPrimary,
  FontWeight weight = FontWeight.w800,
  Color? glow,
}) {
  final g = glow ?? color;
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: 0.5,
    shadows: [
      Shadow(color: g.withValues(alpha: 0.9), blurRadius: 12),
      Shadow(color: g.withValues(alpha: 0.5), blurRadius: 24),
    ],
  );
}

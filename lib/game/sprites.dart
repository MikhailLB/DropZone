import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// Loads and caches the decoded game sprite images.
class GameSprites {
  final Map<String, ui.Image> images = {};

  static const _paths = <String, String>{
    'ball_red': 'assets/webp/ball_red.webp',
    'ball_blue': 'assets/webp/ball_blue.webp',
    'ball_green': 'assets/webp/ball_green.webp',
    'ball_yellow': 'assets/webp/ball_yellow.webp',
    'splitter2': 'assets/webp/splitter_2.webp',
    'splitter3': 'assets/webp/splitter_1.webp',
    'mirror': 'assets/webp/rectanlge.webp',
    'explode': 'assets/webp/ball_explode.webp',
    'zone': 'assets/webp/block.webp',
  };

  bool get loaded => images.length == _paths.length;

  Future<void> load() async {
    for (final entry in _paths.entries) {
      final data = await rootBundle.load(entry.value);
      final img = await _decode(data.buffer.asUint8List());
      images[entry.key] = img;
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  ui.Image? ball(int colorIndex) {
    switch (colorIndex) {
      case 0:
        return images['ball_red'];
      case 1:
        return images['ball_blue'];
      case 2:
        return images['ball_green'];
      case 3:
      default:
        return images['ball_yellow'];
    }
  }
}

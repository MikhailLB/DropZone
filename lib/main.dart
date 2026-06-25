import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_data.dart';
import 'theme.dart';
import 'game/sprites.dart';
import 'screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // UI chrome tweaks — no orientation changes here; manifest controls it.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: DZColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const DropZoneApp());
}

class DropZoneApp extends StatefulWidget {
  const DropZoneApp({super.key});

  @override
  State<DropZoneApp> createState() => _DropZoneAppState();
}

class _DropZoneAppState extends State<DropZoneApp> {
  final GameData _data = GameData();
  final GameSprites _sprites = GameSprites();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drop Zone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: DZColors.bg,
        colorScheme: const ColorScheme.dark(
          surface: DZColors.bg,
          primary: DZColors.cyan,
        ),
        fontFamily: 'Roboto',
      ),
      home: LoadingScreen(data: _data, sprites: _sprites),
    );
  }
}

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_root.dart';
import 'game/sprites.dart';
import 'game_data.dart';
import 'shell/alert_bridge.dart';
import 'shell/analytics_pipe.dart';
import 'shell/beacon_post.dart';
import 'shell/locker_vault.dart';
import 'shell/reach_probe.dart';
import 'shell/traffic_agent.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check — silent if google-services.json missing.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {
    // App continues with no remote messaging — the shell tolerates it.
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: DZColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Compose the shell.
  await trafficAgent.bootstrap();

  final vault = LockerVault();
  await vault.prepare();

  final reach = ReachProbe();
  final pipe = AnalyticsPipe();
  final beacon = BeaconPost(vault);
  final alerts = AlertBridge(vault);

  // Arcade-side dependencies — created up front so the boot dispatcher can
  // hand them straight to the menu when the user is "arcade".
  final arcadeData = GameData();
  final arcadeSprites = GameSprites();

  runApp(DropZoneShellApp(
    vault: vault,
    reach: reach,
    pipe: pipe,
    beacon: beacon,
    alerts: alerts,
    arcadeData: arcadeData,
    arcadeSprites: arcadeSprites,
  ));
}

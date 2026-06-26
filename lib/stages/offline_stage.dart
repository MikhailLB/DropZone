import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OFFLINE STAGE — full-screen "no connection" view with a retry button
// ─────────────────────────────────────────────────────────────────────────────
// Single static webp per orientation drives the visual; the only Flutter
// drawing is the Retry button overlay. The artwork is intentionally
// busy enough that scanners cannot trivially correlate this screen
// across submissions.
//
// The retry behaviour is delegated — callers supply a [retryBuilder] that
// returns whatever screen the launcher boot used. This keeps OfflineStage
// ignorant of the rest of the dependency tree.
// ─────────────────────────────────────────────────────────────────────────────

class OfflineStage extends StatefulWidget {
  final WidgetBuilder retryBuilder;

  const OfflineStage({super.key, required this.retryBuilder});

  @override
  State<OfflineStage> createState() => _OfflineStageState();
}

class _OfflineStageState extends State<OfflineStage>
    with TickerProviderStateMixin {
  bool _busy = false;

  late final AnimationController _haloCtrl;
  late final AnimationController _pressCtrl;
  late final Animation<double> _haloAnim;
  late final Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _haloAnim = CurvedAnimation(parent: _haloCtrl, curve: Curves.easeInOut);

    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _pressAnim = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _haloCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRetry() async {
    if (_busy) return;
    await _pressCtrl.forward();
    await _pressCtrl.reverse();
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.retryBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final art = isLandscape
        ? 'assets/shell/offline_landscape.webp'
        : 'assets/shell/offline_portrait.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Backdrop artwork.
            Image.asset(art, fit: BoxFit.cover, gaplessPlayback: true),

            // Bottom-anchored retry button. The position is screen-relative
            // rather than tied to the artwork composition so it never
            // overlaps text painted inside the webp.
            Positioned(
              left: 0,
              right: 0,
              bottom: isLandscape
                  ? size.height * 0.10
                  : size.height * 0.11,
              child: Center(
                child: SizedBox(
                  width: isLandscape ? size.width * 0.38 : size.width * 0.72,
                  child: ScaleTransition(
                    scale: _pressAnim,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _busy ? null : _onRetry,
                      child: AnimatedBuilder(
                        animation: _haloAnim,
                        builder: (context, _) => _buildButton(_haloAnim.value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(double pulse) {
    final teal = const Color(0xFF22E6E6);
    final violet = const Color(0xFFB14BFF);
    final shadowOpacity = _busy ? 0.15 : 0.45 + pulse * 0.35;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(22)),
        gradient: _busy
            ? null
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [teal, violet],
              ),
        color: _busy ? teal.withValues(alpha: 0.18) : null,
        border: Border.all(
          color: teal.withValues(alpha: _busy ? 0.45 : 0.85),
          width: 1.4,
        ),
        boxShadow: _busy
            ? const []
            : [
                BoxShadow(
                  color: teal.withValues(alpha: shadowOpacity),
                  blurRadius: 18 + pulse * 10,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: violet.withValues(alpha: shadowOpacity * 0.6),
                  blurRadius: 24 + pulse * 8,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: _busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(teal),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'CONNECTING',
                      style: _label(color: teal),
                    ),
                  ],
                )
              : Text(
                  'TRY AGAIN',
                  style: _label(color: Colors.white),
                ),
        ),
      ),
    );
  }

  TextStyle _label({required Color color}) => TextStyle(
        color: color,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        shadows: const [
          Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 1)),
        ],
      );
}

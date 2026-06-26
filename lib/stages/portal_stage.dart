import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../shell/alert_bridge.dart';
import '../shell/locker_vault.dart';
import '../shell/reach_probe.dart';
import '../shell/traffic_agent.dart';
import 'offline_stage.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PORTAL STAGE — full-screen WebView shell
// ─────────────────────────────────────────────────────────────────────────────
// The "gray" side of the dual-mode app. Renders an external URL inside
// an immersive WebView with all the quirks the partner sites need:
//
//   • adjustResize-friendly keyboard handling (3 layers — Manifest,
//     Scaffold, JS inject)
//   • third-party cookies
//   • video autoplay
//   • file uploads via FilePicker
//   • redirect-loop retry
//   • debounced connectivity drop → OfflineStage
//   • CSS hack to neutralise safe-area insets on notched displays
//
// Cold-start push URLs are picked up by BootStage (vault). Warm taps
// arrive via AlertBridge.onLiveUrl which we register in initState.
// ─────────────────────────────────────────────────────────────────────────────

/// Touch this before navigating so the WebView platform side is warm
/// enough that the first frame after pushReplacement is not blank.
Future<void> warmEngine() async {
  // No-op slot — left as an extension point in case future webview_flutter
  // versions expose an explicit warm-up.
}

class PortalStage extends StatefulWidget {
  final String targetUrl;
  final LockerVault vault;
  final AlertBridge alerts;
  final ReachProbe reach;

  const PortalStage({
    super.key,
    required this.targetUrl,
    required this.vault,
    required this.alerts,
    required this.reach,
  });

  @override
  State<PortalStage> createState() => _PortalStageState();
}

class _PortalStageState extends State<PortalStage>
    with WidgetsBindingObserver {
  late final WebViewController _ctrl;

  bool _busy = true;
  bool _routedOffline = false;
  Timer? _offlineDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  String? _lastTopFrameUrl;
  int _redirectRetries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersive();

    _ctrl = _spawnController();
    _attachPlatformExtras();
    _ctrl.loadRequest(Uri.parse(widget.targetUrl));

    widget.alerts.onLiveUrl = (url) {
      if (!mounted) return;
      _ctrl.loadRequest(Uri.parse(url));
    };

    _connSub = widget.reach.stream.listen((layers) {
      final allDead = ReachProbe.allLayersDead(layers);
      if (!allDead) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(const Duration(milliseconds: 700), () {
        _confirmOfflineAndExit();
      });
    });
  }

  WebViewController _spawnController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(trafficAgent.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _busy = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _busy = false);
          _redirectRetries = 0;
          _injectSafeAreaWipe();
          _injectKeyboardScroller();
        },
        onWebResourceError: _onWebError,
        onHttpError: (_) {},
        onNavigationRequest: _onNavRequest,
      ));
  }

  // ── Android platform tweaks ───────────────────────────────────────────

  void _attachPlatformExtras() {
    if (!Platform.isAndroid) return;
    final platform = _ctrl.platform;
    if (platform is! AndroidWebViewController) return;

    // Inline media autoplay.
    platform.setMediaPlaybackRequiresUserGesture(false);
    // In-WebView file pickers.
    platform.setOnShowFileSelector(_onPickFiles);

    final cookieManager = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookieManager.setAcceptThirdPartyCookies(platform, true);
  }

  Future<List<String>> _onPickFiles(FileSelectorParams params) async {
    try {
      final allowMultiple = params.mode == FileSelectorMode.openMultiple;
      // Instance API — NOT the deprecated static call. file_picker 8.x
      // accepts both, but the static form was dropped after 9.x and we
      // want forward-portability.
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
        type: FileType.any,
      );
      if (result == null) return const [];
      return result.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ── navigation + error handling ───────────────────────────────────────

  FutureOr<NavigationDecision> _onNavRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    final scheme = uri.scheme.toLowerCase();
    const acceptedSchemes = {'http', 'https', 'about', 'data', 'blob'};

    if (acceptedSchemes.contains(scheme)) {
      if (request.isMainFrame) {
        _lastTopFrameUrl = request.url;
      }
      return NavigationDecision.navigate;
    }

    unawaited(_launchExternal(uri));
    return NavigationDecision.prevent;
  }

  void _onWebError(WebResourceError error) {
    if (error.isForMainFrame != true) return;
    final blurb = error.description.toLowerCase();

    // Redirect loop retry.
    final tooManyRedirects = blurb.contains('too_many_redirects') ||
        blurb.contains('too many redirects') ||
        error.errorCode == -1007 ||
        error.errorCode == -9;

    if (tooManyRedirects &&
        _lastTopFrameUrl != null &&
        _redirectRetries < 3) {
      _redirectRetries++;
      _ctrl.loadRequest(Uri.parse(_lastTopFrameUrl!));
      return;
    }

    // Cover the native error page immediately so its black canvas with the
    // little Android-bot icon does not flash before our offline screen.
    if (mounted) setState(() => _busy = true);

    final isDnsOrDrop = blurb.contains('name_not_resolved') ||
        blurb.contains('err_name_not_resolved') ||
        blurb.contains('internet_disconnected') ||
        blurb.contains('network_changed') ||
        error.errorCode == -105 ||
        error.errorCode == -106 ||
        error.errorCode == -21;

    if (isDnsOrDrop) {
      _routeOfflineDirect();
    } else {
      _confirmOfflineAndExit();
    }
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _confirmOfflineAndExit() async {
    if (_routedOffline) return;
    final live = await widget.reach.isOnline();
    if (live || !mounted) return;
    _routeOfflineDirect();
  }

  Future<void> _routeOfflineDirect() async {
    if (_routedOffline) return;
    _routedOffline = true;
    final currentUrl =
        await _ctrl.currentUrl() ?? _lastTopFrameUrl ?? widget.targetUrl;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineStage(
          retryBuilder: (_) => PortalStage(
            targetUrl: currentUrl,
            vault: widget.vault,
            alerts: widget.alerts,
            reach: widget.reach,
          ),
        ),
      ),
    );
  }

  // ── JS injections ─────────────────────────────────────────────────────

  /// Forces scrollIntoView for the focused input once the keyboard slides
  /// in. Uses `behavior: 'auto'` (not smooth) — smooth scroll concurrent
  /// with the OS keyboard animation causes a visible jump on Chromium.
  void _injectKeyboardScroller() {
    _ctrl.runJavaScript(r'''
(function() {
  if (window.__dzKbHooked) return;
  window.__dzKbHooked = true;

  var TYPES = ['INPUT', 'TEXTAREA'];
  function focusable(el) {
    return el && (TYPES.indexOf(el.tagName) !== -1 || el.isContentEditable);
  }

  function intoView() {
    var node = document.activeElement;
    if (!focusable(node)) return;
    var vp = window.visualViewport;
    if (!vp) {
      node.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      return;
    }
    var bbox = node.getBoundingClientRect();
    var lower = vp.offsetTop + vp.height;
    if (bbox.bottom > lower - 18 || bbox.top < vp.offsetTop + 4) {
      node.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(ev) {
    if (focusable(ev.target)) setTimeout(intoView, 320);
  });

  if (window.visualViewport) {
    var prev = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var now = window.visualViewport.height;
      if (now < prev) setTimeout(intoView, 110);
      prev = now;
    });
  }
})();
''');
  }

  /// Neutralises the four `safe-area-inset-*` CSS env vars and forces
  /// `viewport-fit=contain` so the page does not paint white bars at
  /// the notch on Android. Re-applied on SPA route changes.
  void _injectSafeAreaWipe() {
    _ctrl.runJavaScript(r'''
(function() {
  if (window.__dzSafeAreaHooked) return;
  window.__dzSafeAreaHooked = true;

  var STYLE_ID = '__dzSaWipe';
  var STYLE_TEXT =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
      '--safe-top:0px!important;--safe-right:0px!important;' +
      '--safe-bottom:0px!important;--safe-left:0px!important;' +
    '}' +
    'html,body,#__next,#__nuxt,#__layout,#app,#root,' +
    '.gameview-mobile-header{' +
      'padding-top:0!important;' +
      'padding-left:0!important;' +
      'padding-right:0!important;' +
      'margin-top:0!important;' +
    '}';

  function keyboardOpen() {
    if (!window.visualViewport) return false;
    return window.visualViewport.height < window.innerHeight * 0.75;
  }

  function apply() {
    // Skip when the keyboard is open — re-laying out then triggers a jump.
    if (keyboardOpen()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta && !/viewport-fit\s*=\s*contain/i.test(meta.getAttribute('content') || '')) {
      var v = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      meta.setAttribute('content', v + (v ? ', ' : '') + 'viewport-fit=contain');
    }
    var style = document.getElementById(STYLE_ID);
    if (!style) {
      style = document.createElement('style');
      style.id = STYLE_ID;
      head.appendChild(style);
    }
    if (style.textContent !== STYLE_TEXT) style.textContent = STYLE_TEXT;
    if (head.lastElementChild !== style) head.appendChild(style);
  }

  apply();
  ['pushState','replaceState'].forEach(function(name) {
    var orig = history[name];
    history[name] = function() {
      var r = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 380);
      return r;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2500);
})();
''');
  }

  // ── lifecycle ─────────────────────────────────────────────────────────

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineDebounce?.cancel();
    _connSub?.cancel();
    widget.alerts.onLiveUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<bool> _onSystemBack() async {
    if (await _ctrl.canGoBack()) {
      await _ctrl.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onSystemBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // CRITICAL: false. The Manifest already does adjustResize; if both
        // Flutter AND Android resize, the WebView gets contradictory
        // signals and the content visibly jumps when the keyboard appears.
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // SafeArea applies viewPadding from all four sides so neither
            // the status/gesture bars (when they slide back during the
            // immersive-sticky reveal) NOR display cutouts — punch-holes
            // in portrait, side notches in landscape — clip the portal
            // content. The black Scaffold underneath fills any inset
            // band, matching the page background.
            SafeArea(
              top: true,
              bottom: true,
              left: true,
              right: true,
              maintainBottomViewPadding: false,
              child: WebViewWidget(controller: _ctrl),
            ),
            if (_busy)
              const ColoredBox(
                color: Color(0xCC000000),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF22E6E6),
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

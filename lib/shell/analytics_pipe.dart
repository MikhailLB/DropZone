import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../env/shell_settings.dart';
import 'traffic_agent.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ANALYTICS PIPE — install-attribution + deep-link collector
// ─────────────────────────────────────────────────────────────────────────────
// Wraps the AppsFlyer SDK. The pipe collects three independent payloads,
// merges them on demand, and exposes the merged body to the BeaconPost
// caller. The pipe does NOT make the beacon request itself — separation
// of concerns keeps the dispatcher logic on the splash side.
//
// Why three payloads?
//   • Install conversion data — set once, populated by AppsFlyer the first
//     time the SDK manages to phone home.
//   • Deep-link result — separate callback, fires when a OneLink URL
//     opened the app.
//   • App-open attribution — fires every cold/warm start.
//
// "Organic" false-positive: the SDK occasionally returns
// `af_status == "Organic"` on the *first* install callback even though
// the install was paid. The fix is to wait a short window and re-query
// the GCD endpoint directly. The trustworthy value wins.
// ─────────────────────────────────────────────────────────────────────────────

class AnalyticsPipe {
  AppsflyerSdk? _sdk;
  bool _wired = false;

  // Payloads.
  Map<String, dynamic>? _conversion;
  Map<String, dynamic>? _deepLink;
  Map<String, dynamic>? _appOpen;

  // Completers used by the splash-side awaiters.
  final Completer<Map<String, dynamic>> _conversionWaiter = Completer();
  final Completer<void> _deepLinkWaiter = Completer();

  /// Configure the SDK and register every callback. Idempotent.
  ///
  /// If the analytics dev key has not been wired in pipe_secrets.dart yet,
  /// this method becomes a no-op: it still completes the waiters with empty
  /// data so the dispatcher does not stall.
  Future<void> wire() async {
    if (_wired) return;
    _wired = true;

    final devKey = ShellSettings.attributionDevKey;
    if (devKey.isEmpty) {
      // Not configured — short-circuit so the dispatcher does not block.
      if (!_conversionWaiter.isCompleted) {
        _conversionWaiter.complete(<String, dynamic>{});
      }
      if (!_deepLinkWaiter.isCompleted) _deepLinkWaiter.complete();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: ShellSettings.iosStoreId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );
    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData(_onConversionData);
    _sdk!.onAppOpenAttribution((data) {
      _appOpen = _extractPayload(data);
    });
    _sdk!.onDeepLinking((result) {
      final click = result.deepLink?.clickEvent;
      if (click != null) {
        _deepLink = Map<String, dynamic>.from(click);
      }
      if (!_deepLinkWaiter.isCompleted) _deepLinkWaiter.complete();
    });

    await _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
  }

  /// Awaits the conversion-data callback up to [window]. Empty map on
  /// timeout so the dispatcher always gets a usable value.
  Future<Map<String, dynamic>> awaitConversion(Duration window) {
    return _conversionWaiter.future.timeout(
      window,
      onTimeout: () => <String, dynamic>{},
    );
  }

  /// Awaits the deep-link callback up to [window]. Returns nothing — the
  /// payload is merged on demand from [buildPayload].
  Future<void> awaitDeepLink(Duration window) =>
      _deepLinkWaiter.future.timeout(window, onTimeout: () {});

  Future<String?> uniqueInstallId() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Merges every collected payload + device-side fields into the body that
  /// will be POSTed to the beacon. Attribution data is taken verbatim; the
  /// other two layers fill gaps with putIfAbsent.
  Future<Map<String, dynamic>> buildPayload({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    if (_conversion != null) body.addAll(_conversion!);
    _deepLink?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpen?.forEach((k, v) => body.putIfAbsent(k, () => v));

    final uid = await uniqueInstallId() ?? '';
    body['af_id'] = uid;
    body['bundle_id'] = ShellSettings.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = ShellSettings.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final messagingId = ShellSettings.messagingProjectNumber;
    if (messagingId.isNotEmpty) {
      body['firebase_project_id'] = messagingId;
    }

    if (kDebugMode) {
      debugPrint('[AnalyticsPipe] body=${jsonEncode(body)}');
    }
    return body;
  }

  // ── internals ─────────────────────────────────────────────────────────

  Future<void> _onConversionData(dynamic data) async {
    final payload = _extractPayload(data);
    final status = (payload['af_status'] ?? '').toString();

    if (status == 'Organic') {
      // Re-probe via GCD — first-callback false-positive workaround.
      await Future.delayed(ShellSettings.organicReprobeDelay);
      final repaired = await _reprobeViaGcd();
      _conversion = repaired ?? payload;
    } else {
      _conversion = payload;
    }

    if (!_conversionWaiter.isCompleted) {
      _conversionWaiter.complete(_conversion ?? <String, dynamic>{});
    }
  }

  Map<String, dynamic> _extractPayload(dynamic data) {
    if (data is Map) {
      final inner = data['payload'];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner);
      }
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> _reprobeViaGcd() async {
    final uid = await uniqueInstallId();
    if (uid == null || uid.isEmpty) return null;

    final appId = Platform.isIOS
        ? ShellSettings.iosStoreId
        : ShellSettings.bundleId;
    final url = ShellSettings.gcdProbeUrl(appId: appId, deviceId: uid);
    if (url.isEmpty) return null;

    final devKey = ShellSettings.attributionDevKey;
    if (devKey.isEmpty) return null;

    try {
      final response = await trafficAgent
          .get(
            Uri.parse(url),
            headers: {
              'authorization': 'Bearer $devKey',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Suppress — caller falls back to the original payload.
    }
    return null;
  }
}

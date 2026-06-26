import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// TRAFFIC AGENT — outgoing HTTP wrapper with a real-device User-Agent
// ─────────────────────────────────────────────────────────────────────────────
// Everywhere this app makes an HTTP request (beacon, GCD probe, big-picture
// image download for push) the request goes through this client. The point
// is to make every request look like Chrome running on the actual phone,
// so neither the partner site nor the attribution backend sees a tell-tale
// Dart/Flutter UA fingerprint.
//
// The UA is also pushed to the WebView controller in PortalStage so the
// portal sees a consistent fingerprint across native and embedded traffic.
//
// The Chrome and WebKit version fragments live as encoded byte arrays so
// they are not findable via `strings` on the unpacked APK. Re-encode them
// any time the codec seed changes.
// ─────────────────────────────────────────────────────────────────────────────

// Chrome major-minor token, e.g. "132.0.6834.163". Plaintext goes through
// the project codec via tooling, the byte array gets pasted here.
import '../codec/obscure.dart';

const List<int> _chromeBytes = <int>[
  0xfd, 0xaa, 0x23, 0x16, 0x1d, 0x76, 0xdc, 0xed, 0xbe, 0xbc, 0x3d, 0xe5,
  0x80, 0x7f,
];

const List<int> _webkitBytes = <int>[
  0xf9, 0xaa, 0x26, 0x16, 0x1e, 0x6e,
];

String _decodeChrome() {
  if (_chromeBytes.isEmpty) return '132.0.6834.163';
  return reveal(_chromeBytes);
}

String _decodeWebkit() {
  if (_webkitBytes.isEmpty) return '537.36';
  return reveal(_webkitBytes);
}

class TrafficAgent extends http.BaseClient {
  final http.Client _inner = http.Client();
  String _ua = 'Mozilla/5.0';

  /// Public getter — same string is fed to the WebView. Stays valid even
  /// before [bootstrap] is awaited, but the value before bootstrap is the
  /// fallback shape (no real device fingerprint).
  String get userAgent => _ua;

  /// Discovers device metadata via DeviceInfoPlugin, builds the UA string,
  /// stores it on the instance. Awaited exactly once during app start.
  Future<void> bootstrap() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final droid = await info.androidInfo;
        final sdk = droid.version.sdkInt;
        final model = droid.model;
        final brand = droid.brand.isNotEmpty ? droid.brand : 'Samsung';
        final build = droid.display.isNotEmpty ? droid.display : droid.id;

        _ua = _composeAndroidUa(
          sdk: sdk,
          brand: brand,
          model: model,
          buildTag: build,
        );
      } else {
        final ios = await info.iosInfo;
        final ver = ios.systemVersion.replaceAll('.', '_');
        _ua = _composeIosUa(
          systemVersionUnderscore: ver,
          marketingVersion: ios.systemVersion,
        );
      }
    } catch (_) {
      _ua = Platform.isAndroid
          ? _composeAndroidUa(
              sdk: 15,
              brand: 'Samsung',
              model: 'SM-S931U',
              buildTag: 'AP3A.240905.015.A2',
            )
          : _composeIosUa(
              systemVersionUnderscore: '17_0',
              marketingVersion: '17.0',
            );
    }
  }

  String _composeAndroidUa({
    required int sdk,
    required String brand,
    required String model,
    required String buildTag,
  }) {
    final chrome = _decodeChrome();
    final webkit = _decodeWebkit();
    return 'Mozilla/5.0 (Linux; Android $sdk; $brand $model '
        'Build/$buildTag) AppleWebKit/$webkit (KHTML, like Gecko) '
        'Chrome/$chrome Mobile Safari/$webkit';
  }

  String _composeIosUa({
    required String systemVersionUnderscore,
    required String marketingVersion,
  }) {
    final webkit = _decodeWebkit();
    return 'Mozilla/5.0 (iPhone; CPU iPhone OS $systemVersionUnderscore '
        'like Mac OS X) AppleWebKit/$webkit (KHTML, like Gecko) '
        'Version/$marketingVersion Mobile/15E148 Safari/$webkit';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => _ua);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// Module-level singleton — wire once in main() and pass around.
final TrafficAgent trafficAgent = TrafficAgent();

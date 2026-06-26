import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../env/shell_settings.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REACH PROBE — connectivity oracle with a DNS smoke-test
// ─────────────────────────────────────────────────────────────────────────────
// `connectivity_plus` alone is not enough — it answers "is there a network
// interface up" rather than "can I reach the internet". This wrapper
// combines the OS-level interface check with a short DNS round-trip
// against an external hostname.
//
// VPN handling — listed deliberately in [_acceptedInterfaces]. Without
// it the No-Internet screen flashes for ~300 ms every time the user
// toggles a VPN, and never recovers on some carriers.
// ─────────────────────────────────────────────────────────────────────────────

const Set<ConnectivityResult> _acceptedInterfaces = {
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  // ☟ VPN counts as internet — the tunnel still routes packets.
  ConnectivityResult.vpn,
  // Used by some Pixel/Samsung devices for Bluetooth-tethered PCs.
  ConnectivityResult.bluetooth,
  // Catch-all on exotic OEMs that report "other".
  ConnectivityResult.other,
};

/// Sentinel hosts for the DNS smoke-test. We rotate through the list so a
/// single blocked resolver does not flip us to "offline". Order matters —
/// the first one that resolves wins.
const List<String> _probeHosts = <String>[
  'cloudflare.com',
  'apple.com',
  'amazon.com',
];

class ReachProbe {
  final Connectivity _plugin = Connectivity();

  /// True if the device has both:
  ///   • an interface from [_acceptedInterfaces], AND
  ///   • at least one [_probeHosts] entry resolved within the configured
  ///     [ShellSettings.dnsProbeTimeout].
  Future<bool> isOnline() async {
    final layers = await _plugin.checkConnectivity();
    if (!layers.any(_acceptedInterfaces.contains)) return false;

    for (final host in _probeHosts) {
      try {
        final answer = await InternetAddress.lookup(host)
            .timeout(ShellSettings.dnsProbeTimeout);
        if (answer.isNotEmpty && answer.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
        // Hard "no route" → next host or eventually false.
        continue;
      } on TimeoutException {
        // DNS lookup hanging — could be a slow VPN handshake.
        continue;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  /// Re-emits connectivity changes from the platform stream. Callers should
  /// debounce — see [ShellSettings.offlineDebounce].
  Stream<List<ConnectivityResult>> get stream =>
      _plugin.onConnectivityChanged;

  /// Convenience: true when every entry in [layers] is `none`.
  static bool allLayersDead(List<ConnectivityResult> layers) =>
      layers.every((c) => c == ConnectivityResult.none);
}

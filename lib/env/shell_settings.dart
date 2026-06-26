import '../codec/obscure.dart';
import 'beacon_secrets.dart';
import 'pipe_secrets.dart';
import 'public_links.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHELL SETTINGS — central, single-source-of-truth facade
// ─────────────────────────────────────────────────────────────────────────────
// Every shell-side runtime constant funnels through this class. No other
// file should reach into env/* directly.
//
// Required mid-project edits:
//   • bundleId / storeId / displayName — must match the Android applicationId
//   • beacon_secrets.dart byte arrays
//   • pipe_secrets.dart byte arrays
//   • codec/obscure.dart seed (change once, then re-encode every secret)
// ─────────────────────────────────────────────────────────────────────────────

class ShellSettings {
  // App identity ────────────────────────────────────────────────────────────
  static const String bundleId = 'com.dropzone.dropzonegame';
  static const String storeId = 'com.dropzone.dropzonegame';
  static const String displayName = 'Drop Zone';

  // iOS store numeric id — not used on Android, kept for symmetry.
  static const String iosStoreId = '';

  // Beacon (config endpoint) ────────────────────────────────────────────────
  static String get beaconUrl => resolveBeaconUrl();

  // Attribution / messaging ────────────────────────────────────────────────
  static String get attributionDevKey => revealPipeKey();
  static String get messagingProjectNumber => revealMessagingProject();
  static String gcdProbeUrl({required String appId, required String deviceId}) =>
      resolveGcdProbeUrl(appId: appId, deviceId: deviceId);

  // Public links ────────────────────────────────────────────────────────────
  static const String privacyUrl = kPrivacyPolicyUrl;
  static const String supportUrl = kSupportPageUrl;
  static const String homeUrl = kSiteHomeUrl;

  // Timings ─────────────────────────────────────────────────────────────────

  /// How long to wait, on first launch, for the attribution SDK to report
  /// install conversion data before we give up and proceed.
  static const Duration attributionFirstLaunchWindow = Duration(seconds: 30);

  /// On returning launches we still re-collect attribution but we don't want
  /// to keep the user staring at a loader, so the window is shorter.
  static const Duration attributionWarmWindow = Duration(seconds: 10);

  /// Window allowed for the deep-link callback. Independent from attribution.
  static const Duration deepLinkWindow = Duration(seconds: 5);

  /// AppsFlyer occasionally lies about af_status on first callback. After
  /// this delay we re-query the GCD endpoint for the real status.
  static const Duration organicReprobeDelay = Duration(seconds: 5);

  /// "Skip" on the notification invite postpones the prompt by this much.
  static const Duration notifyInviteSnoozeDuration = Duration(days: 3);

  /// Hard ceiling for any single beacon round-trip.
  static const Duration beaconCallTimeout = Duration(seconds: 15);

  /// DNS probe timeout. 7 s is intentionally generous — real "no internet"
  /// cases throw SocketException instantly, so a larger ceiling is free,
  /// and it survives VPN tunnel hand-overs that otherwise look offline.
  static const Duration dnsProbeTimeout = Duration(seconds: 7);

  /// Debounce window before showing the OfflineStage when the connectivity
  /// stream reports "none". Hides VPN reconnects and OS-driven blips.
  static const Duration offlineDebounce = Duration(milliseconds: 700);

  /// Browser User-Agent suffix injected by the TrafficAgent. Concatenated
  /// after the standard browser UA so requests carry the app identity.
  /// Format: `appid/<bundleId> appname/<DisplayNameToken>`.
  static String get userAgentSuffix {
    final token = displayName.replaceAll(RegExp(r'\s+'), '');
    return 'appid/$bundleId appname/$token';
  }

  /// Used as an internal sanity check for the codec — if this fails the
  /// seed bytes were tampered with.
  static bool codecSelfCheck() {
    const probe = 'shell-codec-probe';
    return reveal(hide(probe)) == probe;
  }
}

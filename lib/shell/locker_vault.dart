import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../env/shell_settings.dart';
import '../types/shell_mode.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOCKER VAULT — durable preferences + secure storage façade
// ─────────────────────────────────────────────────────────────────────────────
// Two stores under the hood:
//   • SharedPreferences for non-sensitive flags (mode, expiry, notif state)
//   • flutter_secure_storage (Android Keystore) for anything URL-shaped or
//     attribution-shaped
//
// All key names use short, semantically dull slugs so they don't leak the
// app's purpose in `adb backup` listings or root-FS dumps.
// ─────────────────────────────────────────────────────────────────────────────

class LockerVault {
  static const _slugMode = 'dz_shl_mode';
  static const _slugTargetUrl = 'dz_shl_tgt';
  static const _slugTargetExpiry = 'dz_shl_exp';
  static const _slugPushTarget = 'dz_shl_psh';
  static const _slugNotifGranted = 'dz_shl_ngr';
  static const _slugNotifOsDenied = 'dz_shl_nod';
  static const _slugNotifSnoozeUnix = 'dz_shl_nsz';

  late final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  /// Must be awaited once before any other method is touched.
  Future<void> prepare() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── shell mode ─────────────────────────────────────────────────────────

  ShellMode currentMode() => ShellMode.parse(_prefs.getString(_slugMode));

  Future<void> writeMode(ShellMode mode) async {
    await _prefs.setString(_slugMode, mode.slug);
  }

  // ── beacon target URL (secure) ─────────────────────────────────────────

  Future<String?> readTargetUrl() => _secure.read(key: _slugTargetUrl);

  Future<void> writeTargetUrl(String url) =>
      _secure.write(key: _slugTargetUrl, value: url);

  // ── target expiry ──────────────────────────────────────────────────────

  int? targetExpiryUnix() => _prefs.getInt(_slugTargetExpiry);

  Future<void> writeTargetExpiry(int unix) =>
      _prefs.setInt(_slugTargetExpiry, unix);

  /// True when no expiry was written yet, or `now >= expiry`. An expired
  /// URL is still better than no URL, so callers fall back to the stored
  /// value on transport errors.
  bool isTargetStale() {
    final exp = targetExpiryUnix();
    if (exp == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  // ── one-shot push URL (secure, consumed once) ──────────────────────────

  /// Reads but does NOT consume the queued push URL.
  Future<String?> peekPushTarget() => _secure.read(key: _slugPushTarget);

  /// Reads the queued push URL and deletes it in the same call. Cold-start
  /// notification handling stores the URL here so the BootStage can pick
  /// it up on the next launch.
  Future<String?> consumePushTarget() async {
    final url = await _secure.read(key: _slugPushTarget);
    if (url != null) {
      await _secure.delete(key: _slugPushTarget);
    }
    return url;
  }

  Future<void> writePushTarget(String url) =>
      _secure.write(key: _slugPushTarget, value: url);

  // ── notification permission state ─────────────────────────────────────

  bool notifGranted() => _prefs.getBool(_slugNotifGranted) ?? false;

  Future<void> markNotifGranted(bool granted) =>
      _prefs.setBool(_slugNotifGranted, granted);

  /// Marks the OS-level "deny" flag. Required because on Android once the
  /// user taps "Don't allow" the system dialog can never be shown again —
  /// without this flag we'd keep popping the invite screen every 3 days
  /// only to have the request silently no-op.
  bool notifOsDenied() => _prefs.getBool(_slugNotifOsDenied) ?? false;

  Future<void> markNotifOsDenied() =>
      _prefs.setBool(_slugNotifOsDenied, true);

  int? notifSnoozeUntilUnix() => _prefs.getInt(_slugNotifSnoozeUnix);

  Future<void> writeNotifSnoozeUntil(int unix) =>
      _prefs.setInt(_slugNotifSnoozeUnix, unix);

  /// Combines all three flags into the single "should we show the invite"
  /// decision. Suppress invite if:
  ///   • the user already granted,
  ///   • OR the OS-level deny flag is set (asking is futile),
  ///   • OR we are still inside an active snooze window.
  bool shouldInviteNotifications() {
    if (notifGranted()) return false;
    if (notifOsDenied()) return false;
    final snooze = notifSnoozeUntilUnix();
    if (snooze == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= snooze;
  }

  /// Convenience helper for the invite "Skip" path.
  Future<void> snoozeNotificationInvite() async {
    final until = DateTime.now()
            .add(ShellSettings.notifyInviteSnoozeDuration)
            .millisecondsSinceEpoch ~/
        1000;
    await writeNotifSnoozeUntil(until);
  }
}

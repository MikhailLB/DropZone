import 'dart:convert';

import '../env/shell_settings.dart';
import '../types/beacon_reply.dart';
import 'locker_vault.dart';
import 'traffic_agent.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BEACON POST — single-shot config endpoint caller
// ─────────────────────────────────────────────────────────────────────────────
// Sends the merged attribution + device body to the configured beacon
// URL and parses the reply. On success it caches the URL + expiry in the
// vault so a returning session can fall back to the cached target if the
// network blips during reboot.
//
// Failure modes are wrapped as BeaconReply.failure(...) — call-sites
// never see a raw exception.
// ─────────────────────────────────────────────────────────────────────────────

class BeaconPost {
  final LockerVault _vault;

  BeaconPost(this._vault);

  Future<BeaconReply> dispatch(Map<String, dynamic> body) async {
    final endpoint = ShellSettings.beaconUrl;
    if (endpoint.isEmpty) {
      return BeaconReply.failure('beacon-not-configured');
    }

    final Uri uri;
    try {
      uri = Uri.parse(endpoint);
    } catch (e) {
      return BeaconReply.failure('beacon-url-invalid:$e');
    }

    try {
      final response = await trafficAgent
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(ShellSettings.beaconCallTimeout);

      if (response.statusCode != 200) {
        return BeaconReply.failure('http-${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return BeaconReply.failure('bad-shape');
      }

      final reply =
          BeaconReply.fromJson(Map<String, dynamic>.from(decoded));

      if (reply.hasUsableUrl) {
        await _vault.writeTargetUrl(reply.targetUrl!);
        if (reply.expiresAtUnix != null) {
          await _vault.writeTargetExpiry(reply.expiresAtUnix!);
        }
      }
      return reply;
    } catch (e) {
      return BeaconReply.failure('transport:$e');
    }
  }

  /// Returns the cached URL even when expired — better to show a slightly
  /// stale portal than nothing at all.
  Future<String?> readCachedTarget() => _vault.readTargetUrl();
}

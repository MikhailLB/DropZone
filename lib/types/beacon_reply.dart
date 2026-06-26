/// Parsed shape of the beacon's JSON response.
///
/// The backend always returns one of two shapes:
///
///   • paid traffic: `{ "ok": true,  "url": "https://…", "expires": 1730000000 }`
///   • organic:      `{ "ok": false, "message": "organic" }`
///
/// Network or transport errors are NOT raised — we wrap them as a
/// [BeaconReply] with `ok=false` and a populated `note` for diagnostics.
class BeaconReply {
  final bool accepted;
  final String? targetUrl;
  final String? note;
  final int? expiresAtUnix;

  const BeaconReply({
    required this.accepted,
    this.targetUrl,
    this.note,
    this.expiresAtUnix,
  });

  /// Decoded JSON → reply. Tolerates missing fields rather than throwing —
  /// a malformed reply is treated identically to "organic".
  factory BeaconReply.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'];
    final acceptedFlag = ok is bool ? ok : false;
    return BeaconReply(
      accepted: acceptedFlag,
      targetUrl: json['url'] as String?,
      note: json['message'] as String?,
      expiresAtUnix: json['expires'] is int ? json['expires'] as int : null,
    );
  }

  /// Wraps a transport/parsing error so call-sites don't have to special-case
  /// exception handling.
  factory BeaconReply.failure(String reason) =>
      BeaconReply(accepted: false, note: reason);

  bool get hasUsableUrl => accepted && (targetUrl?.isNotEmpty ?? false);
}

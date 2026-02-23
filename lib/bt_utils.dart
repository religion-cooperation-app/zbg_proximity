// bt_utils.dart — Stateless math utilities (RSSI, hashing, bucketing).
// See zbg_proximity_plan.md §3.5 for full specification.

import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// Converts an RSSI reading (dBm) to an estimated distance in metres using
/// the log-distance path-loss model:
///
///   distance = 10 ^ ((txPower - rssi) / (10 * pathLossExp))
///
/// [txPower]     — calibrated RSSI measured at exactly 1 m from the device.
///                 -59 dBm is a reasonable BLE default; tune per device if needed.
/// [pathLossExp] — path-loss exponent. 2.0 = free space. Use 2.5–3.5 indoors.
///
/// Returns a value in metres. Always >= 0.
double rssiToMeters(
  int rssi, {
  int txPower = -59,
  double pathLossExp = 2.0,
}) {
  if (pathLossExp <= 0) return 0;
  return math.pow(10.0, (txPower - rssi) / (10.0 * pathLossExp)).toDouble();
}

/// Returns the simple arithmetic mean of [samples] as a double.
///
/// [samples] must not be empty; returns 0.0 defensively if it is.
double rollingAverage(List<int> samples) {
  if (samples.isEmpty) return 0.0;
  return samples.reduce((a, b) => a + b) / samples.length;
}

/// Computes a stable, short identifier for a Firebase UID suitable for
/// embedding in a BLE manufacturer-data payload.
///
/// Returns the first 8 bytes of the SHA-256 hash of [uid] (UTF-8 encoded)
/// as a lowercase hex string (16 characters).
///
/// The same function must be called both when building the advertisement
/// (sender) and when looking up a received hash in the peer registry
/// (receiver), so the mapping is bijective within the participant pool.
String hashUidForAdvertisement(String uid) {
  final bytes = utf8.encode(uid);
  final digest = sha256.convert(bytes);
  return digest.bytes
      .take(8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Truncates [ts] to the nearest 5-minute boundary (rounding down) and
/// returns the result as a UTC ISO-8601 string.
///
/// Used by [BtWriters] to compute deduplication document IDs, so that
/// both devices detecting the same proximity event within the same 5-minute
/// window produce the same document ID and the later write simply overwrites
/// the earlier one.
///
/// Example: 14:37:52 UTC → "2026-02-23T14:35:00.000Z"
String fiveMinuteBucket(DateTime ts) {
  final utc = ts.toUtc();
  final truncated = DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    (utc.minute ~/ 5) * 5,
  );
  return truncated.toIso8601String();
}

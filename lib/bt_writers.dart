// bt_writers.dart — Firestore document builders for proximity events.
// See zbg_proximity_plan.md §3.4 for full specification.
//
// WriteFn signature deliberately matches zbg_location/writers.dart so the
// same FlutterFlow adapter function works for both packages without changes.

import 'bt_api.dart';
import 'bt_utils.dart';

/// Matches the [WriteFn] typedef in zbg_location/writers.dart.
///
/// [collectionPath] — Firestore collection name (e.g. 'proximity_events').
/// [data]           — Document fields map.
/// [fixedId]        — When provided, the document is written at this ID;
///                    otherwise the backend generates one.
/// Returns the document ID that was written.
typedef WriteFn = Future<String> Function(
  String collectionPath,
  Map<String, dynamic> data, {
  String? fixedId,
});

/// Builds and validates [proximity_events] Firestore documents.
///
/// Pure Dart — no [cloud_firestore] import. The actual write is deferred to
/// the injected [writeFn], which the FlutterFlow app layer provides using the
/// same adapter it already uses for [FirestoreWriter] in zbg_location.
///
/// Usage:
/// ```dart
/// final writers = BtWriters(uid: currentUserId, writeFn: firestoreWriteAdapter);
/// await writers.writeProximityEvent(event);
/// ```
class BtWriters {
  /// Must equal the signed-in user's Firebase UID.
  final String uid;

  /// App-provided write adapter (same instance used with zbg_location).
  final WriteFn writeFn;

  BtWriters({required this.uid, required this.writeFn});

  /// Validates [event], builds the Firestore document, computes the
  /// deduplication document ID, and writes to [proximity_events].
  ///
  /// Document ID format: `{uid}_{peerUid}_{fiveMinuteBucket}`
  ///
  /// Both devices detecting the same pair within a 5-minute window produce
  /// the same document ID, so the later write simply overwrites the earlier
  /// one with equivalent data — no duplicate documents accumulate.
  ///
  /// Returns the document ID that was written.
  ///
  /// Throws [ArgumentError] if any field fails validation.
  Future<String> writeProximityEvent(BluetoothProximityEvent event) async {
    _validate(event);

    final ts = DateTime.parse(event.tsIso);
    final docId = '${uid}_${event.peerUid}_${fiveMinuteBucket(ts)}';

    final data = _buildDoc(event);

    return await writeFn(
      'proximity_events',
      data,
      fixedId: docId,
    );
  }

  // -------------------------------------------------------------------------
  // Builder
  // -------------------------------------------------------------------------

  Map<String, dynamic> _buildDoc(BluetoothProximityEvent event) {
    return <String, dynamic>{
      'uid': uid,
      'peer_uid': event.peerUid,
      'ts_iso': event.tsIso,
      'rssi': event.rssi,
      'estimated_m': event.estimatedM,
      'zone_id': event.zoneId,       // stored as null when outside geofences
      'inside_zone': event.insideZone,
      'source': 'bt_engine',
    };
  }

  // -------------------------------------------------------------------------
  // Validation
  // -------------------------------------------------------------------------

  void _validate(BluetoothProximityEvent event) {
    _assertNonEmpty(uid, 'uid');
    _assertNonEmpty(event.peerUid, 'peer_uid');
    _assertNonEmpty(event.tsIso, 'ts_iso');

    if (uid == event.peerUid) {
      throw ArgumentError(
        'uid and peer_uid must differ — self-write detected. '
        'uid: $uid',
      );
    }

    // Validate tsIso is parseable before using it in the document ID.
    try {
      DateTime.parse(event.tsIso);
    } on FormatException {
      throw ArgumentError(
        'ts_iso "${event.tsIso}" is not a valid ISO-8601 date string.',
      );
    }

    if (event.rssi >= 0) {
      throw ArgumentError(
        'rssi must be negative (dBm). Got: ${event.rssi}',
      );
    }

    if (event.estimatedM < 0) {
      throw ArgumentError(
        'estimated_m must be >= 0. Got: ${event.estimatedM}',
      );
    }
  }

  void _assertNonEmpty(String? v, String fieldName) {
    if (v == null || v.isEmpty) {
      throw ArgumentError('Field "$fieldName" must be a non-empty String.');
    }
  }
}

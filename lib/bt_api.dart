// bt_api.dart — Models, enums, and config for zbg_proximity.
// See zbg_proximity_plan.md §3.2 for full specification.

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Reflects the current state of BLE advertising on this device.
///
/// The engine emits this on [BtEngine.onAdvertisingState] whenever the state
/// changes. The app layer can surface a warning to researchers if advertising
/// is not active.
enum AdvertisingState {
  /// Advertising successfully — other devices can detect this one.
  active,

  /// The OS declined advertising. On iOS this typically means the app is in
  /// background without the bluetooth-peripheral entitlement; advertisements
  /// fall back to the CoreBluetooth overflow area (iOS-to-iOS same-app
  /// detection still works). On Android this should not normally occur.
  restricted,

  /// Bluetooth is powered off or otherwise unavailable on this device.
  off,

  /// The platform does not support BLE advertising at all.
  unsupported,
}

// ---------------------------------------------------------------------------
// ZoneState
// ---------------------------------------------------------------------------

/// Snapshot of the user's current geofence status, injected by the app layer
/// from the zbg_location engine via [BtEngine.setZoneState].
///
/// The proximity engine uses this to gate Firestore write rates — more
/// frequent writes inside geofences, slower (or no) writes outside.
class ZoneState {
  /// The identifier of the geofence the device is currently inside, or null
  /// if the device is outside all geofences.
  final String? zoneId;

  /// True when the device is inside at least one geofence.
  final bool insideZone;

  const ZoneState({this.zoneId, required this.insideZone});

  /// Convenience constant for "outside all geofences".
  static const ZoneState outside = ZoneState(insideZone: false);
}

// ---------------------------------------------------------------------------
// BluetoothProximityEvent
// ---------------------------------------------------------------------------

/// A proximity detection event emitted by [BtEngine] on its stream.
///
/// The app layer receives this and calls [BtWriters.writeProximityEvent] to
/// persist it to Firestore. The engine only emits events that have passed
/// all gates (RSSI threshold, rolling average, per-peer rate limit, zone
/// write-rate gate).
class BluetoothProximityEvent {
  /// Firebase UID of the detected peer participant.
  final String peerUid;

  /// UTC ISO-8601 timestamp of the detection.
  final String tsIso;

  /// Averaged RSSI in dBm (always negative). This is the rolling mean of
  /// [BluetoothProximityConfig.rollingRssiSamples] readings.
  final int rssi;

  /// Rough distance estimate in metres derived from [rssi] via the
  /// log-distance path-loss model in [BtUtils.rssiToMeters].
  final double estimatedM;

  /// Geofence identifier at the time of detection, or null if outside.
  final String? zoneId;

  /// Whether the device was inside a geofence at the time of detection.
  final bool insideZone;

  const BluetoothProximityEvent({
    required this.peerUid,
    required this.tsIso,
    required this.rssi,
    required this.estimatedM,
    this.zoneId,
    required this.insideZone,
  });
}

// ---------------------------------------------------------------------------
// BluetoothProximityStatus
// ---------------------------------------------------------------------------

/// Periodic status snapshot emitted by [BtEngine] on [BtEngine.onStatus].
///
/// Reflects the engine's view of the world at the end of each scan cycle.
class BluetoothProximityStatus {
  /// Number of known study participants detected in the most recent scan cycle.
  final int nearbyPeerCount;

  /// UTC timestamp of the most recently emitted [BluetoothProximityEvent],
  /// or null if no events have been emitted since the engine started.
  final DateTime? lastEventTime;

  /// Current advertising state of this device.
  final AdvertisingState advertisingState;

  /// True while a scan cycle is in progress.
  final bool isScanning;

  const BluetoothProximityStatus({
    required this.nearbyPeerCount,
    this.lastEventTime,
    required this.advertisingState,
    required this.isScanning,
  });
}

// ---------------------------------------------------------------------------
// BluetoothProximityConfig
// ---------------------------------------------------------------------------

/// Full runtime configuration for [BtEngine].
///
/// Loaded from Firestore (baseline at [appConfig/btRuntime], optional sparse
/// overrides in study and enrollment documents) and merged via [merge] before
/// being passed to [BtEngine.setConfig]. See user_config_plan.md for the
/// three-layer merge architecture.
class BluetoothProximityConfig {
  // ---- Detection gating --------------------------------------------------

  /// Master kill switch. When false the engine does not scan, advertise, or
  /// emit events.
  final bool enabled;

  /// RSSI threshold in dBm. Averaged readings below this value (i.e. more
  /// negative, meaning further away) are discarded. Default -80 ≈ 6–9 m.
  /// More negative = wider detection range.
  final int rssiThresholdDbm;

  /// Number of RSSI readings to accumulate per peer before applying the
  /// threshold gate. Smooths out momentary signal spikes.
  final int rollingRssiSamples;

  // ---- Write rates -------------------------------------------------------

  /// Minimum seconds between Firestore writes for the same peer when the
  /// device is inside a geofence.
  final int insideGeofenceRateS;

  /// Minimum seconds between Firestore writes for the same peer when outside
  /// all geofences. Null disables outside-geofence writes entirely.
  final int? outsideGeofenceRateS;

  // ---- Scan timing -------------------------------------------------------

  /// Seconds between scan cycle starts. A new scan begins every
  /// [scanIntervalS] seconds.
  final int scanIntervalS;

  /// How long each scan cycle runs in seconds. Must be <= [scanIntervalS].
  final int scanDurationS;

  // ---- Advertisement identity -------------------------------------------

  /// BLE service UUID that identifies this app's advertisements. All devices
  /// advertise with this UUID and all scan filters are keyed to it. Not
  /// overridable per study — set once in [appConfig/btRuntime].
  final String advertiseServiceUuid;

  // ---- Constructors ------------------------------------------------------

  const BluetoothProximityConfig({
    required this.enabled,
    required this.rssiThresholdDbm,
    required this.rollingRssiSamples,
    required this.insideGeofenceRateS,
    required this.outsideGeofenceRateS,
    required this.scanIntervalS,
    required this.scanDurationS,
    required this.advertiseServiceUuid,
  });

  /// Deserializes from a Firestore document map (e.g. [appConfig/btRuntime]).
  ///
  /// All fields except [advertiseServiceUuid] have safe defaults so that a
  /// partially-populated document still produces a valid config.
  /// Throws [ArgumentError] if [advertise_service_uuid] is absent or empty —
  /// this field must be set before the package is used.
  factory BluetoothProximityConfig.fromMap(Map<String, dynamic> m) {
    final uuid = m['advertise_service_uuid'] as String?;
    if (uuid == null || uuid.isEmpty) {
      throw ArgumentError(
        'BluetoothProximityConfig: advertise_service_uuid is required. '
        'Set it in appConfig/btRuntime before starting the BT engine.',
      );
    }
    return BluetoothProximityConfig(
      enabled: m['enabled'] as bool? ?? true,
      rssiThresholdDbm: m['rssi_threshold_dbm'] as int? ?? -80,
      rollingRssiSamples: m['rolling_rssi_samples'] as int? ?? 3,
      insideGeofenceRateS: m['inside_geofence_rate_s'] as int? ?? 60,
      // Explicit null in Firestore disables outside writes.
      // Missing key defaults to 300 s (writes everywhere, just slowly).
      outsideGeofenceRateS: m.containsKey('outside_geofence_rate_s')
          ? m['outside_geofence_rate_s'] as int?
          : 300,
      scanIntervalS: m['scan_interval_s'] as int? ?? 10,
      scanDurationS: m['scan_duration_s'] as int? ?? 5,
      advertiseServiceUuid: uuid,
    );
  }

  // ---- Merge -------------------------------------------------------------

  /// Merges [baseline] with a list of sparse override maps, applying
  /// "most aggressive wins" rules field-by-field.
  ///
  /// [overrides] is a list of raw Firestore maps — typically the concatenation
  /// of study-level (Layer 2) and enrollment-level (Layer 3) config maps.
  /// Only keys that are **explicitly present** in an override map (checked via
  /// [Map.containsKey]) participate in the merge for that map, preventing
  /// absent fields from inadvertently overriding the baseline with defaults.
  ///
  /// Rules:
  /// - [enabled]               → true wins (||)
  /// - [rssiThresholdDbm]      → min() — more negative = wider range
  /// - [rollingRssiSamples]    → min() — fewer samples = faster response
  /// - [insideGeofenceRateS]   → min() — lower rate = more writes
  /// - [outsideGeofenceRateS]  → min of non-null values; null only if all null
  ///                             (a null override never suppresses a non-null
  ///                             baseline — writing is more aggressive than not)
  /// - [scanIntervalS]         → min() — more frequent scanning
  /// - [scanDurationS]         → max() — longer windows catch more devices
  /// - [advertiseServiceUuid]  → baseline always wins; override ignored
  static BluetoothProximityConfig merge(
    BluetoothProximityConfig baseline,
    List<Map<String, dynamic>> overrides,
  ) {
    // Start from baseline values.
    var enabled = baseline.enabled;
    var rssiThresholdDbm = baseline.rssiThresholdDbm;
    var rollingRssiSamples = baseline.rollingRssiSamples;
    var insideGeofenceRateS = baseline.insideGeofenceRateS;
    var outsideGeofenceRateS = baseline.outsideGeofenceRateS;
    var scanIntervalS = baseline.scanIntervalS;
    var scanDurationS = baseline.scanDurationS;
    // advertiseServiceUuid never changes — always baseline.

    for (final o in overrides) {
      if (o.containsKey('enabled')) {
        enabled = enabled || (o['enabled'] as bool? ?? false);
      }
      if (o.containsKey('rssi_threshold_dbm')) {
        final v = o['rssi_threshold_dbm'] as int?;
        if (v != null) rssiThresholdDbm = math.min(rssiThresholdDbm, v);
      }
      if (o.containsKey('rolling_rssi_samples')) {
        final v = o['rolling_rssi_samples'] as int?;
        if (v != null) rollingRssiSamples = math.min(rollingRssiSamples, v);
      }
      if (o.containsKey('inside_geofence_rate_s')) {
        final v = o['inside_geofence_rate_s'] as int?;
        if (v != null) insideGeofenceRateS = math.min(insideGeofenceRateS, v);
      }
      if (o.containsKey('outside_geofence_rate_s')) {
        final v = o['outside_geofence_rate_s'] as int?;
        // null override does NOT suppress a non-null baseline — a study
        // opting out of outside writes shouldn't silence another study
        // that wants them. Null result only when baseline is also null.
        if (v != null) {
          outsideGeofenceRateS = outsideGeofenceRateS == null
              ? v
              : math.min(outsideGeofenceRateS, v);
        }
      }
      if (o.containsKey('scan_interval_s')) {
        final v = o['scan_interval_s'] as int?;
        if (v != null) scanIntervalS = math.min(scanIntervalS, v);
      }
      if (o.containsKey('scan_duration_s')) {
        final v = o['scan_duration_s'] as int?;
        if (v != null) scanDurationS = math.max(scanDurationS, v);
      }
    }

    return BluetoothProximityConfig(
      enabled: enabled,
      rssiThresholdDbm: rssiThresholdDbm,
      rollingRssiSamples: rollingRssiSamples,
      insideGeofenceRateS: insideGeofenceRateS,
      outsideGeofenceRateS: outsideGeofenceRateS,
      scanIntervalS: scanIntervalS,
      scanDurationS: scanDurationS,
      advertiseServiceUuid: baseline.advertiseServiceUuid,
    );
  }
}

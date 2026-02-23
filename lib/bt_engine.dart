// bt_engine.dart — BLE advertising and scanning engine.
// See zbg_proximity_plan.md §3.3 for full specification.
//
// ⚠️  ADVERTISING API NOTE
// flutter_blue_plus advertising support was added in v1.14 and has evolved.
// Before running on device, verify that the FlutterBluePlus.startAdvertising()
// call below matches the API in your installed version. The scan-side API is
// stable and unlikely to need adjustment.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'bt_api.dart';
import 'bt_utils.dart';

// Company ID embedded in BLE manufacturer data payloads.
// 0xFFFF is an unregistered / proprietary ID used here to identify this app.
// Must be the same value on advertising and scanning sides.
const int _kCompanyId = 0xFFFF;

/// BLE proximity detection engine.
///
/// Lifecycle:
///   1. [setIdentity] — provide uid and regionId (call once at sign-in)
///   2. [setConfig]   — provide merged [BluetoothProximityConfig]
///   3. [registerPeer] — register each study participant's uid (builds the
///                       in-memory hash→uid lookup table)
///   4. [start]       — begin advertising + scan loop
///   5. Subscribe to [onProximity] to receive [BluetoothProximityEvent]s,
///      then write each one to Firestore via [BtWriters]
///   6. [stop] / [clearPeerRegistry] on sign-out
///
/// The engine is zone-state-aware but does not import zbg_location. The app
/// layer calls [setZoneState] whenever the geofence state changes (wired from
/// the existing GeofenceEvent stream handler).
class BtEngine {
  // --- Identity (set before start) ----------------------------------------

  String? _uid;
  String? _regionId;

  // --- Config --------------------------------------------------------------

  BluetoothProximityConfig? _cfg;

  // --- Runtime state -------------------------------------------------------

  /// Tracks zone status injected from the app layer via [setZoneState].
  ZoneState _zoneState = ZoneState.outside;

  /// True between [start] and [stop].
  bool _started = false;

  /// Current BLE advertising state, reflected on [onAdvertisingState].
  AdvertisingState _advertisingState = AdvertisingState.off;

  /// Mirrors the flutter_blue_plus scan-in-progress state.
  bool _isScanning = false;

  /// UTC timestamp of the most recent event emitted to [onProximity].
  DateTime? _lastEventTime;

  // --- Peer registry -------------------------------------------------------

  /// Maps UID hash (8-byte hex from [hashUidForAdvertisement]) → Firebase UID.
  /// Populated by [registerPeer]; used to resolve received advertisement data.
  final Map<String, String> _peerRegistry = {};

  /// Per-peer rolling buffer of raw RSSI readings (most recent first).
  /// Trimmed to [BluetoothProximityConfig.rollingRssiSamples] entries.
  final Map<String, List<int>> _rssiBuffer = {};

  /// Per-peer timestamp of the last Firestore write.
  /// Used to enforce [BluetoothProximityConfig.insideGeofenceRateS] /
  /// [BluetoothProximityConfig.outsideGeofenceRateS].
  final Map<String, DateTime> _lastWriteTime = {};

  /// Hashes of peers that passed all gates in the current scan cycle.
  /// Cleared at the start of each cycle; used for [BluetoothProximityStatus].
  final Set<String> _nearbyHashes = {};

  // --- Timers / subscriptions ---------------------------------------------

  Timer? _scanTimer;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  // --- Streams (broadcast so multiple listeners are supported) ------------

  final _proxCtl = StreamController<BluetoothProximityEvent>.broadcast();
  final _statusCtl = StreamController<BluetoothProximityStatus>.broadcast();
  final _advCtl = StreamController<AdvertisingState>.broadcast();

  // =========================================================================
  // Public API
  // =========================================================================

  /// Set the signed-in user's UID and active region. Call before [setConfig].
  void setIdentity({required String uid, required String regionId}) {
    _uid = uid;
    _regionId = regionId;
  }

  /// Apply a (possibly merged) [BluetoothProximityConfig].
  ///
  /// Safe to call while the engine is running — it stops, updates the config,
  /// then restarts. Peer registry and rate-limit state are preserved across
  /// the restart so a config change does not reset proximity tracking.
  Future<void> setConfig(BluetoothProximityConfig cfg) async {
    final wasStarted = _started;
    if (wasStarted) await stop();
    _cfg = cfg;
    if (wasStarted) await start();
  }

  /// Update the current geofence zone state.
  ///
  /// Call this from the same FlutterFlow action that handles [GeofenceEvent]s
  /// from the zbg_location engine. The engine uses this to decide whether to
  /// apply [BluetoothProximityConfig.insideGeofenceRateS] or
  /// [BluetoothProximityConfig.outsideGeofenceRateS].
  void setZoneState(ZoneState state) {
    _zoneState = state;
  }

  /// Register a study participant so that their BLE advertisements can be
  /// recognised and their UID resolved during scanning.
  ///
  /// Internally computes `hash = hashUidForAdvertisement(uid)` and stores
  /// `hash → uid`. Call once per participant at session start via the
  /// [populatePeerRegistry] FlutterFlow action.
  void registerPeer(String uid) {
    final hash = hashUidForAdvertisement(uid);
    _peerRegistry[hash] = uid;
    if (kDebugMode) {
      debugPrint('[BtEngine] registerPeer uid=$uid hash=$hash');
    }
  }

  /// Removes all registered peers and clears per-peer RSSI and rate-limit
  /// state. Call on sign-out.
  void clearPeerRegistry() {
    _peerRegistry.clear();
    _rssiBuffer.clear();
    _lastWriteTime.clear();
    _nearbyHashes.clear();
  }

  /// Start BLE advertising and the scan loop.
  ///
  /// Requires [setIdentity] and [setConfig] to have been called.
  /// Subsequent calls while already started are no-ops.
  Future<void> start() async {
    assert(_uid != null, 'BtEngine: call setIdentity() before start()');
    assert(_cfg != null, 'BtEngine: call setConfig() before start()');
    if (_started) return;

    final cfg = _cfg!;
    if (!cfg.enabled) {
      if (kDebugMode) debugPrint('[BtEngine] start() skipped — enabled=false');
      return;
    }

    _started = true;
    await _startAdvertising();
    _startScanLoop();
    if (kDebugMode) debugPrint('[BtEngine] started');
  }

  /// Stop advertising, cancel the scan loop, and release scan subscriptions.
  ///
  /// Peer registry and rate-limit state are intentionally preserved so that
  /// a stop/start cycle (e.g. from [setConfig]) does not reset proximity data.
  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    _scanTimer?.cancel();
    _scanTimer = null;

    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      if (kDebugMode) debugPrint('[BtEngine] stopScan error (ignored): $e');
    }

    try {
      await FlutterBluePlus.stopAdvertising();
    } catch (e) {
      if (kDebugMode) debugPrint('[BtEngine] stopAdvertising error (ignored): $e');
    }

    _isScanning = false;
    _updateAdvertisingState(AdvertisingState.off);
    if (kDebugMode) debugPrint('[BtEngine] stopped');
  }

  /// Stream of proximity events. Each event represents one peer passing all
  /// gates (RSSI threshold, rolling average, per-peer rate limit, zone gate).
  /// Subscribe in the [startBtEngine] FlutterFlow action and write each event
  /// to Firestore via [BtWriters.writeProximityEvent].
  Stream<BluetoothProximityEvent> onProximity() => _proxCtl.stream;

  /// Periodic status snapshots, emitted at the end of each scan cycle.
  Stream<BluetoothProximityStatus> onStatus() => _statusCtl.stream;

  /// Emits whenever [AdvertisingState] changes. Useful for surfacing a
  /// warning to researchers if advertising is not active.
  Stream<AdvertisingState> onAdvertisingState() => _advCtl.stream;

  /// The currently applied config, or null before [setConfig] is called.
  BluetoothProximityConfig? get currentConfig => _cfg;

  // =========================================================================
  // Advertising
  // =========================================================================

  Future<void> _startAdvertising() async {
    final cfg = _cfg!;
    final uid = _uid!;

    // Build the 8-byte manufacturer payload from the UID hash.
    final hashHex = hashUidForAdvertisement(uid);
    final hashBytes = _hexToBytes(hashHex);

    try {
      // ⚠️  Verify this call against your installed flutter_blue_plus version.
      // The AdvertisementData constructor and startAdvertising signature have
      // evolved. As of v1.32 the call below is expected to be correct.
      //
      // On iOS without the bluetooth-peripheral entitlement, startAdvertising
      // succeeds but the advertisement is moved to the CoreBluetooth overflow
      // area when backgrounded — iOS-to-iOS same-app detection still works.
      // We cannot distinguish this from full advertising at the Dart level, so
      // we report AdvertisingState.active in both cases.
      await FlutterBluePlus.startAdvertising(
        AdvertisementData(
          advName: '',
          connectable: false,
          serviceUuids: [Guid(cfg.advertiseServiceUuid)],
          manufacturerData: {_kCompanyId: hashBytes},
        ),
        timeout: const Duration(hours: 24),
      );
      _updateAdvertisingState(AdvertisingState.active);
      if (kDebugMode) {
        debugPrint(
          '[BtEngine] advertising active. '
          'uuid=${cfg.advertiseServiceUuid} hashHex=$hashHex',
        );
      }
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[BtEngine] advertising PlatformException: ${e.code} — ${e.message}');
      }
      final code = e.code.toLowerCase();
      if (code.contains('unavailable') || code.contains('off') || code.contains('disabled')) {
        _updateAdvertisingState(AdvertisingState.off);
      } else if (code.contains('not_supported') || code.contains('unsupported')) {
        _updateAdvertisingState(AdvertisingState.unsupported);
      } else {
        // Catch-all: most likely a background restriction on iOS.
        // Advertisements may still reach other iOS devices via overflow area.
        _updateAdvertisingState(AdvertisingState.restricted);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[BtEngine] advertising failed: $e');
      _updateAdvertisingState(AdvertisingState.unsupported);
    }
  }

  // =========================================================================
  // Scan loop
  // =========================================================================

  void _startScanLoop() {
    final cfg = _cfg!;

    // Subscribe once to the cumulative scan-results stream. flutter_blue_plus
    // emits the full list of all devices found so far whenever a new device
    // appears or an existing device's RSSI updates. The subscription persists
    // across scan cycles; the results list resets when each new scan starts.
    _scanResultsSub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (Object e) {
        if (kDebugMode) debugPrint('[BtEngine] scanResults stream error: $e');
      },
    );

    // Run the first scan immediately so the user doesn't wait scanIntervalS
    // before any detection happens.
    _runOneScan();

    // Then fire a new scan cycle every scanIntervalS seconds.
    _scanTimer = Timer.periodic(
      Duration(seconds: cfg.scanIntervalS),
      (_) {
        // Clear the "nearby" set at the start of each cycle so the status
        // snapshot reflects only peers seen in that cycle.
        _nearbyHashes.clear();
        _runOneScan();
      },
    );
  }

  Future<void> _runOneScan() async {
    final cfg = _cfg;
    if (cfg == null || !_started) return;

    // Guard: don't start a new scan if one is already in progress. This
    // prevents overlap if scanDurationS is close to scanIntervalS.
    if (FlutterBluePlus.isScanningNow) return;

    try {
      _isScanning = true;
      await FlutterBluePlus.startScan(
        withServices: [Guid(cfg.advertiseServiceUuid)],
        timeout: Duration(seconds: cfg.scanDurationS),
      );
      // startScan with a timeout auto-stops after scanDurationS. We wait for
      // the same duration so _isScanning reflects the actual scan window.
      await Future.delayed(Duration(seconds: cfg.scanDurationS));
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[BtEngine] startScan PlatformException: ${e.code}');
    } catch (e) {
      if (kDebugMode) debugPrint('[BtEngine] startScan error: $e');
    } finally {
      _isScanning = false;
      _emitStatus();
    }
  }

  // =========================================================================
  // Scan result processing
  // =========================================================================

  /// Called by the [FlutterBluePlus.scanResults] stream with the cumulative
  /// list of all devices found in the current scan.
  void _onScanResults(List<ScanResult> results) {
    final cfg = _cfg;
    if (cfg == null || !_started) return;
    for (final result in results) {
      _processScanResult(result, cfg);
    }
  }

  void _processScanResult(ScanResult result, BluetoothProximityConfig cfg) {
    // --- Step 1: extract manufacturer data using our company ID ---
    final hashBytes = result.advertisementData.manufacturerData[_kCompanyId];
    if (hashBytes == null || hashBytes.isEmpty) return;

    // --- Step 2: reconstruct the peer hash hex string ---
    final peerHash = _bytesToHex(hashBytes);

    // --- Step 3: resolve peer UID from registry ---
    final peerUid = _peerRegistry[peerHash];
    if (peerUid == null) return; // not a known study participant

    // --- Step 4: self-detection guard ---
    if (peerUid == _uid) return;

    // --- Step 5: accumulate RSSI; trim to rolling window ---
    final buffer = _rssiBuffer.putIfAbsent(peerHash, () => []);
    buffer.add(result.rssi);
    if (buffer.length > cfg.rollingRssiSamples) {
      buffer.removeAt(0);
    }

    // --- Step 6: wait for a full window before gating ---
    if (buffer.length < cfg.rollingRssiSamples) return;

    // --- Step 7: apply RSSI threshold (rounded average) ---
    final avgRssi = rollingAverage(buffer).round();
    if (avgRssi < cfg.rssiThresholdDbm) return; // signal too weak → too far

    // --- Step 8: zone-gated write rate ---
    // When outside all geofences and outsideGeofenceRateS is null, writes
    // are disabled entirely — return early without updating any state.
    if (!_zoneState.insideZone && cfg.outsideGeofenceRateS == null) return;

    final effectiveRateS = _zoneState.insideZone
        ? cfg.insideGeofenceRateS
        : cfg.outsideGeofenceRateS!;

    // --- Step 9: per-peer rate limit ---
    final lastWrite = _lastWriteTime[peerHash];
    if (lastWrite != null) {
      final elapsedS = DateTime.now().toUtc().difference(lastWrite).inSeconds;
      if (elapsedS < effectiveRateS) return;
    }

    // --- Step 10: all gates passed — build and emit event ---
    final nowUtc = DateTime.now().toUtc();
    final event = BluetoothProximityEvent(
      peerUid: peerUid,
      regionId: _regionId ?? '',
      tsIso: nowUtc.toIso8601String(),
      rssi: avgRssi,
      estimatedM: rssiToMeters(avgRssi),
      zoneId: _zoneState.zoneId,
      insideZone: _zoneState.insideZone,
    );

    _proxCtl.add(event);
    _lastEventTime = nowUtc;
    _lastWriteTime[peerHash] = nowUtc;
    _nearbyHashes.add(peerHash);

    if (kDebugMode) {
      debugPrint(
        '[BtEngine] proximity event: peer=$peerUid '
        'rssi=$avgRssi (${event.estimatedM.toStringAsFixed(1)} m) '
        'zone=${_zoneState.zoneId ?? "outside"}',
      );
    }
  }

  // =========================================================================
  // Status
  // =========================================================================

  void _emitStatus() {
    _statusCtl.add(BluetoothProximityStatus(
      nearbyPeerCount: _nearbyHashes.length,
      lastEventTime: _lastEventTime,
      advertisingState: _advertisingState,
      isScanning: _isScanning,
    ));
  }

  void _updateAdvertisingState(AdvertisingState state) {
    _advertisingState = state;
    _advCtl.add(state);
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  /// Converts a lowercase hex string (e.g. "deadbeef01020304") to a byte list.
  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// Converts a byte list to a lowercase hex string.
  /// Inverse of [_hexToBytes] and consistent with [hashUidForAdvertisement].
  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

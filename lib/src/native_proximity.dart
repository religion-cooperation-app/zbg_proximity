import 'package:flutter/services.dart';

/// Configuration persisted by the native Android proximity plugin.
class NativeProximityConfig {
  const NativeProximityConfig({
    required this.uid,
    required this.advertiseServiceUuid,
    required this.activationMode,
  });

  final String uid;
  final String advertiseServiceUuid;
  final String activationMode;

  Map<String, Object?> toMap() => <String, Object?>{
        'uid': uid,
        'advertiseServiceUuid': advertiseServiceUuid,
        'activationMode': activationMode,
      };
}

/// Current state reported by the native Android plugin.
class NativeProximityStatus {
  const NativeProximityStatus({
    required this.platform,
    required this.configured,
    required this.running,
    required this.advertising,
    required this.advertisingState,
    required this.scanning,
    required this.scanningState,
    required this.knownPeerCount,
    required this.nearbyPeerCount,
    required this.scanCallbackCount,
    required this.validFrameCount,
    required this.recognizedPeerCount,
    this.activationMode,
    this.lastDetectedPeerUid,
    this.lastDetectedRssi,
    this.lastDetectedAt,
    this.lastBleError,
  });

  factory NativeProximityStatus.fromMap(Map<Object?, Object?> map) {
    return NativeProximityStatus(
      platform: map['platform'] as String? ?? 'unknown',
      configured: map['configured'] as bool? ?? false,
      running: map['running'] as bool? ?? false,
      activationMode: map['activationMode'] as String?,
      advertising: map['advertising'] as bool? ?? false,
      advertisingState: map['advertisingState'] as String? ?? 'unknown',
      scanning: map['scanning'] as bool? ?? false,
      scanningState: map['scanningState'] as String? ?? 'unknown',
      knownPeerCount: map['knownPeerCount'] as int? ?? 0,
      nearbyPeerCount: map['nearbyPeerCount'] as int? ?? 0,
      scanCallbackCount: map['scanCallbackCount'] as int? ?? 0,
      validFrameCount: map['validFrameCount'] as int? ?? 0,
      recognizedPeerCount: map['recognizedPeerCount'] as int? ?? 0,
      lastDetectedPeerUid: map['lastDetectedPeerUid'] as String?,
      lastDetectedRssi: map['lastDetectedRssi'] as int?,
      lastDetectedAt: _dateTimeFromMilliseconds(map['lastDetectedAtMs']),
      lastBleError: map['lastBleError'] as String?,
    );
  }

  final String platform;
  final bool configured;
  final bool running;
  final String? activationMode;
  final bool advertising;
  final String advertisingState;
  final bool scanning;
  final String scanningState;
  final int knownPeerCount;
  final int nearbyPeerCount;
  final int scanCallbackCount;
  final int validFrameCount;
  final int recognizedPeerCount;
  final String? lastDetectedPeerUid;
  final int? lastDetectedRssi;
  final DateTime? lastDetectedAt;
  final String? lastBleError;
}

/// Last-seen state for one configured participant peer.
class NativeNearbyPeer {
  const NativeNearbyPeer({
    required this.uid,
    required this.rssi,
    required this.sampleCount,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.nearby,
  });

  factory NativeNearbyPeer.fromMap(Map<Object?, Object?> map) {
    return NativeNearbyPeer(
      uid: map['uid'] as String? ?? '',
      rssi: map['rssi'] as int? ?? 0,
      sampleCount: map['sampleCount'] as int? ?? 0,
      firstSeenAt: _dateTimeFromMilliseconds(map['firstSeenAtMs']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastSeenAt: _dateTimeFromMilliseconds(map['lastSeenAtMs']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      nearby: map['nearby'] as bool? ?? false,
    );
  }

  final String uid;
  final int rssi;
  final int sampleCount;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final bool nearby;
}

/// Channel facade for the native Android migration.
abstract final class NativeProximity {
  static const MethodChannel _channel =
      MethodChannel('app.zbg.proximity/methods');

  static Future<void> configure(NativeProximityConfig config) async {
    await _channel.invokeMethod<void>('configure', config.toMap());
  }

  /// Replaces the native registry of participant UIDs that may be detected.
  ///
  /// Returns the number of non-self peers stored by Android.
  static Future<int> syncPeers(List<String> peerUids) async {
    return await _channel.invokeMethod<int>(
          'syncPeers',
          <String, Object?>{'peerUids': peerUids},
        ) ??
        0;
  }

  /// Starts the native Android foreground-service lifecycle.
  ///
  /// BLE scanning and advertising are added in a later milestone.
  static Future<void> startAlways() async {
    await _channel.invokeMethod<void>('startAlways');
  }

  static Future<NativeProximityStatus> getStatus() async {
    final result =
        await _channel.invokeMethod<Map<Object?, Object?>>('getStatus');
    return NativeProximityStatus.fromMap(result ?? const <Object?, Object?>{});
  }

  static Future<List<NativeNearbyPeer>> getNearbyPeers() async {
    final result =
        await _channel.invokeMethod<List<Object?>>('getNearbyPeers') ??
            const <Object?>[];
    return result
        .whereType<Map<Object?, Object?>>()
        .map(NativeNearbyPeer.fromMap)
        .toList(growable: false);
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}

DateTime? _dateTimeFromMilliseconds(Object? value) {
  if (value is! int) return null;
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

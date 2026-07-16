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
    this.activationMode,
  });

  factory NativeProximityStatus.fromMap(Map<Object?, Object?> map) {
    return NativeProximityStatus(
      platform: map['platform'] as String? ?? 'unknown',
      configured: map['configured'] as bool? ?? false,
      running: map['running'] as bool? ?? false,
      activationMode: map['activationMode'] as String?,
    );
  }

  final String platform;
  final bool configured;
  final bool running;
  final String? activationMode;
}

/// Channel facade for the native Android migration.
abstract final class NativeProximity {
  static const MethodChannel _channel =
      MethodChannel('app.zbg.proximity/methods');

  static Future<void> configure(NativeProximityConfig config) async {
    await _channel.invokeMethod<void>('configure', config.toMap());
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

  static Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}

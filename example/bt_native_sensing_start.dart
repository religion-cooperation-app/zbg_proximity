// Automatic FlutterFlow imports
import '/backend/backend.dart';
import '/backend/schema/structs/index.dart';
import '/backend/schema/enums/enums.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'index.dart'; // Imports other custom actions
import '/flutter_flow/custom_functions.dart';
import 'package:flutter/material.dart';
// Begin custom action code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import 'package:zbg_proximity/zbg_proximity.dart';

/// Configures native BLE, registers one test peer, and starts sensing.
///
/// FlutterFlow configuration:
/// - Name: btNativeSensingStart
/// - Arguments:
///   - uid: String, required
///   - serviceUuid: String, required
///   - peerUid: String, required
/// - Return type: String
Future<String> btNativeSensingStart(
  String uid,
  String serviceUuid,
  String peerUid,
) async {
  try {
    await NativeProximity.configure(
      NativeProximityConfig(
        uid: uid,
        advertiseServiceUuid: serviceUuid,
        activationMode: 'always',
      ),
    );
    final knownPeerCount = await NativeProximity.syncPeers(<String>[peerUid]);
    await NativeProximity.startAlways();
    await Future<void>.delayed(const Duration(seconds: 2));
    final status = await NativeProximity.getStatus();

    return _formatSensingStatus(status, knownPeerCount: knownPeerCount);
  } catch (error, stackTrace) {
    debugPrint('btNativeSensingStart failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

String _formatSensingStatus(
  NativeProximityStatus status, {
  int? knownPeerCount,
}) {
  return <String>[
    'running=${status.running}',
    'advertising=${status.advertising}(${status.advertisingState})',
    'scanning=${status.scanning}(${status.scanningState})',
    'known=${knownPeerCount ?? status.knownPeerCount}',
    'nearby=${status.nearbyPeerCount}',
    'last=${status.lastDetectedPeerUid ?? "none"}',
    'rssi=${status.lastDetectedRssi?.toString() ?? "none"}',
    if (status.lastBleError != null) 'error=${status.lastBleError}',
  ].join(', ');
}

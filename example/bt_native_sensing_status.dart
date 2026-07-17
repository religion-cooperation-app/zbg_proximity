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

/// Returns current native advertising, scanning, and last-detection status.
///
/// FlutterFlow configuration:
/// - Name: btNativeSensingStatus
/// - Arguments: none
/// - Return type: String
Future<String> btNativeSensingStatus() async {
  try {
    final status = await NativeProximity.getStatus();
    return <String>[
      'running=${status.running}',
      'advertising=${status.advertising}(${status.advertisingState})',
      'scanning=${status.scanning}(${status.scanningState})',
      'known=${status.knownPeerCount}',
      'nearby=${status.nearbyPeerCount}',
      'callbacks=${status.scanCallbackCount}',
      'frames=${status.validFrameCount}',
      'recognized=${status.recognizedPeerCount}',
      'last=${status.lastDetectedPeerUid ?? "none"}',
      'rssi=${status.lastDetectedRssi?.toString() ?? "none"}',
      if (status.lastDetectedAt != null)
        'at=${status.lastDetectedAt!.toIso8601String()}',
      if (status.lastBleError != null) 'error=${status.lastBleError}',
    ].join(', ');
  } catch (error, stackTrace) {
    debugPrint('btNativeSensingStatus failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

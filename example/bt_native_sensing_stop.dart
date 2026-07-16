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

/// Stops native BLE sensing and clears test identity, peers, and detections.
///
/// FlutterFlow configuration:
/// - Name: btNativeSensingStop
/// - Arguments: none
/// - Return type: String
Future<String> btNativeSensingStop() async {
  try {
    await NativeProximity.stop();
    final status = await NativeProximity.getStatus();
    return 'running=${status.running}, advertising=${status.advertising}, '
        'scanning=${status.scanning}, known=${status.knownPeerCount}, '
        'nearby=${status.nearbyPeerCount}';
  } catch (error, stackTrace) {
    debugPrint('btNativeSensingStop failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

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

/// Returns a compact display string for all persisted known-peer detections.
///
/// FlutterFlow configuration:
/// - Name: btNativeNearbyPeers
/// - Arguments: none
/// - Return type: String
Future<String> btNativeNearbyPeers() async {
  try {
    final peers = await NativeProximity.getNearbyPeers();
    if (peers.isEmpty) return 'No known peers detected';
    return peers.map((peer) {
      return '${peer.uid}: rssi=${peer.rssi}, samples=${peer.sampleCount}, '
          'nearby=${peer.nearby}, last=${peer.lastSeenAt.toIso8601String()}';
    }).join('\n');
  } catch (error, stackTrace) {
    debugPrint('btNativeNearbyPeers failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

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

/// Reads the persisted native foreground-service status.
///
/// FlutterFlow configuration:
/// - Name: btNativeServiceStatus
/// - Arguments: none
/// - Return type: String
Future<String> btNativeServiceStatus() async {
  try {
    final status = await NativeProximity.getStatus();
    return <String>[
      'platform=${status.platform}',
      'configured=${status.configured}',
      'running=${status.running}',
      'mode=${status.activationMode}',
    ].join(', ');
  } catch (error, stackTrace) {
    debugPrint('btNativeServiceStatus failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

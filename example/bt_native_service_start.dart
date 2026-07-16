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

/// Configures and starts the native foreground-service lifecycle.
///
/// FlutterFlow configuration:
/// - Name: btNativeServiceStart
/// - Arguments:
///   - uid: String, required
///   - serviceUuid: String, required
/// - Return type: String
Future<String> btNativeServiceStart(
  String uid,
  String serviceUuid,
) async {
  try {
    await NativeProximity.configure(
      NativeProximityConfig(
        uid: uid,
        advertiseServiceUuid: serviceUuid,
        activationMode: 'always',
      ),
    );
    await NativeProximity.startAlways();

    // Give Android a moment to enter the foreground-service state.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final status = await NativeProximity.getStatus();

    return <String>[
      'platform=${status.platform}',
      'configured=${status.configured}',
      'running=${status.running}',
      'mode=${status.activationMode}',
    ].join(', ');
  } catch (error, stackTrace) {
    debugPrint('btNativeServiceStart failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

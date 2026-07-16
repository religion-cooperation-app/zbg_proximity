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

/// Temporary integration check for the native zbg_proximity Android plugin.
///
/// FlutterFlow configuration:
/// - Name: btNativePluginCheck
/// - Arguments:
///   - uid: String, required
///   - serviceUuid: String, required
/// - Return type: String
///
/// This action does not start scanning, advertising, a foreground service, or
/// Firestore writes. It only proves that Dart can call the Kotlin plugin.
Future<String> btNativePluginCheck(
  String uid,
  String serviceUuid,
) async {
  try {
    final initial = await NativeProximity.getStatus();

    await NativeProximity.configure(
      NativeProximityConfig(
        uid: uid,
        advertiseServiceUuid: serviceUuid,
        activationMode: 'disabled',
      ),
    );

    final configured = await NativeProximity.getStatus();

    await NativeProximity.stop();

    final stopped = await NativeProximity.getStatus();

    return <String>[
      'platform=${configured.platform}',
      'initial=${initial.configured}',
      'configured=${configured.configured}',
      'running=${configured.running}',
      'stopped=${stopped.configured}',
    ].join(', ');
  } catch (error, stackTrace) {
    debugPrint('btNativePluginCheck failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

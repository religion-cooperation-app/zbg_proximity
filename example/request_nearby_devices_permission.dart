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

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests Android 12+ Nearby devices permissions used by native BLE.
///
/// FlutterFlow configuration:
/// - Name: requestNearbyDevicesPermission
/// - Arguments: none
/// - Return type: String
///
/// Android 10/11 use the legacy Bluetooth + location permission model, so
/// this action returns `not_required` there without showing a dialog.
Future<String> requestNearbyDevicesPermission() async {
  try {
    if (!Platform.isAndroid) return 'not_android';

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt < 31) {
      return 'not_required:android_sdk=${androidInfo.version.sdkInt}';
    }

    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ].request();

    String label(Permission permission) {
      final status = statuses[permission] ?? PermissionStatus.denied;
      if (status.isGranted || status.isLimited) return 'granted';
      if (status.isPermanentlyDenied) return 'permanently_denied';
      if (status.isRestricted) return 'restricted';
      return 'denied';
    }

    final scan = label(Permission.bluetoothScan);
    final advertise = label(Permission.bluetoothAdvertise);
    final connect = label(Permission.bluetoothConnect);
    final allGranted =
        scan == 'granted' && advertise == 'granted' && connect == 'granted';

    return 'nearby=${allGranted ? "granted" : "not_granted"}, '
        'scan=$scan, advertise=$advertise, connect=$connect, '
        'android_sdk=${androidInfo.version.sdkInt}';
  } catch (error, stackTrace) {
    debugPrint('requestNearbyDevicesPermission failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

// Native implementation of BLE advertising via flutter_ble_peripheral.
//
// ⚠️  iOS LIMITATION: Apple restricts manufacturer data in BLE advertisements.
// On iOS, only serviceUuid is broadcast — manufacturerData and manufacturerId
// are silently ignored. This means peer identification via UID hash does not
// work on iOS using this advertising approach. iOS-to-iOS proximity detection
// can confirm another app user is nearby (via service UUID match) but cannot
// identify which user. Android-to-Android and Android-to-iOS detection of the
// peer identity works correctly via manufacturer data.
//
// A future revision may address iOS peer identification via a GATT characteristic
// read after service UUID discovery.

import 'dart:typed_data';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

Future<void> startBleAdvertising({
  required String serviceUuid,
  required List<int> hashBytes,
  required int companyId,
}) async {
  await _peripheral.start(
    advertiseData: AdvertiseData(
      serviceUuid: serviceUuid,
      manufacturerData: Uint8List.fromList(hashBytes), // Android only
      manufacturerId: companyId,                        // Android only
    ),
  );
}

Future<void> stopBleAdvertising() async {
  await _peripheral.stop();
}

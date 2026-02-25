// Native implementation of BLE advertising via flutter_ble_peripheral.
//
// PLATFORM BEHAVIOUR
//
// Android:
//   Advertises with the fixed app service UUID + manufacturer data containing
//   the 8-byte UID hash. Scanners read the manufacturer data directly to
//   identify the peer without any connection.
//
// iOS:
//   Apple silently drops manufacturerData and manufacturerId from outgoing BLE
//   advertisements. Peer identification via manufacturer data is therefore
//   impossible on iOS.
//
//   Instead, each iOS device advertises a single per-user "identity UUID"
//   derived from the UID hash via hashToIdentityUuid(). The scanning peer
//   includes all registered peer identity UUIDs in its startScan withServices
//   filter. iOS background scanning wakes the app whenever a device advertising
//   any of those UUIDs comes into range, and the peer is identified by calling
//   identityUuidToHash() on the matched service UUID — no GATT connection
//   required.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import '../bt_utils.dart';

final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

Future<void> startBleAdvertising({
  required String serviceUuid,
  required List<int> hashBytes,
  required int companyId,
}) async {
  if (Platform.isIOS) {
    // Derive the per-user identity UUID from the hash bytes and advertise it
    // as the sole service UUID. Manufacturer data is omitted — iOS ignores it.
    final hashHex =
        hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final identityUuid = hashToIdentityUuid(hashHex);
    await _peripheral.start(
      advertiseData: AdvertiseData(
        serviceUuids: [identityUuid],
      ),
    );
  } else {
    // Android: advertise with the fixed app service UUID so scan filters keyed
    // to that UUID find this device, plus manufacturer data with the UID hash
    // so the scanner can identify the peer without a GATT connection.
    await _peripheral.start(
      advertiseData: AdvertiseData(
        serviceUuid: serviceUuid,
        manufacturerData: Uint8List.fromList(hashBytes),
        manufacturerId: companyId,
      ),
    );
  }
}

Future<void> stopBleAdvertising() async {
  await _peripheral.stop();
}

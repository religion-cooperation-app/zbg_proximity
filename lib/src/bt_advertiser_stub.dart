// Stub implementation for web and unsupported platforms.
// All calls are no-ops so the package compiles cleanly for web
// even though BLE advertising is not available there.

Future<void> startBleAdvertising({
  required String serviceUuid,
  required List<int> hashBytes,
  required int companyId,
}) async {}

Future<void> stopBleAdvertising() async {}

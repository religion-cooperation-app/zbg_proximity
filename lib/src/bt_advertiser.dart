// Conditional export: web/unsupported platforms get the stub,
// native platforms get the real flutter_ble_peripheral implementation.
export 'bt_advertiser_stub.dart' if (dart.library.io) 'bt_advertiser_native.dart';

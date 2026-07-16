import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zbg_proximity/zbg_proximity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.zbg.proximity/methods');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getStatus':
          return <String, Object?>{
            'platform': 'android',
            'configured': true,
            'running': false,
            'activationMode': 'always',
          };
        case 'configure':
        case 'stop':
          return null;
      }
      throw PlatformException(code: 'not_implemented');
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('configure serializes the minimal native contract', () async {
    await NativeProximity.configure(
      const NativeProximityConfig(
        uid: 'user-1',
        advertiseServiceUuid: '11111111-2222-3333-4444-555555555555',
        activationMode: 'always',
      ),
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'configure');
    expect(
      calls.single.arguments,
      <String, Object?>{
        'uid': 'user-1',
        'advertiseServiceUuid': '11111111-2222-3333-4444-555555555555',
        'activationMode': 'always',
      },
    );
  });

  test('getStatus parses the Android response', () async {
    final status = await NativeProximity.getStatus();

    expect(status.platform, 'android');
    expect(status.configured, isTrue);
    expect(status.running, isFalse);
    expect(status.activationMode, 'always');
  });

  test('stop invokes the native stop operation', () async {
    await NativeProximity.stop();

    expect(calls.single.method, 'stop');
  });
}

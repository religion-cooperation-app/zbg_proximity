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
            'running': true,
            'activationMode': 'always',
            'advertising': true,
            'advertisingState': 'active',
            'scanning': true,
            'scanningState': 'active',
            'knownPeerCount': 1,
            'nearbyPeerCount': 1,
            'lastDetectedPeerUid': 'peer-1',
            'lastDetectedRssi': -67,
            'lastDetectedAtMs': 1000,
            'lastBleError': null,
          };
        case 'syncPeers':
          return 1;
        case 'getNearbyPeers':
          return <Map<String, Object?>>[
            <String, Object?>{
              'uid': 'peer-1',
              'rssi': -67,
              'sampleCount': 5,
              'firstSeenAtMs': 500,
              'lastSeenAtMs': 1000,
              'nearby': true,
            },
          ];
        case 'configure':
        case 'startAlways':
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

  test('UID hash has the fixed cross-platform compatibility value', () {
    expect(
      hashUidForAdvertisement('user-1'),
      'c6c289e49e9c05b2',
    );
  });

  test('getStatus parses the Android response', () async {
    final status = await NativeProximity.getStatus();

    expect(status.platform, 'android');
    expect(status.configured, isTrue);
    expect(status.running, isTrue);
    expect(status.activationMode, 'always');
    expect(status.advertising, isTrue);
    expect(status.scanning, isTrue);
    expect(status.knownPeerCount, 1);
    expect(status.nearbyPeerCount, 1);
    expect(status.lastDetectedPeerUid, 'peer-1');
    expect(status.lastDetectedRssi, -67);
    expect(status.lastDetectedAt,
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true));
  });

  test('syncPeers sends the participant UID list', () async {
    final count = await NativeProximity.syncPeers(const <String>['peer-1']);

    expect(count, 1);
    expect(calls.single.method, 'syncPeers');
    expect(calls.single.arguments, <String, Object?>{
      'peerUids': const <String>['peer-1'],
    });
  });

  test('getNearbyPeers parses persisted detections', () async {
    final peers = await NativeProximity.getNearbyPeers();

    expect(peers, hasLength(1));
    expect(peers.single.uid, 'peer-1');
    expect(peers.single.rssi, -67);
    expect(peers.single.sampleCount, 5);
    expect(peers.single.nearby, isTrue);
  });

  test('startAlways invokes the native service operation', () async {
    await NativeProximity.startAlways();

    expect(calls.single.method, 'startAlways');
  });

  test('stop invokes the native stop operation', () async {
    await NativeProximity.stop();

    expect(calls.single.method, 'stop');
  });
}

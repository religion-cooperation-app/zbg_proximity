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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zbg_proximity/zbg_proximity.dart';

/// Production-like native BLE startup using Firebase Auth and Firestore.
///
/// FlutterFlow configuration:
/// - Name: btNativeSensingStartFromFirestore
/// - Arguments: none
/// - Return type: String
///
/// Peer eligibility for this milestone matches the existing BtBootstrap:
/// users sharing at least one `geolocation_region` with the signed-in user.
/// The native activation mode is deliberately forced to `always` so the
/// two-device swipe-away test works outside a geofence.
Future<String> btNativeSensingStartFromFirestore() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'ERROR: no authenticated user';

    final firestore = FirebaseFirestore.instance;

    final configSnapshot = await firestore.doc('appConfig/btRuntime').get();
    final userSnapshot = await firestore.doc('users/${user.uid}').get();

    if (!configSnapshot.exists) {
      return 'ERROR: missing appConfig/btRuntime';
    }
    if (!userSnapshot.exists) {
      return 'ERROR: missing users/${user.uid}';
    }

    final config = configSnapshot.data() as Map<String, dynamic>? ?? const {};
    final serviceUuid =
        (config['advertise_service_uuid'] as String? ?? '').trim();
    if (serviceUuid.isEmpty) {
      return 'ERROR: appConfig/btRuntime.advertise_service_uuid is empty';
    }

    final userData = userSnapshot.data() as Map<String, dynamic>? ?? const {};
    final regions = ((userData['geolocation_region'] as List<dynamic>?) ??
            const <dynamic>[])
        .whereType<String>()
        .map((region) => region.trim())
        .where((region) => region.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (regions.isEmpty) {
      return 'ERROR: signed-in user has no geolocation_region';
    }

    // Firestore arrayContainsAny accepts at most 30 comparison values.
    final peerUids = <String>{};
    for (var offset = 0; offset < regions.length; offset += 30) {
      final end = (offset + 30 < regions.length) ? offset + 30 : regions.length;
      final regionChunk = regions.sublist(offset, end);
      final peerSnapshot = await firestore
          .collection('users')
          .where('geolocation_region', arrayContainsAny: regionChunk)
          .get();
      for (final peer in peerSnapshot.docs) {
        if (peer.id != user.uid) peerUids.add(peer.id);
      }
    }

    await NativeProximity.configure(
      NativeProximityConfig(
        uid: user.uid,
        advertiseServiceUuid: serviceUuid,
        activationMode: 'always',
      ),
    );
    final knownPeerCount =
        await NativeProximity.syncPeers(peerUids.toList(growable: false));
    await NativeProximity.startAlways();

    await Future<void>.delayed(const Duration(seconds: 2));
    final status = await NativeProximity.getStatus();

    return <String>[
      'regions=${regions.length}',
      'running=${status.running}',
      'advertising=${status.advertising}(${status.advertisingState})',
      'scanning=${status.scanning}(${status.scanningState})',
      'known=$knownPeerCount',
      'nearby=${status.nearbyPeerCount}',
      'callbacks=${status.scanCallbackCount}',
      'frames=${status.validFrameCount}',
      'recognized=${status.recognizedPeerCount}',
      'last=${status.lastDetectedPeerUid ?? "none"}',
      'rssi=${status.lastDetectedRssi?.toString() ?? "none"}',
      if (status.lastBleError != null) 'error=${status.lastBleError}',
    ].join(', ');
  } catch (error, stackTrace) {
    debugPrint('btNativeSensingStartFromFirestore failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return 'ERROR: $error';
  }
}

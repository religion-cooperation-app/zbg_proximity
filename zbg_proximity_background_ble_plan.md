# zbg_proximity Android Background and Swipe-Away Implementation Plan

## Purpose

Implement reliable Android device-to-device Bluetooth Low Energy (BLE) proximity sensing while the SPARRC Flutter UI is:

- open in the foreground;
- backgrounded;
- removed from Recents by swiping it away; or
- recreated after process death or device reboot.

The implementation must preserve the existing cross-platform Dart API where practical, but Android proximity sensing must no longer depend on the Flutter process, Dart timers, Dart stream subscriptions, or Dart Firestore writes remaining alive.

This document covers participant-device detection only. Fixed BLE beacon support is specified separately in `ZBG_PROXIMITY_BEACON_INTEGRATION_PLAN.md`.

## Current System and Gap

The current package:

- scans with `flutter_blue_plus`;
- advertises with `flutter_ble_peripheral`;
- schedules Android scan windows with `Timer.periodic`;
- stores peer hashes, RSSI buffers, and write timestamps in Dart memory;
- emits `BluetoothProximityEvent` objects through a Dart stream; and
- relies on FlutterFlow custom code to write events to Firestore.

This works while the Flutter engine remains alive. It cannot guarantee scanning, advertising, peer resolution, rate limiting, or writes after Android destroys the Flutter process.

The Android implementation therefore needs a native execution path that owns the entire pipeline:

```text
Native config and identity
    -> foreground service
    -> BLE advertise and scan
    -> identify known peer
    -> smooth and gate RSSI
    -> durable local event
    -> native upload
    -> retry until acknowledged
```

## Required Behavior

### Foreground

- Start proximity sensing after a signed-in user is configured.
- Advertise a stable, privacy-preserving participant identifier.
- Scan for known participants.
- Apply RSSI, sampling, zone, and write-rate gates.
- Write accepted observations to Firestore.

### Background

- Continue the same native pipeline.
- Keep an Android foreground-service notification visible whenever BLE is active.
- Update the notification when the activation mode changes.

### Swipe-Away

- Removing the app from Recents must not stop an already-running native BLE foreground service.
- Native scan, advertisement, local queue, and uploads must continue without Dart.
- Geofence events may change the service between outside, near, and inside modes.

### Reboot and Process Recreation

- Restore sensing only when persisted state says the user is still signed in, configured, and enabled.
- Restore the last safe activation mode and peer registry.
- Do not require Flutter to open before the native queue can retry.

### Explicit Stop

- Sign-out, enrollment end, or an explicit `btStop` must stop scanning and advertising, cancel scheduled work, remove the foreground notification, and clear identity-sensitive persisted state.
- Android Settings **Force stop** cannot be bypassed. The app must be reopened.

## Architecture

Convert `zbg_proximity` into a Flutter plugin with an Android implementation under `android/`.

Recommended structure:

```text
android/src/main/kotlin/.../zbg_proximity/
  ZbgProximityPlugin.kt
  ProximityMethodHandler.kt
  ProximityForegroundService.kt
  ProximityServiceController.kt
  BleAdvertiser.kt
  BleScanner.kt
  ParticipantFrameCodec.kt
  PeerRegistry.kt
  ProximityConfig.kt
  ProximityStateStore.kt
  RssiWindowStore.kt
  ProximityEventStore.kt
  ProximityUploader.kt
  ProximityRetryWorker.kt
  ProximityBootReceiver.kt
  ProximityNotification.kt
  DiagnosticsLogger.kt
```

Use:

- Kotlin;
- Android `BluetoothLeScanner`;
- Android `BluetoothLeAdvertiser`;
- `Room` or a carefully versioned SQLite helper for durable events and per-target state;
- encrypted preferences for identity/configuration where feasible;
- Firebase Android SDK for Firestore writes; and
- WorkManager for queued upload retries when immediate native writes fail.

The foreground service owns active scanning and advertising. WorkManager is only a retry mechanism; it must not be treated as a continuous BLE scanner.

## Public Dart API

Add a platform facade while retaining `BtEngine` for iOS and compatibility.

Suggested API:

```dart
abstract final class ZbgProximity {
  static Future<void> configure(ProximityNativeConfig config);
  static Future<void> startAlways();
  static Future<void> setZoneMode({
    required ProximityZoneMode mode,
    String? zoneId,
  });
  static Future<void> syncPeers(List<ProximityPeer> peers);
  static Future<void> flush();
  static Future<ProximityNativeStatus> getStatus();
  static Stream<ProximityNativeEvent> events();
  static Future<void> stop({required bool clearIdentity});
}
```

On Android these methods use a `MethodChannel` and optional `EventChannel`. On iOS they can continue to delegate to the existing Dart engine until a native iOS migration is separately approved.

Do not make Flutter callback delivery a prerequisite for event persistence. Native events may be mirrored to Dart for diagnostics, but the native database and uploader are authoritative.

## Android Method Channel Contract

Implement the following operations:

- `configure`
  - persists identity, service UUID, activation mode, cadence, thresholds, notification text, Firestore destination, and schema version;
  - does not start BLE unless the active mode requires it.
- `syncPeers`
  - atomically replaces or versions the known-peer registry;
  - accepts UID hash plus the UID required for the Firestore event.
- `startAlways`
  - starts the foreground service in `always` mode.
- `setZoneMode`
  - accepts `outside`, `near`, or `inside` and an optional `zoneId`;
  - starts, reconfigures, or stops BLE according to `activation_mode`.
- `flush`
  - attempts immediate upload of queued events.
- `getStatus`
  - returns service, adapter, scan, advertise, mode, queue, and last-observation status.
- `stop`
  - stops service and BLE;
  - optionally clears persisted identity, peers, and queued events.

Every call must be idempotent. Duplicate Flutter lifecycle calls must not create multiple services, scans, receivers, or upload loops.

## Participant Advertisement Format

Continue using a non-reversible truncated hash of the Firebase UID, but version the frame explicitly.

Recommended payload:

```text
byte 0       protocol version
byte 1       flags
bytes 2..9   first 8 bytes of SHA-256(uid)
bytes 10..13 optional rotating epoch/token data
```

Design requirements:

- Do not advertise the raw Firebase UID.
- Use a stable service UUID dedicated to SPARRC participant advertisements.
- Do not identify peers by BLE MAC address.
- Reserve a protocol-version byte before deployment.
- Reject malformed or unsupported versions.
- Document the collision risk of an eight-byte hash and add a startup collision check when building the peer registry.

The current use of manufacturer ID `0xFFFF` should be reviewed before production. Prefer a properly assigned company identifier, a documented service-data frame under a 128-bit service UUID, or another standards-compliant encoding. Do not silently claim another vendor's company identifier.

## Peer Registry

The native service cannot query the full users collection on each scan result.

At startup or configuration refresh, Flutter should:

1. read the current user's active enrollment and allowed geolocation regions;
2. query eligible participant UIDs;
3. hash each UID using the package's canonical hash function;
4. detect hash collisions;
5. call `syncPeers` with the complete versioned registry.

Persist:

- peer UID;
- participant hash;
- registry version;
- region/study scope if needed;
- enabled state; and
- refresh timestamp.

`syncPeers` should write a new registry transactionally and then activate it. A failed refresh must leave the previous valid registry usable.

Define a refresh policy:

- at sign-in/proximity start;
- whenever enrollment or region assignment changes;
- on app foreground if the registry is older than a configurable TTL;
- after remote-config refresh; and
- optionally once per 24 hours.

## Foreground Service Lifecycle

Create `ProximityForegroundService`.

It must:

- call `startForeground()` immediately within Android's allowed startup window;
- declare the appropriate foreground-service type and permissions for the target SDK;
- create a dedicated, low-disruption notification channel;
- start scanning and advertising only after Bluetooth permission and adapter checks;
- recover persisted config and peer data in `onCreate`;
- handle repeated start commands safely;
- use `START_STICKY` only if restart behavior has been tested across target Android versions;
- stop itself when policy says BLE should be inactive; and
- release scan callbacks, advertisers, wake locks, executors, and database handles in `onDestroy`.

Notification content should clearly describe research sensing without exposing participant identifiers. Suggested default:

```text
Title: SPARRC proximity active
Text: Detecting nearby study participants
```

For zone-gated operation, the notification exists only while scanning/advertising is active.

## Activation Modes

Add `activation_mode` to `appConfig/btRuntime`:

- `disabled`: never run BLE.
- `always`: run after successful signed-in configuration regardless of geofence state.
- `near_or_inside`: run in `near` and `inside`; stop in `outside`.
- `inside_only`: run only in `inside`.

Persist the last zone mode:

- `outside`;
- `near`; or
- `inside`.

The service controller maps activation and zone modes to service state:

| Activation mode | Outside | Near | Inside |
| --- | --- | --- | --- |
| disabled | off | off | off |
| always | active | active | active |
| near_or_inside | off | active | active |
| inside_only | off | off | active |

When multiple geofences overlap, maintain a set of active inner and near fence IDs. Do not reduce state to one last event. Compute:

- `inside` if any inner fence is active;
- otherwise `near` if any near fence is active;
- otherwise `outside`.

Persist this set so out-of-order or duplicated geofence events do not incorrectly stop BLE.

## Geofence Integration

### Foreground Flutter Path

Update `BtBootstrap` to listen to `GeoBootstrap.instance.onZoneChange` and call the native `setZoneMode`.

### Android Headless Path

Update `geoFbgHeadlessTask` to call the static native facade after every relevant geofence event:

- `_near ENTER` -> add near fence and recompute mode;
- inner `ENTER`/`DWELL` -> add inner fence and recompute mode;
- inner `EXIT` -> remove inner fence and recompute mode;
- `_near EXIT` -> remove near fence and recompute mode.

The headless callback must not instantiate `BtBootstrap`, rebuild the peer registry, or perform the continuous scan itself.

### Native Safety Net

Because headless Dart startup can fail, the implementation should evaluate whether the geolocation package can forward geofence events directly to the proximity plugin's Android receiver/service. If direct native integration is feasible, prefer it. If not, persist the most recently commanded mode and use `always` for initial field validation before relying on zone gating.

Document the residual risk if mode transitions depend exclusively on a fresh headless Dart isolate.

## BLE Scanning

Use filtered Android BLE scans:

- filter on the SPARRC service UUID;
- parse only the expected versioned participant frame;
- ignore unknown hashes;
- ignore the observer's own hash;
- avoid GATT connections;
- avoid MAC-address identity;
- handle duplicate advertisements explicitly.

For a continuously running foreground service, choose one of two scan strategies after device testing:

1. **Continuous low-latency/balanced scan**
   - simplest and best detection;
   - highest battery use.
2. **Native duty-cycled scan**
   - service schedules start/stop using a native executor/alarm;
   - lower battery use;
   - may miss short encounters.

Do not use Dart timers.

Recommended initial Android field-test values:

| Mode | Scan window | Scan interval | Duty cycle |
| --- | ---: | ---: | ---: |
| always/outside test | 5 s | 15 s | 33% |
| near | 5 s | 15 s | 33% |
| inside | 5 s | 10 s | 50% |

After collecting battery and detection data, consider:

- near: 5 seconds every 20 seconds;
- inside: 5 seconds every 10 seconds;
- continuous scanning only for short validation sessions.

Validate behavior on Samsung, Motorola, Pixel, and at least one aggressively managed OEM device.

## BLE Advertising

Advertise whenever scanning is active so detection is symmetric.

Recommended initial settings:

- balanced advertising mode;
- medium transmit power;
- non-connectable advertisement;
- 500-1000 ms advertising interval if the API/device permits;
- fixed SPARRC service UUID;
- versioned participant identity frame.

If Android APIs do not expose the exact interval through the chosen abstraction, record the actual platform setting used.

Handle:

- no advertiser support;
- Bluetooth disabled;
- permission revoked;
- too many advertisers;
- data-too-large failures; and
- adapter restarts.

The service should retry with bounded backoff and surface durable diagnostics rather than crash.

## RSSI Processing and Encounter Logic

Raw RSSI is noisy. Store enough information to permit later scientific reprocessing.

For online gating:

- maintain a per-peer rolling median or trimmed mean rather than a simple mean;
- require at least three observations;
- apply an entry threshold and a weaker exit threshold;
- expire stale buffers;
- rate-limit writes per peer;
- store raw or summary sample counts.

Recommended initial values:

- rolling window: 5 observations;
- minimum samples: 3;
- entry threshold: `-80 dBm`;
- exit threshold: `-85 dBm`;
- peer-lost timeout: 30-60 seconds;
- write interval inside: 30-60 seconds;
- write interval near/outside test: 60-180 seconds.

These values are design starting points, not physical distance guarantees. Calibrate with the actual phone mix, body placement, and environment.

Do not treat `estimated_m` as a precise distance. Keep it for convenience only and retain:

- smoothed RSSI;
- minimum/maximum RSSI;
- sample count;
- window duration;
- observer device model if permitted;
- advertisement protocol version; and
- configured TX-power assumption.

## Event Model and Deduplication

Continue writing to `proximity_events`, but version and clarify the schema.

Suggested device event:

```js
{
  schema_version: 2,
  observer_uid: "...",
  target_type: "participant_device",
  peer_uid: "...",
  observed_at: <server timestamp>,
  observed_at_device_iso: "...",
  rssi: -67,
  rssi_min: -73,
  rssi_max: -63,
  sample_count: 5,
  estimated_m: 2.4,
  zone_id: "...",
  zone_mode: "inside",
  source: "android_native",
  protocol_version: 1,
  app_version: "...",
  queued_at_device_iso: "...",
  uploaded_at: <server timestamp>
}
```

Use directional observations: the document records that `observer_uid` saw `peer_uid`. Do not assume both phones will detect each other in the same window.

Use a deterministic document ID:

```text
observerUid_peerUid_timeBucket
```

Do not sort the pair unless the intended analysis explicitly wants one merged bidirectional record. Sorting currently risks one device overwriting the other device's materially different RSSI observation.

## Native Persistence

Persist the following across process death:

- enabled/configured state;
- signed-in UID hash and upload UID;
- activation mode;
- active zone sets and derived mode;
- service UUID and frame version;
- peer registry;
- current scan/advertise policy;
- per-peer last-write timestamp;
- recent RSSI window if useful;
- queued events;
- upload attempt count and last error;
- config and schema versions.

Use a local event state machine:

- `pending`;
- `uploading`;
- `uploaded`; or
- `dead_letter`.

Mark an event uploaded only after Firestore confirms success. Recover rows left in `uploading` after process death.

Bound storage by:

- deleting acknowledged rows after a retention period;
- limiting total rows/bytes;
- compacting repeated observations if offline for a long period; and
- never deleting newest pending data merely because an old retry is failing.

## Native Firestore Writes

Preferred implementation:

- include Firebase Firestore Android SDK in the plugin;
- use the existing app's Firebase initialization;
- authenticate as the signed-in Firebase user;
- write deterministic documents directly;
- use server timestamps for upload time;
- retain device observation time separately.

Important authentication decision:

- verify that Firebase Auth state is available to the native Android process/service after swipe-away;
- if the auth user is unavailable, queue locally and retry after auth restoration;
- never store a reusable Firebase credential in plain preferences.

Firestore security rules must allow the signed-in observer to create only valid events where `observer_uid == request.auth.uid`.

If direct native Firestore integration proves brittle, use an authenticated HTTPS ingestion endpoint. The local queue and service design remain the same; only `ProximityUploader` changes.

## Retry and Connectivity

- Attempt upload immediately after accepting an event.
- Batch queued writes when connectivity returns.
- Use exponential backoff with jitter.
- Register WorkManager with a network constraint.
- Trigger a flush on app foreground and after successful configuration.
- Distinguish retryable errors from permanent validation/auth errors.
- Move permanently invalid rows to `dead_letter` with diagnostics.

Avoid an unbounded retry loop inside the foreground service.

## Android Manifest and Build Changes

The plugin manifest should contribute or document:

- `BLUETOOTH_SCAN`;
- `BLUETOOTH_ADVERTISE`;
- `BLUETOOTH_CONNECT`;
- legacy Bluetooth/location permissions for supported pre-Android-12 versions;
- `FOREGROUND_SERVICE`;
- the target-SDK-required foreground-service permission/type;
- `POST_NOTIFICATIONS`;
- `RECEIVE_BOOT_COMPLETED` if boot restoration is enabled;
- the foreground service declaration;
- boot/package-replaced receiver if used; and
- WorkManager integration.

Verify the exact foreground-service type against the app's target SDK and Android's current BLE guidance during implementation.

Add ProGuard/R8 consumer rules only if Firebase/Room/plugin reflection requires them.

## Permission UX

FlutterFlow must request and explain:

- Nearby devices/Bluetooth scan;
- Bluetooth advertise/connect where surfaced by Android;
- notification permission on Android 13+; and
- any location permission still required by the app's geofence system.

If notification permission is denied, test whether the foreground service remains compliant and how Android surfaces it. Do not silently claim that background sensing is working when required capabilities are unavailable.

Add a status check that can report:

- Bluetooth off;
- permission missing;
- notification permission missing;
- service stopped;
- advertising unsupported;
- scan failure;
- queue backlog; and
- stale peer registry.

## Package Code Changes

### `pubspec.yaml`

- Add Flutter plugin metadata for Android.
- Add platform-interface dependencies only if needed.
- Keep current Dart dependencies for iOS until migration.
- Document native Firebase/Room Android dependencies in Gradle.

### `lib/bt_api.dart`

- Add `ProximityActivationMode` and `ProximityZoneMode`.
- Add zone-specific scan/advertise cadence fields.
- Add notification config.
- Add schema/frame version.
- Add upload and retry config.
- Add `ProximityNativeStatus`.
- Validate ranges and relationships such as duration <= interval.
- Update merge semantics for activation modes and zone-specific rates.

### `lib/bt_engine.dart`

- Keep as the iOS/Dart implementation.
- On Android, delegate lifecycle to the native platform facade or clearly deprecate direct use.
- Prevent simultaneous Dart and native Android scanning/writing.

### `lib/bt_writers.dart`

- Update schema to distinguish observer and target.
- Align deterministic IDs with directional events.
- Add schema version and native source compatibility.
- Keep it for iOS and tests.

### New Dart files

- `lib/src/proximity_platform.dart`;
- `lib/src/proximity_method_channel.dart`;
- `lib/src/proximity_models.dart`; and
- test fakes.

### Tests

- frame encode/decode;
- UID hash compatibility between Dart and Kotlin;
- config serialization;
- activation-mode matrix;
- document ID parity;
- malformed frame rejection;
- hash collision handling; and
- Android platform-channel contract.

## FlutterFlow.io Changes

Persistent changes should be made through FlutterFlow custom code and configuration, not by editing generated output.

### Package dependency

- Point `zbg_proximity` to the implementation branch during development.
- Pin to a tested commit before production.
- Refresh generated code and verify Android manifest merging.

### Custom file: `bt_bootstrap.dart`

Replace Android use of the in-memory `BtEngine` with orchestration that:

1. reads and merges `appConfig/btRuntime`;
2. verifies the authenticated UID;
3. loads eligible peer UIDs;
4. builds and collision-checks the peer registry;
5. calls native `configure`;
6. calls `syncPeers`;
7. subscribes to geofence mode changes;
8. starts according to activation mode;
9. triggers a queue flush; and
10. exposes status for diagnostics.

Keep the existing Dart path for iOS until separately migrated.

### Custom action: `btStart`

- Continue accepting the authenticated UID.
- Call the revised bootstrap.
- Return a structured success/status result or throw a useful error.
- Ensure it runs only after Firebase auth and geo startup are ready.

### Custom action: `btStop`

- Accept whether this is a temporary pause or sign-out.
- On sign-out/enrollment end, use `clearIdentity: true`.
- Do not clear native pending events before deciding the retention/privacy policy.

### New custom actions

Add:

- `btGetStatus`;
- `btRefreshConfig`;
- `btRefreshPeers`;
- `btFlushPendingEvents`;
- optionally `btWriteDiagnosticsSnapshot`.

### `geo_fcm_handler.dart`

- Forward inner and near geofence transitions to the native proximity facade.
- Preserve fresh-isolate compatibility.
- Do not call `BtBootstrap.instance`.
- Log success/failure without blocking geolocation handling indefinitely.

### App startup and sign-in flow

Order:

1. Firebase initialized;
2. user authenticated;
3. runtime config loaded;
4. geolocation system configured;
5. proximity configured and peers synced;
6. native service started if policy requires.

### App sign-out/enrollment-end flow

Call `btStop(clearIdentity: true)` before or as part of auth teardown so native work cannot continue under stale identity.

### FlutterFlow settings

- Add required Android permissions.
- Add user-facing permission descriptions.
- Ensure Android minimum/target SDK compatibility.
- Ensure notification channel behavior is acceptable.
- Add the package branch/commit.
- Verify custom files are included in the project.

## Firestore Configuration

Suggested baseline:

```js
appConfig/btRuntime = {
  schema_version: 2,
  enabled: true,
  activation_mode: "near_or_inside",
  advertise_service_uuid: "...",
  frame_version: 1,

  scan_interval_outside_s: 15,
  scan_duration_outside_s: 5,
  scan_interval_near_s: 15,
  scan_duration_near_s: 5,
  scan_interval_inside_s: 10,
  scan_duration_inside_s: 5,

  rolling_rssi_samples: 5,
  min_rssi_samples: 3,
  rssi_enter_threshold_dbm: -80,
  rssi_exit_threshold_dbm: -85,
  peer_lost_timeout_s: 45,

  write_rate_outside_s: 120,
  write_rate_near_s: 60,
  write_rate_inside_s: 30,

  foreground_notification_title: "SPARRC proximity active",
  foreground_notification_text: "Detecting nearby study participants",

  peer_registry_ttl_s: 86400,
  max_pending_events: 10000
}
```

For swipe-away testing outside all geofences:

```js
activation_mode: "always"
```

Production should normally use `near_or_inside` if that matches the approved study and battery/privacy requirements.

## Diagnostics

Record structured native diagnostics:

- service start/stop reason;
- app/process start reason;
- activation and zone mode;
- scan start/stop/failure;
- advertise start/stop/failure;
- Bluetooth adapter state;
- permission state;
- peer registry count/version;
- recognized/unknown/self advertisement counts;
- RSSI gate acceptance/rejection counts;
- queue depth;
- upload success/failure;
- last successful observation and upload; and
- boot restoration result.

Do not log raw participant UIDs or full advertisement payloads in production logs.

Expose a bounded diagnostics export for field troubleshooting.

## Testing Plan

### Unit tests

- Dart/Kotlin hash parity.
- Advertisement frame parsing.
- Activation-mode decisions.
- RSSI smoothing and hysteresis.
- Rate limiting and deterministic IDs.
- queue state transitions.
- config migrations.

### Android integration tests

- configure/start/stop idempotence;
- service lifecycle;
- database recovery;
- WorkManager retry;
- auth unavailable then restored;
- Bluetooth off/on;
- permission revoked/restored;
- peer registry atomic replacement.

### Two-device field matrix

Test:

- both apps foreground;
- observer foreground, peer background;
- both background;
- observer swiped away;
- peer swiped away;
- both swiped away;
- screen off;
- network offline then online;
- Bluetooth toggled;
- notification permission denied;
- app upgraded;
- device rebooted;
- force-stop from Settings;
- OEM battery optimization enabled/disabled.

### Zone tests

- outside -> near -> inside -> near -> outside;
- overlapping zones;
- duplicate ENTER/DWELL;
- missing or delayed EXIT;
- swipe-away before transition;
- reboot while inside;
- config changed from `always` to `near_or_inside`.

### Acceptance criteria

- BLE notification remains after Recents swipe when mode is active.
- Two physical Android devices continue producing directional observations after swipe-away.
- Offline observations appear after connectivity returns.
- No duplicate service or scan loops occur.
- Explicit sign-out stops BLE and prevents later writes.
- Reboot restoration follows persisted policy.
- Battery impact is measured and documented for at least 8-12 hours.

## Rollout

1. Implement native plugin and tests on a feature branch.
2. Use `activation_mode: "always"` with internal test accounts.
3. Validate two-device foreground behavior against the old Dart path.
4. Validate background and swipe-away behavior.
5. Validate offline queue and reboot.
6. Measure battery and thermal impact.
7. Enable zone-gated mode.
8. Pilot on a small device cohort.
9. Pin the package commit in FlutterFlow.
10. Expand rollout only after diagnostics show stable scanning and uploads.

Include a Firestore kill switch (`enabled: false`) and ensure the app refreshes it frequently enough to stop sensing promptly.

## Known Limits

- Android Force stop prevents automatic restart until the app is opened again.
- Users may stop foreground services from system UI.
- OEM battery managers can interfere.
- RSSI is not exact distance.
- Directional detections may be asymmetric.
- A headless Dart-only geofence bridge remains a reliability risk unless replaced by direct native forwarding.
- This plan does not promise equivalent terminated-state behavior on iOS.


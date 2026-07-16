# zbg_proximity Fixed BLE Beacon Integration Plan

## Purpose

Extend `zbg_proximity` so participant phones can detect fixed Bluetooth Low Energy beacons and write beacon-proximity observations to Firestore alongside participant-device observations.

The beacon does not need internet access, a Firebase identity, or a connection to the phone. It periodically broadcasts a stable identifier. The participant's phone detects the advertisement, applies signal and rate gates, and uploads an observation.

This plan builds on the native Android service described in `ZBG_PROXIMITY_ANDROID_BACKGROUND_IMPLEMENTATION_PLAN.md`.

## Goals

- Detect configured fixed beacons in foreground, background, and Android swipe-away states.
- Use the same native scan service and durable upload queue as device-to-device sensing.
- Distinguish beacon observations from participant-device observations.
- Support meaningful beacon metadata such as room, site, and placement.
- Keep the deployment vendor-independent.
- Preserve raw signal data for research analysis.
- Allow future iOS detection using the same physical beacon fleet.

## Non-Goals

- Centimeter-level indoor positioning.
- Reliable exact distance from RSSI.
- Connecting to beacons over GATT during normal sensing.
- Using beacon MAC addresses as durable identity.
- Depending on a beacon vendor's cloud.
- Supporting every proprietary beacon format.

## Recommended Beacon Protocol

Use configurable **iBeacon-compatible** advertisements as the required baseline.

Reasons:

- supported by many commercial beacon vendors;
- readable from Android BLE advertisement data;
- natively recognized by Apple's Core Location beacon APIs;
- provides a clear identifier hierarchy: UUID, major, and minor;
- includes calibrated transmit power for rough ranging; and
- does not require a GATT connection.

Recommended identity assignment:

```text
proximity UUID = one UUID for the SPARRC deployment or study
major          = site/building/region number
minor          = unique beacon number within that major value
```

Every physical beacon must have a unique UUID/major/minor combination within the deployment.

Eddystone-UID or a custom service-data frame could be added later through a protocol parser interface, but initial production scope should stay with iBeacon to reduce hardware and software variability.

## Hardware Purchasing Requirements

The beacon type matters. Purchase BLE beacons that provide:

- configurable iBeacon mode;
- configurable proximity UUID, major, and minor;
- configurable advertising interval;
- configurable transmit power;
- calibrated/measured power metadata;
- password-protected or physically controlled configuration;
- replaceable battery, USB power, or another suitable power design;
- documented configuration process;
- stable broadcasting without a mandatory vendor cloud;
- exportable inventory/configuration records;
- environmental rating appropriate to the installation;
- expected battery-life information at chosen settings; and
- a way to restore or reprovision a replaced unit.

Prefer hardware that can broadcast iBeacon and Eddystone concurrently only if this does not reduce stability or battery life. The first deployment should broadcast one required frame format.

Avoid beacons that:

- expose only a proprietary encrypted format;
- rotate identifiers without allowing rotation to be disabled or integrated;
- identify themselves only by MAC address;
- require continuous vendor-cloud access;
- cannot assign unique IDs;
- hide transmit-power or interval settings;
- are Apple Find My or Google tracker-network accessories rather than general BLE beacons; or
- cannot be locked against unauthorized reconfiguration.

Before bulk purchase, obtain a small evaluation set from at least two candidate vendors and test them with target Android and iPhone models.

## Beacon Inventory Model

Create a Firestore collection such as `proximity_beacons`.

Suggested document:

```js
proximity_beacons/{beaconId} = {
  schema_version: 1,
  enabled: true,
  protocol: "ibeacon",

  proximity_uuid: "...",
  major: 3,
  minor: 12,

  label: "Activity room northeast",
  site_id: "site_003",
  region_id: "region_003",
  zone_id: "activity_room",

  placement_description: "North wall, 2.2 m above floor",
  installed_at: <timestamp>,
  retired_at: null,

  expected_tx_power_dbm: -59,
  configured_advertising_interval_ms: 750,
  configured_transmit_power: "medium",

  config_version: 4,
  notes: "..."
}
```

Use an application-level `beaconId` that survives hardware replacement. If a unit is replaced, either:

- program the replacement with the same iBeacon identity and update hardware metadata; or
- create a new identity and preserve an installation-history mapping.

Do not place participant or sensitive study data in beacon advertisements.

## Native Configuration

Extend the Android native `configure` or add `syncBeacons`.

Suggested Dart model:

```dart
class ProximityBeaconDefinition {
  final String beaconId;
  final BeaconProtocol protocol;
  final String proximityUuid;
  final int major;
  final int minor;
  final String? siteId;
  final String? regionId;
  final String? zoneId;
  final bool enabled;
  final int? expectedTxPowerDbm;
}
```

`syncBeacons` must:

- validate identifiers and ranges;
- reject duplicate protocol identities;
- transactionally replace/version the native beacon registry;
- persist it across process death;
- retain the last valid registry if refresh fails; and
- report registry version and count through native status.

Flutter should refresh beacon definitions:

- when proximity starts;
- when active study/region assignment changes;
- when app config is refreshed;
- on app foreground if stale; and
- periodically, such as once per 24 hours.

Only sync beacons relevant to the participant's active studies/regions when possible.

## Scan Architecture

Use the same `BluetoothLeScanner` session that scans for participant devices.

The scanner should route each advertisement through protocol parsers:

```text
Scan result
  -> participant frame parser
  -> iBeacon parser
  -> future Eddystone/custom parsers
```

Each parser returns either:

- no match;
- a recognized configured target; or
- a valid but unknown target for bounded diagnostics.

Do not start a separate continuous BLE scan for beacons. Multiple scan owners increase battery use and create lifecycle conflicts.

## iBeacon Parsing

Parse iBeacon manufacturer data and extract:

- proximity UUID;
- major;
- minor;
- measured power/TX calibration byte; and
- received RSSI from the Android scan result.

Match the tuple `(UUID, major, minor)` against the persisted beacon registry.

Reject:

- malformed frames;
- unsupported length/version;
- disabled beacons;
- unknown beacon identities unless diagnostic sampling is enabled.

The parser must have byte-level unit tests using known frames and malformed cases.

## Scan Filtering

Android scan filters may not be equally reliable for every manufacturer-data pattern and device implementation. Use the broadest filter that still avoids scanning the entire BLE environment:

- include the SPARRC participant service UUID filter;
- add an iBeacon manufacturer-data prefix filter if verified on target devices; or
- use a broader scan and perform strict in-process frame parsing when necessary.

Benchmark whether multiple filters reduce delivery or increase scan failures on common Android devices.

Do not filter by beacon MAC address.

## Observation Processing

Maintain independent state per beacon:

- rolling RSSI window;
- minimum/maximum RSSI;
- sample count;
- first/last seen time;
- last accepted write;
- current proximity band;
- last configured TX power;
- stale/lost timeout.

Recommended initial values:

- minimum observations: 3;
- rolling window: 5-7 samples;
- beacon-lost timeout: 30-60 seconds;
- write interval: 30-60 seconds inside an active sensing area;
- health/last-seen write interval: 15-60 minutes;
- entry and exit RSSI thresholds with 5 dB hysteresis.

Use a rolling median or trimmed mean. Beacon RSSI is affected by:

- walls and furniture;
- human bodies;
- phone orientation and pocket/bag placement;
- installation height;
- beacon casing;
- beacon transmit power;
- phone radio variation; and
- reflective indoor environments.

Store raw summary data and treat distance estimates as approximate.

## Proximity Bands

If the application needs a simple classification, use calibrated bands:

- `immediate`;
- `near`;
- `present`;
- `weak`;
- `lost`.

Do not rely on a universal threshold across every site and phone model. Store site/beacon-specific overrides if field calibration demonstrates a need.

Example configuration:

```js
{
  immediate_enter_dbm: -55,
  near_enter_dbm: -70,
  present_enter_dbm: -82,
  exit_hysteresis_db: 5,
  lost_timeout_s: 45
}
```

These are starting values only.

## Firestore Event Schema

Use the same `proximity_events` collection if downstream analysis benefits from one normalized stream.

Suggested beacon event:

```js
{
  schema_version: 2,
  observer_uid: "...",
  target_type: "fixed_beacon",
  target_id: "beacon_room_12",

  beacon_protocol: "ibeacon",
  beacon_uuid: "...",
  beacon_major: 3,
  beacon_minor: 12,

  observed_at: <server timestamp>,
  observed_at_device_iso: "...",

  rssi: -67,
  rssi_min: -73,
  rssi_max: -63,
  sample_count: 5,
  advertised_tx_power_dbm: -59,
  estimated_m: 2.4,
  proximity_band: "near",

  site_id: "site_003",
  region_id: "region_003",
  zone_id: "activity_room",
  phone_zone_mode: "inside",

  source: "android_native",
  queued_at_device_iso: "...",
  uploaded_at: <server timestamp>
}
```

Use a deterministic directional document ID:

```text
observerUid_beaconId_timeBucket
```

Beacon observations must never populate `peer_uid`; use `target_id` and `target_type` so participant-device and beacon records remain unambiguous.

## Native Queue and Upload

Beacon events use the same durable queue and uploader as participant-device events.

The local row should include:

- target type;
- beacon ID and protocol identity;
- observation timestamps;
- RSSI summary;
- metadata snapshot/version;
- upload state and attempts.

If the beacon registry changes while an event is queued, preserve the metadata used at observation time or retain the registry version so historical interpretation remains possible.

Firestore rules should require:

- authenticated observer;
- `observer_uid == request.auth.uid`;
- valid `target_type`;
- bounded field sizes and numeric ranges; and
- no client ability to redefine authoritative beacon installation metadata.

Consider having the server enrich `beaconId` with authoritative metadata rather than trusting all site fields from the phone.

## FlutterFlow.io Changes

### `bt_bootstrap.dart`

Extend startup to:

1. read participant proximity config;
2. query active beacon definitions for the user's studies/regions;
3. convert them to `ProximityBeaconDefinition`;
4. call native `syncBeacons`;
5. then start or reconfigure the native service.

Beacon-registry failure should be visible in status, but the design must decide whether participant-device scanning can continue independently. Recommended behavior: continue participant scanning while disabling beacon event writes until a valid beacon registry exists.

### New custom actions

Add:

- `btRefreshBeacons`;
- `btGetBeaconStatus`;
- optional `btExportUnknownBeaconDiagnostics`.

### Admin/configuration UI

If beacon management is done in FlutterFlow, provide an admin-only workflow to:

- create/import beacon records;
- assign site/zone/label;
- enable/disable/retire a beacon;
- record installation and replacement;
- check last observed time;
- flag low battery when telemetry is available; and
- export inventory.

Do not allow ordinary participants to enumerate the full beacon inventory unless required.

## iOS Integration

The same iBeacon hardware can be detected on iOS.

Recommended iOS architecture:

- use Core Location `CLBeaconRegion` monitoring for presence/wake behavior;
- use beacon ranging while permitted for RSSI updates;
- configure required location authorization and background modes;
- map UUID/major/minor to the same Firestore beacon IDs.

Expect different observation cadence and reliability from Android:

- foreground ranging can be frequent;
- background monitoring/ranging is system-controlled;
- user force-quit can suppress relaunch behavior;
- terminated-state continuous RSSI sampling should not be promised.

The cross-platform data model should include platform/source fields so analysis can account for this asymmetry.

## Beacon Health and Operations

Because beacons are unattended infrastructure, add operational monitoring.

Track:

- `last_seen_at` per beacon;
- number of unique observing phones over a period;
- rolling RSSI distribution;
- expected versus observed site;
- firmware/config version if available;
- battery telemetry if the hardware supports a separate frame;
- prolonged absence; and
- duplicate identity detection.

Use a scheduled backend process to flag:

- never seen after installation;
- not seen for a configurable interval;
- same identity observed in incompatible sites;
- sudden RSSI distribution shifts suggesting movement;
- probable low battery; or
- accidental duplicate programming.

Do not write a Firestore health document on every advertisement. Aggregate/rate-limit health updates.

## Security and Privacy

- Beacon IDs should identify places/infrastructure, not people.
- Do not embed Firebase IDs, participant IDs, study secrets, or precise descriptive metadata in the broadcast.
- Assume anyone nearby can receive the beacon frame.
- Lock configuration with a password and manage credentials securely.
- Change vendor default passwords.
- Keep an inventory of physical placement and responsible staff.
- Include beacon sensing in consent/privacy documentation where required.
- Define retention for beacon proximity data.

If spoofing matters to the study, recognize that ordinary iBeacon frames are copyable. Options include:

- accepting spoofing risk and detecting anomalies;
- using rotating authenticated frames supported by selected hardware; or
- adding server-side plausibility checks.

Rotating frames increase implementation complexity and may reduce iOS interoperability, so they should be a separate design decision.

## Calibration Procedure

Before deployment:

1. choose advertising interval and transmit power;
2. mount the beacon in its intended orientation and height;
3. test with representative Android and iPhone models;
4. measure RSSI at known positions and with realistic body placement;
5. repeat with room occupancy and doors open/closed;
6. determine useful proximity bands;
7. record beacon-specific calibration metadata;
8. test adjacent-room bleed-through; and
9. test battery consumption over several days.

Calibration should optimize classification for the research question, not attempt to produce falsely precise meter estimates.

## Suggested Hardware Settings

Initial evaluation settings:

- iBeacon mode;
- advertising interval: 500-1000 ms;
- transmit power: low or medium;
- non-connectable advertising where supported;
- unique UUID/major/minor;
- configuration lock enabled.

Faster advertising improves detection and uses more battery. Higher transmit power increases range and adjacent-room bleed. Final settings should be chosen after site testing.

## Testing

### Parser tests

- known iBeacon frames;
- every major/minor boundary;
- negative measured-power byte;
- malformed lengths;
- unrelated manufacturer data;
- duplicate identities;
- disabled and unknown beacons.

### Field tests

- one beacon and one phone;
- several beacons in one room;
- adjacent rooms;
- overlapping signal areas;
- beacon moved or rotated;
- phone foreground/background/swiped away;
- screen off;
- offline/online;
- Android reboot;
- Bluetooth toggled;
- mixed participant-device and beacon advertisements;
- high-density BLE environment.

### Cross-platform tests

- same beacon detected by Android and iOS;
- identifier maps to the same `beaconId`;
- compare RSSI distributions and cadence by platform;
- verify iOS force-quit behavior is documented.

### Acceptance criteria

- Configured beacons are uniquely recognized without MAC addresses.
- Android records continue after swipe-away while the proximity service is active.
- Participant and beacon records cannot be confused.
- Offline events upload after connectivity returns.
- Unknown beacons do not produce production proximity events.
- Beacon fleet can be replaced or reconfigured without an app release.
- Battery life and adjacent-room detection are measured before scale deployment.

## Rollout

1. Purchase a small evaluation batch.
2. Implement iBeacon parser and registry behind a feature flag.
3. Bench-test frame parsing and identity stability.
4. Install 2-4 beacons in one controlled area.
5. Collect raw RSSI and battery data.
6. Tune thresholds, interval, transmit power, and write cadence.
7. Validate Android swipe-away operation.
8. Validate iOS behavior separately.
9. Add health monitoring.
10. Expand to additional sites with a documented provisioning checklist.

Recommended feature flags:

```js
beacons_enabled: false
beacon_protocols: ["ibeacon"]
unknown_beacon_diagnostics_enabled: false
```

## Provisioning Checklist

For every beacon:

- assign application `beaconId`;
- program UUID/major/minor;
- set interval and transmit power;
- change configuration password;
- label the physical device;
- record serial number and battery type;
- photograph/document placement;
- create Firestore inventory record;
- verify detection from representative phones;
- verify no duplicate identity exists;
- record installation date; and
- schedule battery/placement inspection.

## Known Limits

- RSSI does not provide exact distance.
- Signals cross walls and are blocked by bodies.
- Different phones report different RSSI.
- iOS background cadence differs from Android.
- iBeacon identities can be spoofed unless a more advanced authenticated frame is used.
- Beacon batteries and physical placement require ongoing operations.


package app.zbg.proximity

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Android platform-channel entry point for zbg_proximity. */
class ZbgProximityPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: android.content.Context
    private lateinit var stateStore: ProximityStateStore

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        stateStore = ProximityStateStore(applicationContext)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> configure(call, result)
            "syncPeers" -> syncPeers(call, result)
            "startAlways" -> startAlways(result)
            "getStatus" -> getStatus(result)
            "getNearbyPeers" -> getNearbyPeers(result)
            "stop" -> stop(result)
            else -> result.notImplemented()
        }
    }

    private fun configure(call: MethodCall, result: MethodChannel.Result) {
        val uid = call.argument<String>("uid")
        val serviceUuid = call.argument<String>("advertiseServiceUuid")
        val requestedActivationMode = call.argument<String>("activationMode")

        if (uid.isNullOrBlank() || serviceUuid.isNullOrBlank() ||
            requestedActivationMode.isNullOrBlank()
        ) {
            result.error(
                "invalid_config",
                "uid, advertiseServiceUuid, and activationMode are required",
                null,
            )
            return
        }

        try {
            java.util.UUID.fromString(serviceUuid)
        } catch (_: IllegalArgumentException) {
            result.error("invalid_config", "advertiseServiceUuid must be a valid UUID", null)
            return
        }

        // Persist only the derived self hash, never the raw local UID.
        stateStore.saveConfiguration(uid, serviceUuid, requestedActivationMode)
        result.success(null)
    }

    private fun syncPeers(call: MethodCall, result: MethodChannel.Result) {
        if (!stateStore.isConfigured()) {
            result.error("not_configured", "Call configure before syncPeers", null)
            return
        }
        val peers = call.argument<List<String>>("peerUids")
        if (peers == null) {
            result.error("invalid_peers", "peerUids is required", null)
            return
        }
        try {
            val count = PeerRegistry(applicationContext).replace(
                peers,
                stateStore.selfHashHex() ?: "",
            )
            result.success(count)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_peers", error.message, null)
        }
    }

    private fun startAlways(result: MethodChannel.Result) {
        if (!stateStore.isConfigured()) {
            result.error(
                "not_configured",
                "Call configure before startAlways",
                null,
            )
            return
        }

        try {
            ProximityServiceController.start(applicationContext)
            result.success(null)
        } catch (error: SecurityException) {
            result.error(
                "foreground_service_not_allowed",
                error.message,
                null,
            )
        } catch (error: RuntimeException) {
            result.error(
                "foreground_service_start_failed",
                error.message,
                null,
            )
        }
    }

    private fun getStatus(result: MethodChannel.Result) {
        val peers = NearbyPeerStore(applicationContext).snapshots()
        val lastPeer = peers.firstOrNull()
        result.success(
            mapOf(
                "platform" to "android",
                "configured" to stateStore.isConfigured(),
                "running" to stateStore.isRunning(),
                "activationMode" to stateStore.activationMode(),
                "advertising" to stateStore.isAdvertising(),
                "advertisingState" to stateStore.advertisingState(),
                "scanning" to stateStore.isScanning(),
                "scanningState" to stateStore.scanningState(),
                "knownPeerCount" to PeerRegistry(applicationContext).count(),
                "nearbyPeerCount" to peers.count { it.nearby },
                "lastDetectedPeerUid" to lastPeer?.uid,
                "lastDetectedRssi" to lastPeer?.rssi,
                "lastDetectedAtMs" to lastPeer?.lastSeenAtMs,
                "lastBleError" to stateStore.lastBleError(),
                "scanCallbackCount" to stateStore.scanCallbackCount(),
                "validFrameCount" to stateStore.validFrameCount(),
                "recognizedPeerCount" to stateStore.recognizedPeerCount(),
            ),
        )
    }

    private fun getNearbyPeers(result: MethodChannel.Result) {
        result.success(
            NearbyPeerStore(applicationContext).snapshots().map { it.toMap() },
        )
    }

    private fun stop(result: MethodChannel.Result) {
        ProximityServiceController.stop(applicationContext)
        stateStore.clear()
        PeerRegistry(applicationContext).clear()
        NearbyPeerStore(applicationContext).clear()
        result.success(null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val CHANNEL_NAME = "app.zbg.proximity/methods"
    }
}

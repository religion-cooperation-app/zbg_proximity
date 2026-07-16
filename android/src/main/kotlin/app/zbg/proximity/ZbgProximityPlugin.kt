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
            "startAlways" -> startAlways(result)
            "getStatus" -> getStatus(result)
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

        // The UID is validated but intentionally not persisted in this
        // lifecycle-only milestone. Identity storage is added later with an
        // encrypted-at-rest design.
        stateStore.saveConfiguration(serviceUuid, requestedActivationMode)
        result.success(null)
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
        result.success(
            mapOf(
                "platform" to "android",
                "configured" to stateStore.isConfigured(),
                "running" to stateStore.isRunning(),
                "activationMode" to stateStore.activationMode(),
            ),
        )
    }

    private fun stop(result: MethodChannel.Result) {
        ProximityServiceController.stop(applicationContext)
        stateStore.clear()
        result.success(null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val CHANNEL_NAME = "app.zbg.proximity/methods"
    }
}

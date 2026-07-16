package app.zbg.proximity

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Minimal Android platform-channel scaffold for zbg_proximity. */
class ZbgProximityPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var configured = false
    private var activationMode: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> configure(call, result)
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

        configured = true
        activationMode = requestedActivationMode
        result.success(null)
    }

    private fun getStatus(result: MethodChannel.Result) {
        result.success(
            mapOf(
                "platform" to "android",
                "configured" to configured,
                "running" to false,
                "activationMode" to activationMode,
            ),
        )
    }

    private fun stop(result: MethodChannel.Result) {
        configured = false
        activationMode = null
        result.success(null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private companion object {
        const val CHANNEL_NAME = "app.zbg.proximity/methods"
    }
}

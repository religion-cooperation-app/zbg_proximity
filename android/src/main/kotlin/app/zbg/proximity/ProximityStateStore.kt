package app.zbg.proximity

import android.content.Context

internal class ProximityStateStore(context: Context) {
    private val preferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun saveConfiguration(uid: String, serviceUuid: String, activationMode: String) {
        val selfHashHex = ParticipantFrameCodec.toHex(ParticipantFrameCodec.hashUid(uid))
        preferences.edit()
            .putBoolean(KEY_CONFIGURED, true)
            .putString(KEY_SERVICE_UUID, serviceUuid)
            .putString(KEY_ACTIVATION_MODE, activationMode)
            .putString(KEY_SELF_HASH, selfHashHex)
            .commit()
    }

    fun isConfigured(): Boolean = preferences.getBoolean(KEY_CONFIGURED, false)

    fun activationMode(): String? = preferences.getString(KEY_ACTIVATION_MODE, null)

    fun serviceUuid(): String? = preferences.getString(KEY_SERVICE_UUID, null)

    fun selfHashHex(): String? = preferences.getString(KEY_SELF_HASH, null)

    fun setRunning(running: Boolean) {
        preferences.edit().putBoolean(KEY_RUNNING, running).apply()
    }

    fun isRunning(): Boolean = preferences.getBoolean(KEY_RUNNING, false)

    fun setAdvertisingState(active: Boolean, state: String, error: String?) {
        preferences.edit()
            .putBoolean(KEY_ADVERTISING, active)
            .putString(KEY_ADVERTISING_STATE, state)
            .putNullableString(KEY_ADVERTISING_ERROR, error)
            .apply()
    }

    fun isAdvertising(): Boolean = preferences.getBoolean(KEY_ADVERTISING, false)

    fun advertisingState(): String =
        preferences.getString(KEY_ADVERTISING_STATE, "stopped") ?: "stopped"

    fun setScanningState(active: Boolean, state: String, error: String?) {
        preferences.edit()
            .putBoolean(KEY_SCANNING, active)
            .putString(KEY_SCANNING_STATE, state)
            .putNullableString(KEY_SCANNING_ERROR, error)
            .apply()
    }

    fun isScanning(): Boolean = preferences.getBoolean(KEY_SCANNING, false)

    fun scanningState(): String =
        preferences.getString(KEY_SCANNING_STATE, "stopped") ?: "stopped"

    fun lastBleError(): String? =
        preferences.getString(KEY_SCANNING_ERROR, null)
            ?: preferences.getString(KEY_ADVERTISING_ERROR, null)

    fun clear() {
        preferences.edit().clear().apply()
    }

    private fun android.content.SharedPreferences.Editor.putNullableString(
        key: String,
        value: String?,
    ): android.content.SharedPreferences.Editor =
        if (value == null) remove(key) else putString(key, value)

    private companion object {
        const val PREFERENCES_NAME = "zbg_proximity_native"
        const val KEY_CONFIGURED = "configured"
        const val KEY_SERVICE_UUID = "service_uuid"
        const val KEY_ACTIVATION_MODE = "activation_mode"
        const val KEY_SELF_HASH = "self_hash"
        const val KEY_RUNNING = "running"
        const val KEY_ADVERTISING = "advertising"
        const val KEY_ADVERTISING_STATE = "advertising_state"
        const val KEY_SCANNING = "scanning"
        const val KEY_SCANNING_STATE = "scanning_state"
        const val KEY_ADVERTISING_ERROR = "advertising_error"
        const val KEY_SCANNING_ERROR = "scanning_error"
    }
}

package app.zbg.proximity

import android.content.Context

internal class ProximityStateStore(context: Context) {
    private val preferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun saveConfiguration(serviceUuid: String, activationMode: String) {
        preferences.edit()
            .putBoolean(KEY_CONFIGURED, true)
            .putString(KEY_SERVICE_UUID, serviceUuid)
            .putString(KEY_ACTIVATION_MODE, activationMode)
            .apply()
    }

    fun isConfigured(): Boolean = preferences.getBoolean(KEY_CONFIGURED, false)

    fun activationMode(): String? = preferences.getString(KEY_ACTIVATION_MODE, null)

    fun setRunning(running: Boolean) {
        preferences.edit().putBoolean(KEY_RUNNING, running).apply()
    }

    fun isRunning(): Boolean = preferences.getBoolean(KEY_RUNNING, false)

    fun clear() {
        preferences.edit().clear().apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "zbg_proximity_native"
        const val KEY_CONFIGURED = "configured"
        const val KEY_SERVICE_UUID = "service_uuid"
        const val KEY_ACTIVATION_MODE = "activation_mode"
        const val KEY_RUNNING = "running"
    }
}

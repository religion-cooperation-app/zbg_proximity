package app.zbg.proximity

import android.content.Context
import android.content.Intent
import android.os.Build

internal object ProximityServiceController {
    fun start(context: Context) {
        val intent = Intent(context, ProximityForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    fun stop(context: Context) {
        context.stopService(Intent(context, ProximityForegroundService::class.java))
        ProximityStateStore(context).setRunning(false)
    }
}

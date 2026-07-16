package app.zbg.proximity

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground-service lifecycle foundation for native proximity sensing.
 *
 * BLE scanning and advertising are intentionally not part of this milestone.
 */
class ProximityForegroundService : Service() {
    private lateinit var stateStore: ProximityStateStore

    override fun onCreate() {
        super.onCreate()
        stateStore = ProximityStateStore(applicationContext)

        val notification = ProximityNotification.create(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                ProximityNotification.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(ProximityNotification.NOTIFICATION_ID, notification)
        }
        stateStore.setRunning(true)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!stateStore.isConfigured()) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stateStore.setRunning(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Deliberately do not stop. The service remains active after the
        // Flutter activity is removed from Android Recents.
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

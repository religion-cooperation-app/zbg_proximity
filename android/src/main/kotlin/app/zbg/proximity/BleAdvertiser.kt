package app.zbg.proximity

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import java.util.UUID

internal class BleAdvertiser(
    private val context: Context,
    private val stateStore: ProximityStateStore,
) {
    private var callback: AdvertiseCallback? = null

    fun start() {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) {
            stateStore.setAdvertisingState(false, "bluetooth_off", "Bluetooth is unavailable or off")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stateStore.setAdvertisingState(false, "permission_denied", "BLUETOOTH_ADVERTISE missing")
            return
        }
        val nativeAdvertiser = adapter.bluetoothLeAdvertiser
        if (nativeAdvertiser == null || !adapter.isMultipleAdvertisementSupported) {
            stateStore.setAdvertisingState(false, "unsupported", "BLE advertising unsupported")
            return
        }
        val uuid = stateStore.serviceUuid()?.let {
            try {
                UUID.fromString(it)
            } catch (_: IllegalArgumentException) {
                null
            }
        }
        val hash = stateStore.selfHashHex()?.let(ParticipantFrameCodec::fromHex)
        if (uuid == null || hash == null) {
            stateStore.setAdvertisingState(false, "invalid_config", "Missing service UUID or identity hash")
            return
        }

        stop()
        val newCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                stateStore.setAdvertisingState(true, "active", null)
            }

            override fun onStartFailure(errorCode: Int) {
                stateStore.setAdvertisingState(false, "failed", "advertise_error_$errorCode")
            }
        }
        callback = newCallback
        stateStore.setAdvertisingState(false, "starting", null)
        try {
            nativeAdvertiser.startAdvertising(
                AdvertiseSettings.Builder()
                    .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                    .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                    .setConnectable(false)
                    .build(),
                AdvertiseData.Builder()
                    .setIncludeDeviceName(false)
                    .setIncludeTxPowerLevel(false)
                    .addServiceData(ParcelUuid(uuid), ParticipantFrameCodec.encode(hash))
                    .build(),
                newCallback,
            )
        } catch (error: SecurityException) {
            callback = null
            stateStore.setAdvertisingState(false, "permission_denied", error.message)
        } catch (error: RuntimeException) {
            callback = null
            stateStore.setAdvertisingState(false, "failed", error.message)
        }
    }

    fun stop() {
        val activeCallback = callback ?: run {
            stateStore.setAdvertisingState(false, "stopped", null)
            return
        }
        try {
            BluetoothAdapter.getDefaultAdapter()?.bluetoothLeAdvertiser?.stopAdvertising(activeCallback)
        } catch (_: SecurityException) {
            // State is still cleared below.
        } finally {
            callback = null
            stateStore.setAdvertisingState(false, "stopped", null)
        }
    }
}

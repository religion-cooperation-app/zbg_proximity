package app.zbg.proximity

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelUuid
import java.util.UUID

internal class BleScanner(
    private val context: Context,
    private val stateStore: ProximityStateStore,
    private val peerRegistry: PeerRegistry,
    private val nearbyPeerStore: NearbyPeerStore,
) {
    private var callback: ScanCallback? = null
    private var peersByHash: Map<String, String> = emptyMap()

    fun start() {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) {
            stateStore.setScanningState(false, "bluetooth_off", "Bluetooth is unavailable or off")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            stateStore.setScanningState(false, "permission_denied", "BLUETOOTH_SCAN missing")
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            stateStore.setScanningState(false, "unsupported", "BLE scanning unavailable")
            return
        }
        val uuid = stateStore.serviceUuid()?.let {
            try {
                UUID.fromString(it)
            } catch (_: IllegalArgumentException) {
                null
            }
        }
        if (uuid == null) {
            stateStore.setScanningState(false, "invalid_config", "Missing service UUID")
            return
        }

        stop()
        peersByHash = peerRegistry.byHash()
        val serviceParcelUuid = ParcelUuid(uuid)
        val newCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                process(result, serviceParcelUuid)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach { process(it, serviceParcelUuid) }
            }

            override fun onScanFailed(errorCode: Int) {
                callback = null
                stateStore.setScanningState(false, "failed", "scan_error_$errorCode")
            }
        }
        callback = newCallback
        stateStore.setScanningState(false, "starting", null)
        try {
            scanner.startScan(
                listOf(
                    ScanFilter.Builder()
                        .setServiceData(
                            serviceParcelUuid,
                            byteArrayOf(ParticipantFrameCodec.VERSION),
                        )
                        .build(),
                ),
                ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
                    .setReportDelay(0)
                    .build(),
                newCallback,
            )
            stateStore.setScanningState(true, "active", null)
        } catch (error: SecurityException) {
            callback = null
            stateStore.setScanningState(false, "permission_denied", error.message)
        } catch (error: RuntimeException) {
            callback = null
            stateStore.setScanningState(false, "failed", error.message)
        }
    }

    private fun process(result: ScanResult, serviceUuid: ParcelUuid) {
        val hash = ParticipantFrameCodec.decode(
            result.scanRecord?.getServiceData(serviceUuid),
        ) ?: return
        val hashHex = ParticipantFrameCodec.toHex(hash)
        if (hashHex == stateStore.selfHashHex()) return
        val uid = peersByHash[hashHex] ?: return
        nearbyPeerStore.record(uid, result.rssi)
    }

    fun stop() {
        val activeCallback = callback ?: run {
            stateStore.setScanningState(false, "stopped", null)
            return
        }
        try {
            BluetoothAdapter.getDefaultAdapter()?.bluetoothLeScanner?.stopScan(activeCallback)
        } catch (_: SecurityException) {
            // State is still cleared below.
        } finally {
            callback = null
            peersByHash = emptyMap()
            stateStore.setScanningState(false, "stopped", null)
        }
    }
}

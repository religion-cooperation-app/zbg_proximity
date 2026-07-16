package app.zbg.proximity

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToInt

internal data class NearbyPeerSnapshot(
    val uid: String,
    val rssi: Int,
    val sampleCount: Int,
    val firstSeenAtMs: Long,
    val lastSeenAtMs: Long,
    val nearby: Boolean,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "uid" to uid,
        "rssi" to rssi,
        "sampleCount" to sampleCount,
        "firstSeenAtMs" to firstSeenAtMs,
        "lastSeenAtMs" to lastSeenAtMs,
        "nearby" to nearby,
    )
}

internal class NearbyPeerStore(context: Context) {
    private val preferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val lock = Any()

    fun record(uid: String, rssi: Int, observedAtMs: Long = System.currentTimeMillis()) {
        synchronized(lock) {
            val all = readMutable()
            val previous = all[uid]
            val samples = previous?.samples ?: mutableListOf()
            samples.add(rssi)
            while (samples.size > MAX_SAMPLES) samples.removeAt(0)
            all[uid] = MutableObservation(
                uid = uid,
                samples = samples,
                firstSeenAtMs = previous?.firstSeenAtMs ?: observedAtMs,
                lastSeenAtMs = observedAtMs,
            )
            write(all)
        }
    }

    fun snapshots(nowMs: Long = System.currentTimeMillis()): List<NearbyPeerSnapshot> =
        synchronized(lock) {
            readMutable().values.map { observation ->
                val sorted = observation.samples.sorted()
                val median = if (sorted.isEmpty()) {
                    0
                } else if (sorted.size % 2 == 1) {
                    sorted[sorted.size / 2]
                } else {
                    ((sorted[sorted.size / 2 - 1] + sorted[sorted.size / 2]) / 2.0).roundToInt()
                }
                NearbyPeerSnapshot(
                    uid = observation.uid,
                    rssi = median,
                    sampleCount = observation.samples.size,
                    firstSeenAtMs = observation.firstSeenAtMs,
                    lastSeenAtMs = observation.lastSeenAtMs,
                    nearby = nowMs - observation.lastSeenAtMs <= LOST_TIMEOUT_MS,
                )
            }.sortedByDescending { it.lastSeenAtMs }
        }

    fun nearbyCount(): Int = snapshots().count { it.nearby }

    fun clear() {
        preferences.edit().clear().apply()
    }

    private fun readMutable(): MutableMap<String, MutableObservation> {
        val encoded = preferences.getString(KEY_OBSERVATIONS, null) ?: return linkedMapOf()
        return try {
            val array = JSONArray(encoded)
            linkedMapOf<String, MutableObservation>().apply {
                for (index in 0 until array.length()) {
                    val item = array.getJSONObject(index)
                    val samplesJson = item.getJSONArray("samples")
                    val samples = mutableListOf<Int>()
                    for (sampleIndex in 0 until samplesJson.length()) {
                        samples.add(samplesJson.getInt(sampleIndex))
                    }
                    val observation = MutableObservation(
                        uid = item.getString("uid"),
                        samples = samples,
                        firstSeenAtMs = item.getLong("firstSeenAtMs"),
                        lastSeenAtMs = item.getLong("lastSeenAtMs"),
                    )
                    put(observation.uid, observation)
                }
            }
        } catch (_: Exception) {
            linkedMapOf()
        }
    }

    private fun write(observations: Map<String, MutableObservation>) {
        val array = JSONArray()
        observations.values.forEach { observation ->
            array.put(
                JSONObject()
                    .put("uid", observation.uid)
                    .put("samples", JSONArray(observation.samples))
                    .put("firstSeenAtMs", observation.firstSeenAtMs)
                    .put("lastSeenAtMs", observation.lastSeenAtMs),
            )
        }
        preferences.edit().putString(KEY_OBSERVATIONS, array.toString()).apply()
    }

    private data class MutableObservation(
        val uid: String,
        val samples: MutableList<Int>,
        val firstSeenAtMs: Long,
        val lastSeenAtMs: Long,
    )

    private companion object {
        const val PREFERENCES_NAME = "zbg_proximity_nearby"
        const val KEY_OBSERVATIONS = "observations"
        const val MAX_SAMPLES = 5
        const val LOST_TIMEOUT_MS = 45_000L
    }
}

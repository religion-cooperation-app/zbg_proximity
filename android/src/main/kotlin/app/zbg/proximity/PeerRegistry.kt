package app.zbg.proximity

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal class PeerRegistry(context: Context) {
    private val preferences =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun replace(peerUids: List<String>, selfHashHex: String): Int {
        val byHash = linkedMapOf<String, String>()
        peerUids.forEach { uid ->
            require(uid.isNotBlank()) { "Peer UID must not be blank" }
            val hashHex = ParticipantFrameCodec.toHex(ParticipantFrameCodec.hashUid(uid))
            if (hashHex == selfHashHex) return@forEach
            val previous = byHash.put(hashHex, uid)
            require(previous == null || previous == uid) {
                "Participant hash collision between $previous and $uid"
            }
        }

        val array = JSONArray()
        byHash.forEach { (hash, uid) ->
            array.put(JSONObject().put("hash", hash).put("uid", uid))
        }
        preferences.edit().putString(KEY_PEERS, array.toString()).commit()
        return byHash.size
    }

    fun byHash(): Map<String, String> {
        val encoded = preferences.getString(KEY_PEERS, null) ?: return emptyMap()
        return try {
            val array = JSONArray(encoded)
            buildMap {
                for (index in 0 until array.length()) {
                    val item = array.getJSONObject(index)
                    put(item.getString("hash"), item.getString("uid"))
                }
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun count(): Int = byHash().size

    fun clear() {
        preferences.edit().clear().apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "zbg_proximity_peers"
        const val KEY_PEERS = "peers"
    }
}

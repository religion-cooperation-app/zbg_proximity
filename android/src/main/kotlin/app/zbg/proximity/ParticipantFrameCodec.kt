package app.zbg.proximity

import java.security.MessageDigest

internal object ParticipantFrameCodec {
    const val VERSION: Byte = 1
    private const val FRAME_LENGTH = 10
    private const val HASH_LENGTH = 8

    fun hashUid(uid: String): ByteArray =
        MessageDigest.getInstance("SHA-256")
            .digest(uid.toByteArray(Charsets.UTF_8))
            .copyOfRange(0, HASH_LENGTH)

    fun encode(hash: ByteArray): ByteArray {
        require(hash.size == HASH_LENGTH) { "Participant hash must be 8 bytes" }
        return byteArrayOf(VERSION, 0) + hash
    }

    fun decode(frame: ByteArray?): ByteArray? {
        if (frame == null || frame.size != FRAME_LENGTH || frame[0] != VERSION) {
            return null
        }
        return frame.copyOfRange(2, FRAME_LENGTH)
    }

    fun toHex(bytes: ByteArray): String =
        bytes.joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xff) }

    fun fromHex(hex: String): ByteArray? {
        if (hex.length != HASH_LENGTH * 2) return null
        return try {
            ByteArray(HASH_LENGTH) { index ->
                hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
            }
        } catch (_: NumberFormatException) {
            null
        }
    }
}

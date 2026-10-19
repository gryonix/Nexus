package com.skaymer.gryonixnexus.agentclient

object ConnectEnvelope {
    const val END_OF_STREAM_FLAG: Byte = 0x02

    /** The largest message either side accepts */
    const val MAX_PAYLOAD = 16 shl 20
    const val CUT_OFF_MESSAGE = "the connection ended before the agent finished"

    fun encode(payload: ByteArray, flags: Byte = 0): ByteArray {
        val out = ByteArray(5 + payload.size)
        out[0] = flags
        val len = payload.size
        out[1] = ((len ushr 24) and 0xff).toByte()
        out[2] = ((len ushr 16) and 0xff).toByte()
        out[3] = ((len ushr 8) and 0xff).toByte()
        out[4] = (len and 0xff).toByte()
        payload.copyInto(out, 5)
        return out
    }

    data class Frame(val flags: Byte, val payload: ByteArray) {
        val isEndOfStream: Boolean get() = (flags.toInt() and END_OF_STREAM_FLAG.toInt()) != 0

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Frame) return false
            return flags == other.flags && payload.contentEquals(other.payload)
        }

        override fun hashCode(): Int = 31 * flags.toInt() + payload.contentHashCode()
    }

    class Decoder {
        private var buffer = ByteArray(0)

        fun append(data: ByteArray) {
            buffer = buffer + data
        }

        fun next(): Frame? {
            if (buffer.size < 5) return null
            val flags = buffer[0]
            val len = ((buffer[1].toInt() and 0xff) shl 24) or
                ((buffer[2].toInt() and 0xff) shl 16) or
                ((buffer[3].toInt() and 0xff) shl 8) or
                (buffer[4].toInt() and 0xff)
            if (len < 0 || len > MAX_PAYLOAD) {
                throw AgentError.Transport("the agent sent a message larger than $MAX_PAYLOAD bytes")
            }
            val total = 5 + len
            if (buffer.size < total) return null
            val payload = buffer.copyOfRange(5, total)
            buffer = buffer.copyOfRange(total, buffer.size)
            return Frame(flags, payload)
        }
    }
}

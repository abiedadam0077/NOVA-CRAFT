package io.github.abiedadam0077.novacraft.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.Socket

/** Real protocol pings from the phone itself: Java Server List Ping (TCP) and Bedrock RakNet (UDP). */
object MinecraftPing {
    suspend fun pingJava(host: String, port: Int): PingResult = withContext(Dispatchers.IO) {
        val start = System.nanoTime()
        try {
            Socket().use { s ->
                s.connect(InetSocketAddress(host, port), 4000); s.soTimeout = 4000
                val out = s.getOutputStream(); val inp = s.getInputStream()
                val handshake = ByteArrayOutputStream().apply {
                    writeVarInt(0x00); writeVarInt(767); writeString(host); write(port ushr 8); write(port and 0xFF); writeVarInt(1)
                }.toByteArray()
                out.writePacket(handshake); out.writePacket(byteArrayOf(0x00)); out.flush()
                val len = inp.readVarInt(); if (len <= 0) throw Exception("Empty status")
                var packetId = inp.readVarInt(); if (packetId != 0) throw Exception("Bad status packet")
                val jsonLen = inp.readVarInt(); val bytes = ByteArray(jsonLen); var off = 0
                while (off < jsonLen) { val r = inp.read(bytes, off, jsonLen - off); if (r < 0) break; off += r }
                val o = JSONObject(String(bytes, Charsets.UTF_8))
                val players = o.optJSONObject("players"); val version = o.optJSONObject("version")
                val desc = o.opt("description")
                val motd = when (desc) { is JSONObject -> desc.optString("text", desc.toString()); is String -> desc; else -> "" }
                PingResult(true, (System.nanoTime() - start) / 1_000_000, players?.optInt("online"), players?.optInt("max"), motd, version?.optString("name") ?: "")
            }
        } catch (e: Exception) { PingResult(false, (System.nanoTime() - start) / 1_000_000, null, null, "", "", e.message) }
    }

    suspend fun pingBedrock(host: String, port: Int): PingResult = withContext(Dispatchers.IO) {
        val start = System.nanoTime()
        try {
            DatagramSocket().use { sock ->
                sock.soTimeout = 4000
                val magic = byteArrayOf(0x00, 0xff.toByte(), 0xff.toByte(), 0x00, 0xfe.toByte(), 0xfe.toByte(), 0xfe.toByte(), 0xfe.toByte(), 0xfd.toByte(), 0xfd.toByte(), 0xfd.toByte(), 0xfd.toByte(), 0x12, 0x34, 0x56, 0x78)
                val payload = ByteArrayOutputStream().apply {
                    write(0x01); val t = System.currentTimeMillis(); for (i in 7 downTo 0) write((t ushr (i * 8)).toInt() and 0xFF)
                    write(magic); val g = 123456789L; for (i in 7 downTo 0) write((g ushr (i * 8)).toInt() and 0xFF)
                }.toByteArray()
                sock.send(DatagramPacket(payload, payload.size, InetSocketAddress(host, port)))
                val buf = ByteArray(2048); val resp = DatagramPacket(buf, buf.size); sock.receive(resp)
                val data = resp.data.copyOfRange(0, resp.length)
                if (data.isEmpty() || data[0] != 0x1c.toByte()) throw Exception("Unexpected RakNet reply")
                // 1 + 8 time + 8 guid + 16 magic = 33, then 2-byte string length
                val strLen = ((data[33].toInt() and 0xFF) shl 8) or (data[34].toInt() and 0xFF)
                val str = String(data, 35, minOf(strLen, data.size - 35), Charsets.UTF_8)
                val f = str.split(";")
                PingResult(true, (System.nanoTime() - start) / 1_000_000,
                    f.getOrNull(4)?.toIntOrNull(), f.getOrNull(5)?.toIntOrNull(),
                    listOfNotNull(f.getOrNull(1), f.getOrNull(7)).joinToString(" "), f.getOrNull(3) ?: "")
            }
        } catch (e: Exception) { PingResult(false, (System.nanoTime() - start) / 1_000_000, null, null, "", "", e.message) }
    }
}

private fun ByteArrayOutputStream.writeVarInt(v0: Int) { var v = v0; while (true) { if (v and 0x7F.inv() == 0) { write(v); return }; write(v and 0x7F or 0x80); v = v ushr 7 } }
private fun ByteArrayOutputStream.writeString(s: String) { val b = s.toByteArray(Charsets.UTF_8); writeVarInt(b.size); write(b) }
private fun java.io.OutputStream.writePacket(p: ByteArray) { val len = ByteArrayOutputStream().apply { writeVarInt(p.size) }.toByteArray(); write(len); write(p) }
private fun java.io.InputStream.readVarInt(): Int { var num = 0; var result = 0; while (true) { val b = read(); if (b < 0) throw Exception("EOF"); result = result or ((b and 0x7F) shl (7 * num)); num++; if (b and 0x80 == 0) break; if (num > 5) throw Exception("VarInt too big") }; return result }

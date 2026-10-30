package com.magnates.bluetooth

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.godotengine.godot.Dictionary
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/**
 * Sockets Bluetooth RFCOMM para Godot. Contrato usado por net/bluetooth_peer.gd:
 * startServer, connectTo, send, disconnect, close, getPairedDevices
 * y señales connected / disconnected / data_received / error.
 */
@SuppressLint("MissingPermission")
class MagnatesBluetooth(godot: Godot) : GodotPlugin(godot) {

    private val sockets = ConcurrentHashMap<Int, BluetoothSocket>()
    private val nextId = AtomicInteger(1)
    private var serverSocket: BluetoothServerSocket? = null
    @Volatile private var running = false

    override fun getPluginName() = "MagnatesBluetooth"

    override fun getPluginSignals() = setOf(
        SignalInfo("connected", Integer::class.java),
        SignalInfo("disconnected", Integer::class.java),
        SignalInfo("data_received", Integer::class.java, ByteArray::class.java),
        SignalInfo("error", String::class.java),
    )

    private fun adapter(): BluetoothAdapter? {
        val ctx = activity ?: return null
        return (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    }

    private fun ensurePermissions(): Boolean {
        val act = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val perms = arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN)
        val missing = perms.filter { act.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) {
            act.requestPermissions(missing.toTypedArray(), 4711)
            emitSignal("error", "Concede el permiso de Bluetooth y vuelve a intentarlo")
            return false
        }
        return true
    }

    @UsedByGodot
    fun startServer(name: String, uuid: String) {
        if (!ensurePermissions()) return
        val ad = adapter() ?: return emitSignal("error", "Bluetooth no disponible")
        running = true
        thread(name = "bt-accept") {
            try {
                serverSocket = ad.listenUsingRfcommWithServiceRecord(name, UUID.fromString(uuid))
                while (running) {
                    val socket = serverSocket?.accept() ?: break
                    register(socket)
                }
            } catch (e: IOException) {
                if (running) emitSignal("error", "Servidor Bluetooth: ${e.message}")
            }
        }
    }

    @UsedByGodot
    fun connectTo(address: String, uuid: String) {
        if (!ensurePermissions()) return
        val ad = adapter() ?: return emitSignal("error", "Bluetooth no disponible")
        running = true
        thread(name = "bt-connect") {
            try {
                ad.cancelDiscovery()
                val socket = ad.getRemoteDevice(address).createRfcommSocketToServiceRecord(UUID.fromString(uuid))
                socket.connect()
                register(socket)
            } catch (e: IOException) {
                emitSignal("error", "No se pudo conectar: ${e.message}")
            }
        }
    }

    private fun register(socket: BluetoothSocket) {
        val id = nextId.getAndIncrement()
        sockets[id] = socket
        emitSignal("connected", id)
        thread(name = "bt-read-$id") {
            val buf = ByteArray(4096)
            try {
                val input = socket.inputStream
                while (running) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n > 0) emitSignal("data_received", id, buf.copyOf(n))
                }
            } catch (_: IOException) {
            }
            sockets.remove(id)?.let { runCatching { it.close() } }
            emitSignal("disconnected", id)
        }
    }

    @UsedByGodot
    fun send(connId: Int, data: ByteArray) {
        val socket = sockets[connId] ?: return
        try {
            synchronized(socket) {
                socket.outputStream.write(data)
                socket.outputStream.flush()
            }
        } catch (e: IOException) {
            disconnect(connId)
        }
    }

    @UsedByGodot
    fun disconnect(connId: Int) {
        sockets.remove(connId)?.let { runCatching { it.close() } }
    }

    @UsedByGodot
    fun close() {
        running = false
        runCatching { serverSocket?.close() }
        serverSocket = null
        sockets.keys.toList().forEach { disconnect(it) }
    }

    @UsedByGodot
    fun getPairedDevices(): Array<Dictionary> {
        if (!ensurePermissions()) return emptyArray()
        val ad = adapter() ?: return emptyArray()
        return ad.bondedDevices.map { d ->
            Dictionary().apply {
                put("name", d.name ?: d.address)
                put("address", d.address)
            }
        }.toTypedArray()
    }
}

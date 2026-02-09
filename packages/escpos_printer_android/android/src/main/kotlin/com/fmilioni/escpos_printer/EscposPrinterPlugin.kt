package com.fmilioni.escpos_printer

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.OutputStream
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** EscposPrinterPlugin */
class EscposPrinterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private val sessions = ConcurrentHashMap<String, NativeConnection>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "escpos_printer/native_transport")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "openConnection" -> handleOpenConnection(call, result)
                "write" -> handleWrite(call, result)
                "readStatus" -> handleReadStatus(call, result)
                "closeConnection" -> handleCloseConnection(call, result)
                "getCapabilities" -> handleGetCapabilities(call, result)
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("transport_error", error.message, null)
        }
    }

    private fun handleOpenConnection(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("openConnection requer payload")
        val transport = args["transport"] as? String ?: throw IllegalArgumentException("transport ausente")

        val connection = when (transport.lowercase()) {
            "usb" -> openUsbConnection(args)
            "bluetooth" -> openBluetoothConnection(args)
            "wifi" -> openWifiConnection(args)
            else -> throw IllegalArgumentException("Transporte nao suportado: $transport")
        }

        val sessionId = UUID.randomUUID().toString()
        sessions[sessionId] = connection
        result.success(
            mapOf(
                "sessionId" to sessionId,
                "capabilities" to connection.capabilities(),
            ),
        )
    }

    private fun handleWrite(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("write requer payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("sessionId ausente")
        val payload = args["bytes"] as? ByteArray ?: throw IllegalArgumentException("bytes ausente")

        val connection = sessions[sessionId] ?: throw IllegalStateException("Sessao nao encontrada: $sessionId")
        connection.write(payload)
        result.success(null)
    }

    private fun handleReadStatus(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("readStatus requer payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("sessionId ausente")

        val connection = sessions[sessionId] ?: throw IllegalStateException("Sessao nao encontrada: $sessionId")
        result.success(connection.readStatus())
    }

    private fun handleCloseConnection(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("closeConnection requer payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("sessionId ausente")

        val connection = sessions.remove(sessionId)
        connection?.close()
        result.success(null)
    }

    private fun handleGetCapabilities(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("getCapabilities requer payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("sessionId ausente")

        val connection = sessions[sessionId] ?: throw IllegalStateException("Sessao nao encontrada: $sessionId")
        result.success(mapOf("capabilities" to connection.capabilities()))
    }

    private fun openUsbConnection(args: Map<*, *>): NativeConnection {
        val vendorId = (args["vendorId"] as? Number)?.toInt() ?: throw IllegalArgumentException("vendorId ausente")
        val productId = (args["productId"] as? Number)?.toInt() ?: throw IllegalArgumentException("productId ausente")
        val interfaceNumber = (args["interfaceNumber"] as? Number)?.toInt()

        val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = findUsbDevice(manager, vendorId, productId)
            ?: throw IllegalStateException("Dispositivo USB nao encontrado ($vendorId:$productId)")

        if (!manager.hasPermission(device)) {
            throw SecurityException("Sem permissao USB para o dispositivo selecionado")
        }

        val connection = manager.openDevice(device)
            ?: throw IllegalStateException("Falha ao abrir conexao USB")

        val usbInterface = pickInterface(device, interfaceNumber)
            ?: throw IllegalStateException("Nao foi encontrada interface USB compativel")

        if (!connection.claimInterface(usbInterface, true)) {
            connection.close()
            throw IllegalStateException("Falha ao claim da interface USB")
        }

        val endpoint = pickBulkOutEndpoint(usbInterface)
            ?: run {
                connection.releaseInterface(usbInterface)
                connection.close()
                throw IllegalStateException("Nao foi encontrado endpoint BULK OUT")
            }

        return UsbNativeConnection(connection, usbInterface, endpoint)
    }

    private fun openBluetoothConnection(args: Map<*, *>): NativeConnection {
        val address = args["address"] as? String ?: throw IllegalArgumentException("address ausente")
        val serviceUuidRaw = args["serviceUuid"] as? String

        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw IllegalStateException("Bluetooth nao disponivel")

        val device = adapter.getRemoteDevice(address)
        val uuid = if (serviceUuidRaw.isNullOrBlank()) {
            DEFAULT_SPP_UUID
        } else {
            UUID.fromString(serviceUuidRaw)
        }

        val socket = device.createRfcommSocketToServiceRecord(uuid)
        socket.connect()

        return BluetoothNativeConnection(socket)
    }

    private fun openWifiConnection(args: Map<*, *>): NativeConnection {
        val host = args["host"] as? String ?: throw IllegalArgumentException("host ausente")
        val port = (args["port"] as? Number)?.toInt() ?: 9100
        val timeoutMs = (args["timeoutMs"] as? Number)?.toInt() ?: 5000

        val socket = Socket(host, port)
        socket.soTimeout = timeoutMs
        return WifiNativeConnection(socket)
    }

    private fun findUsbDevice(manager: UsbManager, vendorId: Int, productId: Int): UsbDevice? {
        return manager.deviceList.values.firstOrNull {
            it.vendorId == vendorId && it.productId == productId
        }
    }

    private fun pickInterface(device: UsbDevice, interfaceNumber: Int?): UsbInterface? {
        if (interfaceNumber != null) {
            val exact = (0 until device.interfaceCount)
                .map { device.getInterface(it) }
                .firstOrNull { it.id == interfaceNumber }
            if (exact != null) {
                return exact
            }
        }

        return (0 until device.interfaceCount)
            .map { device.getInterface(it) }
            .firstOrNull { pickBulkOutEndpoint(it) != null }
    }

    private fun pickBulkOutEndpoint(usbInterface: UsbInterface): UsbEndpoint? {
        return (0 until usbInterface.endpointCount)
            .map { usbInterface.getEndpoint(it) }
            .firstOrNull {
                it.type == UsbConstants.USB_ENDPOINT_XFER_BULK &&
                    it.direction == UsbConstants.USB_DIR_OUT
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sessions.values.forEach {
            runCatching { it.close() }
        }
        sessions.clear()
        channel.setMethodCallHandler(null)
    }

    private interface NativeConnection {
        fun write(bytes: ByteArray)
        fun readStatus(): Map<String, String>
        fun capabilities(): Map<String, Boolean>
        fun close()
    }

    private class UsbNativeConnection(
        private val connection: UsbDeviceConnection,
        private val usbInterface: UsbInterface,
        private val endpoint: UsbEndpoint,
    ) : NativeConnection {
        override fun write(bytes: ByteArray) {
            val transferred = connection.bulkTransfer(endpoint, bytes, bytes.size, 4000)
            if (transferred < 0) {
                throw IllegalStateException("Falha ao enviar dados via USB")
            }
        }

        override fun readStatus(): Map<String, String> = unknownStatus()

        override fun capabilities(): Map<String, Boolean> = defaultCapabilities(realtime = false)

        override fun close() {
            connection.releaseInterface(usbInterface)
            connection.close()
        }
    }

    private class BluetoothNativeConnection(
        private val socket: BluetoothSocket,
    ) : NativeConnection {
        private val output: OutputStream = socket.outputStream

        override fun write(bytes: ByteArray) {
            output.write(bytes)
            output.flush()
        }

        override fun readStatus(): Map<String, String> = unknownStatus()

        override fun capabilities(): Map<String, Boolean> = defaultCapabilities(realtime = false)

        override fun close() {
            runCatching { output.close() }
            socket.close()
        }
    }

    private class WifiNativeConnection(
        private val socket: Socket,
    ) : NativeConnection {
        private val output: OutputStream = socket.getOutputStream()

        override fun write(bytes: ByteArray) {
            output.write(bytes)
            output.flush()
        }

        override fun readStatus(): Map<String, String> = unknownStatus()

        override fun capabilities(): Map<String, Boolean> = defaultCapabilities(realtime = false)

        override fun close() {
            runCatching { output.close() }
            socket.close()
        }
    }

    companion object {
        private val DEFAULT_SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        private fun unknownStatus(): Map<String, String> {
            return mapOf(
                "paperOut" to "unknown",
                "paperNearEnd" to "unknown",
                "coverOpen" to "unknown",
                "cutterError" to "unknown",
                "offline" to "unknown",
                "drawerSignal" to "unknown",
            )
        }

        private fun defaultCapabilities(realtime: Boolean): Map<String, Boolean> {
            return mapOf(
                "supportsPartialCut" to true,
                "supportsFullCut" to true,
                "supportsDrawerKick" to true,
                "supportsRealtimeStatus" to realtime,
                "supportsQrCode" to true,
                "supportsBarcode" to true,
                "supportsImage" to true,
            )
        }
    }
}

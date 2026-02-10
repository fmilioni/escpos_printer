package com.fmilioni.escpos_printer

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
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
                "searchPrinters" -> handleSearchPrinters(call, result)
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("transport_error", error.message, null)
        }
    }

    private fun handleOpenConnection(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("openConnection requires payload")
        val transport = args["transport"] as? String ?: throw IllegalArgumentException("missing transport")

        val connection = when (transport.lowercase()) {
            "usb" -> openUsbConnection(args)
            "bluetooth" -> openBluetoothConnection(args)
            "wifi" -> openWifiConnection(args)
            else -> throw IllegalArgumentException("Unsupported transport: $transport")
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
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("write requires payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("missing sessionId")
        val payload = args["bytes"] as? ByteArray ?: throw IllegalArgumentException("missing bytes")

        val connection = sessions[sessionId] ?: throw IllegalStateException("Session not found: $sessionId")
        connection.write(payload)
        result.success(null)
    }

    private fun handleReadStatus(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("readStatus requires payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("missing sessionId")

        val connection = sessions[sessionId] ?: throw IllegalStateException("Session not found: $sessionId")
        result.success(connection.readStatus())
    }

    private fun handleCloseConnection(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("closeConnection requires payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("missing sessionId")

        val connection = sessions.remove(sessionId)
        connection?.close()
        result.success(null)
    }

    private fun handleGetCapabilities(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: throw IllegalArgumentException("getCapabilities requires payload")
        val sessionId = args["sessionId"] as? String ?: throw IllegalArgumentException("missing sessionId")

        val connection = sessions[sessionId] ?: throw IllegalStateException("Session not found: $sessionId")
        result.success(mapOf("capabilities" to connection.capabilities()))
    }

    private fun handleSearchPrinters(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        val transports = (args["transports"] as? List<*>)
            ?.mapNotNull { (it as? String)?.lowercase() }
            ?.toSet()
            ?: setOf("usb", "bluetooth")
        val devices = mutableListOf<Map<String, Any?>>()

        if (transports.contains("usb")) {
            devices += discoverUsbPrinters()
        }
        if (transports.contains("bluetooth")) {
            devices += discoverBluetoothPrinters()
        }

        result.success(devices)
    }

    private fun openUsbConnection(args: Map<*, *>): NativeConnection {
        val vendorId = (args["vendorId"] as? Number)?.toInt() ?: throw IllegalArgumentException("missing vendorId")
        val productId = (args["productId"] as? Number)?.toInt() ?: throw IllegalArgumentException("missing productId")
        val interfaceNumber = (args["interfaceNumber"] as? Number)?.toInt()

        val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = findUsbDevice(manager, vendorId, productId)
            ?: throw IllegalStateException("USB device not found ($vendorId:$productId)")

        if (!manager.hasPermission(device)) {
            throw SecurityException("No USB permission for the selected device")
        }

        val connection = manager.openDevice(device)
            ?: throw IllegalStateException("Failed to open USB connection")

        val usbInterface = pickInterface(device, interfaceNumber)
            ?: throw IllegalStateException("No compatible USB interface found")

        if (!connection.claimInterface(usbInterface, true)) {
            connection.close()
            throw IllegalStateException("Failed to claim USB interface")
        }

        val endpoint = pickBulkOutEndpoint(usbInterface)
            ?: run {
                connection.releaseInterface(usbInterface)
                connection.close()
                throw IllegalStateException("BULK OUT endpoint not found")
            }

        return UsbNativeConnection(connection, usbInterface, endpoint)
    }

    private fun openBluetoothConnection(args: Map<*, *>): NativeConnection {
        val address = args["address"] as? String ?: throw IllegalArgumentException("missing address")
        val serviceUuidRaw = args["serviceUuid"] as? String

        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw IllegalStateException("Bluetooth not available")

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
        val host = args["host"] as? String ?: throw IllegalArgumentException("missing host")
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

    private fun discoverUsbPrinters(): List<Map<String, Any?>> {
        val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val devices = mutableListOf<Map<String, Any?>>()
        for (device in manager.deviceList.values) {
            val usbInterface = pickInterface(device, null) ?: continue
            val endpoint = pickBulkOutEndpoint(usbInterface) ?: continue
            val serialNumber = runCatching { device.serialNumber }.getOrNull()
            val id = "usb:${device.vendorId}:${device.productId}:${serialNumber ?: device.deviceName}"
            val name = device.productName ?: device.deviceName ?: "USB ${device.vendorId}:${device.productId}"
            devices += mapOf(
                "id" to id,
                "name" to name,
                "transport" to "usb",
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "interfaceNumber" to usbInterface.id,
                "serialNumber" to serialNumber,
                "metadata" to mapOf(
                    "endpointAddress" to endpoint.address,
                    "hasPermission" to manager.hasPermission(device),
                    "deviceClass" to device.deviceClass,
                ),
            )
        }
        return devices
    }

    private fun discoverBluetoothPrinters(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            return emptyList()
        }

        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        val devices = mutableListOf<Map<String, Any?>>()
        for (device in adapter.bondedDevices) {
            if (device.type == android.bluetooth.BluetoothDevice.DEVICE_TYPE_LE) {
                continue
            }
            val address = device.address ?: continue
            devices += mapOf(
                "id" to "bluetooth:$address",
                "name" to (device.name ?: address),
                "transport" to "bluetooth",
                "address" to address,
                "mode" to "classic",
                "isPaired" to true,
            )
        }
        return devices
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
                throw IllegalStateException("Failed to send data over USB")
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

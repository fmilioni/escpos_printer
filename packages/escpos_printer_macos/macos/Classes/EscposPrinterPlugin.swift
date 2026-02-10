import Cocoa
import Darwin
import FlutterMacOS
import Foundation
import IOBluetooth
import IOKit
import IOKit.serial
import IOKit.usb

public class EscposPrinterPlugin: NSObject, FlutterPlugin {
  private var sessions: [String: NativeConnection] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "escpos_printer/native_transport",
      binaryMessenger: registrar.messenger
    )
    let instance = EscposPrinterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "openConnection":
        let payload = try parseArgs(call.arguments)
        let response = try handleOpenConnection(payload: payload)
        result(response)
      case "write":
        let payload = try parseArgs(call.arguments)
        try handleWrite(payload: payload)
        result(nil)
      case "readStatus":
        let payload = try parseArgs(call.arguments)
        let status = try handleReadStatus(payload: payload)
        result(status)
      case "closeConnection":
        let payload = try parseArgs(call.arguments)
        try handleCloseConnection(payload: payload)
        result(nil)
      case "getCapabilities":
        let payload = try parseArgs(call.arguments)
        let capabilities = try handleGetCapabilities(payload: payload)
        result(capabilities)
      case "searchPrinters":
        let payload = (call.arguments as? [String: Any]) ?? [:]
        let devices = handleSearchPrinters(payload: payload)
        result(devices)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch let error as NativeTransportError {
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      result(FlutterError(code: "transport_error", message: error.localizedDescription, details: nil))
    }
  }

  private func parseArgs(_ raw: Any?) throws -> [String: Any] {
    guard let args = raw as? [String: Any] else {
      throw NativeTransportError.invalidArgs("Payload must be a map")
    }
    return args
  }

  private func handleOpenConnection(payload: [String: Any]) throws -> [String: Any] {
    let transport = try requiredString(payload, key: "transport")

    let connection: NativeConnection
    switch transport {
    case "wifi":
      let host = try requiredString(payload, key: "host")
      let port = (payload["port"] as? NSNumber)?.intValue ?? 9100
      connection = try WifiNativeConnection(host: host, port: port)
    case "bluetooth":
      let address = try requiredString(payload, key: "address")
      let serviceUuid = payload["serviceUuid"] as? String
      connection = try BluetoothNativeConnection(
        address: address,
        serviceUuid: serviceUuid
      )
    case "usb":
      let serialOrPath = payload["serialNumber"] as? String
      if let serialOrPath, !serialOrPath.isEmpty {
        connection = try UsbDeviceFileConnection(serialOrPath: serialOrPath)
      } else if
        let vendorId = (payload["vendorId"] as? NSNumber)?.intValue,
        let productId = (payload["productId"] as? NSNumber)?.intValue,
        let resolvedPath = resolveSerialPath(vendorId: vendorId, productId: productId)
      {
        connection = try UsbDeviceFileConnection(serialOrPath: resolvedPath)
      } else {
        throw NativeTransportError.invalidArgs(
          "For USB, provide serialNumber/path or valid vendorId+productId"
        )
      }
    default:
      throw NativeTransportError.invalidArgs("Unsupported transport: \(transport)")
    }

    let sessionId = UUID().uuidString
    sessions[sessionId] = connection

    return [
      "sessionId": sessionId,
      "capabilities": connection.capabilities(),
    ]
  }

  private func handleWrite(payload: [String: Any]) throws {
    let sessionId = try requiredString(payload, key: "sessionId")
    guard let connection = sessions[sessionId] else {
      throw NativeTransportError.invalidSession("Session not found")
    }

    guard let typedBytes = payload["bytes"] as? FlutterStandardTypedData else {
      throw NativeTransportError.invalidArgs("bytes field must be Uint8List")
    }

    try connection.write(typedBytes.data)
  }

  private func handleReadStatus(payload: [String: Any]) throws -> [String: String] {
    let sessionId = try requiredString(payload, key: "sessionId")
    guard let connection = sessions[sessionId] else {
      throw NativeTransportError.invalidSession("Session not found")
    }

    return connection.readStatus()
  }

  private func handleCloseConnection(payload: [String: Any]) throws {
    let sessionId = try requiredString(payload, key: "sessionId")
    guard let connection = sessions.removeValue(forKey: sessionId) else {
      return
    }
    connection.close()
  }

  private func handleGetCapabilities(payload: [String: Any]) throws -> [String: Any] {
    let sessionId = try requiredString(payload, key: "sessionId")
    guard let connection = sessions[sessionId] else {
      throw NativeTransportError.invalidSession("Session not found")
    }

    return ["capabilities": connection.capabilities()]
  }

  private func handleSearchPrinters(payload: [String: Any]) -> [[String: Any]] {
    var devices: [[String: Any]] = []
    if shouldDiscoverTransport(payload: payload, transport: "usb") {
      devices.append(contentsOf: discoverUsbSerialPrinters())
    }
    if shouldDiscoverTransport(payload: payload, transport: "bluetooth") {
      devices.append(contentsOf: discoverBluetoothPrinters())
    }
    return devices
  }

  private func requiredString(_ payload: [String: Any], key: String) throws -> String {
    guard let value = payload[key] as? String, !value.isEmpty else {
      throw NativeTransportError.invalidArgs("Missing required field: \(key)")
    }
    return value
  }

  private func shouldDiscoverTransport(payload: [String: Any], transport: String) -> Bool {
    guard let transports = payload["transports"] as? [String], !transports.isEmpty else {
      return true
    }
    return transports.contains { $0.lowercased() == transport }
  }

  private func discoverBluetoothPrinters() -> [[String: Any]] {
    guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
      return []
    }

    return paired.compactMap { device -> [String: Any]? in
      guard let address = device.addressString, !address.isEmpty else {
        return nil
      }

      return [
        "id": "bluetooth:\(address)",
        "name": device.nameOrAddress ?? address,
        "transport": "bluetooth",
        "address": address,
        "mode": "classic",
        "isPaired": true,
      ]
    }
  }

  private func discoverUsbSerialPrinters() -> [[String: Any]] {
    let infoByPath = serialUsbInfoByPath()
    let manager = FileManager.default
    guard let entries = try? manager.contentsOfDirectory(atPath: "/dev") else {
      return []
    }

    let serialEntries = entries
      .filter { $0.hasPrefix("cu.") || $0.hasPrefix("tty.") }
      .sorted()

    return serialEntries.map { entry in
      let path = "/dev/\(entry)"
      let info = infoByPath[path]
      var metadata: [String: Any] = ["path": path]
      if let service = info?.serviceName {
        metadata["serviceName"] = service
      }
      var item: [String: Any] = [
        "id": "usb:\(path)",
        "name": "Serial \(entry)",
        "transport": "usb",
        "serialNumber": path,
        "metadata": metadata,
      ]
      if let vendorId = info?.vendorId {
        item["vendorId"] = vendorId
      }
      if let productId = info?.productId {
        item["productId"] = productId
      }
      return item
    }
  }

  private func resolveSerialPath(vendorId: Int, productId: Int) -> String? {
    return discoverUsbSerialPrinters().first { item in
      guard let vid = item["vendorId"] as? Int,
            let pid = item["productId"] as? Int else {
        return false
      }
      return vid == vendorId && pid == productId
    }?["serialNumber"] as? String
  }
}

private protocol NativeConnection {
  func write(_ data: Data) throws
  func readStatus() -> [String: String]
  func capabilities() -> [String: Bool]
  func close()
}

private final class WifiNativeConnection: NativeConnection {
  private let stream: OutputStream

  init(host: String, port: Int) throws {
    var readStream: Unmanaged<CFReadStream>?
    var writeStream: Unmanaged<CFWriteStream>?
    CFStreamCreatePairWithSocketToHost(
      nil,
      host as CFString,
      UInt32(port),
      &readStream,
      &writeStream
    )
    _ = readStream

    guard let stream = writeStream?.takeRetainedValue() as OutputStream? else {
      throw NativeTransportError.connectFailed("Failed to create TCP stream")
    }

    self.stream = stream
    self.stream.open()

    if self.stream.streamStatus == .error || self.stream.streamStatus == .closed {
      throw NativeTransportError.connectFailed(
        self.stream.streamError?.localizedDescription ?? "Failed to open TCP stream"
      )
    }
  }

  func write(_ data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return
      }

      var totalWritten = 0
      while totalWritten < data.count {
        let wrote = stream.write(baseAddress.advanced(by: totalWritten),
                                 maxLength: data.count - totalWritten)
        if wrote <= 0 {
          throw NativeTransportError.writeFailed(
            stream.streamError?.localizedDescription ?? "Failed to write to TCP stream"
          )
        }
        totalWritten += wrote
      }
    }
  }

  func readStatus() -> [String: String] {
    return unknownStatusMap()
  }

  func capabilities() -> [String: Bool] {
    return defaultCapabilities(realtimeStatus: false)
  }

  func close() {
    stream.close()
  }
}

private final class BluetoothNativeConnection: NativeConnection {
  private let device: IOBluetoothDevice
  private let channel: IOBluetoothRFCOMMChannel

  init(address: String, serviceUuid: String?) throws {
    guard let device = IOBluetoothDevice(addressString: address) else {
      throw NativeTransportError.invalidArgs("Invalid Bluetooth address")
    }

    let channelID: BluetoothRFCOMMChannelID = 1
    if let serviceUuid, !serviceUuid.isEmpty {
      // `serviceUuid` is reserved for future extensions; for SPP compatibility we use channel 1.
      _ = serviceUuid
    }

    var channelRef: IOBluetoothRFCOMMChannel?
    let openStatus = device.openRFCOMMChannelSync(&channelRef, withChannelID: channelID, delegate: nil)
    guard openStatus == kIOReturnSuccess, let channel = channelRef else {
      throw NativeTransportError.connectFailed("Failed to open RFCOMM channel")
    }

    self.device = device
    self.channel = channel
  }

  func write(_ data: Data) throws {
    var mutableData = data
    let length = mutableData.count
    let status = mutableData.withUnsafeMutableBytes { rawBuffer -> IOReturn in
      guard let baseAddress = rawBuffer.baseAddress else {
        return kIOReturnSuccess
      }

      return channel.writeSync(baseAddress, length: UInt16(length))
    }

    guard status == kIOReturnSuccess else {
      throw NativeTransportError.writeFailed("Failed to send bytes over RFCOMM")
    }
  }

  func readStatus() -> [String: String] {
    return unknownStatusMap()
  }

  func capabilities() -> [String: Bool] {
    return defaultCapabilities(realtimeStatus: false)
  }

  func close() {
    _ = channel.close()
    _ = device
  }
}

private final class UsbDeviceFileConnection: NativeConnection {
  private let fileDescriptor: Int32

  init(serialOrPath: String) throws {
    let path: String
    if serialOrPath.hasPrefix("/dev/") {
      path = serialOrPath
    } else {
      path = "/dev/\(serialOrPath)"
    }

    let fd = Darwin.open(path, O_WRONLY | O_NOCTTY)
    guard fd >= 0 else {
      throw NativeTransportError.connectFailed("Failed to open USB device at \(path)")
    }

    self.fileDescriptor = fd
  }

  func write(_ data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
      guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return
      }

      var totalWritten = 0
      while totalWritten < data.count {
        let wrote = Darwin.write(fileDescriptor,
                                 baseAddress.advanced(by: totalWritten),
                                 data.count - totalWritten)
        if wrote < 0 {
          throw NativeTransportError.writeFailed("Failed to send bytes to USB device")
        }
        totalWritten += wrote
      }
    }
  }

  func readStatus() -> [String: String] {
    return unknownStatusMap()
  }

  func capabilities() -> [String: Bool] {
    return defaultCapabilities(realtimeStatus: false)
  }

  func close() {
    Darwin.close(fileDescriptor)
  }
}

private struct SerialUsbInfo {
  let vendorId: Int?
  let productId: Int?
  let serviceName: String?
}

private func serialUsbInfoByPath() -> [String: SerialUsbInfo] {
  guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary? else {
    return [:]
  }
  matching[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes

  var iterator: io_iterator_t = 0
  guard IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator) == KERN_SUCCESS else {
    return [:]
  }
  defer { IOObjectRelease(iterator) }

  var result: [String: SerialUsbInfo] = [:]
  while true {
    let service = IOIteratorNext(iterator)
    if service == 0 {
      break
    }
    defer { IOObjectRelease(service) }

    guard let callout = ioRegistryStringProperty(service: service, key: kIOCalloutDeviceKey) else {
      continue
    }

    let vendorId = lookupUsbIntProperty(service: service, key: "idVendor")
    let productId = lookupUsbIntProperty(service: service, key: "idProduct")
    let serviceName = ioRegistryServiceName(service: service)
    result[callout] = SerialUsbInfo(
      vendorId: vendorId,
      productId: productId,
      serviceName: serviceName
    )
  }

  return result
}

private func ioRegistryServiceName(service: io_registry_entry_t) -> String? {
  var nameBuffer = [CChar](repeating: 0, count: 128)
  guard IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS else {
    return nil
  }
  return String(cString: nameBuffer)
}

private func lookupUsbIntProperty(service: io_registry_entry_t, key: String) -> Int? {
  var current = service
  var ownedEntries: [io_registry_entry_t] = []
  defer {
    for entry in ownedEntries {
      IOObjectRelease(entry)
    }
  }

  for _ in 0..<8 {
    if let value = ioRegistryIntProperty(service: current, key: key) {
      return value
    }

    var parent: io_registry_entry_t = 0
    let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
    if status != KERN_SUCCESS || parent == 0 {
      break
    }
    ownedEntries.append(parent)
    current = parent
  }

  return nil
}

private func ioRegistryIntProperty(service: io_registry_entry_t, key: String) -> Int? {
  guard let unmanaged = IORegistryEntryCreateCFProperty(
    service,
    key as CFString,
    kCFAllocatorDefault,
    0
  ) else {
    return nil
  }
  let value = unmanaged.takeRetainedValue()
  if let number = value as? NSNumber {
    return number.intValue
  }
  return nil
}

private func ioRegistryStringProperty(service: io_registry_entry_t, key: String) -> String? {
  guard let unmanaged = IORegistryEntryCreateCFProperty(
    service,
    key as CFString,
    kCFAllocatorDefault,
    0
  ) else {
    return nil
  }
  return unmanaged.takeRetainedValue() as? String
}

private enum NativeTransportError: Error {
  case invalidArgs(String)
  case invalidSession(String)
  case connectFailed(String)
  case writeFailed(String)

  var code: String {
    switch self {
    case .invalidArgs:
      return "invalid_args"
    case .invalidSession:
      return "invalid_session"
    case .connectFailed:
      return "connect_failed"
    case .writeFailed:
      return "write_failed"
    }
  }

  var message: String {
    switch self {
    case .invalidArgs(let message),
         .invalidSession(let message),
         .connectFailed(let message),
         .writeFailed(let message):
      return message
    }
  }
}

private func unknownStatusMap() -> [String: String] {
  return [
    "paperOut": "unknown",
    "paperNearEnd": "unknown",
    "coverOpen": "unknown",
    "cutterError": "unknown",
    "offline": "unknown",
    "drawerSignal": "unknown",
  ]
}

private func defaultCapabilities(realtimeStatus: Bool) -> [String: Bool] {
  return [
    "supportsPartialCut": true,
    "supportsFullCut": true,
    "supportsDrawerKick": true,
    "supportsRealtimeStatus": realtimeStatus,
    "supportsQrCode": true,
    "supportsBarcode": true,
    "supportsImage": true,
  ]
}

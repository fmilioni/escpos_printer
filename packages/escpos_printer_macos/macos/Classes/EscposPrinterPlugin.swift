import Cocoa
import Darwin
import FlutterMacOS
import Foundation
import IOBluetooth

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
      throw NativeTransportError.invalidArgs("Payload deve ser um map")
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
      let serialOrPath = try requiredString(payload, key: "serialNumber")
      connection = try UsbDeviceFileConnection(serialOrPath: serialOrPath)
    default:
      throw NativeTransportError.invalidArgs("Transporte nao suportado: \(transport)")
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
      throw NativeTransportError.invalidSession("Sessao nao encontrada")
    }

    guard let typedBytes = payload["bytes"] as? FlutterStandardTypedData else {
      throw NativeTransportError.invalidArgs("Campo bytes deve ser Uint8List")
    }

    try connection.write(typedBytes.data)
  }

  private func handleReadStatus(payload: [String: Any]) throws -> [String: String] {
    let sessionId = try requiredString(payload, key: "sessionId")
    guard let connection = sessions[sessionId] else {
      throw NativeTransportError.invalidSession("Sessao nao encontrada")
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
      throw NativeTransportError.invalidSession("Sessao nao encontrada")
    }

    return ["capabilities": connection.capabilities()]
  }

  private func requiredString(_ payload: [String: Any], key: String) throws -> String {
    guard let value = payload[key] as? String, !value.isEmpty else {
      throw NativeTransportError.invalidArgs("Campo obrigatorio ausente: \(key)")
    }
    return value
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
    guard let stream = OutputStream(toHost: host, port: port) else {
      throw NativeTransportError.connectFailed("Falha ao criar stream TCP")
    }

    self.stream = stream
    self.stream.open()

    if self.stream.streamStatus == .error || self.stream.streamStatus == .closed {
      throw NativeTransportError.connectFailed(
        self.stream.streamError?.localizedDescription ?? "Falha ao abrir stream TCP"
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
            stream.streamError?.localizedDescription ?? "Falha ao escrever em stream TCP"
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
      throw NativeTransportError.invalidArgs("Endereco Bluetooth invalido")
    }

    var channelID: BluetoothRFCOMMChannelID = 1
    if let serviceUuid, !serviceUuid.isEmpty {
      // `serviceUuid` reservado para extensao futura; por compatibilidade SPP usamos canal 1.
      _ = serviceUuid
    }

    var channelRef: IOBluetoothRFCOMMChannel?
    let openStatus = device.openRFCOMMChannelSync(&channelRef, withChannelID: channelID, delegate: nil)
    guard openStatus == kIOReturnSuccess, let channel = channelRef else {
      throw NativeTransportError.connectFailed("Falha ao abrir canal RFCOMM")
    }

    self.device = device
    self.channel = channel
  }

  func write(_ data: Data) throws {
    let status = data.withUnsafeBytes { rawBuffer -> IOReturn in
      guard let baseAddress = rawBuffer.baseAddress else {
        return kIOReturnSuccess
      }

      return channel.writeSync(baseAddress, length: UInt16(data.count))
    }

    guard status == kIOReturnSuccess else {
      throw NativeTransportError.writeFailed("Falha ao enviar bytes via RFCOMM")
    }
  }

  func readStatus() -> [String: String] {
    return unknownStatusMap()
  }

  func capabilities() -> [String: Bool] {
    return defaultCapabilities(realtimeStatus: false)
  }

  func close() {
    channel.closeChannel()
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
      throw NativeTransportError.connectFailed("Falha ao abrir dispositivo USB em \(path)")
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
          throw NativeTransportError.writeFailed("Falha ao enviar bytes no dispositivo USB")
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

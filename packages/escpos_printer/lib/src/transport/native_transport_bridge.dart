import 'dart:typed_data';

import 'package:escpos_printer_platform_interface/escpos_printer_platform_interface.dart';

import '../model/endpoints.dart';
import '../model/exceptions.dart';
import '../model/status.dart';

final class NativeConnectionSession {
  const NativeConnectionSession({
    required this.sessionId,
    required this.capabilities,
  });

  final String sessionId;
  final PrinterCapabilities capabilities;
}

/// Bridge para operações de transporte nativo (USB/Bluetooth) usando contrato tipado.
class NativeTransportBridge {
  NativeTransportBridge({NativeTransportApi? api})
      : _api = api ?? NativeTransportApi();

  final NativeTransportApi _api;

  Future<NativeConnectionSession> openConnection(PrinterEndpoint endpoint) async {
    try {
      final response = await _api.openConnection(_endpointToPayload(endpoint));
      return NativeConnectionSession(
        sessionId: response.sessionId,
        capabilities: _mapCapabilities(response.capabilities),
      );
    } catch (error) {
      throw TransportException('Falha ao abrir conexao nativa.', error);
    }
  }

  Future<void> write(String sessionId, List<int> bytes) async {
    try {
      await _api.write(
        WritePayload(
          sessionId: sessionId,
          bytes: Uint8List.fromList(bytes),
        ),
      );
    } catch (error) {
      throw TransportException('Falha ao escrever no transporte nativo.', error);
    }
  }

  Future<PrinterStatus> readStatus(String sessionId) async {
    try {
      final status = await _api.readStatus(SessionPayload(sessionId));
      return _mapStatus(status);
    } catch (_) {
      return const PrinterStatus.unknown();
    }
  }

  Future<PrinterCapabilities> getCapabilities(String sessionId) async {
    try {
      final caps = await _api.getCapabilities(SessionPayload(sessionId));
      return _mapCapabilities(caps);
    } catch (_) {
      return const PrinterCapabilities();
    }
  }

  Future<void> closeConnection(String sessionId) async {
    try {
      await _api.closeConnection(SessionPayload(sessionId));
    } catch (error) {
      throw TransportException('Falha ao fechar conexao nativa.', error);
    }
  }

  EndpointPayload _endpointToPayload(PrinterEndpoint endpoint) {
    return switch (endpoint) {
      WifiEndpoint endpoint => EndpointPayload(
        transport: endpoint.transport,
        host: endpoint.host,
        port: endpoint.port,
        timeoutMs: endpoint.timeout.inMilliseconds,
      ),
      UsbEndpoint endpoint => EndpointPayload(
        transport: endpoint.transport,
        vendorId: endpoint.vendorId,
        productId: endpoint.productId,
        serialNumber: endpoint.serialNumber,
        interfaceNumber: endpoint.interfaceNumber,
      ),
      BluetoothEndpoint endpoint => EndpointPayload(
        transport: endpoint.transport,
        address: endpoint.address,
        mode: endpoint.mode.name,
        serviceUuid: endpoint.serviceUuid,
      ),
    };
  }

  PrinterCapabilities _mapCapabilities(CapabilityPayload payload) {
    return PrinterCapabilities(
      supportsPartialCut: payload.supportsPartialCut,
      supportsFullCut: payload.supportsFullCut,
      supportsDrawerKick: payload.supportsDrawerKick,
      supportsRealtimeStatus: payload.supportsRealtimeStatus,
      supportsQrCode: payload.supportsQrCode,
      supportsBarcode: payload.supportsBarcode,
      supportsImage: payload.supportsImage,
    );
  }

  PrinterStatus _mapStatus(StatusPayload payload) {
    return PrinterStatus(
      paperOut: _parseTri(payload.paperOut),
      paperNearEnd: _parseTri(payload.paperNearEnd),
      coverOpen: _parseTri(payload.coverOpen),
      cutterError: _parseTri(payload.cutterError),
      offline: _parseTri(payload.offline),
      drawerSignal: _parseTri(payload.drawerSignal),
    );
  }

  TriState _parseTri(String value) {
    return switch (value.toLowerCase()) {
      'yes' => TriState.yes,
      'no' => TriState.no,
      _ => TriState.unknown,
    };
  }
}

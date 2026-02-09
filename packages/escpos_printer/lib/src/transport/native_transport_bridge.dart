import 'dart:typed_data';

import 'package:escpos_printer_platform_interface/escpos_printer_platform_interface.dart';

import '../model/discovery.dart';
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

  Future<NativeConnectionSession> openConnection(
    PrinterEndpoint endpoint,
  ) async {
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
        WritePayload(sessionId: sessionId, bytes: Uint8List.fromList(bytes)),
      );
    } catch (error) {
      throw TransportException(
        'Falha ao escrever no transporte nativo.',
        error,
      );
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

  Future<List<DiscoveredPrinter>> searchNativePrinters({
    required Set<DiscoveryTransport> transports,
    Duration timeout = const Duration(seconds: 8),
    int wifiPort = 9100,
    List<String> wifiCidrs = const <String>[],
  }) async {
    try {
      final devices = await _api.searchPrinters(
        DiscoveryRequestPayload(
          transports: transports.map((transport) => transport.name).toList(),
          timeoutMs: timeout.inMilliseconds,
          wifiPort: wifiPort,
          wifiCidrs: wifiCidrs,
        ),
      );
      final discovered = <DiscoveredPrinter>[];
      for (final payload in devices) {
        final mapped = _mapDiscoveredDevice(payload);
        if (mapped == null) {
          continue;
        }
        if (!transports.contains(mapped.transport)) {
          continue;
        }
        discovered.add(mapped);
      }
      return List<DiscoveredPrinter>.unmodifiable(discovered);
    } catch (error) {
      throw TransportException('Falha ao buscar impressoras nativas.', error);
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

  DiscoveredPrinter? _mapDiscoveredDevice(DiscoveredDevicePayload payload) {
    final rawTransport = payload.transport.trim().toLowerCase();
    switch (rawTransport) {
      case 'wifi':
        final host = payload.host;
        if (host == null || host.isEmpty) {
          return null;
        }
        final port = payload.port ?? 9100;
        return DiscoveredPrinter(
          id: payload.id ?? 'wifi:$host:$port',
          name: payload.name,
          transport: DiscoveryTransport.wifi,
          endpoint: WifiEndpoint(host, port: port),
          host: host,
          metadata: payload.metadata,
        );

      case 'usb':
        final serialOrPath = payload.serialNumber ?? payload.comPort;
        final UsbEndpoint? endpoint;
        if (serialOrPath != null && serialOrPath.isNotEmpty) {
          endpoint = UsbEndpoint.serial(
            serialOrPath,
            vendorId: payload.vendorId,
            productId: payload.productId,
            interfaceNumber: payload.interfaceNumber,
          );
        } else if (payload.vendorId != null && payload.productId != null) {
          endpoint = UsbEndpoint(
            payload.vendorId!,
            payload.productId!,
            interfaceNumber: payload.interfaceNumber,
          );
        } else {
          endpoint = null;
        }
        if (endpoint == null) {
          return null;
        }

        return DiscoveredPrinter(
          id:
              payload.id ??
              'usb:${payload.vendorId ?? 0}:${payload.productId ?? 0}:${serialOrPath ?? ''}',
          name: payload.name,
          transport: DiscoveryTransport.usb,
          endpoint: endpoint,
          vendorId: payload.vendorId,
          productId: payload.productId,
          comPort: payload.comPort,
          serialNumber: payload.serialNumber,
          metadata: payload.metadata,
        );

      case 'bluetooth':
        final address = payload.address;
        if (address == null || address.isEmpty) {
          return null;
        }
        final mode = (payload.mode ?? 'classic').toLowerCase() == 'ble'
            ? BluetoothMode.ble
            : BluetoothMode.classic;
        return DiscoveredPrinter(
          id: payload.id ?? 'bluetooth:$address',
          name: payload.name,
          transport: DiscoveryTransport.bluetooth,
          endpoint: BluetoothEndpoint(
            address,
            mode: mode,
            serviceUuid: payload.serviceUuid,
          ),
          address: address,
          isPaired: payload.isPaired,
          metadata: payload.metadata,
        );
    }

    return null;
  }
}

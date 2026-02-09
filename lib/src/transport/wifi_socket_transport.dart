import 'dart:io';

import '../model/endpoints.dart';
import '../model/exceptions.dart';
import '../model/status.dart';
import 'transport.dart';

final class WifiSocketTransport implements PrinterTransport {
  WifiSocketTransport(this.endpoint);

  final WifiEndpoint endpoint;
  Socket? _socket;

  @override
  bool get isConnected => _socket != null;

  @override
  PrinterCapabilities get capabilities =>
      const PrinterCapabilities(supportsRealtimeStatus: false);

  @override
  Future<void> connect() async {
    try {
      _socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: endpoint.timeout,
      );
    } catch (error) {
      throw ConnectionException(
        'Falha ao conectar no endpoint Wi-Fi ${endpoint.host}:${endpoint.port}.',
        error,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) {
      return;
    }

    await socket.flush();
    await socket.close();
  }

  @override
  Future<PrinterStatus> getStatus() async {
    // Em RAW TCP 9100, status em tempo real depende de hardware/protocolo extra.
    return const PrinterStatus.unknown();
  }

  @override
  Future<void> write(List<int> data) async {
    final socket = _socket;
    if (socket == null) {
      throw ConnectionException('Transporte Wi-Fi nao conectado.');
    }

    try {
      socket.add(data);
      await socket.flush();
    } catch (error) {
      _socket = null;
      throw TransportException(
        'Falha ao enviar bytes para impressora Wi-Fi.',
        error,
      );
    }
  }
}

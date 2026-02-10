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
  String? get sessionId => null;

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
        'Failed to connect to Wi-Fi endpoint ${endpoint.host}:${endpoint.port}.',
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
    // In raw TCP 9100 mode, realtime status depends on extra hardware/protocol support.
    return const PrinterStatus.unknown();
  }

  @override
  Future<void> write(List<int> data) async {
    final socket = _socket;
    if (socket == null) {
      throw ConnectionException('Wi-Fi transport is not connected.');
    }

    try {
      socket.add(data);
      await socket.flush();
    } catch (error) {
      _socket = null;
      throw TransportException('Failed to send bytes to Wi-Fi printer.', error);
    }
  }
}

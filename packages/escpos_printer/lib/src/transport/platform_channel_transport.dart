import '../model/exceptions.dart';
import '../model/status.dart';
import 'native_transport_bridge.dart';
import 'transport.dart';

abstract class PlatformChannelTransport implements PrinterTransport {
  PlatformChannelTransport(this.bridge);

  final NativeTransportBridge bridge;

  String? _sessionId;
  PrinterCapabilities _capabilities = const PrinterCapabilities();

  @override
  String? get sessionId => _sessionId;

  @override
  bool get isConnected => _sessionId != null;

  @override
  PrinterCapabilities get capabilities => _capabilities;

  @override
  Future<void> connect() async {
    if (_sessionId != null) {
      return;
    }
    final session = await openSession();
    _sessionId = session.sessionId;
    _capabilities = session.capabilities;
  }

  Future<NativeConnectionSession> openSession();

  @override
  Future<void> disconnect() async {
    final current = _sessionId;
    _sessionId = null;
    if (current == null) {
      return;
    }
    await bridge.closeConnection(current);
  }

  @override
  Future<void> write(List<int> data) async {
    final current = _sessionId;
    if (current == null) {
      throw ConnectionException('Native transport is not connected.');
    }

    try {
      await bridge.write(current, data);
    } catch (error) {
      _sessionId = null;
      rethrow;
    }
  }

  @override
  Future<PrinterStatus> getStatus() async {
    final current = _sessionId;
    if (current == null) {
      throw ConnectionException('Native transport is not connected.');
    }

    try {
      return await bridge.readStatus(current);
    } catch (_) {
      return const PrinterStatus.unknown();
    }
  }
}

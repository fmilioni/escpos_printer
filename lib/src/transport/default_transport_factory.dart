import '../model/endpoints.dart';
import '../model/exceptions.dart';
import '../model/status.dart';
import 'transport.dart';
import 'wifi_socket_transport.dart';

final class DefaultTransportFactory implements TransportFactory {
  const DefaultTransportFactory();

  @override
  Future<PrinterTransport> create(PrinterEndpoint endpoint) async {
    return switch (endpoint) {
      WifiEndpoint endpoint => WifiSocketTransport(endpoint),
      UsbEndpoint() => UnsupportedTransport(endpoint.transport),
      BluetoothEndpoint() => UnsupportedTransport(endpoint.transport),
    };
  }
}

final class UnsupportedTransport implements PrinterTransport {
  UnsupportedTransport(this.transportName);

  final String transportName;

  @override
  bool get isConnected => false;

  @override
  PrinterCapabilities get capabilities => const PrinterCapabilities();

  @override
  Future<void> connect() {
    throw TransportException(
      'Transporte "$transportName" nao possui implementacao Dart padrao. '
      'Forneca um TransportFactory customizado para esta plataforma.',
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<PrinterStatus> getStatus() async => const PrinterStatus.unknown();

  @override
  Future<void> write(List<int> data) {
    throw TransportException(
      'Transporte "$transportName" nao possui implementacao Dart padrao. '
      'Forneca um TransportFactory customizado para esta plataforma.',
    );
  }
}

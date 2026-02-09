import '../model/endpoints.dart';
import '../model/status.dart';

abstract interface class PrinterTransport {
  bool get isConnected;
  PrinterCapabilities get capabilities;

  Future<void> connect();
  Future<void> disconnect();
  Future<void> write(List<int> data);
  Future<PrinterStatus> getStatus();
}

abstract interface class TransportFactory {
  Future<PrinterTransport> create(PrinterEndpoint endpoint);
}

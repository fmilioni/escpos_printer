import '../model/endpoints.dart';
import 'native_transport_bridge.dart';
import 'platform_bluetooth_transport.dart';
import 'platform_usb_transport.dart';
import 'transport.dart';
import 'wifi_socket_transport.dart';

final class DefaultTransportFactory implements TransportFactory {
  DefaultTransportFactory({NativeTransportBridge? nativeBridge})
    : _nativeBridge = nativeBridge ?? NativeTransportBridge();

  final NativeTransportBridge _nativeBridge;

  @override
  Future<PrinterTransport> create(PrinterEndpoint endpoint) async {
    return switch (endpoint) {
      WifiEndpoint endpoint => WifiSocketTransport(endpoint),
      UsbEndpoint endpoint => PlatformUsbTransport(
        endpoint,
        bridge: _nativeBridge,
      ),
      BluetoothEndpoint endpoint => PlatformBluetoothTransport(
        endpoint,
        bridge: _nativeBridge,
      ),
    };
  }
}

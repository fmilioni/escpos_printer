import '../model/endpoints.dart';
import 'native_transport_bridge.dart';
import 'platform_channel_transport.dart';

final class PlatformUsbTransport extends PlatformChannelTransport {
  PlatformUsbTransport(this.endpoint, {required NativeTransportBridge bridge})
    : super(bridge);

  final UsbEndpoint endpoint;

  @override
  Future<NativeConnectionSession> openSession() {
    return bridge.openConnection(endpoint);
  }
}

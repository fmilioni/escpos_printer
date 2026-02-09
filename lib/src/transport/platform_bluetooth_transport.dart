import '../model/endpoints.dart';
import 'native_transport_bridge.dart';
import 'platform_channel_transport.dart';

final class PlatformBluetoothTransport extends PlatformChannelTransport {
  PlatformBluetoothTransport(
    this.endpoint, {
    required NativeTransportBridge bridge,
  }) : super(bridge);

  final BluetoothEndpoint endpoint;

  @override
  Future<NativeConnectionSession> openSession() {
    return bridge.openConnection(endpoint);
  }
}

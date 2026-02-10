// Typed contract reference (Pigeon style) for NativeTransport.
// This version stays in-repo as a contract spec without external dependency,
// avoiding build coupling with code generation at this stage.

class EndpointPayload {
  const EndpointPayload();
}

class OpenConnectionResponse {
  const OpenConnectionResponse();
}

class CapabilityPayload {
  const CapabilityPayload();
}

class StatusPayload {
  const StatusPayload();
}

class WritePayload {
  const WritePayload();
}

class SessionPayload {
  const SessionPayload();
}

class DiscoveryRequestPayload {
  const DiscoveryRequestPayload();
}

class DiscoveredDevicePayload {
  const DiscoveredDevicePayload();
}

abstract class NativeTransportApi {
  OpenConnectionResponse openConnection(EndpointPayload endpoint);
  void write(WritePayload payload);
  StatusPayload readStatus(SessionPayload payload);
  void closeConnection(SessionPayload payload);
  CapabilityPayload getCapabilities(SessionPayload payload);
  List<DiscoveredDevicePayload> searchPrinters(DiscoveryRequestPayload payload);
}

// Referência do contrato tipado (estilo Pigeon) para NativeTransport.
// Esta versão fica no repositório como spec de contrato sem dependência externa,
// para evitar acoplamento de build com geração automática neste momento.

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

abstract class NativeTransportApi {
  OpenConnectionResponse openConnection(EndpointPayload endpoint);
  void write(WritePayload payload);
  StatusPayload readStatus(SessionPayload payload);
  void closeConnection(SessionPayload payload);
  CapabilityPayload getCapabilities(SessionPayload payload);
}

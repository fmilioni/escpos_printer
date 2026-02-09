import 'package:flutter/services.dart';

final class EndpointPayload {
  const EndpointPayload({
    required this.transport,
    this.host,
    this.port,
    this.timeoutMs,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.interfaceNumber,
    this.address,
    this.mode,
    this.serviceUuid,
  });

  final String transport;
  final String? host;
  final int? port;
  final int? timeoutMs;
  final int? vendorId;
  final int? productId;
  final String? serialNumber;
  final int? interfaceNumber;
  final String? address;
  final String? mode;
  final String? serviceUuid;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'transport': transport,
      'host': host,
      'port': port,
      'timeoutMs': timeoutMs,
      'vendorId': vendorId,
      'productId': productId,
      'serialNumber': serialNumber,
      'interfaceNumber': interfaceNumber,
      'address': address,
      'mode': mode,
      'serviceUuid': serviceUuid,
    };
  }
}

final class CapabilityPayload {
  const CapabilityPayload({
    this.supportsPartialCut = true,
    this.supportsFullCut = true,
    this.supportsDrawerKick = true,
    this.supportsRealtimeStatus = false,
    this.supportsQrCode = true,
    this.supportsBarcode = true,
    this.supportsImage = true,
  });

  final bool supportsPartialCut;
  final bool supportsFullCut;
  final bool supportsDrawerKick;
  final bool supportsRealtimeStatus;
  final bool supportsQrCode;
  final bool supportsBarcode;
  final bool supportsImage;

  factory CapabilityPayload.fromMap(Map<String, Object?> map) {
    bool read(String key, bool fallback) {
      final raw = map[key];
      return raw is bool ? raw : fallback;
    }

    return CapabilityPayload(
      supportsPartialCut: read('supportsPartialCut', true),
      supportsFullCut: read('supportsFullCut', true),
      supportsDrawerKick: read('supportsDrawerKick', true),
      supportsRealtimeStatus: read('supportsRealtimeStatus', false),
      supportsQrCode: read('supportsQrCode', true),
      supportsBarcode: read('supportsBarcode', true),
      supportsImage: read('supportsImage', true),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'supportsPartialCut': supportsPartialCut,
      'supportsFullCut': supportsFullCut,
      'supportsDrawerKick': supportsDrawerKick,
      'supportsRealtimeStatus': supportsRealtimeStatus,
      'supportsQrCode': supportsQrCode,
      'supportsBarcode': supportsBarcode,
      'supportsImage': supportsImage,
    };
  }
}

final class StatusPayload {
  const StatusPayload({
    this.paperOut = 'unknown',
    this.paperNearEnd = 'unknown',
    this.coverOpen = 'unknown',
    this.cutterError = 'unknown',
    this.offline = 'unknown',
    this.drawerSignal = 'unknown',
  });

  final String paperOut;
  final String paperNearEnd;
  final String coverOpen;
  final String cutterError;
  final String offline;
  final String drawerSignal;

  factory StatusPayload.fromMap(Map<String, Object?> map) {
    String read(String key) {
      final raw = map[key];
      if (raw is String) {
        return raw;
      }
      if (raw is bool) {
        return raw ? 'yes' : 'no';
      }
      return 'unknown';
    }

    return StatusPayload(
      paperOut: read('paperOut'),
      paperNearEnd: read('paperNearEnd'),
      coverOpen: read('coverOpen'),
      cutterError: read('cutterError'),
      offline: read('offline'),
      drawerSignal: read('drawerSignal'),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'paperOut': paperOut,
      'paperNearEnd': paperNearEnd,
      'coverOpen': coverOpen,
      'cutterError': cutterError,
      'offline': offline,
      'drawerSignal': drawerSignal,
    };
  }
}

final class WritePayload {
  const WritePayload({required this.sessionId, required this.bytes});

  final String sessionId;
  final Uint8List bytes;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sessionId': sessionId,
      'bytes': bytes,
    };
  }
}

final class SessionPayload {
  const SessionPayload(this.sessionId);

  final String sessionId;

  Map<String, Object?> toMap() {
    return <String, Object?>{'sessionId': sessionId};
  }
}

final class OpenConnectionResponse {
  const OpenConnectionResponse({
    required this.sessionId,
    required this.capabilities,
  });

  final String sessionId;
  final CapabilityPayload capabilities;

  factory OpenConnectionResponse.fromMap(Map<String, Object?> map) {
    final rawSessionId = map['sessionId'];
    if (rawSessionId is! String || rawSessionId.isEmpty) {
      throw PlatformException(
        code: 'invalid_response',
        message: 'sessionId ausente na resposta de openConnection.',
      );
    }

    final rawCapabilities = map['capabilities'];
    final capabilitiesMap = rawCapabilities is Map<Object?, Object?>
        ? rawCapabilities.map((Object? key, Object? value) {
            return MapEntry('$key', value);
          })
        : <String, Object?>{};

    return OpenConnectionResponse(
      sessionId: rawSessionId,
      capabilities: CapabilityPayload.fromMap(capabilitiesMap),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sessionId': sessionId,
      'capabilities': capabilities.toMap(),
    };
  }
}

/// Contrato tipado de host API (implementação compatível com MethodChannel).
class NativeTransportApi {
  NativeTransportApi({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('escpos_printer/native_transport');

  final MethodChannel _channel;

  Future<OpenConnectionResponse> openConnection(EndpointPayload endpoint) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'openConnection',
      endpoint.toMap(),
    );
    if (raw == null) {
      throw PlatformException(
        code: 'invalid_response',
        message: 'Resposta vazia para openConnection.',
      );
    }

    final map = raw.map((Object? key, Object? value) {
      return MapEntry('$key', value);
    });
    return OpenConnectionResponse.fromMap(map);
  }

  Future<void> write(WritePayload payload) async {
    await _channel.invokeMethod<void>('write', payload.toMap());
  }

  Future<StatusPayload> readStatus(SessionPayload payload) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'readStatus',
      payload.toMap(),
    );
    if (raw == null) {
      return const StatusPayload();
    }

    final map = raw.map((Object? key, Object? value) {
      return MapEntry('$key', value);
    });
    return StatusPayload.fromMap(map);
  }

  Future<void> closeConnection(SessionPayload payload) async {
    await _channel.invokeMethod<void>('closeConnection', payload.toMap());
  }

  Future<CapabilityPayload> getCapabilities(SessionPayload payload) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'getCapabilities',
      payload.toMap(),
    );
    if (raw == null) {
      return const CapabilityPayload();
    }

    final map = raw.map((Object? key, Object? value) {
      return MapEntry('$key', value);
    });
    final inner = map['capabilities'];
    if (inner is Map<Object?, Object?>) {
      return CapabilityPayload.fromMap(inner.map((Object? key, Object? value) {
        return MapEntry('$key', value);
      }));
    }

    return CapabilityPayload.fromMap(map);
  }
}

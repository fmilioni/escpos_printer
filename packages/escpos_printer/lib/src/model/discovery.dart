import 'package:flutter/foundation.dart';

import 'endpoints.dart';

enum DiscoveryTransport { wifi, usb, bluetooth }

@immutable
final class PrinterDiscoveryOptions {
  const PrinterDiscoveryOptions({
    this.transports = const <DiscoveryTransport>{
      DiscoveryTransport.wifi,
      DiscoveryTransport.usb,
      DiscoveryTransport.bluetooth,
    },
    this.timeout = const Duration(seconds: 8),
    this.wifiPort = 9100,
    this.wifiHostTimeout = const Duration(milliseconds: 250),
    this.wifiMaxConcurrentHosts = 64,
    this.wifiCidrs = const <String>[],
  }) : assert(wifiPort > 0 && wifiPort <= 65535),
       assert(wifiMaxConcurrentHosts > 0);

  final Set<DiscoveryTransport> transports;
  final Duration timeout;
  final int wifiPort;
  final Duration wifiHostTimeout;
  final int wifiMaxConcurrentHosts;
  final List<String> wifiCidrs;
}

@immutable
final class DiscoveredPrinter {
  const DiscoveredPrinter({
    required this.id,
    required this.transport,
    required this.endpoint,
    this.name,
    this.vendorId,
    this.productId,
    this.comPort,
    this.serialNumber,
    this.address,
    this.host,
    this.isPaired,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String? name;
  final DiscoveryTransport transport;
  final PrinterEndpoint endpoint;
  final int? vendorId;
  final int? productId;
  final String? comPort;
  final String? serialNumber;
  final String? address;
  final String? host;
  final bool? isPaired;
  final Map<String, Object?> metadata;

  String dedupeKey() {
    switch (transport) {
      case DiscoveryTransport.wifi:
        return 'wifi:${host ?? _wifiHost}:$_wifiPort';
      case DiscoveryTransport.usb:
        if ((comPort ?? '').isNotEmpty) {
          return 'usb:com:${comPort!.toUpperCase()}';
        }
        if ((serialNumber ?? '').isNotEmpty) {
          return 'usb:serial:$serialNumber';
        }
        if (vendorId != null && productId != null) {
          return 'usb:vidpid:${vendorId!}:${productId!}';
        }
        return 'usb:$id';
      case DiscoveryTransport.bluetooth:
        if ((address ?? '').isNotEmpty) {
          return 'bluetooth:$address';
        }
        return 'bluetooth:$id';
    }
  }

  String get _wifiHost {
    final endpointValue = endpoint;
    if (endpointValue is WifiEndpoint) {
      return endpointValue.host;
    }
    return '';
  }

  int get _wifiPort {
    final endpointValue = endpoint;
    if (endpointValue is WifiEndpoint) {
      return endpointValue.port;
    }
    return 0;
  }
}

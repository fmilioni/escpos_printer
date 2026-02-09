import '../model/discovery.dart';
import '../transport/native_transport_bridge.dart';
import 'wifi_discovery.dart';

class PrinterDiscoveryService {
  PrinterDiscoveryService({
    NativeTransportBridge? nativeBridge,
    WifiDiscovery? wifiDiscovery,
  }) : _nativeBridge = nativeBridge ?? NativeTransportBridge(),
       _wifiDiscovery = wifiDiscovery ?? const WifiSubnetDiscovery();

  final NativeTransportBridge _nativeBridge;
  final WifiDiscovery _wifiDiscovery;

  Future<List<DiscoveredPrinter>> search(
    PrinterDiscoveryOptions options,
  ) async {
    final results = <DiscoveredPrinter>[];

    if (options.transports.contains(DiscoveryTransport.wifi)) {
      try {
        results.addAll(await _wifiDiscovery.search(options));
      } catch (_) {
        // best effort
      }
    }

    final nativeTransports = options.transports
        .where((transport) => transport != DiscoveryTransport.wifi)
        .toSet();
    if (nativeTransports.isNotEmpty) {
      try {
        results.addAll(
          await _nativeBridge.searchNativePrinters(
            transports: nativeTransports,
            timeout: options.timeout,
            wifiPort: options.wifiPort,
            wifiCidrs: options.wifiCidrs,
          ),
        );
      } catch (_) {
        // best effort
      }
    }

    final deduped = <String, DiscoveredPrinter>{};
    for (final item in results) {
      deduped[item.dedupeKey()] = item;
    }

    final ordered = deduped.values.toList(growable: false)..sort(_compare);
    return List<DiscoveredPrinter>.unmodifiable(ordered);
  }

  int _compare(DiscoveredPrinter a, DiscoveredPrinter b) {
    final byTransport = a.transport.index.compareTo(b.transport.index);
    if (byTransport != 0) {
      return byTransport;
    }

    final nameA = (a.name ?? '').toLowerCase();
    final nameB = (b.name ?? '').toLowerCase();
    final byName = nameA.compareTo(nameB);
    if (byName != 0) {
      return byName;
    }

    return a.id.compareTo(b.id);
  }
}

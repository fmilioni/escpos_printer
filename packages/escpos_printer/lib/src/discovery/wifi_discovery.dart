import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../model/discovery.dart';
import '../model/endpoints.dart';

abstract interface class WifiDiscovery {
  Future<List<DiscoveredPrinter>> search(PrinterDiscoveryOptions options);
}

final class WifiSubnetDiscovery implements WifiDiscovery {
  const WifiSubnetDiscovery();

  @override
  Future<List<DiscoveredPrinter>> search(
    PrinterDiscoveryOptions options,
  ) async {
    final candidates = await _buildCandidates(options);
    if (candidates.isEmpty) {
      return const <DiscoveredPrinter>[];
    }

    final maxConcurrent = options.wifiMaxConcurrentHosts.clamp(1, 512);
    final queue = Queue<String>.from(candidates);
    final found = <DiscoveredPrinter>[];
    var active = 0;
    var done = false;

    final completer = Completer<void>();

    void schedule() {
      if (done) {
        return;
      }

      while (active < maxConcurrent && queue.isNotEmpty && !done) {
        final host = queue.removeFirst();
        active++;
        _probeHost(host, options)
            .then((printer) {
              if (printer != null) {
                found.add(printer);
              }
            })
            .whenComplete(() {
              active--;
              if (queue.isEmpty && active == 0 && !completer.isCompleted) {
                completer.complete();
              } else {
                schedule();
              }
            });
      }
    }

    schedule();

    try {
      await completer.future.timeout(options.timeout);
    } on TimeoutException {
      done = true;
    }

    found.sort((a, b) => a.id.compareTo(b.id));
    return List<DiscoveredPrinter>.unmodifiable(found);
  }

  Future<List<String>> _buildCandidates(PrinterDiscoveryOptions options) async {
    final cidrs = options.wifiCidrs.isNotEmpty
        ? options.wifiCidrs
        : await _inferLocalCidrs();
    if (cidrs.isEmpty) {
      return const <String>[];
    }

    final hosts = <String>{};
    for (final cidr in cidrs) {
      final parsed = _parse24(cidr);
      if (parsed == null) {
        continue;
      }
      for (var host = 1; host <= 254; host++) {
        hosts.add('${parsed.$1}.${parsed.$2}.${parsed.$3}.$host');
      }
    }

    return hosts.toList(growable: false);
  }

  Future<List<String>> _inferLocalCidrs() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final cidrs = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final bytes = address.rawAddress;
        if (bytes.length != 4) {
          continue;
        }
        cidrs.add('${bytes[0]}.${bytes[1]}.${bytes[2]}.0/24');
      }
    }
    return cidrs.toList(growable: false);
  }

  (int, int, int)? _parse24(String cidr) {
    final slashIndex = cidr.indexOf('/');
    final ipPart = slashIndex >= 0 ? cidr.substring(0, slashIndex) : cidr;
    final maskPart = slashIndex >= 0 ? cidr.substring(slashIndex + 1) : '24';
    if (maskPart.trim() != '24') {
      return null;
    }

    final chunks = ipPart.split('.');
    if (chunks.length != 4) {
      return null;
    }
    final octets = chunks.map((chunk) => int.tryParse(chunk.trim())).toList();
    if (octets.any((value) => value == null || value < 0 || value > 255)) {
      return null;
    }
    return (octets[0]!, octets[1]!, octets[2]!);
  }

  Future<DiscoveredPrinter?> _probeHost(
    String host,
    PrinterDiscoveryOptions options,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        options.wifiPort,
        timeout: options.wifiHostTimeout,
      );
      await socket.close();
      return DiscoveredPrinter(
        id: 'wifi:$host:${options.wifiPort}',
        name: 'Wi-Fi $host',
        transport: DiscoveryTransport.wifi,
        endpoint: WifiEndpoint(host, port: options.wifiPort),
        host: host,
        metadata: <String, Object?>{'port': options.wifiPort},
      );
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }
}

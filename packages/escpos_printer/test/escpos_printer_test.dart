import 'dart:convert';
import 'dart:typed_data';

import 'package:escpos_printer/escpos_printer.dart';
import 'package:escpos_printer/src/discovery/printer_discovery_service.dart';
import 'package:escpos_printer/src/discovery/wifi_discovery.dart';
import 'package:escpos_printer_platform_interface/escpos_printer_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MustacheRenderer', () {
    test('renders variables, each, and if', () {
      const renderer = MustacheRenderer();
      final output = renderer.render(
        'Store: {{store}}\n{{#each items}}- {{this}}\n{{/each}}{{#if hasCoupon}}COUPON{{/if}}',
        <String, Object?>{
          'store': 'Mini Market',
          'items': <String>['Coffee', 'Bread'],
          'hasCoupon': true,
        },
      );

      expect(output, 'Store: Mini Market\n- Coffee\n- Bread\nCOUPON');
    });

    test('throws when required variable is missing', () {
      const renderer = MustacheRenderer();
      expect(
        () => renderer.render('Total: {{price}}', <String, Object?>{}),
        throwsA(isA<TemplateRenderException>()),
      );
    });
  });

  group('EscTplParser', () {
    test('parses template with row and col', () {
      const parser = EscTplParser();
      final ops = parser.parse('''
@text align=center bold=true Store XPTO
@row
  @col flex=2 align=left Product
  @col flex=1 align=right 10.00
@endrow
@cut mode=partial
''');

      expect(ops.length, 3);
      expect(ops[0], isA<TextOp>());
      expect(ops[1], isA<RowOp>());
      expect(ops[2], isA<CutOp>());

      final row = ops[1] as RowOp;
      expect(row.columns.length, 2);
      expect(row.columns.first.flex, 2);
      expect(row.columns.last.align, TextAlign.right);
    });

    test('throws for row block without closing', () {
      const parser = EscTplParser();
      expect(
        () => parser.parse('@row\n@col flex=1 A'),
        throwsA(isA<TemplateParseException>()),
      );
    });
  });

  group('DefaultTransportFactory', () {
    test('routes USB and Bluetooth to native transports', () async {
      final bridge = FakeNativeTransportBridge();
      final factory = DefaultTransportFactory(nativeBridge: bridge);

      final usbTransport = await factory.create(
        const UsbEndpoint(0x1234, 0x5678),
      );
      expect(usbTransport, isA<PlatformUsbTransport>());

      await usbTransport.connect();
      await usbTransport.write(<int>[0x1B, 0x40]);

      final bluetoothTransport = await factory.create(
        const BluetoothEndpoint('AA:BB:CC:DD:EE:FF'),
      );
      expect(bluetoothTransport, isA<PlatformBluetoothTransport>());

      await bluetoothTransport.connect();
      await bluetoothTransport.write(<int>[0x1D, 0x56, 0x00]);

      expect(bridge.openedEndpoints.length, 2);
      expect(bridge.writes.length, 2);
    });

    test('keeps Wi-Fi with Dart socket transport', () async {
      final factory = DefaultTransportFactory();
      final transport = await factory.create(const WifiEndpoint('127.0.0.1'));
      expect(transport, isA<WifiSocketTransport>());
    });
  });

  group('EscPosClient', () {
    test('sends WCP1252 code table by default for accented text', () async {
      final factory = FakeTransportFactory();
      final client = EscPosClient(transportFactory: factory);

      await client.connect(const WifiEndpoint('127.0.0.1'));
      await client.print(
        template: ReceiptTemplate.dsl((builder) {
          builder.text('FAÇADE RÉSUMÉ');
        }),
      );

      final payload = factory.lastPayload!;
      expect(
        _containsSequence(payload, <int>[0x1B, 0x40, 0x1B, 0x74, 0x10]),
        isTrue,
      );
      expect(
        _containsSequence(payload, latin1.encode('FAÇADE RÉSUMÉ')),
        isTrue,
      );
    });

    test('allows disabling code table in PrintOptions', () async {
      final factory = FakeTransportFactory();
      final client = EscPosClient(transportFactory: factory);

      await client.connect(const WifiEndpoint('127.0.0.1'));
      await client.print(
        template: ReceiptTemplate.dsl((builder) {
          builder.text('Test');
        }),
        printOptions: const PrintOptions(codeTable: null),
      );

      final payload = factory.lastPayload!;
      expect(_containsSequence(payload, <int>[0x1B, 0x74]), isFalse);
    });

    test('prints string template with variables', () async {
      final factory = FakeTransportFactory();
      final client = EscPosClient(transportFactory: factory);

      await client.connect(const WifiEndpoint('127.0.0.1'));
      final result = await client.printFromString(
        template: '@text Total: {{price}}\n@cut mode=full',
        variables: <String, Object?>{'price': '10.50'},
      );

      expect(result.bytesSent, greaterThan(0));
      expect(factory.lastPayload, isNotNull);
      expect(_containsAscii(factory.lastPayload!, 'Total: 10.50'), isTrue);
      expect(
        _containsSequence(factory.lastPayload!, <int>[0x1D, 0x56, 0x00]),
        isTrue,
      );
    });

    test('combines DSL with textTemplate and templateBlock', () async {
      final factory = FakeTransportFactory();
      final client = EscPosClient(transportFactory: factory);
      await client.connect(const WifiEndpoint('127.0.0.1'));

      final template = ReceiptTemplate.dsl((builder) {
        builder.text('HEADER', align: TextAlign.center, bold: true);
        builder.textTemplate(
          'Customer: {{name}}',
          vars: <String, Object?>{'name': 'Ana'},
        );
        builder.templateBlock(
          '''
@row
  @col flex=2 Product
  @col flex=1 align=right {{price}}
@endrow
@feed lines=1
''',
          vars: <String, Object?>{'price': '9.90'},
        );
        builder.cut(CutMode.partial);
      });

      await client.print(template: template);

      final payload = factory.lastPayload!;
      expect(_containsAscii(payload, 'HEADER'), isTrue);
      expect(_containsAscii(payload, 'Customer: Ana'), isTrue);
      expect(_containsAscii(payload, 'Product'), isTrue);
      expect(_containsAscii(payload, '9.90'), isTrue);
      expect(_containsSequence(payload, <int>[0x1B, 0x64, 0x01]), isTrue);
      expect(_containsSequence(payload, <int>[0x1D, 0x56, 0x01]), isTrue);
    });

    test('retries with reconnection when first write fails', () async {
      final factory = FakeTransportFactory(failFirstWrite: true);
      final client = EscPosClient(
        transportFactory: factory,
        reconnectPolicy: const ReconnectPolicy(maxAttempts: 2),
      );

      await client.connect(const WifiEndpoint('127.0.0.1'));
      await client.print(
        template: ReceiptTemplate.string('@text Reconnect test'),
      );

      expect(factory.createdTransports.length, greaterThanOrEqualTo(2));
      expect(factory.lastPayload, isNotNull);
      expect(_containsAscii(factory.lastPayload!, 'Reconnect test'), isTrue);
    });

    test(
      'generates bytes for qrcode, barcode, image, feed, cut, and drawer',
      () async {
        final factory = FakeTransportFactory();
        final client = EscPosClient(transportFactory: factory);
        await client.connect(const WifiEndpoint('127.0.0.1'));

        final template = ReceiptTemplate.dsl((builder) {
          builder.qrCode('pix-code', size: 4, align: TextAlign.center);
          builder.barcode('123456789012', type: BarcodeType.ean13);
          builder.imageRaster(
            Uint8List.fromList(<int>[0xFF, 0x00]),
            widthBytes: 1,
            heightDots: 2,
          );
          builder.feed(3);
          builder.cut(CutMode.full);
          builder.drawer(pin: DrawerPin.pin5, onMs: 100, offMs: 200);
        });

        await client.print(template: template);

        final payload = factory.lastPayload!;
        expect(
          _containsSequence(payload, <int>[0x1D, 0x28, 0x6B]),
          isTrue,
        ); // QR
        expect(
          _containsSequence(payload, <int>[0x1D, 0x6B]),
          isTrue,
        ); // Barcode
        expect(
          _containsSequence(payload, <int>[0x1D, 0x76, 0x30]),
          isTrue,
        ); // Image
        expect(
          _containsSequence(payload, <int>[0x1B, 0x64, 0x03]),
          isTrue,
        ); // Feed
        expect(
          _containsSequence(payload, <int>[0x1D, 0x56, 0x00]),
          isTrue,
        ); // Full cut
        expect(
          _containsSequence(payload, <int>[0x1B, 0x70, 0x01, 0x64, 0xC8]),
          isTrue,
        ); // Drawer
      },
    );
  });

  group('Discovery', () {
    test('aggregates Wi-Fi and native with stable-key deduplication', () async {
      final wifi = FakeWifiDiscovery(<DiscoveredPrinter>[
        DiscoveredPrinter(
          id: 'wifi-1',
          name: 'Printer A',
          transport: DiscoveryTransport.wifi,
          endpoint: const WifiEndpoint('192.168.0.10'),
          host: '192.168.0.10',
        ),
        DiscoveredPrinter(
          id: 'wifi-2-duplicado',
          name: 'Printer A (dup)',
          transport: DiscoveryTransport.wifi,
          endpoint: const WifiEndpoint('192.168.0.10'),
          host: '192.168.0.10',
        ),
      ]);

      final native = FakeDiscoveryBridge(<DiscoveredPrinter>[
        DiscoveredPrinter(
          id: 'usb-1',
          name: 'USB Printer',
          transport: DiscoveryTransport.usb,
          endpoint: const UsbEndpoint.serial(
            'COM5',
            vendorId: 0x1234,
            productId: 0x5678,
          ),
          comPort: 'COM5',
          vendorId: 0x1234,
          productId: 0x5678,
        ),
      ]);

      final service = PrinterDiscoveryService(
        nativeBridge: native,
        wifiDiscovery: wifi,
      );

      final result = await service.search(const PrinterDiscoveryOptions());

      expect(result.length, 2);
      expect(
        result
            .where((item) => item.transport == DiscoveryTransport.wifi)
            .length,
        1,
      );
      expect(
        result.where((item) => item.transport == DiscoveryTransport.usb).length,
        1,
      );
    });

    test('applies transport filter during search', () async {
      final wifi = FakeWifiDiscovery(<DiscoveredPrinter>[
        DiscoveredPrinter(
          id: 'wifi-1',
          transport: DiscoveryTransport.wifi,
          endpoint: const WifiEndpoint('192.168.0.20'),
          host: '192.168.0.20',
        ),
      ]);
      final native = FakeDiscoveryBridge(<DiscoveredPrinter>[
        DiscoveredPrinter(
          id: 'bt-1',
          transport: DiscoveryTransport.bluetooth,
          endpoint: const BluetoothEndpoint('AA:BB:CC:DD:EE:FF'),
          address: 'AA:BB:CC:DD:EE:FF',
          isPaired: true,
        ),
      ]);

      final service = PrinterDiscoveryService(
        nativeBridge: native,
        wifiDiscovery: wifi,
      );

      final onlyUsb = await service.search(
        const PrinterDiscoveryOptions(
          transports: <DiscoveryTransport>{DiscoveryTransport.usb},
        ),
      );
      expect(onlyUsb, isEmpty);

      final onlyWifi = await service.search(
        const PrinterDiscoveryOptions(
          transports: <DiscoveryTransport>{DiscoveryTransport.wifi},
        ),
      );
      expect(onlyWifi.length, 1);
      expect(onlyWifi.first.transport, DiscoveryTransport.wifi);
    });

    test('maps USB with COM + VID/PID to serial endpoint in bridge', () async {
      final bridge = NativeTransportBridge(
        api: FakeNativeTransportApi(<DiscoveredDevicePayload>[
          const DiscoveredDevicePayload(
            id: 'usb-com-3',
            name: 'POS USB',
            transport: 'usb',
            comPort: 'COM3',
            serialNumber: 'COM3',
            vendorId: 0x04B8,
            productId: 0x0E15,
          ),
        ]),
      );

      final devices = await bridge.searchNativePrinters(
        transports: const <DiscoveryTransport>{DiscoveryTransport.usb},
      );

      expect(devices.length, 1);
      final endpoint = devices.first.endpoint as UsbEndpoint;
      expect(endpoint.serialNumber, 'COM3');
      expect(endpoint.vendorId, 0x04B8);
      expect(endpoint.productId, 0x0E15);
    });
  });
}

bool _containsAscii(List<int> bytes, String value) {
  final needle = value.codeUnits;
  return _containsSequence(bytes, needle);
}

bool _containsSequence(List<int> bytes, List<int> sequence) {
  if (sequence.isEmpty) {
    return true;
  }
  if (sequence.length > bytes.length) {
    return false;
  }

  for (var i = 0; i <= bytes.length - sequence.length; i++) {
    var matched = true;
    for (var j = 0; j < sequence.length; j++) {
      if (bytes[i + j] != sequence[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return true;
    }
  }
  return false;
}

final class FakeTransportFactory implements TransportFactory {
  FakeTransportFactory({this.failFirstWrite = false});

  final bool failFirstWrite;

  final List<FakeTransport> createdTransports = <FakeTransport>[];
  bool _failureInjected = false;

  List<int>? get lastPayload {
    if (createdTransports.isEmpty) {
      return null;
    }
    for (var i = createdTransports.length - 1; i >= 0; i--) {
      final transport = createdTransports[i];
      if (transport.writes.isNotEmpty) {
        return transport.writes.last;
      }
    }
    return null;
  }

  @override
  Future<PrinterTransport> create(PrinterEndpoint endpoint) async {
    final shouldFail = failFirstWrite && !_failureInjected;
    _failureInjected = _failureInjected || shouldFail;

    final transport = FakeTransport(shouldFailFirstWrite: shouldFail);
    createdTransports.add(transport);
    return transport;
  }
}

final class FakeTransport implements PrinterTransport {
  FakeTransport({required this.shouldFailFirstWrite});

  final bool shouldFailFirstWrite;
  final List<List<int>> writes = <List<int>>[];
  bool _connected = false;
  String? _sessionId;

  @override
  String? get sessionId => _sessionId;

  @override
  bool get isConnected => _connected;

  @override
  PrinterCapabilities get capabilities =>
      const PrinterCapabilities(supportsRealtimeStatus: true);

  @override
  Future<void> connect() async {
    _connected = true;
    _sessionId = 'fake-session';
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _sessionId = null;
  }

  @override
  Future<PrinterStatus> getStatus() async {
    return const PrinterStatus(
      paperOut: TriState.no,
      paperNearEnd: TriState.unknown,
      coverOpen: TriState.no,
      cutterError: TriState.no,
      offline: TriState.no,
      drawerSignal: TriState.unknown,
    );
  }

  @override
  Future<void> write(List<int> data) async {
    if (!_connected) {
      throw ConnectionException('Fake transport disconnected.');
    }

    if (shouldFailFirstWrite && writes.isEmpty) {
      _connected = false;
      throw TransportException('Simulated failure on first write.');
    }

    writes.add(List<int>.from(data));
  }
}

final class FakeNativeTransportBridge extends NativeTransportBridge {
  final List<PrinterEndpoint> openedEndpoints = <PrinterEndpoint>[];
  final Map<String, List<int>> writes = <String, List<int>>{};

  int _sessionCounter = 0;

  @override
  Future<NativeConnectionSession> openConnection(
    PrinterEndpoint endpoint,
  ) async {
    openedEndpoints.add(endpoint);
    final sessionId = 'session-${_sessionCounter++}';
    return NativeConnectionSession(
      sessionId: sessionId,
      capabilities: const PrinterCapabilities(supportsRealtimeStatus: false),
    );
  }

  @override
  Future<void> write(String sessionId, List<int> bytes) async {
    writes[sessionId] = List<int>.from(bytes);
  }

  @override
  Future<PrinterStatus> readStatus(String sessionId) async {
    return const PrinterStatus.unknown();
  }

  @override
  Future<PrinterCapabilities> getCapabilities(String sessionId) async {
    return const PrinterCapabilities(supportsRealtimeStatus: false);
  }

  @override
  Future<void> closeConnection(String sessionId) async {}
}

final class FakeDiscoveryBridge extends NativeTransportBridge {
  FakeDiscoveryBridge(this.results);

  final List<DiscoveredPrinter> results;

  @override
  Future<List<DiscoveredPrinter>> searchNativePrinters({
    required Set<DiscoveryTransport> transports,
    Duration timeout = const Duration(seconds: 8),
    int wifiPort = 9100,
    List<String> wifiCidrs = const <String>[],
  }) async {
    return results
        .where((device) => transports.contains(device.transport))
        .toList(growable: false);
  }
}

final class FakeWifiDiscovery implements WifiDiscovery {
  FakeWifiDiscovery(this.results);

  final List<DiscoveredPrinter> results;

  @override
  Future<List<DiscoveredPrinter>> search(
    PrinterDiscoveryOptions options,
  ) async {
    return results
        .where((device) => options.transports.contains(device.transport))
        .toList(growable: false);
  }
}

final class FakeNativeTransportApi extends NativeTransportApi {
  FakeNativeTransportApi(this.discoveredDevices);

  final List<DiscoveredDevicePayload> discoveredDevices;

  @override
  Future<List<DiscoveredDevicePayload>> searchPrinters(
    DiscoveryRequestPayload payload,
  ) async {
    return discoveredDevices;
  }
}

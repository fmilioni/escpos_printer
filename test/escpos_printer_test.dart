import 'dart:typed_data';

import 'package:escpos_printer/escpos_printer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MustacheRenderer', () {
    test('renderiza variaveis, each e if', () {
      const renderer = MustacheRenderer();
      final output = renderer.render(
        'Loja: {{store}}\n{{#each items}}- {{this}}\n{{/each}}{{#if hasCoupon}}CUPOM{{/if}}',
        <String, Object?>{
          'store': 'Mercadinho',
          'items': <String>['Cafe', 'Pao'],
          'hasCoupon': true,
        },
      );

      expect(output, 'Loja: Mercadinho\n- Cafe\n- Pao\nCUPOM');
    });

    test('lanca erro quando variavel obrigatoria nao existe', () {
      const renderer = MustacheRenderer();
      expect(
        () => renderer.render('Total: {{price}}', <String, Object?>{}),
        throwsA(isA<TemplateRenderException>()),
      );
    });
  });

  group('EscTplParser', () {
    test('parseia template com row e col', () {
      const parser = EscTplParser();
      final ops = parser.parse('''
@text align=center bold=true Loja XPTO
@row
  @col flex=2 align=left Produto
  @col flex=1 align=right 10,00
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

    test('lanca erro para bloco row sem fechamento', () {
      const parser = EscTplParser();
      expect(
        () => parser.parse('@row\n@col flex=1 A'),
        throwsA(isA<TemplateParseException>()),
      );
    });
  });

  group('EscPosClient', () {
    test('imprime template string com variaveis', () async {
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

    test('combina DSL com textTemplate e templateBlock', () async {
      final factory = FakeTransportFactory();
      final client = EscPosClient(transportFactory: factory);
      await client.connect(const WifiEndpoint('127.0.0.1'));

      final template = ReceiptTemplate.dsl((builder) {
        builder.text('CABECALHO', align: TextAlign.center, bold: true);
        builder.textTemplate(
          'Cliente: {{name}}',
          vars: <String, Object?>{'name': 'Ana'},
        );
        builder.templateBlock(
          '''
@row
  @col flex=2 Produto
  @col flex=1 align=right {{price}}
@endrow
@feed lines=1
''',
          vars: <String, Object?>{'price': '9,90'},
        );
        builder.cut(CutMode.partial);
      });

      await client.print(template: template);

      final payload = factory.lastPayload!;
      expect(_containsAscii(payload, 'CABECALHO'), isTrue);
      expect(_containsAscii(payload, 'Cliente: Ana'), isTrue);
      expect(_containsAscii(payload, 'Produto'), isTrue);
      expect(_containsAscii(payload, '9,90'), isTrue);
      expect(_containsSequence(payload, <int>[0x1B, 0x64, 0x01]), isTrue);
      expect(_containsSequence(payload, <int>[0x1D, 0x56, 0x01]), isTrue);
    });

    test('faz retry com reconexao quando primeira escrita falha', () async {
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
      'gera bytes para qrcode, barcode, image, feed, cut e drawer',
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

  @override
  bool get isConnected => _connected;

  @override
  PrinterCapabilities get capabilities =>
      const PrinterCapabilities(supportsRealtimeStatus: true);

  @override
  Future<void> connect() async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
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
      throw ConnectionException('Fake transport desconectado.');
    }

    if (shouldFailFirstWrite && writes.isEmpty) {
      _connected = false;
      throw TransportException('Falha simulada na primeira escrita.');
    }

    writes.add(List<int>.from(data));
  }
}

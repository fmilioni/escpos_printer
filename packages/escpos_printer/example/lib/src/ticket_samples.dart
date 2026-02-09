import 'package:escpos_printer/escpos_printer.dart';

import 'sample_image.dart';

final class DemoTicketItem {
  const DemoTicketItem({required this.name, required this.price});

  final String name;
  final String price;
}

final class DemoTicketData {
  const DemoTicketData({
    required this.store,
    required this.customer,
    required this.items,
    required this.total,
    required this.pixPayload,
    required this.barcodeValue,
    this.shouldCut = true,
  });

  final String store;
  final String customer;
  final List<DemoTicketItem> items;
  final String total;
  final String pixPayload;
  final String barcodeValue;
  final bool shouldCut;
}

DemoTicketData defaultDemoTicketData() {
  return DemoTicketData(
    store: 'Loja Exemplo ESC/POS',
    customer: 'Cliente Demo',
    items: const <DemoTicketItem>[
      DemoTicketItem(name: 'Cafe', price: '9,90'),
      DemoTicketItem(name: 'Pao de queijo', price: '6,50'),
      DemoTicketItem(name: 'Suco', price: '7,00'),
    ],
    total: '23,40',
    pixPayload:
        '00020101021226890014br.gov.bcb.pix2567pix.exemplo.com/qr/abc123520400005303986540523.405802BR5925LOJA EXEMPLO ESCPOS6009SAO PAULO62070503***6304A1B2',
    barcodeValue: '123456789012',
    shouldCut: true,
  );
}

List<DemoTicketItem> parseDemoItems(String raw) {
  final items = <DemoTicketItem>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }

    final parts = trimmed.split(RegExp(r'\s*[|=:;-]\s*'));
    if (parts.length >= 2) {
      final name = parts.first.trim();
      final price = parts.sublist(1).join(' ').trim();
      if (name.isNotEmpty && price.isNotEmpty) {
        items.add(DemoTicketItem(name: name, price: price));
      }
      continue;
    }

    items.add(DemoTicketItem(name: trimmed, price: '0,00'));
  }

  if (items.isEmpty) {
    return defaultDemoTicketData().items;
  }

  return List<DemoTicketItem>.unmodifiable(items);
}

Map<String, Object?> buildTemplateVariables(DemoTicketData data) {
  return <String, Object?>{
    'store': data.store,
    'customer': data.customer,
    'total': data.total,
    'pixPayload': data.pixPayload,
    'barcodeValue': data.barcodeValue,
    'shouldCut': data.shouldCut,
    'items': data.items
        .map(
          (item) => <String, Object?>{'name': item.name, 'price': item.price},
        )
        .toList(growable: false),
  };
}

ReceiptTemplate buildDslTicketTemplate(
  DemoTicketData data, {
  SampleRasterImage? image,
}) {
  final raster = image ?? buildSampleRasterImage();

  return ReceiptTemplate.dsl((b) {
    b.text(
      data.store,
      bold: true,
      widthScale: 2,
      heightScale: 2,
      align: TextAlign.center,
    );
    b.text('Cliente: ${data.customer}', underline: true, align: TextAlign.left);
    b.text('DEMO INVERTIDO', invert: true, align: TextAlign.center);
    b.text(
      'Fonte B 2x1',
      font: FontType.b,
      widthScale: 2,
      heightScale: 1,
      align: TextAlign.left,
    );
    b.textTemplate(
      'Total parcial: {{total}}',
      vars: <String, Object?>{'total': data.total},
      bold: true,
      align: TextAlign.right,
    );

    b.row(<RowColumnSpec>[
      b.col('Item', flex: 3, bold: true),
      b.col('Valor', flex: 1, align: TextAlign.right, bold: true),
    ]);

    for (final item in data.items) {
      b.row(<RowColumnSpec>[
        b.col(item.name, flex: 3),
        b.col(item.price, flex: 1, align: TextAlign.right),
      ]);
    }

    b.row(<RowColumnSpec>[
      b.col('TOTAL', flex: 2, bold: true),
      b.col(data.total, flex: 1, align: TextAlign.right, bold: true),
    ]);

    b.qrCode(data.pixPayload, size: 5, align: TextAlign.center);
    b.barcode(
      data.barcodeValue,
      type: BarcodeType.code128,
      height: 90,
      align: TextAlign.center,
    );
    b.imageRaster(
      raster.rasterData,
      widthBytes: raster.widthBytes,
      heightDots: raster.heightDots,
      mode: 0,
      align: TextAlign.center,
    );
    b.feed(2);
    b.cut(CutMode.partial);
    b.drawer(pin: DrawerPin.pin2, onMs: 120, offMs: 240);
  });
}

String buildEscTplTicketString({required SampleRasterImage image}) {
  return '''
@text align=center bold=true width=2 height=2 {{store}}
@text underline=true Cliente: {{customer}}
@text invert=true align=center DEMO INVERTIDO
@text font=b width=2 height=1 Fonte B 2x1
@row
  @col flex=3 bold=true Item
  @col flex=1 align=right bold=true Valor
@endrow
{{#each items}}
@row
  @col flex=3 {{name}}
  @col flex=1 align=right {{price}}
@endrow
{{/each}}
@text align=right bold=true TOTAL: {{total}}
@qrcode size=5 align=center {{pixPayload}}
@barcode type=code128 height=90 align=center {{barcodeValue}}
@image widthBytes=${image.widthBytes} heightDots=${image.heightDots} mode=0 align=center ${image.base64Data}
@feed lines=2
{{#if shouldCut}}
@cut mode=full
{{/if}}
@drawer pin=5 on=110 off=220
''';
}

ReceiptTemplate buildHybridTicketTemplate(
  DemoTicketData data, {
  SampleRasterImage? image,
}) {
  final raster = image ?? buildSampleRasterImage();
  final vars = <String, Object?>{
    ...buildTemplateVariables(data),
    'imageWidthBytes': raster.widthBytes,
    'imageHeightDots': raster.heightDots,
    'imageBase64': raster.base64Data,
  };

  return ReceiptTemplate.dsl((b) {
    b.text('TICKET HIBRIDO', bold: true, align: TextAlign.center);
    b.textTemplate(
      'Loja: {{store}}',
      vars: <String, Object?>{'store': data.store},
      underline: true,
    );
    b.templateBlock('''
@row
  @col flex=3 bold=true Item
  @col flex=1 align=right bold=true Valor
@endrow
{{#each items}}
@row
  @col flex=3 {{name}}
  @col flex=1 align=right {{price}}
@endrow
{{/each}}
@qrcode size=4 align=center {{pixPayload}}
@barcode type=code39 height=70 align=center {{barcodeValue}}
@image widthBytes={{imageWidthBytes}} heightDots={{imageHeightDots}} mode=1 align=center {{imageBase64}}
@feed lines=1
{{#if shouldCut}}
@cut mode=partial
{{/if}}
@drawer pin=2 on=100 off=180
''', vars: vars);
  });
}

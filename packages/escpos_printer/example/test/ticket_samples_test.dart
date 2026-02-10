import 'package:escpos_printer/escpos_printer.dart';
import 'package:escpos_printer_example/src/sample_image.dart';
import 'package:escpos_printer_example/src/ticket_samples.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DSL sample generates core operations', () {
    final data = defaultDemoTicketData();
    final template = buildDslTicketTemplate(data);

    expect(template, isA<DslReceiptTemplate>());
    final ops = (template as DslReceiptTemplate).ops;

    expect(ops.any((op) => op is TextOp), isTrue);
    expect(ops.any((op) => op is RowOp), isTrue);
    expect(ops.any((op) => op is QrCodeOp), isTrue);
    expect(ops.any((op) => op is BarcodeOp), isTrue);
    expect(ops.any((op) => op is ImageOp), isTrue);
    expect(ops.any((op) => op is FeedOp), isTrue);
    expect(ops.any((op) => op is CutOp), isTrue);
    expect(ops.any((op) => op is DrawerKickOp), isTrue);
  });

  test('EscTpl sample contains expected commands and placeholders', () {
    final image = buildSampleRasterImage(widthBytes: 2, heightDots: 2);
    final template = buildEscTplTicketString(image: image);

    expect(template, contains('@text'));
    expect(template, contains('@row'));
    expect(template, contains('@qrcode'));
    expect(template, contains('@barcode'));
    expect(template, contains('@image'));
    expect(template, contains('@feed'));
    expect(template, contains('@cut'));
    expect(template, contains('@drawer'));
    expect(template, contains('{{#each items}}'));
    expect(template, contains('{{#if shouldCut}}'));
  });

  test('parseDemoItems converts text into item list', () {
    final items = parseDemoItems('Coffee=9.90\nCheese bread=6.50');

    expect(items.length, 2);
    expect(items[0].name, 'Coffee');
    expect(items[0].price, '9.90');
    expect(items[1].name, 'Cheese bread');
    expect(items[1].price, '6.50');
  });
}

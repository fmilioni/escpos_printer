import 'package:flutter/foundation.dart';

import '../model/options.dart';

enum FontType { a, b }

enum BarcodeType { upca, upce, ean13, ean8, code39, code128 }

@immutable
final class ReceiptTextStyle {
  const ReceiptTextStyle({
    this.bold = false,
    this.underline = false,
    this.invert = false,
    this.font = FontType.a,
    this.widthScale = 1,
    this.heightScale = 1,
    this.align = TextAlign.left,
  }) : assert(widthScale >= 1 && widthScale <= 8),
       assert(heightScale >= 1 && heightScale <= 8);

  final bool bold;
  final bool underline;
  final bool invert;
  final FontType font;
  final int widthScale;
  final int heightScale;
  final TextAlign align;

  static const defaults = ReceiptTextStyle();
}

@immutable
sealed class PrintOp {
  const PrintOp();
}

@immutable
final class TextOp extends PrintOp {
  const TextOp(this.text, {this.style = ReceiptTextStyle.defaults});

  final String text;
  final ReceiptTextStyle style;
}

@immutable
final class RowColumnSpec {
  const RowColumnSpec({
    required this.text,
    this.flex = 1,
    this.align = TextAlign.left,
    this.style = ReceiptTextStyle.defaults,
  }) : assert(flex > 0);

  final String text;
  final int flex;
  final TextAlign align;
  final ReceiptTextStyle style;
}

@immutable
final class RowOp extends PrintOp {
  const RowOp(this.columns) : assert(columns.length > 0);

  final List<RowColumnSpec> columns;
}

@immutable
final class QrCodeOp extends PrintOp {
  const QrCodeOp(this.data, {this.size = 6, this.align = TextAlign.left})
    : assert(size >= 1 && size <= 16);

  final String data;
  final int size;
  final TextAlign align;
}

@immutable
final class BarcodeOp extends PrintOp {
  const BarcodeOp(
    this.data, {
    this.type = BarcodeType.code39,
    this.height = 80,
    this.align = TextAlign.left,
  }) : assert(height >= 1 && height <= 255);

  final String data;
  final BarcodeType type;
  final int height;
  final TextAlign align;
}

@immutable
final class ImageOp extends PrintOp {
  const ImageOp({
    required this.rasterData,
    required this.widthBytes,
    required this.heightDots,
    this.mode = 0,
    this.align = TextAlign.left,
  }) : assert(mode >= 0 && mode <= 3),
       assert(widthBytes > 0),
       assert(heightDots > 0);

  final Uint8List rasterData;
  final int widthBytes;
  final int heightDots;
  final int mode;
  final TextAlign align;
}

@immutable
final class FeedOp extends PrintOp {
  const FeedOp(this.lines) : assert(lines >= 0 && lines <= 255);

  final int lines;
}

@immutable
final class CutOp extends PrintOp {
  const CutOp(this.mode);

  final CutMode mode;
}

@immutable
final class DrawerKickOp extends PrintOp {
  const DrawerKickOp({
    this.pin = DrawerPin.pin2,
    this.onMs = 120,
    this.offMs = 240,
  }) : assert(onMs >= 0 && onMs <= 255),
       assert(offMs >= 0 && offMs <= 255);

  final DrawerPin pin;
  final int onMs;
  final int offMs;
}

@immutable
final class TextTemplateOp extends PrintOp {
  const TextTemplateOp(
    this.template, {
    this.vars = const <String, Object?>{},
    this.style = ReceiptTextStyle.defaults,
  });

  final String template;
  final Map<String, Object?> vars;
  final ReceiptTextStyle style;
}

@immutable
final class TemplateBlockOp extends PrintOp {
  const TemplateBlockOp(this.template, {this.vars = const <String, Object?>{}});

  final String template;
  final Map<String, Object?> vars;
}

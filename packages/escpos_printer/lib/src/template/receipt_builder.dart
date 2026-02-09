import 'dart:typed_data';

import '../model/options.dart';
import 'operations.dart';

final class ReceiptBuilder {
  final List<PrintOp> _ops = <PrintOp>[];

  void text(
    String value, {
    bool bold = false,
    bool underline = false,
    bool invert = false,
    FontType font = FontType.a,
    int widthScale = 1,
    int heightScale = 1,
    TextAlign align = TextAlign.left,
  }) {
    _ops.add(
      TextOp(
        value,
        style: ReceiptTextStyle(
          bold: bold,
          underline: underline,
          invert: invert,
          font: font,
          widthScale: widthScale,
          heightScale: heightScale,
          align: align,
        ),
      ),
    );
  }

  void textTemplate(
    String template, {
    Map<String, Object?> vars = const <String, Object?>{},
    bool bold = false,
    bool underline = false,
    bool invert = false,
    FontType font = FontType.a,
    int widthScale = 1,
    int heightScale = 1,
    TextAlign align = TextAlign.left,
  }) {
    _ops.add(
      TextTemplateOp(
        template,
        vars: vars,
        style: ReceiptTextStyle(
          bold: bold,
          underline: underline,
          invert: invert,
          font: font,
          widthScale: widthScale,
          heightScale: heightScale,
          align: align,
        ),
      ),
    );
  }

  void templateBlock(
    String template, {
    Map<String, Object?> vars = const <String, Object?>{},
  }) {
    _ops.add(TemplateBlockOp(template, vars: vars));
  }

  void row(List<RowColumnSpec> columns) {
    _ops.add(RowOp(List<RowColumnSpec>.unmodifiable(columns)));
  }

  RowColumnSpec col(
    String text, {
    int flex = 1,
    TextAlign align = TextAlign.left,
    bool bold = false,
    bool underline = false,
    bool invert = false,
    FontType font = FontType.a,
    int widthScale = 1,
    int heightScale = 1,
  }) {
    return RowColumnSpec(
      text: text,
      flex: flex,
      align: align,
      style: ReceiptTextStyle(
        bold: bold,
        underline: underline,
        invert: invert,
        font: font,
        widthScale: widthScale,
        heightScale: heightScale,
        align: align,
      ),
    );
  }

  void qrCode(String data, {int size = 6, TextAlign align = TextAlign.left}) {
    _ops.add(QrCodeOp(data, size: size, align: align));
  }

  void barcode(
    String data, {
    BarcodeType type = BarcodeType.code39,
    int height = 80,
    TextAlign align = TextAlign.left,
  }) {
    _ops.add(BarcodeOp(data, type: type, height: height, align: align));
  }

  void imageRaster(
    Uint8List rasterData, {
    required int widthBytes,
    required int heightDots,
    int mode = 0,
    TextAlign align = TextAlign.left,
  }) {
    _ops.add(
      ImageOp(
        rasterData: rasterData,
        widthBytes: widthBytes,
        heightDots: heightDots,
        mode: mode,
        align: align,
      ),
    );
  }

  void feed([int lines = 1]) {
    _ops.add(FeedOp(lines));
  }

  void cut([CutMode mode = CutMode.partial]) {
    _ops.add(CutOp(mode));
  }

  void drawer({
    DrawerPin pin = DrawerPin.pin2,
    int onMs = 120,
    int offMs = 240,
  }) {
    _ops.add(DrawerKickOp(pin: pin, onMs: onMs, offMs: offMs));
  }

  List<PrintOp> build() => List<PrintOp>.unmodifiable(_ops);
}

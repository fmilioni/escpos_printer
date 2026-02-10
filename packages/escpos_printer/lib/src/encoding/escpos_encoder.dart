import 'dart:convert';
import 'dart:typed_data';

import '../model/exceptions.dart';
import '../model/options.dart';
import '../template/operations.dart';

final class EscPosEncoder {
  const EscPosEncoder({
    this.paperWidthChars = 48,
    this.codeTable = EscPosCodeTable.wcp1252,
  }) : assert(paperWidthChars > 0);

  final int paperWidthChars;
  final EscPosCodeTable? codeTable;

  List<int> encode(List<PrintOp> ops, {bool initializePrinter = true}) {
    final bytes = <int>[];

    if (initializePrinter) {
      bytes.addAll(const <int>[0x1B, 0x40]);
      final selectedCodeTable = codeTable;
      if (selectedCodeTable != null) {
        bytes.addAll(<int>[0x1B, 0x74, selectedCodeTable.value]);
      }
    }

    for (final op in ops) {
      switch (op) {
        case TextOp(:final text, :final style):
          _appendStyledText(bytes, text, style);

        case RowOp(:final columns):
          _appendRow(bytes, columns);

        case QrCodeOp(:final data, :final size, :final align):
          _appendAlign(bytes, align);
          _appendQrCode(bytes, data, size: size);

        case BarcodeOp(:final data, :final type, :final height, :final align):
          _appendAlign(bytes, align);
          _appendBarcode(bytes, data, type: type, height: height);

        case ImageOp(
          :final rasterData,
          :final widthBytes,
          :final heightDots,
          :final mode,
          :final align,
        ):
          _appendAlign(bytes, align);
          _appendImage(
            bytes,
            rasterData,
            widthBytes: widthBytes,
            heightDots: heightDots,
            mode: mode,
          );

        case FeedOp(:final lines):
          bytes.addAll(<int>[0x1B, 0x64, lines]);

        case CutOp(:final mode):
          bytes.addAll(<int>[0x1D, 0x56, mode == CutMode.full ? 0 : 1]);

        case DrawerKickOp(:final pin, :final onMs, :final offMs):
          bytes.addAll(<int>[
            0x1B,
            0x70,
            pin == DrawerPin.pin2 ? 0 : 1,
            onMs,
            offMs,
          ]);

        case TextTemplateOp() || TemplateBlockOp():
          throw TemplateValidationException(
            'Operacao de template nao resolvida antes do encoding.',
          );
      }
    }

    return bytes;
  }

  void _appendStyledText(
    List<int> output,
    String text,
    ReceiptTextStyle style,
  ) {
    _appendAlign(output, style.align);

    output.addAll(<int>[0x1B, 0x45, style.bold ? 1 : 0]);
    output.addAll(<int>[0x1B, 0x2D, style.underline ? 1 : 0]);
    output.addAll(<int>[0x1D, 0x42, style.invert ? 1 : 0]);
    output.addAll(<int>[0x1B, 0x4D, style.font == FontType.a ? 0 : 1]);

    final size = ((style.widthScale - 1) << 4) | (style.heightScale - 1);
    output.addAll(<int>[0x1D, 0x21, size]);

    output.addAll(_latin1WithFallback(text));
    output.add(0x0A);

    // Prevent style state from leaking into the next block.
    output.addAll(const <int>[0x1B, 0x45, 0]);
    output.addAll(const <int>[0x1B, 0x2D, 0]);
    output.addAll(const <int>[0x1D, 0x42, 0]);
    output.addAll(const <int>[0x1B, 0x4D, 0]);
    output.addAll(const <int>[0x1D, 0x21, 0]);
  }

  void _appendRow(List<int> output, List<RowColumnSpec> columns) {
    if (columns.isEmpty) {
      return;
    }

    final totalFlex = columns.fold<int>(0, (sum, item) => sum + item.flex);
    final widths = List<int>.filled(columns.length, 0);

    var used = 0;
    for (var i = 0; i < columns.length; i++) {
      final width = (paperWidthChars * columns[i].flex / totalFlex).floor();
      widths[i] = width;
      used += width;
    }

    var remaining = paperWidthChars - used;
    var cursor = 0;
    while (remaining > 0) {
      widths[cursor] += 1;
      remaining--;
      cursor = (cursor + 1) % widths.length;
    }

    final wrappedColumns = <List<String>>[];
    var maxLines = 1;
    for (var i = 0; i < columns.length; i++) {
      final wrapped = _wrapText(columns[i].text, widths[i]);
      wrappedColumns.add(wrapped);
      if (wrapped.length > maxLines) {
        maxLines = wrapped.length;
      }
    }

    for (var line = 0; line < maxLines; line++) {
      final row = StringBuffer();
      for (var colIndex = 0; colIndex < columns.length; colIndex++) {
        final chunk = line < wrappedColumns[colIndex].length
            ? wrappedColumns[colIndex][line]
            : '';
        final aligned = _alignCell(
          chunk,
          widths[colIndex],
          columns[colIndex].align,
        );
        row.write(aligned);
      }
      output.addAll(_latin1WithFallback(row.toString()));
      output.add(0x0A);
    }
  }

  void _appendQrCode(List<int> output, String data, {required int size}) {
    final dataBytes = _latin1WithFallback(data);
    output.addAll(const <int>[
      0x1D,
      0x28,
      0x6B,
      0x04,
      0x00,
      0x31,
      0x41,
      0x32,
      0x00,
    ]);
    output.addAll(<int>[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size]);
    output.addAll(const <int>[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30]);

    final payloadLength = dataBytes.length + 3;
    final pL = payloadLength & 0xFF;
    final pH = (payloadLength >> 8) & 0xFF;
    output.addAll(<int>[0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
    output.addAll(dataBytes);
    output.addAll(const <int>[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    output.add(0x0A);
  }

  void _appendBarcode(
    List<int> output,
    String data, {
    required BarcodeType type,
    required int height,
  }) {
    final dataBytes = _latin1WithFallback(data);
    final barcodeType = switch (type) {
      BarcodeType.upca => 65,
      BarcodeType.upce => 66,
      BarcodeType.ean13 => 67,
      BarcodeType.ean8 => 68,
      BarcodeType.code39 => 69,
      BarcodeType.code128 => 73,
    };

    output.addAll(<int>[0x1D, 0x68, height]);
    output.addAll(const <int>[0x1D, 0x48, 0x00]);
    output.addAll(<int>[0x1D, 0x6B, barcodeType, dataBytes.length]);
    output.addAll(dataBytes);
    output.add(0x0A);
  }

  void _appendImage(
    List<int> output,
    Uint8List rasterData, {
    required int widthBytes,
    required int heightDots,
    required int mode,
  }) {
    final expectedLength = widthBytes * heightDots;
    if (rasterData.length != expectedLength) {
      throw TemplateValidationException(
        'Invalid image data. Expected $expectedLength bytes (widthBytes * heightDots), got ${rasterData.length}.',
      );
    }

    final xL = widthBytes & 0xFF;
    final xH = (widthBytes >> 8) & 0xFF;
    final yL = heightDots & 0xFF;
    final yH = (heightDots >> 8) & 0xFF;

    output.addAll(<int>[0x1D, 0x76, 0x30, mode, xL, xH, yL, yH]);
    output.addAll(rasterData);
    output.add(0x0A);
  }

  void _appendAlign(List<int> output, TextAlign align) {
    final alignValue = switch (align) {
      TextAlign.left => 0,
      TextAlign.center => 1,
      TextAlign.right => 2,
    };
    output.addAll(<int>[0x1B, 0x61, alignValue]);
  }

  List<int> _latin1WithFallback(String value) {
    final runes = value.runes;
    final chars = StringBuffer();
    for (final rune in runes) {
      if (rune <= 0xFF) {
        chars.writeCharCode(rune);
      } else {
        chars.write('?');
      }
    }
    return latin1.encode(chars.toString());
  }

  List<String> _wrapText(String text, int width) {
    if (width <= 0) {
      return const <String>[''];
    }

    final normalized = text.replaceAll('\r', '');
    final paragraphs = normalized.split('\n');
    final lines = <String>[];

    for (final paragraph in paragraphs) {
      final words = paragraph
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList(growable: false);
      if (words.isEmpty) {
        lines.add('');
        continue;
      }

      var current = '';
      for (final word in words) {
        if (current.isEmpty) {
          if (word.length <= width) {
            current = word;
          } else {
            lines.addAll(_chunkWord(word, width));
            current = '';
          }
          continue;
        }

        final candidate = '$current $word';
        if (candidate.length <= width) {
          current = candidate;
          continue;
        }

        lines.add(current);
        if (word.length <= width) {
          current = word;
        } else {
          final chunks = _chunkWord(word, width);
          lines.addAll(chunks.take(chunks.length - 1));
          current = chunks.last;
        }
      }

      if (current.isNotEmpty) {
        lines.add(current);
      }
    }

    return lines;
  }

  List<String> _chunkWord(String word, int width) {
    final chunks = <String>[];
    var cursor = 0;
    while (cursor < word.length) {
      final end = (cursor + width).clamp(0, word.length);
      chunks.add(word.substring(cursor, end));
      cursor = end;
    }
    return chunks;
  }

  String _alignCell(String text, int width, TextAlign align) {
    final trimmed = text.length > width ? text.substring(0, width) : text;
    final padding = width - trimmed.length;
    if (padding <= 0) {
      return trimmed;
    }

    return switch (align) {
      TextAlign.left => '$trimmed${' ' * padding}',
      TextAlign.right => '${' ' * padding}$trimmed',
      TextAlign.center =>
        '${' ' * (padding ~/ 2)}$trimmed${' ' * (padding - (padding ~/ 2))}',
    };
  }
}

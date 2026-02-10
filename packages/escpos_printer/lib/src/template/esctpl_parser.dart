import 'dart:convert';
import 'dart:typed_data';

import '../model/exceptions.dart';
import '../model/options.dart';
import 'operations.dart';

final class EscTplParser {
  const EscTplParser();

  List<PrintOp> parse(String source) {
    final lines = const LineSplitter().convert(source);
    final ops = <PrintOp>[];

    var index = 0;
    while (index < lines.length) {
      final rawLine = lines[index];
      final line = rawLine.trim();
      index++;

      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      if (!line.startsWith('@')) {
        throw TemplateParseException(
          'Invalid line: "$line". Expected a command starting with @.',
        );
      }

      final command = _parseCommandLine(line);

      switch (command.name) {
        case 'row':
          final rowColumns = <RowColumnSpec>[];
          var foundEnd = false;

          while (index < lines.length) {
            final candidate = lines[index].trim();
            index++;

            if (candidate.isEmpty || candidate.startsWith('#')) {
              continue;
            }

            if (candidate == '@endrow') {
              foundEnd = true;
              break;
            }

            if (!candidate.startsWith('@col')) {
              throw TemplateParseException(
                'Only @col and @endrow are allowed inside @row. Received: "$candidate".',
              );
            }

            final colCommand = _parseCommandLine(candidate);
            rowColumns.add(_parseColumn(colCommand));
          }

          if (!foundEnd) {
            throw TemplateParseException('@row block without @endrow closing.');
          }
          if (rowColumns.isEmpty) {
            throw TemplateValidationException(
              '@row requires at least one @col column.',
            );
          }

          ops.add(RowOp(List<RowColumnSpec>.unmodifiable(rowColumns)));

        case 'endrow':
          throw TemplateParseException(
            '@endrow without a matching @row block.',
          );

        case 'text':
          final text = command.content.isNotEmpty
              ? command.content
              : (command.attrs['text'] ?? '');
          ops.add(TextOp(text, style: _parseTextStyle(command.attrs)));

        case 'qrcode':
          final data = _requireContent(command, label: 'qrcode');
          ops.add(
            QrCodeOp(
              data,
              size: _parseIntAttr(
                command,
                'size',
                defaultValue: 6,
                min: 1,
                max: 16,
              ),
              align: _parseAlign(command.attrs['align']),
            ),
          );

        case 'barcode':
          final data = _requireContent(command, label: 'barcode');
          ops.add(
            BarcodeOp(
              data,
              type: _parseBarcodeType(command.attrs['type']),
              height: _parseIntAttr(
                command,
                'height',
                defaultValue: 80,
                min: 1,
                max: 255,
              ),
              align: _parseAlign(command.attrs['align']),
            ),
          );

        case 'image':
          final base64Data = _requireContent(command, label: 'image');
          final widthBytes = _parseIntAttr(command, 'widthBytes', min: 1);
          final heightDots = _parseIntAttr(command, 'heightDots', min: 1);
          final mode = _parseIntAttr(
            command,
            'mode',
            defaultValue: 0,
            min: 0,
            max: 3,
          );
          final rasterData = _decodeBase64(base64Data);
          ops.add(
            ImageOp(
              rasterData: rasterData,
              widthBytes: widthBytes,
              heightDots: heightDots,
              mode: mode,
              align: _parseAlign(command.attrs['align']),
            ),
          );

        case 'feed':
          final linesToFeed = _parseIntAttr(
            command,
            'lines',
            defaultValue: command.content.isEmpty
                ? 1
                : _parseInt(command.content, name: 'feed content'),
            min: 0,
            max: 255,
          );
          ops.add(FeedOp(linesToFeed));

        case 'cut':
          final modeRaw = (command.attrs['mode'] ?? 'partial')
              .trim()
              .toLowerCase();
          final mode = switch (modeRaw) {
            'partial' => CutMode.partial,
            'full' => CutMode.full,
            _ => throw TemplateValidationException(
              'Invalid cut mode: $modeRaw. Use partial or full.',
            ),
          };
          ops.add(CutOp(mode));

        case 'drawer':
          final pinRaw = (command.attrs['pin'] ?? '2').trim();
          final pin = switch (pinRaw) {
            '2' => DrawerPin.pin2,
            '5' => DrawerPin.pin5,
            _ => throw TemplateValidationException(
              'Invalid drawer pin: $pinRaw. Use 2 or 5.',
            ),
          };
          ops.add(
            DrawerKickOp(
              pin: pin,
              onMs: _parseIntAttr(
                command,
                'on',
                defaultValue: 120,
                min: 0,
                max: 255,
              ),
              offMs: _parseIntAttr(
                command,
                'off',
                defaultValue: 240,
                min: 0,
                max: 255,
              ),
            ),
          );

        default:
          throw TemplateParseException('Unsupported command: @${command.name}');
      }
    }

    return List<PrintOp>.unmodifiable(ops);
  }

  RowColumnSpec _parseColumn(_Command command) {
    final text = command.content.isNotEmpty
        ? command.content
        : (command.attrs['text'] ?? '');
    return RowColumnSpec(
      text: text,
      flex: _parseIntAttr(command, 'flex', defaultValue: 1, min: 1),
      align: _parseAlign(command.attrs['align']),
      style: _parseTextStyle(command.attrs),
    );
  }

  ReceiptTextStyle _parseTextStyle(Map<String, String> attrs) {
    return ReceiptTextStyle(
      bold: _parseBool(attrs['bold']),
      underline: _parseBool(attrs['underline']),
      invert: _parseBool(attrs['invert']),
      font: _parseFont(attrs['font']),
      widthScale: _parseIntAttrFromMap(
        attrs,
        'width',
        defaultValue: 1,
        min: 1,
        max: 8,
      ),
      heightScale: _parseIntAttrFromMap(
        attrs,
        'height',
        defaultValue: 1,
        min: 1,
        max: 8,
      ),
      align: _parseAlign(attrs['align']),
    );
  }

  String _requireContent(_Command command, {required String label}) {
    if (command.content.isNotEmpty) {
      return command.content;
    }
    final data = command.attrs['data'];
    if (data != null && data.isNotEmpty) {
      return data;
    }
    throw TemplateValidationException(
      '@$label requires content or a data= attribute.',
    );
  }

  Uint8List _decodeBase64(String content) {
    try {
      return Uint8List.fromList(base64Decode(content));
    } catch (error) {
      throw TemplateValidationException('Invalid base64 in @image.', error);
    }
  }

  TextAlign _parseAlign(String? value) {
    final normalized = (value ?? 'left').toLowerCase();
    return switch (normalized) {
      'left' => TextAlign.left,
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => throw TemplateValidationException(
        'Invalid alignment: $value. Use left, center, or right.',
      ),
    };
  }

  FontType _parseFont(String? value) {
    final normalized = (value ?? 'a').toLowerCase();
    return switch (normalized) {
      'a' => FontType.a,
      'b' => FontType.b,
      _ => throw TemplateValidationException(
        'Invalid font: $value. Use a or b.',
      ),
    };
  }

  BarcodeType _parseBarcodeType(String? value) {
    final normalized = (value ?? 'code39').toLowerCase();
    return switch (normalized) {
      'upca' => BarcodeType.upca,
      'upce' => BarcodeType.upce,
      'ean13' => BarcodeType.ean13,
      'ean8' => BarcodeType.ean8,
      'code39' => BarcodeType.code39,
      'code128' => BarcodeType.code128,
      _ => throw TemplateValidationException('Invalid barcode type: $value.'),
    };
  }

  bool _parseBool(String? value) {
    if (value == null) {
      return false;
    }
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  int _parseIntAttr(
    _Command command,
    String name, {
    int? defaultValue,
    int? min,
    int? max,
  }) {
    final raw = command.attrs[name];
    if (raw == null || raw.isEmpty) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw TemplateValidationException(
        'Missing required attribute: $name in @${command.name}.',
      );
    }
    return _parseInt(
      raw,
      name: '$name em @${command.name}',
      min: min,
      max: max,
    );
  }

  int _parseIntAttrFromMap(
    Map<String, String> attrs,
    String name, {
    int? defaultValue,
    int? min,
    int? max,
  }) {
    final raw = attrs[name];
    if (raw == null || raw.isEmpty) {
      if (defaultValue != null) {
        return defaultValue;
      }
      throw TemplateValidationException('Missing required attribute: $name.');
    }
    return _parseInt(raw, name: name, min: min, max: max);
  }

  int _parseInt(String raw, {required String name, int? min, int? max}) {
    final value = int.tryParse(raw.trim());
    if (value == null) {
      throw TemplateValidationException('Invalid value for $name: "$raw".');
    }
    if (min != null && value < min) {
      throw TemplateValidationException(
        'Value for $name must be >= $min. Received: $value.',
      );
    }
    if (max != null && value > max) {
      throw TemplateValidationException(
        'Value for $name must be <= $max. Received: $value.',
      );
    }
    return value;
  }

  _Command _parseCommandLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (!trimmed.startsWith('@')) {
      throw TemplateParseException('Invalid command: "$rawLine"');
    }

    final body = trimmed.substring(1);
    final tokens = _tokenize(body);
    if (tokens.isEmpty) {
      throw TemplateParseException('Empty command: "$rawLine"');
    }

    final name = tokens.first.toLowerCase();
    final attrs = <String, String>{};
    final contentTokens = <String>[];

    var readingContent = false;
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (!readingContent && token.contains('=')) {
        final separator = token.indexOf('=');
        final key = token.substring(0, separator).trim();
        final value = token.substring(separator + 1).trim();
        if (key.isEmpty) {
          throw TemplateParseException('Invalid attribute in "$rawLine".');
        }
        attrs[key] = _stripQuotes(value);
        continue;
      }
      readingContent = true;
      contentTokens.add(_stripQuotes(token));
    }

    return _Command(
      name: name,
      attrs: attrs,
      content: contentTokens.join(' ').trim(),
    );
  }

  List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();

    String? activeQuote;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if ((char == '"' || char == "'") && activeQuote == null) {
        activeQuote = char;
        continue;
      }

      if (activeQuote != null && char == activeQuote) {
        activeQuote = null;
        continue;
      }

      if (char == ' ' && activeQuote == null) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }

      buffer.write(char);
    }

    if (activeQuote != null) {
      throw TemplateParseException('Aspas nao fechadas em comando: $input');
    }

    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }

    return tokens;
  }

  String _stripQuotes(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return trimmed;
    }

    final startsWithSingle = trimmed.startsWith("'") && trimmed.endsWith("'");
    final startsWithDouble = trimmed.startsWith('"') && trimmed.endsWith('"');
    if (startsWithSingle || startsWithDouble) {
      return trimmed.substring(1, trimmed.length - 1);
    }

    return trimmed;
  }
}

final class _Command {
  const _Command({
    required this.name,
    required this.attrs,
    required this.content,
  });

  final String name;
  final Map<String, String> attrs;
  final String content;
}

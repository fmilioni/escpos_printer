import 'dart:math';

import 'package:flutter/foundation.dart';

enum CutMode { partial, full }

enum TextAlign { left, center, right }

enum DrawerPin { pin2, pin5 }

/// ESC/POS tables that keep compatibility with Latin-1 bytes.
///
/// The text encoder currently uses Latin-1 to generate bytes.
/// For PT-BR accented output, [wcp1252] is the recommended default.
enum EscPosCodeTable {
  /// Windows-1252 on most Epson-compatible ESC/POS printers.
  wcp1252(16);

  const EscPosCodeTable(this.value);

  final int value;
}

@immutable
final class ReconnectPolicy {
  const ReconnectPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 250),
    this.maxDelay = const Duration(seconds: 2),
    this.jitterFactor = 0.15,
  }) : assert(maxAttempts >= 0),
       assert(jitterFactor >= 0 && jitterFactor <= 1);

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitterFactor;

  Duration delayForAttempt(int attempt, {Random? random}) {
    final source = random ?? Random();
    final exponent = attempt <= 0 ? 0 : attempt - 1;
    final baseMs = baseDelay.inMilliseconds * (1 << exponent);
    final cappedMs = baseMs.clamp(0, maxDelay.inMilliseconds).toDouble();
    final jitter = ((source.nextDouble() * 2) - 1) * jitterFactor * cappedMs;
    return Duration(
      milliseconds: (cappedMs + jitter).round().clamp(
        0,
        maxDelay.inMilliseconds,
      ),
    );
  }
}

@immutable
final class TemplateRenderOptions {
  const TemplateRenderOptions({this.strictMissingVariables = true});

  final bool strictMissingVariables;
}

@immutable
final class PrintOptions {
  const PrintOptions({
    this.paperWidthChars = 48,
    this.initializePrinter = true,
    this.codeTable = EscPosCodeTable.wcp1252,
  }) : assert(paperWidthChars > 0);

  final int paperWidthChars;
  final bool initializePrinter;

  /// Code table sent with `ESC t n` when [initializePrinter] is `true`.
  ///
  /// Use `null` to skip code table command emission.
  final EscPosCodeTable? codeTable;
}

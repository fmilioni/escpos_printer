import 'package:flutter/foundation.dart';

import 'status.dart';

@immutable
final class PrintResult {
  const PrintResult({
    required this.bytesSent,
    required this.duration,
    this.status = const PrinterStatus.unknown(),
  });

  final int bytesSent;
  final Duration duration;
  final PrinterStatus status;
}

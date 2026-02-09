import 'package:flutter/foundation.dart';

enum TriState { yes, no, unknown }

@immutable
final class PrinterStatus {
  const PrinterStatus({
    this.paperOut = TriState.unknown,
    this.paperNearEnd = TriState.unknown,
    this.coverOpen = TriState.unknown,
    this.cutterError = TriState.unknown,
    this.offline = TriState.unknown,
    this.drawerSignal = TriState.unknown,
  });

  const PrinterStatus.unknown()
    : paperOut = TriState.unknown,
      paperNearEnd = TriState.unknown,
      coverOpen = TriState.unknown,
      cutterError = TriState.unknown,
      offline = TriState.unknown,
      drawerSignal = TriState.unknown;

  final TriState paperOut;
  final TriState paperNearEnd;
  final TriState coverOpen;
  final TriState cutterError;
  final TriState offline;
  final TriState drawerSignal;
}

@immutable
final class PrinterCapabilities {
  const PrinterCapabilities({
    this.supportsPartialCut = true,
    this.supportsFullCut = true,
    this.supportsDrawerKick = true,
    this.supportsRealtimeStatus = false,
    this.supportsQrCode = true,
    this.supportsBarcode = true,
    this.supportsImage = true,
  });

  final bool supportsPartialCut;
  final bool supportsFullCut;
  final bool supportsDrawerKick;
  final bool supportsRealtimeStatus;
  final bool supportsQrCode;
  final bool supportsBarcode;
  final bool supportsImage;
}

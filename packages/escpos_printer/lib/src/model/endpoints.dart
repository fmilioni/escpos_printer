import 'package:flutter/foundation.dart';

/// Represents a printer endpoint for a specific transport.
@immutable
sealed class PrinterEndpoint {
  const PrinterEndpoint();

  String get transport;
}

/// TCP endpoint, usually port 9100 for ESC/POS.
@immutable
final class WifiEndpoint extends PrinterEndpoint {
  const WifiEndpoint(
    this.host, {
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  });

  final String host;
  final int port;
  final Duration timeout;

  @override
  String get transport => 'wifi';
}

/// USB endpoint identified by vendor/product id.
@immutable
final class UsbEndpoint extends PrinterEndpoint {
  const UsbEndpoint(
    this.vendorId,
    this.productId, {
    this.serialNumber,
    this.interfaceNumber,
  });

  final int vendorId;
  final int productId;
  final String? serialNumber;
  final int? interfaceNumber;

  @override
  String get transport => 'usb';
}

enum BluetoothMode { classic, ble }

/// Bluetooth endpoint for classic SPP/RFCOMM or BLE.
@immutable
final class BluetoothEndpoint extends PrinterEndpoint {
  const BluetoothEndpoint(
    this.address, {
    this.mode = BluetoothMode.classic,
    this.serviceUuid,
  });

  final String address;
  final BluetoothMode mode;
  final String? serviceUuid;

  @override
  String get transport => 'bluetooth';
}

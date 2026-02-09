import 'dart:async';
import 'dart:io';

import 'package:escpos_printer/escpos_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'sample_image.dart';
import 'ticket_samples.dart';

enum ManualConnectionMode { wifi, usbVidPid, usbSerial, bluetooth }

final class ManualConnectionDraft {
  const ManualConnectionDraft({
    required this.mode,
    this.wifiHost = '',
    this.wifiPort = '9100',
    this.usbVendorId = '',
    this.usbProductId = '',
    this.usbInterfaceNumber = '',
    this.usbSerialPath = '',
    this.usbSerialVendorId = '',
    this.usbSerialProductId = '',
    this.usbSerialInterfaceNumber = '',
    this.bluetoothAddress = '',
    this.bluetoothMode = BluetoothMode.classic,
    this.bluetoothServiceUuid = '',
  });

  final ManualConnectionMode mode;

  final String wifiHost;
  final String wifiPort;

  final String usbVendorId;
  final String usbProductId;
  final String usbInterfaceNumber;

  final String usbSerialPath;
  final String usbSerialVendorId;
  final String usbSerialProductId;
  final String usbSerialInterfaceNumber;

  final String bluetoothAddress;
  final BluetoothMode bluetoothMode;
  final String bluetoothServiceUuid;

  PrinterEndpoint toEndpoint() {
    switch (mode) {
      case ManualConnectionMode.wifi:
        final host = _requiredString(wifiHost, 'Host Wi-Fi');
        final port = _requiredInt(wifiPort, 'Porta Wi-Fi', min: 1, max: 65535);
        return WifiEndpoint(host, port: port);

      case ManualConnectionMode.usbVidPid:
        final vendorId = _requiredInt(usbVendorId, 'USB vendorId');
        final productId = _requiredInt(usbProductId, 'USB productId');
        final interfaceNumber = _optionalInt(
          usbInterfaceNumber,
          'USB interfaceNumber',
          min: 0,
        );
        return UsbEndpoint(
          vendorId,
          productId,
          interfaceNumber: interfaceNumber,
        );

      case ManualConnectionMode.usbSerial:
        final serialPath = _requiredString(usbSerialPath, 'USB serial/path');
        final vendorId = _optionalInt(usbSerialVendorId, 'USB serial vendorId');
        final productId = _optionalInt(
          usbSerialProductId,
          'USB serial productId',
        );
        final interfaceNumber = _optionalInt(
          usbSerialInterfaceNumber,
          'USB serial interfaceNumber',
          min: 0,
        );
        return UsbEndpoint.serial(
          serialPath,
          vendorId: vendorId,
          productId: productId,
          interfaceNumber: interfaceNumber,
        );

      case ManualConnectionMode.bluetooth:
        final address = _requiredString(bluetoothAddress, 'Bluetooth address');
        final serviceUuid = bluetoothServiceUuid.trim();
        return BluetoothEndpoint(
          address,
          mode: bluetoothMode,
          serviceUuid: serviceUuid.isEmpty ? null : serviceUuid,
        );
    }
  }

  static List<String> parseCidrsInput(String raw) {
    return raw
        .split(RegExp(r'[\n,;\s]+'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static int parseTimeoutSeconds(String raw) {
    return _requiredInt(raw, 'Timeout', min: 1, max: 120);
  }

  static int parsePort(String raw, {String fieldName = 'Porta'}) {
    return _requiredInt(raw, fieldName, min: 1, max: 65535);
  }

  static String _requiredString(String raw, String fieldName) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw FormatException('$fieldName nao pode ser vazio.');
    }
    return value;
  }

  static int _requiredInt(String raw, String fieldName, {int? min, int? max}) {
    final parsed = _parseFlexibleInt(raw, fieldName);
    if (min != null && parsed < min) {
      throw FormatException('$fieldName deve ser >= $min.');
    }
    if (max != null && parsed > max) {
      throw FormatException('$fieldName deve ser <= $max.');
    }
    return parsed;
  }

  static int? _optionalInt(String raw, String fieldName, {int? min, int? max}) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    return _requiredInt(value, fieldName, min: min, max: max);
  }

  static int _parseFlexibleInt(String raw, String fieldName) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) {
      throw FormatException('$fieldName nao pode ser vazio.');
    }

    final parsed = value.startsWith('0x')
        ? int.tryParse(value.substring(2), radix: 16)
        : int.tryParse(value);

    if (parsed == null) {
      throw FormatException('$fieldName invalido: "$raw".');
    }
    return parsed;
  }
}

class DemoController extends ChangeNotifier {
  DemoController({EscPosClient? client, DateTime Function()? now})
    : _client = client ?? EscPosClient(),
      _now = now ?? DateTime.now;

  final EscPosClient _client;
  final DateTime Function() _now;

  final List<String> _logs = <String>[];

  List<DiscoveredPrinter> _printers = const <DiscoveredPrinter>[];
  PrinterEndpoint? _connectedEndpoint;
  PrinterStatus _lastStatus = const PrinterStatus.unknown();
  PrintResult? _lastPrintResult;
  String? _lastError;

  bool _searching = false;
  bool _connecting = false;
  bool _readingStatus = false;
  bool _sendingCommand = false;
  bool _printing = false;

  List<DiscoveredPrinter> get printers => _printers;
  List<String> get logs => List<String>.unmodifiable(_logs);
  PrinterStatus get lastStatus => _lastStatus;
  PrintResult? get lastPrintResult => _lastPrintResult;
  String? get lastError => _lastError;

  bool get searching => _searching;
  bool get connecting => _connecting;
  bool get readingStatus => _readingStatus;
  bool get sendingCommand => _sendingCommand;
  bool get printing => _printing;

  bool get isConnected => _client.isConnected;
  PrinterEndpoint? get connectedEndpoint => _connectedEndpoint;
  PrinterCapabilities? get capabilities => _client.transportCapabilities;
  String? get sessionId => _client.transportSessionId;

  Future<void> close() async {
    try {
      await _client.disconnect();
    } catch (_) {
      // noop
    }
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  Future<void> searchPrinters({
    required Set<DiscoveryTransport> transports,
    required Duration timeout,
    required int wifiPort,
    required List<String> wifiCidrs,
  }) async {
    _searching = true;
    _lastError = null;
    notifyListeners();

    try {
      if (transports.contains(DiscoveryTransport.bluetooth)) {
        await _ensureBluetoothPermission();
      }

      final found = await _client.searchPrinters(
        options: PrinterDiscoveryOptions(
          transports: transports,
          timeout: timeout,
          wifiPort: wifiPort,
          wifiCidrs: wifiCidrs,
        ),
      );
      _printers = found;
      _log('Busca finalizada: ${found.length} impressora(s) encontrada(s).');
    } catch (error) {
      _lastError = '$error';
      _log('Erro na busca: $error');
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<void> connectDiscovered(DiscoveredPrinter printer) {
    return connectEndpoint(
      printer.endpoint,
      contextLabel: printer.name ?? printer.id,
    );
  }

  Future<void> connectManual(ManualConnectionDraft draft) {
    final endpoint = draft.toEndpoint();
    return connectEndpoint(endpoint, contextLabel: 'Conexao manual');
  }

  Future<void> connectEndpoint(
    PrinterEndpoint endpoint, {
    String? contextLabel,
  }) async {
    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      if (endpoint is BluetoothEndpoint) {
        await _ensureBluetoothPermission();
      }

      await _client.connect(endpoint);
      _connectedEndpoint = endpoint;
      _log('${contextLabel ?? 'Conectado'} em ${describeEndpoint(endpoint)}');
    } catch (error) {
      _lastError = '$error';
      _log('Erro ao conectar: $error');
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _connecting = true;
    _lastError = null;
    notifyListeners();

    try {
      await _client.disconnect();
      _connectedEndpoint = null;
      _log('Sessao desconectada.');
    } catch (error) {
      _lastError = '$error';
      _log('Erro ao desconectar: $error');
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> readStatus() async {
    _readingStatus = true;
    _lastError = null;
    notifyListeners();

    try {
      final status = await _client.getStatus();
      _lastStatus = status;
      _log('Status atualizado: ${formatTriState(status.offline)} offline.');
    } catch (error) {
      _lastError = '$error';
      _log('Erro ao ler status: $error');
    } finally {
      _readingStatus = false;
      notifyListeners();
    }
  }

  Future<void> feed() =>
      _runCommand(name: 'Feed', action: () => _client.feed(1));

  Future<void> cutPartial() => _runCommand(
    name: 'Corte parcial',
    action: () => _client.cut(CutMode.partial),
  );

  Future<void> cutFull() =>
      _runCommand(name: 'Corte total', action: () => _client.cut(CutMode.full));

  Future<void> openDrawer() =>
      _runCommand(name: 'Abrir gaveta', action: () => _client.openCashDrawer());

  Future<void> printDslTicket(
    DemoTicketData data, {
    PrintOptions printOptions = const PrintOptions(paperWidthChars: 48),
  }) async {
    await _runPrint(
      name: 'Ticket DSL',
      action: () {
        final result = _client.print(
          template: buildDslTicketTemplate(data),
          variables: buildTemplateVariables(data),
          printOptions: printOptions,
        );
        return result;
      },
    );
  }

  Future<void> printEscTplTicket(
    DemoTicketData data, {
    PrintOptions printOptions = const PrintOptions(paperWidthChars: 48),
  }) async {
    await _runPrint(
      name: 'Ticket EscTpl',
      action: () {
        final raster = buildSampleRasterImage();
        return _client.printFromString(
          template: buildEscTplTicketString(image: raster),
          variables: buildTemplateVariables(data),
          printOptions: printOptions,
        );
      },
    );
  }

  Future<void> printHybridTicket(
    DemoTicketData data, {
    PrintOptions printOptions = const PrintOptions(paperWidthChars: 48),
  }) async {
    await _runPrint(
      name: 'Ticket hibrido',
      action: () {
        final template = buildHybridTicketTemplate(data);
        return _client.print(
          template: template,
          variables: buildTemplateVariables(data),
          printOptions: printOptions,
        );
      },
    );
  }

  static String describeEndpoint(PrinterEndpoint endpoint) {
    return switch (endpoint) {
      WifiEndpoint e => 'Wi-Fi ${e.host}:${e.port}',
      UsbEndpoint e => 'USB ${_usbLabel(e)}',
      BluetoothEndpoint e => 'Bluetooth ${e.address} (${e.mode.name})',
    };
  }

  static String describeDiscovered(DiscoveredPrinter printer) {
    final name = printer.name?.trim();
    final id = name == null || name.isEmpty ? printer.id : name;
    return '[${printer.transport.name}] $id';
  }

  static String formatTriState(TriState value) {
    return switch (value) {
      TriState.yes => 'yes',
      TriState.no => 'no',
      TriState.unknown => 'unknown',
    };
  }

  static String _usbLabel(UsbEndpoint endpoint) {
    if ((endpoint.serialNumber ?? '').isNotEmpty) {
      final serial = endpoint.serialNumber!;
      if (endpoint.vendorId != null && endpoint.productId != null) {
        return '$serial (${endpoint.vendorId}:${endpoint.productId})';
      }
      return serial;
    }

    if (endpoint.vendorId != null && endpoint.productId != null) {
      return '${endpoint.vendorId}:${endpoint.productId}';
    }

    return 'endpoint indefinido';
  }

  Future<void> _runCommand({
    required String name,
    required Future<void> Function() action,
  }) async {
    _sendingCommand = true;
    _lastError = null;
    notifyListeners();

    try {
      await action();
      _log('Comando executado: $name');
    } catch (error) {
      _lastError = '$error';
      _log('Erro em "$name": $error');
    } finally {
      _sendingCommand = false;
      notifyListeners();
    }
  }

  Future<void> _runPrint({
    required String name,
    required Future<PrintResult> Function() action,
  }) async {
    _printing = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await action();
      _lastPrintResult = result;
      _lastStatus = result.status;
      _log(
        '$name concluido (${result.bytesSent} bytes em '
        '${result.duration.inMilliseconds} ms).',
      );
    } catch (error) {
      _lastError = '$error';
      _log('Erro em "$name": $error');
    } finally {
      _printing = false;
      notifyListeners();
    }
  }

  Future<void> _ensureBluetoothPermission() async {
    if (!Platform.isAndroid) {
      return;
    }

    final requiredPermissions = <Permission>[
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ];

    final result = await requiredPermissions.request();
    final denied = result.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key.toString())
        .toList(growable: false);

    if (denied.isNotEmpty) {
      throw StateError('Permissoes Bluetooth negadas: ${denied.join(', ')}');
    }
  }

  void _log(String message) {
    final now = _now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _logs.add('[$stamp] $message');
  }
}

void disposeController(DemoController controller) {
  unawaited(controller.close());
  controller.dispose();
}

import 'package:escpos_printer/escpos_printer.dart';
import 'package:flutter/material.dart';

import 'demo_controller.dart';
import 'ticket_samples.dart';

enum _PaperWidthPreset { mm58, mm80 }

extension _PaperWidthPresetX on _PaperWidthPreset {
  int get paperWidthChars {
    switch (this) {
      case _PaperWidthPreset.mm58:
        return 32;
      case _PaperWidthPreset.mm80:
        return 48;
    }
  }

  String get label {
    switch (this) {
      case _PaperWidthPreset.mm58:
        return '58mm (32 columns)';
      case _PaperWidthPreset.mm80:
        return '80mm (48 columns)';
    }
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, this.controller});

  final DemoController? controller;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late final DemoController _controller;
  late final bool _ownsController;

  Set<DiscoveryTransport> _searchTransports = <DiscoveryTransport>{
    DiscoveryTransport.wifi,
    DiscoveryTransport.usb,
    DiscoveryTransport.bluetooth,
  };

  final TextEditingController _searchTimeoutCtrl = TextEditingController(
    text: '8',
  );
  final TextEditingController _searchWifiPortCtrl = TextEditingController(
    text: '9100',
  );
  final TextEditingController _searchCidrsCtrl = TextEditingController();

  ManualConnectionMode _manualMode = ManualConnectionMode.wifi;
  BluetoothMode _manualBluetoothMode = BluetoothMode.classic;

  final TextEditingController _wifiHostCtrl = TextEditingController(
    text: '192.168.0.50',
  );
  final TextEditingController _wifiPortCtrl = TextEditingController(
    text: '9100',
  );

  final TextEditingController _usbVendorCtrl = TextEditingController(
    text: '0x04B8',
  );
  final TextEditingController _usbProductCtrl = TextEditingController(
    text: '0x0E15',
  );
  final TextEditingController _usbInterfaceCtrl = TextEditingController();

  final TextEditingController _usbSerialPathCtrl = TextEditingController(
    text: 'COM3',
  );
  final TextEditingController _usbSerialVendorCtrl = TextEditingController();
  final TextEditingController _usbSerialProductCtrl = TextEditingController();
  final TextEditingController _usbSerialInterfaceCtrl = TextEditingController();

  final TextEditingController _bluetoothAddressCtrl = TextEditingController(
    text: 'AA:BB:CC:DD:EE:FF',
  );
  final TextEditingController _bluetoothUuidCtrl = TextEditingController();

  late final TextEditingController _storeCtrl;
  late final TextEditingController _customerCtrl;
  late final TextEditingController _itemsCtrl;
  late final TextEditingController _totalCtrl;
  late final TextEditingController _pixCtrl;
  late final TextEditingController _barcodeCtrl;
  bool _shouldCut = true;
  _PaperWidthPreset _paperWidthPreset = _PaperWidthPreset.mm80;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? DemoController();
    _ownsController = widget.controller == null;

    final defaults = defaultDemoTicketData();
    _storeCtrl = TextEditingController(text: defaults.store);
    _customerCtrl = TextEditingController(text: defaults.customer);
    _itemsCtrl = TextEditingController(
      text: defaults.items
          .map((item) => '${item.name}=${item.price}')
          .join('\n'),
    );
    _totalCtrl = TextEditingController(text: defaults.total);
    _pixCtrl = TextEditingController(text: defaults.pixPayload);
    _barcodeCtrl = TextEditingController(text: defaults.barcodeValue);
    _shouldCut = defaults.shouldCut;
  }

  @override
  void dispose() {
    _searchTimeoutCtrl.dispose();
    _searchWifiPortCtrl.dispose();
    _searchCidrsCtrl.dispose();

    _wifiHostCtrl.dispose();
    _wifiPortCtrl.dispose();

    _usbVendorCtrl.dispose();
    _usbProductCtrl.dispose();
    _usbInterfaceCtrl.dispose();

    _usbSerialPathCtrl.dispose();
    _usbSerialVendorCtrl.dispose();
    _usbSerialProductCtrl.dispose();
    _usbSerialInterfaceCtrl.dispose();

    _bluetoothAddressCtrl.dispose();
    _bluetoothUuidCtrl.dispose();

    _storeCtrl.dispose();
    _customerCtrl.dispose();
    _itemsCtrl.dispose();
    _totalCtrl.dispose();
    _pixCtrl.dispose();
    _barcodeCtrl.dispose();

    if (_ownsController) {
      disposeController(_controller);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('ESC/POS Demo Mobile'),
            centerTitle: false,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                _buildSessionSection(context),
                _buildSearchSection(context),
                _buildManualConnectionSection(context),
                _buildStatusSection(context),
                _buildPrintSection(context),
                _buildLogSection(context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionSection(BuildContext context) {
    final caps = _controller.capabilities;
    return _sectionCard(
      title: '1) Current session',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_controller.isConnected ? 'Connected' : 'Disconnected'),
          const SizedBox(height: 6),
          Text(
            'Endpoint: ${_controller.connectedEndpoint != null ? DemoController.describeEndpoint(_controller.connectedEndpoint!) : '-'}',
          ),
          Text('SessionId: ${_controller.sessionId ?? '-'}'),
          const SizedBox(height: 8),
          if (caps != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                _capabilityChip('Partial cut', caps.supportsPartialCut),
                _capabilityChip('Full cut', caps.supportsFullCut),
                _capabilityChip('Drawer', caps.supportsDrawerKick),
                _capabilityChip('Realtime status', caps.supportsRealtimeStatus),
                _capabilityChip('QR', caps.supportsQrCode),
                _capabilityChip('Barcode', caps.supportsBarcode),
                _capabilityChip('Image', caps.supportsImage),
              ],
            ),
          if (_controller.lastError != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Last error: ${_controller.lastError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _controller.connecting ? null : _controller.disconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection(BuildContext context) {
    return _sectionCard(
      title: '2) Printer search',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                label: const Text('Wi-Fi'),
                selected: _searchTransports.contains(DiscoveryTransport.wifi),
                onSelected: (value) =>
                    _toggleSearchTransport(DiscoveryTransport.wifi, value),
              ),
              FilterChip(
                label: const Text('USB'),
                selected: _searchTransports.contains(DiscoveryTransport.usb),
                onSelected: (value) =>
                    _toggleSearchTransport(DiscoveryTransport.usb, value),
              ),
              FilterChip(
                label: const Text('Bluetooth'),
                selected: _searchTransports.contains(
                  DiscoveryTransport.bluetooth,
                ),
                onSelected: (value) =>
                    _toggleSearchTransport(DiscoveryTransport.bluetooth, value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _field(
                  _searchTimeoutCtrl,
                  label: 'Timeout (seconds)',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  _searchWifiPortCtrl,
                  label: 'Wi-Fi port',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _field(
            _searchCidrsCtrl,
            label: 'Wi-Fi CIDRs (optional, comma/newline-separated)',
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _controller.searching ? null : _onSearchPressed,
            icon: const Icon(Icons.search),
            label: Text(
              _controller.searching ? 'Searching...' : 'Search printers',
            ),
          ),
          const SizedBox(height: 10),
          if (_controller.printers.isEmpty)
            const Text('No printers listed.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final printer = _controller.printers[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(DemoController.describeDiscovered(printer)),
                  subtitle: Text(_describeDiscoveredPrinter(printer)),
                  trailing: FilledButton.tonal(
                    onPressed: _controller.connecting
                        ? null
                        : () => _controller.connectDiscovered(printer),
                    child: const Text('Connect'),
                  ),
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: _controller.printers.length,
            ),
        ],
      ),
    );
  }

  Widget _buildManualConnectionSection(BuildContext context) {
    return _sectionCard(
      title: '3) Manual connection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButtonFormField<ManualConnectionMode>(
            initialValue: _manualMode,
            decoration: const InputDecoration(
              labelText: 'Connection mode',
              border: OutlineInputBorder(),
            ),
            items: ManualConnectionMode.values
                .map(
                  (mode) => DropdownMenuItem<ManualConnectionMode>(
                    value: mode,
                    child: Text(_manualModeLabel(mode)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _manualMode = value;
              });
            },
          ),
          const SizedBox(height: 10),
          ..._buildManualFields(),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _controller.connecting ? null : _onManualConnectPressed,
            icon: const Icon(Icons.link),
            label: const Text('Connect manually'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildManualFields() {
    switch (_manualMode) {
      case ManualConnectionMode.wifi:
        return <Widget>[
          _field(_wifiHostCtrl, label: 'Host Wi-Fi (IP/hostname)'),
          const SizedBox(height: 8),
          _field(
            _wifiPortCtrl,
            label: 'Port',
            keyboardType: TextInputType.number,
          ),
        ];

      case ManualConnectionMode.usbVidPid:
        return <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _field(
                  _usbVendorCtrl,
                  label: 'VendorId (decimal or 0xHEX)',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  _usbProductCtrl,
                  label: 'ProductId (decimal or 0xHEX)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _field(
            _usbInterfaceCtrl,
            label: 'InterfaceNumber (optional)',
            keyboardType: TextInputType.number,
          ),
        ];

      case ManualConnectionMode.usbSerial:
        return <Widget>[
          _field(
            _usbSerialPathCtrl,
            label: 'Serial/COM/path (ex: COM3, /dev/ttyUSB0)',
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _field(
                  _usbSerialVendorCtrl,
                  label: 'VendorId (optional)',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  _usbSerialProductCtrl,
                  label: 'ProductId (optional)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _field(
            _usbSerialInterfaceCtrl,
            label: 'InterfaceNumber (optional)',
            keyboardType: TextInputType.number,
          ),
        ];

      case ManualConnectionMode.bluetooth:
        return <Widget>[
          _field(_bluetoothAddressCtrl, label: 'Bluetooth address (MAC)'),
          const SizedBox(height: 8),
          DropdownButtonFormField<BluetoothMode>(
            initialValue: _manualBluetoothMode,
            decoration: const InputDecoration(
              labelText: 'Bluetooth mode',
              border: OutlineInputBorder(),
            ),
            items: BluetoothMode.values
                .map(
                  (mode) => DropdownMenuItem<BluetoothMode>(
                    value: mode,
                    child: Text(mode.name),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _manualBluetoothMode = value;
              });
            },
          ),
          const SizedBox(height: 8),
          _field(_bluetoothUuidCtrl, label: 'Service UUID (optional)'),
        ];
    }
  }

  Widget _buildStatusSection(BuildContext context) {
    final status = _controller.lastStatus;
    return _sectionCard(
      title: '4) Status and quick commands',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _controller.readingStatus
                    ? null
                    : _controller.readStatus,
                child: const Text('Read status'),
              ),
              FilledButton.tonal(
                onPressed: _controller.sendingCommand ? null : _controller.feed,
                child: const Text('Feed'),
              ),
              FilledButton.tonal(
                onPressed: _controller.sendingCommand
                    ? null
                    : _controller.cutPartial,
                child: const Text('Partial cut'),
              ),
              FilledButton.tonal(
                onPressed: _controller.sendingCommand
                    ? null
                    : _controller.cutFull,
                child: const Text('Full cut'),
              ),
              FilledButton.tonal(
                onPressed: _controller.sendingCommand
                    ? null
                    : _controller.openDrawer,
                child: const Text('Open drawer'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _statusChip(context, 'paperOut', status.paperOut),
              _statusChip(context, 'paperNearEnd', status.paperNearEnd),
              _statusChip(context, 'coverOpen', status.coverOpen),
              _statusChip(context, 'cutterError', status.cutterError),
              _statusChip(context, 'offline', status.offline),
              _statusChip(context, 'drawerSignal', status.drawerSignal),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrintSection(BuildContext context) {
    final result = _controller.lastPrintResult;
    return _sectionCard(
      title: '5) Print sample ticket',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _field(_storeCtrl, label: 'Store'),
          const SizedBox(height: 8),
          _field(_customerCtrl, label: 'Customer'),
          const SizedBox(height: 8),
          _field(
            _itemsCtrl,
            label: 'Items (one per line, format name=price)',
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          _field(_totalCtrl, label: 'Total'),
          const SizedBox(height: 8),
          _field(_pixCtrl, label: 'PIX payload', maxLines: 3),
          const SizedBox(height: 8),
          _field(_barcodeCtrl, label: 'Barcode value'),
          const SizedBox(height: 8),
          DropdownButtonFormField<_PaperWidthPreset>(
            initialValue: _paperWidthPreset,
            decoration: const InputDecoration(
              labelText: 'Paper width',
              border: OutlineInputBorder(),
            ),
            items: _PaperWidthPreset.values
                .map(
                  (preset) => DropdownMenuItem<_PaperWidthPreset>(
                    value: preset,
                    child: Text(preset.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _paperWidthPreset = value;
              });
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Apply cut command in string template'),
            value: _shouldCut,
            onChanged: (value) {
              setState(() {
                _shouldCut = value;
              });
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: _controller.printing ? null : _onPrintDslPressed,
                child: const Text('Print ticket (full DSL)'),
              ),
              FilledButton(
                onPressed: _controller.printing ? null : _onPrintEscTplPressed,
                child: const Text('Print ticket (full EscTpl string)'),
              ),
              FilledButton(
                onPressed: _controller.printing ? null : _onPrintHybridPressed,
                child: const Text('Print ticket (Hybrid DSL+templateBlock)'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result == null
                ? 'No print result yet.'
                : 'Last print: ${result.bytesSent} bytes | '
                      '${result.duration.inMilliseconds} ms | '
                      'paperOut=${DemoController.formatTriState(result.status.paperOut)}',
          ),
        ],
      ),
    );
  }

  Widget _buildLogSection(BuildContext context) {
    return _sectionCard(
      title: '6) Execution log',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _controller.clearLogs,
                child: const Text('Clear log'),
              ),
              const SizedBox(width: 8),
              Text('Entries: ${_controller.logs.length}'),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 220,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _controller.logs.isEmpty
                ? const Text('No logs yet.')
                : ListView.builder(
                    itemCount: _controller.logs.length,
                    itemBuilder: (context, index) {
                      return Text(_controller.logs[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSearchPressed() async {
    try {
      final timeoutSeconds = ManualConnectionDraft.parseTimeoutSeconds(
        _searchTimeoutCtrl.text,
      );
      final wifiPort = ManualConnectionDraft.parsePort(
        _searchWifiPortCtrl.text,
        fieldName: 'Wi-Fi port',
      );
      final cidrs = ManualConnectionDraft.parseCidrsInput(
        _searchCidrsCtrl.text,
      );

      await _controller.searchPrinters(
        transports: _searchTransports,
        timeout: Duration(seconds: timeoutSeconds),
        wifiPort: wifiPort,
        wifiCidrs: cidrs,
      );
    } catch (error) {
      _showSnack('Failed to start search: $error');
    }
  }

  Future<void> _onManualConnectPressed() async {
    final draft = ManualConnectionDraft(
      mode: _manualMode,
      wifiHost: _wifiHostCtrl.text,
      wifiPort: _wifiPortCtrl.text,
      usbVendorId: _usbVendorCtrl.text,
      usbProductId: _usbProductCtrl.text,
      usbInterfaceNumber: _usbInterfaceCtrl.text,
      usbSerialPath: _usbSerialPathCtrl.text,
      usbSerialVendorId: _usbSerialVendorCtrl.text,
      usbSerialProductId: _usbSerialProductCtrl.text,
      usbSerialInterfaceNumber: _usbSerialInterfaceCtrl.text,
      bluetoothAddress: _bluetoothAddressCtrl.text,
      bluetoothMode: _manualBluetoothMode,
      bluetoothServiceUuid: _bluetoothUuidCtrl.text,
    );

    try {
      await _controller.connectManual(draft);
    } catch (error) {
      _showSnack('Manual connection failed: $error');
    }
  }

  Future<void> _onPrintDslPressed() {
    return _controller.printDslTicket(
      _readTicketData(),
      printOptions: _currentPrintOptions(),
    );
  }

  Future<void> _onPrintEscTplPressed() {
    return _controller.printEscTplTicket(
      _readTicketData(),
      printOptions: _currentPrintOptions(),
    );
  }

  Future<void> _onPrintHybridPressed() {
    return _controller.printHybridTicket(
      _readTicketData(),
      printOptions: _currentPrintOptions(),
    );
  }

  PrintOptions _currentPrintOptions() {
    return PrintOptions(paperWidthChars: _paperWidthPreset.paperWidthChars);
  }

  DemoTicketData _readTicketData() {
    return DemoTicketData(
      store: _storeCtrl.text.trim(),
      customer: _customerCtrl.text.trim(),
      items: parseDemoItems(_itemsCtrl.text),
      total: _totalCtrl.text.trim(),
      pixPayload: _pixCtrl.text.trim(),
      barcodeValue: _barcodeCtrl.text.trim(),
      shouldCut: _shouldCut,
    );
  }

  void _toggleSearchTransport(DiscoveryTransport transport, bool selected) {
    setState(() {
      if (selected) {
        _searchTransports = <DiscoveryTransport>{
          ..._searchTransports,
          transport,
        };
      } else {
        final next = <DiscoveryTransport>{..._searchTransports};
        next.remove(transport);
        _searchTransports = next;
      }

      if (_searchTransports.isEmpty) {
        _searchTransports = <DiscoveryTransport>{DiscoveryTransport.wifi};
      }
    });
  }

  String _manualModeLabel(ManualConnectionMode mode) {
    return switch (mode) {
      ManualConnectionMode.wifi => 'Wi-Fi',
      ManualConnectionMode.usbVidPid => 'USB (VID/PID)',
      ManualConnectionMode.usbSerial => 'USB (Serial/COM/Path)',
      ManualConnectionMode.bluetooth => 'Bluetooth',
    };
  }

  String _describeDiscoveredPrinter(DiscoveredPrinter printer) {
    final fields = <String>[];
    fields.add(
      'endpoint: ${DemoController.describeEndpoint(printer.endpoint)}',
    );
    if (printer.vendorId != null || printer.productId != null) {
      fields.add(
        'VID/PID: ${printer.vendorId ?? '-'}:${printer.productId ?? '-'}',
      );
    }
    if ((printer.comPort ?? '').isNotEmpty) {
      fields.add('COM: ${printer.comPort}');
    }
    if ((printer.serialNumber ?? '').isNotEmpty) {
      fields.add('SERIAL: ${printer.serialNumber}');
    }
    if ((printer.address ?? '').isNotEmpty) {
      fields.add('ADDR: ${printer.address}');
    }
    if ((printer.host ?? '').isNotEmpty) {
      fields.add('HOST: ${printer.host}');
    }
    if (printer.isPaired != null) {
      fields.add('paired: ${printer.isPaired}');
    }
    return fields.join(' | ');
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _capabilityChip(String label, bool value) {
    return Chip(
      label: Text('$label: ${value ? 'yes' : 'no'}'),
      backgroundColor: value
          ? const Color(0xFFE3F2FD)
          : const Color(0xFFFFEBEE),
    );
  }

  Widget _statusChip(BuildContext context, String label, TriState value) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (value) {
      TriState.yes => scheme.errorContainer,
      TriState.no => scheme.tertiaryContainer,
      TriState.unknown => scheme.surfaceContainerHighest,
    };

    return Chip(
      label: Text('$label: ${DemoController.formatTriState(value)}'),
      backgroundColor: color,
    );
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

import 'package:escpos_printer/escpos_printer.dart';
import 'package:escpos_printer_example/src/demo_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mapeia draft Wi-Fi para WifiEndpoint', () {
    final endpoint = const ManualConnectionDraft(
      mode: ManualConnectionMode.wifi,
      wifiHost: '192.168.0.10',
      wifiPort: '9100',
    ).toEndpoint();

    expect(endpoint, isA<WifiEndpoint>());
    final wifi = endpoint as WifiEndpoint;
    expect(wifi.host, '192.168.0.10');
    expect(wifi.port, 9100);
  });

  test('mapeia draft USB VID/PID aceitando hexadecimal', () {
    final endpoint = const ManualConnectionDraft(
      mode: ManualConnectionMode.usbVidPid,
      usbVendorId: '0x04B8',
      usbProductId: '0x0E15',
      usbInterfaceNumber: '1',
    ).toEndpoint();

    expect(endpoint, isA<UsbEndpoint>());
    final usb = endpoint as UsbEndpoint;
    expect(usb.vendorId, 0x04B8);
    expect(usb.productId, 0x0E15);
    expect(usb.interfaceNumber, 1);
  });

  test('mapeia draft USB serial/path com VID/PID opcionais', () {
    final endpoint = const ManualConnectionDraft(
      mode: ManualConnectionMode.usbSerial,
      usbSerialPath: 'COM4',
      usbSerialVendorId: '1208',
      usbSerialProductId: '3605',
    ).toEndpoint();

    expect(endpoint, isA<UsbEndpoint>());
    final usb = endpoint as UsbEndpoint;
    expect(usb.serialNumber, 'COM4');
    expect(usb.vendorId, 1208);
    expect(usb.productId, 3605);
  });

  test('mapeia draft Bluetooth para endpoint classic/ble', () {
    final endpoint = const ManualConnectionDraft(
      mode: ManualConnectionMode.bluetooth,
      bluetoothAddress: 'AA:BB:CC:DD:EE:FF',
      bluetoothMode: BluetoothMode.ble,
      bluetoothServiceUuid: '00001101-0000-1000-8000-00805F9B34FB',
    ).toEndpoint();

    expect(endpoint, isA<BluetoothEndpoint>());
    final bluetooth = endpoint as BluetoothEndpoint;
    expect(bluetooth.address, 'AA:BB:CC:DD:EE:FF');
    expect(bluetooth.mode, BluetoothMode.ble);
    expect(bluetooth.serviceUuid, '00001101-0000-1000-8000-00805F9B34FB');
  });

  test('lanca FormatException para campos obrigatorios invalidos', () {
    expect(
      () => const ManualConnectionDraft(
        mode: ManualConnectionMode.wifi,
        wifiHost: '',
        wifiPort: '9100',
      ).toEndpoint(),
      throwsFormatException,
    );

    expect(
      () => const ManualConnectionDraft(
        mode: ManualConnectionMode.usbVidPid,
        usbVendorId: 'xpto',
        usbProductId: '10',
      ).toEndpoint(),
      throwsFormatException,
    );
  });

  test('parseCidrsInput separa por virgula, espaco e quebra de linha', () {
    final cidrs = ManualConnectionDraft.parseCidrsInput(
      '192.168.0.0/24,10.0.0.0/24\n172.16.0.0/24',
    );

    expect(
      cidrs,
      containsAll(<String>['192.168.0.0/24', '10.0.0.0/24', '172.16.0.0/24']),
    );
  });
}

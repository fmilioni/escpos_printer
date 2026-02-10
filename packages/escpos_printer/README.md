# escpos_printer

Flutter library/plugin for ESC/POS thermal printing with support for:

- Typed DSL templates
- String templates (`EscTpl`)
- Mustache variables (`{{var}}`, `{{#each}}`, `{{#if}}`)
- ESC/POS operations: `text`, `row`, `qrcode`, `barcode`, `image`, `feed`, `cut`, `drawer`
- Managed session mode (`connect` + `print`) and one-shot mode (`printOnce`)
- In-memory retry and reconnection
- Transports: `Wi-Fi` (Dart), `USB` and `Bluetooth Classic` (native bridge)
- Federated architecture under `packages/`

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  escpos_printer:
    path: ../escpos_printer/packages/escpos_printer
```

## Vertical mobile example

A complete demo app is available at:

- `packages/escpos_printer/example`

It includes:

- printer discovery (`searchPrinters`) for Wi-Fi, USB, and Bluetooth (where supported)
- manual connection via Wi-Fi, USB VID/PID, USB serial/path, and Bluetooth
- demo ticket printing in 3 modes:
  - full DSL
  - full EscTpl string
  - hybrid DSL + `templateBlock`
- status reading and direct commands (`feed`, `cut`, `openCashDrawer`)

Run it with:

```bash
cd /Users/fmilioni/Projetos/escpos_printer/packages/escpos_printer/example
flutter pub get
flutter run
```

## Template flow in the API

You can print with DSL templates, string templates, or a hybrid approach.

```dart
final client = EscPosClient();

await client.connect(const WifiEndpoint('192.168.0.50', port: 9100));

await client.print(
  template: ReceiptTemplate.dsl((b) {
    b.text('MY STORE', bold: true, align: TextAlign.center);
  }),
  variables: const {'store': 'MY STORE'},
  renderOptions: const TemplateRenderOptions(strictMissingVariables: true),
  printOptions: const PrintOptions(
    paperWidthChars: 48,
    initializePrinter: true,
    codeTable: EscPosCodeTable.wcp1252,
  ),
);
```

### Print methods

- `print({required ReceiptTemplate template, Map<String, Object?> variables = const {}, TemplateRenderOptions renderOptions = const TemplateRenderOptions(), PrintOptions printOptions = const PrintOptions()})`
- `printFromString({required String template, required Map<String, Object?> variables, TemplateRenderOptions renderOptions = const TemplateRenderOptions(), PrintOptions printOptions = const PrintOptions()})`
- `printOnce({required PrinterEndpoint endpoint, required ReceiptTemplate template, Map<String, Object?> variables = const {}, TemplateRenderOptions renderOptions = const TemplateRenderOptions(), PrintOptions printOptions = const PrintOptions(), ReconnectPolicy? reconnectPolicy})`

Template-related parameters:

- `template`: `ReceiptTemplate.dsl(...)` or `ReceiptTemplate.string(...)`
- `variables`: map used by Mustache (`{{...}}`)
- `renderOptions.strictMissingVariables`:
  - `true` (default): missing variable throws `TemplateRenderException`
  - `false`: missing variable is ignored

`PrintOptions` parameters:

- `paperWidthChars`: logical print width in columns (for example, `32` for 58mm, `48` for 80mm)
- `initializePrinter`: sends `ESC @` before the job
- `codeTable`: sends `ESC t n` when `initializePrinter=true`
  - default: `EscPosCodeTable.wcp1252` (recommended for PT-BR accented text)
  - use `null` to skip code table selection

## Template modes

- `ReceiptTemplate.dsl(void Function(ReceiptBuilder b) build)`
- `ReceiptTemplate.string(String template)`

Hybrid example (DSL + string block):

```dart
final template = ReceiptTemplate.dsl((b) {
  b.text('Order', bold: true, align: TextAlign.center);
  b.textTemplate('Customer: {{name}}', vars: {'name': 'Ana'});
  b.templateBlock('''
@row
  @col flex=3 Item
  @col flex=1 align=right {{total}}
@endrow
@cut mode=partial
''', vars: {'total': r'R$ 10,50'});
});
```

## Federated architecture

- `packages/escpos_printer`: main package (public API + core)
- `packages/escpos_printer_platform_interface`: typed native transport contract
- `packages/escpos_printer_android`: Android implementation
- `packages/escpos_printer_linux`: Linux implementation
- `packages/escpos_printer_macos`: macOS implementation
- `packages/escpos_printer_windows`: Windows implementation

The root package keeps compatibility and maps `default_package` to federated implementations.

## Full DSL reference (`ReceiptBuilder`)

### Shared text style (`text`, `textTemplate`, and `col`)

Style parameters:

- `bold`: `bool`, default `false`
- `underline`: `bool`, default `false`
- `invert`: `bool`, default `false`
- `font`: `FontType.a | FontType.b`, default `FontType.a`
- `widthScale`: `int` from `1` to `8`, default `1`
- `heightScale`: `int` from `1` to `8`, default `1`
- `align`: `TextAlign.left | TextAlign.center | TextAlign.right`, default `TextAlign.left`

### 1) Text

- `text(String value, { ...style })`
- `textTemplate(String template, {Map<String, Object?> vars = const {}, ...style})`

Notes:

- `textTemplate` renders Mustache before becoming a `TextOp`
- local `vars` override global `variables` from `print`

### 2) String template block inside DSL

- `templateBlock(String template, {Map<String, Object?> vars = const {}})`

Notes:

- renders Mustache, then parses EscTpl
- useful for longer structured blocks while keeping DSL for the rest

### 3) Multiple columns in one line

- `row(List<RowColumnSpec> columns)`
- `col(String text, {int flex = 1, TextAlign align = TextAlign.left, ...style})`

Rules:

- `flex` must be `>= 1`
- `row` must contain at least one column

### 4) QRCode

- `qrCode(String data, {int size = 6, TextAlign align = TextAlign.left})`

Rules:

- `size` from `1` to `16`

### 5) Barcode

- `barcode(String data, {BarcodeType type = BarcodeType.code39, int height = 80, TextAlign align = TextAlign.left})`

Supported `BarcodeType`:

- `upca`
- `upce`
- `ean13`
- `ean8`
- `code39`
- `code128`

Rules:

- `height` from `1` to `255`

### 6) Raster image

- `imageRaster(Uint8List rasterData, {required int widthBytes, required int heightDots, int mode = 0, TextAlign align = TextAlign.left})`

Rules:

- `mode` from `0` to `3`
- `widthBytes > 0`
- `heightDots > 0`

### 7) Feed

- `feed([int lines = 1])`

Rules:

- `lines` from `0` to `255`

### 8) Cut

- `cut([CutMode mode = CutMode.partial])`

`CutMode`:

- `CutMode.partial`
- `CutMode.full`

### 9) Drawer

- `drawer({DrawerPin pin = DrawerPin.pin2, int onMs = 120, int offMs = 240})`

`DrawerPin`:

- `DrawerPin.pin2`
- `DrawerPin.pin5`

Rules:

- `onMs` from `0` to `255`
- `offMs` from `0` to `255`

## Full string template reference (`EscTpl`)

### General syntax

- each command must start with `@`
- blank lines are ignored
- lines starting with `#` are comments
- format: `@command attr=value attr2="value with spaces" content`
- text after attributes becomes command `content`

### Supported commands

#### `@text`

```text
@text align=center bold=true width=2 height=2 Hello
@text text="Hello from attribute"
```

Parameters:

- content text
- optional `text=...` when you do not want positional content
- style keys: `align`, `bold`, `underline`, `invert`, `font`, `width`, `height`

#### `@row` / `@col`

```text
@row
  @col flex=2 Product
  @col flex=1 align=right bold=true 10,50
@endrow
```

`@col` parameters:

- content (or `text=...`)
- `flex` (default `1`, minimum `1`)
- `align` (`left|center|right`)
- `bold`, `underline`, `invert`
- `font` (`a|b`)
- `width` (`1..8`)
- `height` (`1..8`)

#### `@qrcode`

```text
@qrcode size=6 align=center 000201010211...
```

Parameters:

- content or `data=...` (required)
- `size` (`1..16`, default `6`)
- `align` (`left|center|right`, default `left`)

#### `@barcode`

```text
@barcode type=code128 height=90 align=center 789123456789
```

Parameters:

- content or `data=...` (required)
- `type` (`upca|upce|ean13|ean8|code39|code128`, default `code39`)
- `height` (`1..255`, default `80`)
- `align` (`left|center|right`, default `left`)

#### `@image`

```text
@image widthBytes=48 heightDots=120 mode=0 align=center iVBORw0KGgoAAA...
```

Parameters:

- content or `data=...` in Base64 (required)
- `widthBytes` (required, `> 0`)
- `heightDots` (required, `> 0`)
- `mode` (`0..3`, default `0`)
- `align` (`left|center|right`, default `left`)

#### `@feed`

```text
@feed lines=2
@feed 3
```

Parameters:

- `lines` (`0..255`, default `1`)
- numeric positional content also supported (`@feed 3`)

#### `@cut`

```text
@cut mode=partial
@cut mode=full
```

Parameters:

- `mode`: `partial` (default) or `full`

#### `@drawer`

```text
@drawer pin=2 on=120 off=240
```

Parameters:

- `pin`: `2` (default) or `5`
- `on`: `0..255` (default `120`)
- `off`: `0..255` (default `240`)

### Parsing and validation rules

- `@endrow` without `@row` throws an error
- `@row` block without `@endrow` throws an error
- inside `@row`, only `@col` and `@endrow` are allowed
- unclosed quotes throw `TemplateParseException`
- invalid attribute type/range throws `TemplateValidationException`

## Mustache support in templates

### Simple variables

```text
{{store}}
{{customer.name}}
{{items.0.price}}
```

### Loop

```text
{{#each items}}
@text {{this.name}} - {{this.price}}
{{/each}}
```

### Condition

```text
{{#if shouldCut}}
@cut mode=full
{{/if}}
```

`#if` evaluates to true for:

- `bool == true`
- non-zero number
- non-empty `String`
- non-empty `Iterable`/`Map`

Not supported yet:

- `{{else}}`
- custom helpers

## Full template string example

```dart
import 'package:escpos_printer/escpos_printer.dart';

final client = EscPosClient();

await client.connect(const WifiEndpoint('192.168.0.50', port: 9100));

final template = ReceiptTemplate.dsl((b) {
  b.text('MY STORE', align: TextAlign.center, bold: true);
  b.textTemplate('Customer: {{name}}', vars: {'name': 'Ana'});
  b.templateBlock('''
@row
  @col flex=2 Product
  @col flex=1 align=right {{price}}
@endrow
@qrcode size=5 {{pix}}
@feed lines=2
@cut mode=partial
''', vars: {
    'price': '10,50',
    'pix': '000201010211...'
  });
});

await client.print(template: template);
await client.disconnect();
```

Direct `printFromString` example:

```dart
await client.printFromString(
  template: '''
@text align=center bold=true {{store}}
{{#each items}}
@row
  @col flex=8 {{name}}
  @col flex=4 align=right {{price}}
@endrow
{{/each}}
{{#if shouldCut}}
@cut mode=full
{{/if}}
''',
  variables: {
    'store': 'Market',
    'items': [
      {'name': 'Coffee', 'price': '9,90'},
      {'name': 'Bread', 'price': '2,50'},
    ],
    'shouldCut': true,
  },
);
```

## Printer discovery

### Public API

```dart
Future<List<DiscoveredPrinter>> searchPrinters({
  PrinterDiscoveryOptions options = const PrinterDiscoveryOptions(),
})
```

### `PrinterDiscoveryOptions`

- `transports`: set of transports to search
  - default: `{DiscoveryTransport.wifi, DiscoveryTransport.usb, DiscoveryTransport.bluetooth}`
- `timeout`: global discovery timeout (default `8s`)
- `wifiPort`: TCP port for Wi-Fi probing (default `9100`)
- `wifiHostTimeout`: per-host timeout for Wi-Fi probes (default `250ms`)
- `wifiMaxConcurrentHosts`: concurrent Wi-Fi probe limit (default `64`)
- `wifiCidrs`: list of CIDRs to scan over Wi-Fi
  - if empty, local IPv4 interfaces are detected and `/24` ranges are used

### `DiscoveredPrinter`

Main fields:

- `id`
- `name`
- `transport` (`wifi`, `usb`, `bluetooth`)
- `endpoint` (ready for `client.connect(...)`)
- `vendorId`, `productId`
- `comPort`, `serialNumber`
- `address`, `host`
- `isPaired`
- `metadata`

### Complete example

```dart
final client = EscPosClient();

final printers = await client.searchPrinters(
  options: const PrinterDiscoveryOptions(
    transports: <DiscoveryTransport>{
      DiscoveryTransport.wifi,
      DiscoveryTransport.usb,
      DiscoveryTransport.bluetooth,
    },
    timeout: Duration(seconds: 6),
    wifiPort: 9100,
  ),
);

for (final printer in printers) {
  print('[${printer.transport.name}] ${printer.name ?? printer.id}');
}

if (printers.isNotEmpty) {
  await client.connect(printers.first.endpoint);
  await client.printFromString(
    template: '@text Discovery test\\n@cut mode=partial',
    variables: const {},
  );
  await client.disconnect();
}
```

### Platform/transport behavior

- Wi-Fi: local subnet scan with TCP probe on the configured port (`9100` by default)
- Bluetooth: paired Classic devices only (BLE out of scope in this phase)
- USB:
  - Android/Linux: discovery by `vendorId/productId` (when available, also serial/interface)
  - macOS: serial device discovery (`/dev/cu.*`, `/dev/tty.*`) with `VID/PID` enrichment when available
  - Windows: COM + `VID/PID` in the same result

### Important notes

- Discovery is `best effort`: a transport failure does not cancel other transport results
- On Windows, USB connection accepts:
  - direct `serialNumber`/`COM`
  - or `vendorId + productId` with COM resolution when possible

## Transport notes

- `Wi-Fi` has a default Dart implementation over raw TCP (`9100`)
- `USB` and `Bluetooth` use a typed contract (`escpos_printer_platform_interface`) over native channel (`escpos_printer/native_transport`) and are wired in `DefaultTransportFactory`
- Android: native USB (`UsbManager`) and Bluetooth Classic (`BluetoothSocket` RFCOMM)
- Linux: native USB (`libusb`) and Bluetooth Classic (`BlueZ RFCOMM`)
- macOS: Bluetooth Classic via `IOBluetooth` and USB via device file (`serialNumber` must be `/dev/...`)
- Windows: Bluetooth Classic RFCOMM (channel 1) and USB/serial via device path (`serialNumber`, e.g. `COM3`)

## Platform prerequisites

- Linux/Raspberry: install build/runtime dependencies (`libusb-1.0` and `bluez`)
- macOS: grant Bluetooth access in the host app when needed
- Windows: for USB/serial, endpoint must point to an accessible port/handle (for example `COM3`)

## Printer status

### Status API

- `Future<PrinterStatus> getStatus()`
- `PrintResult.status` (returned by `print`, `printFromString`, and `printOnce`)
- `EscPosClient.transportCapabilities` (current session capabilities)
- `EscPosClient.transportSessionId` (current native session ID)

### Return model (`PrinterStatus`)

All fields use `TriState`:

- `TriState.yes`
- `TriState.no`
- `TriState.unknown`

Fields:

- `paperOut`
- `paperNearEnd`
- `coverOpen`
- `cutterError`
- `offline`
- `drawerSignal`

### Behavior by transport

- Status is `best effort`
- If real-time status is unsupported on a transport/platform, fields return `unknown`
- If `getStatus()` fails due to driver/channel issues, client returns `PrinterStatus.unknown()`

### Example 1: query status after connect

```dart
final client = EscPosClient();
await client.connect(const WifiEndpoint('192.168.0.50', port: 9100));

final capabilities = client.transportCapabilities;
if (capabilities?.supportsRealtimeStatus == true) {
  final status = await client.getStatus();
  if (status.paperOut == TriState.yes) {
    print('Printer is out of paper');
  }
} else {
  print('Realtime status is not available for this session');
}
```

### Example 2: read status from print result

```dart
final result = await client.printFromString(
  template: '@text Order OK\n@cut mode=partial',
  variables: const {},
);

print('Bytes sent: ${result.bytesSent}');
print('Duration: ${result.duration.inMilliseconds} ms');
print('PaperOut: ${result.status.paperOut}');
print('PaperNearEnd: ${result.status.paperNearEnd}');
```

## Template errors

- Missing variable: `TemplateRenderException`
- Invalid command: `TemplateParseException`
- Invalid value/attribute: `TemplateValidationException`

## Tests

```bash
flutter test --no-pub
```

## Supported API endpoints

```dart
const wifi = WifiEndpoint('192.168.0.50', port: 9100);
const usb = UsbEndpoint(0x04b8, 0x0e15, interfaceNumber: 0);
const bt = BluetoothEndpoint('AA:BB:CC:DD:EE:FF', mode: BluetoothMode.classic);
```

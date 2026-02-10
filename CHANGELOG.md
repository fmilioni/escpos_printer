## 0.0.2

- Fixed PT-BR character encoding in the ESC/POS encoder by sending `ESC t 16` (`WCP1252`) by default, improving accented text output such as `FAÇADE` and `RÉSUMÉ`.
- Added `PrintOptions.codeTable` to configure/disable code table selection per print job.
- Adjusted font style reset after `TextOp` to avoid font state leaking across blocks.
- Updated Windows plugin:
  - CMake target renamed to `escpos_printer_windows_plugin`
  - includes moved to `include/escpos_printer_windows/...`
  - added `WIN32_LEAN_AND_MEAN`
  - include order fixed (`winsock2.h` before `windows.h`) to prevent conflicts.
- Updated README with `PrintOptions.codeTable` documentation.
- Added tests covering default code table emission and optional disabling.

## 0.0.1

- Implemented core `EscPosClient` API with session mode, one-shot printing, and reconnection.
- Added typed DSL template support (`ReceiptTemplate.dsl`) and string template support (`ReceiptTemplate.string`).
- Added `textTemplate` and `templateBlock` modules for hybrid composition.
- Implemented Mustache rendering with `{{var}}`, `#each`, and `#if`.
- Implemented EscTpl parser (`@text`, `@row/@col`, `@qrcode`, `@barcode`, `@image`, `@feed`, `@cut`, `@drawer`).
- Implemented ESC/POS encoder for core commands.
- Added default Wi-Fi transport via TCP socket.
- Added native bridge for `USB` and `Bluetooth` via `MethodChannel` (`escpos_printer/native_transport`).
- `DefaultTransportFactory` now routes:
  - `WifiEndpoint` -> `WifiSocketTransport`
  - `UsbEndpoint` -> `PlatformUsbTransport`
  - `BluetoothEndpoint` -> `PlatformBluetoothTransport`
- Added Android plugin with native USB/Bluetooth Classic support.
- Added Linux plugin with USB (`libusb`) and Bluetooth Classic (`BlueZ RFCOMM`).
- Added macOS plugin with Bluetooth Classic (`IOBluetooth`) and USB via device path (`serialNumber` with `/dev/...`).
- Added Windows plugin with Bluetooth Classic RFCOMM and USB/serial via device path (`serialNumber`, e.g. `COM3`).
- Created federated structure under `packages/` with `escpos_printer`, `escpos_printer_platform_interface`, `escpos_printer_android`, `escpos_printer_linux`, `escpos_printer_macos`, and `escpos_printer_windows`.
- Added typed native transport contract in `escpos_printer_platform_interface`.
- Added unit/integration tests for rendering, parsing, reconnection, and byte generation.
- Added printer discovery through `EscPosClient.searchPrinters(...)` with:
  - Wi-Fi subnet scan and TCP probe (`9100`)
  - Native USB on Android/Linux/macOS/Windows
  - Paired Bluetooth Classic devices (where supported by platform/permissions)
- Added new public discovery models:
  - `DiscoveryTransport`
  - `PrinterDiscoveryOptions`
  - `DiscoveredPrinter`
- Added combined USB support on Windows:
  - discovery by `COM`
  - enrichment with `vendorId/productId`
  - fallback connection by `vendorId/productId` to resolve COM when available.

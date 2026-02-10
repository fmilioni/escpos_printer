# escpos_printer (workspace)

This directory is a **monorepo workspace**. The public package implementation is located at:

- `packages/escpos_printer`

The root `lib/` folder was intentionally removed. Use the package from `packages/escpos_printer`.

## How to use in your app (local path)

```yaml
dependencies:
  escpos_printer:
    path: ../escpos_printer/packages/escpos_printer
```

## Full documentation

Complete API documentation (DSL/String templates, parameters, `searchPrinters`, status, transports, and examples) is available at:

- [`packages/escpos_printer/README.md`](packages/escpos_printer/README.md)
- Vertical mobile example: [`packages/escpos_printer/example`](packages/escpos_printer/example)

## Federated structure

- `packages/escpos_printer`: public API and core
- `packages/escpos_printer_platform_interface`: typed contract
- `packages/escpos_printer_android`: Android implementation
- `packages/escpos_printer_linux`: Linux implementation
- `packages/escpos_printer_macos`: macOS implementation
- `packages/escpos_printer_windows`: Windows implementation

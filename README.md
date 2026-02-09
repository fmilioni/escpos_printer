# escpos_printer (workspace)

Este diretório é um **workspace monorepo**. A implementação pública do package está em:

- `packages/escpos_printer`

A pasta `lib/` da raiz foi removida de propósito. Use o package da pasta `packages/escpos_printer`.

## Como usar no app (path local)

```yaml
dependencies:
  escpos_printer:
    path: ../escpos_printer/packages/escpos_printer
```

## Documentação completa

A documentação de API (templates DSL/String, parâmetros, `searchPrinters`, status, transportes e exemplos) está em:

- [`packages/escpos_printer/README.md`](packages/escpos_printer/README.md)

## Estrutura federada

- `packages/escpos_printer`: API pública e core
- `packages/escpos_printer_platform_interface`: contrato tipado
- `packages/escpos_printer_android`: implementação Android
- `packages/escpos_printer_linux`: implementação Linux
- `packages/escpos_printer_macos`: implementação macOS
- `packages/escpos_printer_windows`: implementação Windows

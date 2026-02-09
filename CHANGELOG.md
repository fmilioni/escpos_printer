## 0.0.1

- Implementada API principal `EscPosClient` com sessão, impressão one-shot e reconexão.
- Adicionado suporte a template DSL (`ReceiptTemplate.dsl`) e template string (`ReceiptTemplate.string`).
- Adicionados módulos `textTemplate` e `templateBlock` para composição híbrida.
- Implementada renderização Mustache com `{{var}}`, `#each` e `#if`.
- Implementado parser EscTpl (`@text`, `@row/@col`, `@qrcode`, `@barcode`, `@image`, `@feed`, `@cut`, `@drawer`).
- Implementado encoder ESC/POS para comandos essenciais.
- Transporte padrão Wi-Fi via socket TCP e abstrações para USB/Bluetooth via `TransportFactory`.
- Testes unitários/integrados para renderização, parsing, reconexão e geração de bytes.

# escpos_printer

Library Flutter para impressão térmica ESC/POS com suporte a:

- Template DSL tipado
- Template textual via `String` (EscTpl)
- Variáveis Mustache (`{{var}}`, `{{#each}}`, `{{#if}}`)
- Operações ESC/POS: `text`, `row`, `qrcode`, `barcode`, `image`, `feed`, `cut`, `drawer`
- Sessão gerenciada (`connect` + `print`) e one-shot (`printOnce`)
- Retry e reconexão em memória

## Instalação

Adicione no `pubspec.yaml`:

```yaml
dependencies:
  escpos_printer:
    path: ../escpos_printer
```

## Uso rápido

```dart
import 'package:escpos_printer/escpos_printer.dart';

final client = EscPosClient();

await client.connect(const WifiEndpoint('192.168.0.50', port: 9100));

final template = ReceiptTemplate.dsl((b) {
  b.text('MINHA LOJA', align: TextAlign.center, bold: true);
  b.textTemplate('Cliente: {{name}}', vars: {'name': 'Ana'});
  b.templateBlock('''
@row
  @col flex=2 Produto
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

## Template String (EscTpl)

Exemplo para `printFromString`:

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
    'store': 'Mercadinho',
    'items': [
      {'name': 'Cafe', 'price': '9,90'},
      {'name': 'Pao', 'price': '2,50'},
    ],
    'shouldCut': true,
  },
);
```

## Observações de transporte

- `Wi-Fi` possui implementação padrão via socket TCP (`9100`).
- `USB` e `Bluetooth` estão modelados na API (`UsbEndpoint`, `BluetoothEndpoint`) e podem ser conectados via `TransportFactory` customizado.
- Para suporte nativo completo por plataforma (Windows/Linux/macOS/Android), implemente `PrinterTransport` nativo e injete no `EscPosClient`.

## Erros de template

- Variável ausente: `TemplateRenderException`
- Comando inválido: `TemplateParseException`
- Valor/atributo inválido: `TemplateValidationException`

## Testes

```bash
flutter test --no-pub
```

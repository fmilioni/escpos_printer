# escpos_printer

Library Flutter para impressão térmica ESC/POS com suporte a:

- Template DSL tipado
- Template textual via `String` (EscTpl)
- Variáveis Mustache (`{{var}}`, `{{#each}}`, `{{#if}}`)
- Operações ESC/POS: `text`, `row`, `qrcode`, `barcode`, `image`, `feed`, `cut`, `drawer`
- Sessão gerenciada (`connect` + `print`) e one-shot (`printOnce`)
- Retry e reconexão em memória
- Transportes: `Wi-Fi` (Dart), `USB` e `Bluetooth Classic` (bridge nativa)
- Arquitetura federada em `packages/`

## Instalação

Adicione no `pubspec.yaml`:

```yaml
dependencies:
  escpos_printer:
    path: ../escpos_printer
```

## Fluxo de template na API

Você pode imprimir com template DSL, template string, ou misto.

```dart
final client = EscPosClient();

await client.connect(const WifiEndpoint('192.168.0.50', port: 9100));

await client.print(
  template: ReceiptTemplate.dsl((b) {
    b.text('MINHA LOJA', bold: true, align: TextAlign.center);
  }),
  variables: const {'store': 'MINHA LOJA'},
  renderOptions: const TemplateRenderOptions(strictMissingVariables: true),
  printOptions: const PrintOptions(paperWidthChars: 48, initializePrinter: true),
);
```

### Métodos de impressão com template

- `print({required ReceiptTemplate template, Map<String, Object?> variables = const {}, TemplateRenderOptions renderOptions = const TemplateRenderOptions(), PrintOptions printOptions = const PrintOptions()})`
- `printFromString({required String template, required Map<String, Object?> variables, TemplateRenderOptions renderOptions = const TemplateRenderOptions(), PrintOptions printOptions = const PrintOptions()})`
- `printOnce({required PrinterEndpoint endpoint, required ReceiptTemplate template, Map<String, Object?> variables = const {}, TemplateRenderOptions renderOptions = const TemplateRenderOptions(), PrintOptions printOptions = const PrintOptions(), ReconnectPolicy? reconnectPolicy})`

Parâmetros de template:

- `template`: `ReceiptTemplate.dsl(...)` ou `ReceiptTemplate.string(...)`.
- `variables`: mapa de variáveis usado pelo Mustache (`{{...}}`).
- `renderOptions.strictMissingVariables`:
  - `true` (default): variável ausente gera `TemplateRenderException`.
  - `false`: variável ausente é ignorada.

## Modos de template

- `ReceiptTemplate.dsl(void Function(ReceiptBuilder b) build)`
- `ReceiptTemplate.string(String template)`

Exemplo híbrido (DSL + bloco string):

```dart
final template = ReceiptTemplate.dsl((b) {
  b.text('Pedido', bold: true, align: TextAlign.center);
  b.textTemplate('Cliente: {{name}}', vars: {'name': 'Ana'});
  b.templateBlock('''
@row
  @col flex=3 Item
  @col flex=1 align=right {{total}}
@endrow
@cut mode=partial
''', vars: {'total': 'R\$ 10,50'});
});
```

## Arquitetura Federada

- `packages/escpos_printer`: package principal (API pública e core).
- `packages/escpos_printer_platform_interface`: contrato tipado de transporte nativo.
- `packages/escpos_printer_android`: implementação Android.
- `packages/escpos_printer_linux`: implementação Linux.
- `packages/escpos_printer_macos`: implementação macOS.
- `packages/escpos_printer_windows`: implementação Windows.

O package raiz mantém compatibilidade e mapeia `default_package` para as implementações federadas.

## Referência completa do DSL (`ReceiptBuilder`)

### Estilo de texto reutilizado por `text`, `textTemplate` e `col`

Parâmetros de estilo:

- `bold`: `bool`, default `false`
- `underline`: `bool`, default `false`
- `invert`: `bool`, default `false`
- `font`: `FontType.a | FontType.b`, default `FontType.a`
- `widthScale`: `int` de `1` a `8`, default `1`
- `heightScale`: `int` de `1` a `8`, default `1`
- `align`: `TextAlign.left | TextAlign.center | TextAlign.right`, default `TextAlign.left`

### 1) Texto

- `text(String value, { ...estilo })`
- `textTemplate(String template, {Map<String, Object?> vars = const {}, ...estilo})`

Observações:

- `textTemplate` renderiza Mustache antes de virar `TextOp`.
- `vars` local tem precedência sobre `variables` global do `print`.

### 2) Bloco de template string no DSL

- `templateBlock(String template, {Map<String, Object?> vars = const {}})`

Observações:

- Renderiza Mustache e depois parseia EscTpl.
- Útil para trechos longos de layout sem perder DSL no restante.

### 3) Múltiplas colunas na mesma linha

- `row(List<RowColumnSpec> columns)`
- `col(String text, {int flex = 1, TextAlign align = TextAlign.left, ...estilo})`

Regras:

- `flex` deve ser `>= 1`.
- `row` precisa de ao menos 1 coluna.

### 4) QRCode

- `qrCode(String data, {int size = 6, TextAlign align = TextAlign.left})`

Regras:

- `size` de `1` a `16`.

### 5) Código de barras

- `barcode(String data, {BarcodeType type = BarcodeType.code39, int height = 80, TextAlign align = TextAlign.left})`

`BarcodeType` suportados:

- `upca`
- `upce`
- `ean13`
- `ean8`
- `code39`
- `code128`

Regras:

- `height` de `1` a `255`.

### 6) Imagem raster

- `imageRaster(Uint8List rasterData, {required int widthBytes, required int heightDots, int mode = 0, TextAlign align = TextAlign.left})`

Regras:

- `mode` de `0` a `3`
- `widthBytes > 0`
- `heightDots > 0`

### 7) Feed

- `feed([int lines = 1])`

Regras:

- `lines` de `0` a `255`.

### 8) Corte

- `cut([CutMode mode = CutMode.partial])`

`CutMode`:

- `CutMode.partial`
- `CutMode.full`

### 9) Gaveta

- `drawer({DrawerPin pin = DrawerPin.pin2, int onMs = 120, int offMs = 240})`

`DrawerPin`:

- `DrawerPin.pin2`
- `DrawerPin.pin5`

Regras:

- `onMs` de `0` a `255`
- `offMs` de `0` a `255`

## Referência completa do template string (`EscTpl`)

### Sintaxe geral

- Cada comando deve iniciar com `@`.
- Linhas vazias são ignoradas.
- Linhas iniciadas com `#` são comentários.
- Formato: `@comando attr=valor attr2="valor com espaco" conteudo`
- Se houver conteúdo após os atributos, ele vira `content` do comando.

### Comandos suportados

#### `@text`

```text
@text align=center bold=true width=2 height=2 Olá
@text text="Olá com atributo"
```

Parâmetros:

- Conteúdo: texto da linha.
- Opcionalmente `text=...` quando não quiser usar conteúdo posicional.
- Estilo aceito: `align`, `bold`, `underline`, `invert`, `font`, `width`, `height`.

#### `@row` / `@col`

```text
@row
  @col flex=2 Produto
  @col flex=1 align=right bold=true 10,50
@endrow
```

Parâmetros de `@col`:

- Conteúdo (ou `text=...`)
- `flex` (default `1`, mínimo `1`)
- `align` (`left|center|right`)
- `bold`, `underline`, `invert`
- `font` (`a|b`)
- `width` (`1..8`)
- `height` (`1..8`)

#### `@qrcode`

```text
@qrcode size=6 align=center 000201010211...
```

Parâmetros:

- Conteúdo ou `data=...` (obrigatório)
- `size` (`1..16`, default `6`)
- `align` (`left|center|right`, default `left`)

#### `@barcode`

```text
@barcode type=code128 height=90 align=center 789123456789
```

Parâmetros:

- Conteúdo ou `data=...` (obrigatório)
- `type` (`upca|upce|ean13|ean8|code39|code128`, default `code39`)
- `height` (`1..255`, default `80`)
- `align` (`left|center|right`, default `left`)

#### `@image`

```text
@image widthBytes=48 heightDots=120 mode=0 align=center iVBORw0KGgoAAA...
```

Parâmetros:

- Conteúdo ou `data=...` com Base64 (obrigatório)
- `widthBytes` (obrigatório, `> 0`)
- `heightDots` (obrigatório, `> 0`)
- `mode` (`0..3`, default `0`)
- `align` (`left|center|right`, default `left`)

#### `@feed`

```text
@feed lines=2
@feed 3
```

Parâmetros:

- `lines` (`0..255`, default `1`)
- Também aceita conteúdo numérico (`@feed 3`)

#### `@cut`

```text
@cut mode=partial
@cut mode=full
```

Parâmetros:

- `mode`: `partial` (default) ou `full`

#### `@drawer`

```text
@drawer pin=2 on=120 off=240
```

Parâmetros:

- `pin`: `2` (default) ou `5`
- `on`: `0..255` (default `120`)
- `off`: `0..255` (default `240`)

### Regras de parsing e validação

- `@endrow` sem `@row` gera erro.
- Bloco `@row` sem `@endrow` gera erro.
- Dentro de `@row`, somente `@col` e `@endrow` são permitidos.
- Aspas não fechadas em comando geram `TemplateParseException`.
- Tipo/intervalo inválido de atributo gera `TemplateValidationException`.

## Mustache suportado no template

### Variáveis simples

```text
{{store}}
{{customer.name}}
{{items.0.price}}
```

### Repetição

```text
{{#each items}}
@text {{this.name}} - {{this.price}}
{{/each}}
```

### Condição

```text
{{#if shouldCut}}
@cut mode=full
{{/if}}
```

`#if` considera verdadeiro:

- `bool == true`
- número diferente de `0`
- `String` não vazia
- `Iterable`/`Map` não vazio

Não suportado no momento:

- `{{else}}`
- helpers custom

## Exemplo completo com template string

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

Exemplo direto com `printFromString`:

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

- `Wi-Fi` possui implementação padrão em Dart via socket TCP (`9100`).
- `USB` e `Bluetooth` usam contrato tipado (`escpos_printer_platform_interface`) sobre canal nativo (`escpos_printer/native_transport`) e já estão ligados no `DefaultTransportFactory`.
- Android: implementação nativa de sessão/`write` para USB (`UsbManager`) e Bluetooth Classic (`BluetoothSocket` RFCOMM).
- Linux: implementação nativa para USB (`libusb`) e Bluetooth Classic (`BlueZ RFCOMM`).
- macOS: Bluetooth Classic via `IOBluetooth` e USB via device file (`serialNumber` deve receber caminho `/dev/...`).
- Windows: Bluetooth Classic RFCOMM (canal 1) e USB/serial via device path (`serialNumber`, ex: `COM3`).

## Pré-requisitos por plataforma

- Linux/Raspberry: instalar dependências de build/runtime (`libusb-1.0` e `bluez`).
- macOS: permitir Bluetooth no app host quando necessário.
- Windows: para USB/serial, o endpoint deve apontar para porta/handle acessível (ex: `COM3`).

## Erros de template

- Variável ausente: `TemplateRenderException`
- Comando inválido: `TemplateParseException`
- Valor/atributo inválido: `TemplateValidationException`

## Testes

```bash
flutter test --no-pub
```

## Endpoints suportados na API

```dart
const wifi = WifiEndpoint('192.168.0.50', port: 9100);
const usb = UsbEndpoint(0x04b8, 0x0e15, interfaceNumber: 0);
const bt = BluetoothEndpoint('AA:BB:CC:DD:EE:FF', mode: BluetoothMode.classic);
```

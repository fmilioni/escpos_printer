# escpos_printer_example

App de exemplo mobile (layout vertical) para demonstrar o package `escpos_printer` com:

- busca de impressoras (`searchPrinters`) em Wi-Fi, USB e Bluetooth (onde suportado)
- conexao manual em todos os endpoints suportados
- impressao de ticket de exemplo com DSL, EscTpl string e modo hibrido
- leitura de status e comandos diretos (`feed`, `cut`, `openCashDrawer`)
- configuracao de largura do papel no print (`58mm` ou `80mm`, default `80mm`)

## Executar

```bash
cd /Users/fmilioni/Projetos/escpos_printer/packages/escpos_printer/example
flutter pub get
flutter run
```

## Fluxo sugerido

1. Abra a secao **Busca de impressoras** e clique em `Buscar impressoras`.
2. Conecte por um item descoberto, ou use **Conexao manual**.
3. Em **Status e comandos diretos**, valide `Ler status`, `Feed`, `Cut` e `Abrir gaveta`.
4. Em **Imprimir ticket de exemplo**, teste os tres botoes de impressao:
   - DSL completo
   - EscTpl string completo
   - Hibrido DSL + templateBlock

## Permissoes Android

O exemplo declara permissao para:

- `INTERNET`
- `BLUETOOTH`, `BLUETOOTH_ADMIN`
- `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`
- `android.hardware.usb.host` (feature opcional)

Durante busca/conexao Bluetooth no Android, o app solicita permissao em runtime.

## Arquivos principais

- `lib/src/demo_page.dart`: UI vertical completa
- `lib/src/demo_controller.dart`: estado e acoes assicronas
- `lib/src/ticket_samples.dart`: templates de ticket
- `lib/src/sample_image.dart`: geracao de raster para comando de imagem

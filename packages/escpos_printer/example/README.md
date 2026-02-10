# escpos_printer_example

Mobile example app (vertical layout) to demonstrate `escpos_printer` with:

- printer discovery (`searchPrinters`) over Wi-Fi, USB, and Bluetooth (where supported)
- manual connection for all supported endpoints
- sample ticket printing with DSL, EscTpl string, and hybrid mode
- status reading and direct commands (`feed`, `cut`, `openCashDrawer`)
- paper width selection for printing (`58mm` or `80mm`, default `80mm`)

## Run

```bash
cd /Users/fmilioni/Projetos/escpos_printer/packages/escpos_printer/example
flutter pub get
flutter run
```

## Suggested flow

1. Open the **Printer discovery** section and tap `Search printers`.
2. Connect using a discovered device, or use **Manual connection**.
3. In **Status and direct commands**, validate `Read status`, `Feed`, `Cut`, and `Open drawer`.
4. In **Print sample ticket**, test the three print buttons:
   - Full DSL
   - Full EscTpl string
   - Hybrid DSL + templateBlock

## Android permissions

The example declares permissions for:

- `INTERNET`
- `BLUETOOTH`, `BLUETOOTH_ADMIN`
- `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`
- `android.hardware.usb.host` (optional feature)

During Bluetooth discovery/connection on Android, the app requests runtime permission.

## Main files

- `lib/src/demo_page.dart`: complete vertical UI
- `lib/src/demo_controller.dart`: state and async actions
- `lib/src/ticket_samples.dart`: ticket templates
- `lib/src/sample_image.dart`: raster generation for image command

//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <escpos_printer_linux/escpos_printer_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) escpos_printer_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "EscposPrinterPlugin");
  escpos_printer_plugin_register_with_registrar(escpos_printer_linux_registrar);
}

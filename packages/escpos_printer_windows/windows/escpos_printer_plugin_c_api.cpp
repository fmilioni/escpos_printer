#include "include/escpos_printer_windows/escpos_printer_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "include/escpos_printer_windows/escpos_printer_plugin.h"

void EscposPrinterPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar)
{
    escpos_printer::EscposPrinterPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

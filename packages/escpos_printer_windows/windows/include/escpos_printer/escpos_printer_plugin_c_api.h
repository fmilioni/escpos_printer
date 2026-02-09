#ifndef FLUTTER_PLUGIN_ESCPOS_PRINTER_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_ESCPOS_PRINTER_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void EscposPrinterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_ESCPOS_PRINTER_PLUGIN_C_API_H_

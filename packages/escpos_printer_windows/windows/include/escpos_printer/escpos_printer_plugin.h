#ifndef FLUTTER_PLUGIN_ESCPOS_PRINTER_PLUGIN_H_
#define FLUTTER_PLUGIN_ESCPOS_PRINTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace escpos_printer
{

class EscposPrinterPlugin : public flutter::Plugin
{
  public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

    EscposPrinterPlugin();
    virtual ~EscposPrinterPlugin();

    EscposPrinterPlugin(const EscposPrinterPlugin &) = delete;
    EscposPrinterPlugin &operator=(const EscposPrinterPlugin &) = delete;

  private:
    void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

} // namespace escpos_printer

#endif // FLUTTER_PLUGIN_ESCPOS_PRINTER_PLUGIN_H_

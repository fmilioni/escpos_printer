#include "include/escpos_printer/escpos_printer_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winsock2.h>
#include <ws2bth.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace escpos_printer {
namespace {

enum class SessionKind {
  kWifi,
  kBluetooth,
  kUsbFile,
};

struct NativeSession {
  SessionKind kind;
  SOCKET socket = INVALID_SOCKET;
  HANDLE handle = INVALID_HANDLE_VALUE;
};

std::mutex g_mutex;
std::unordered_map<std::string, std::unique_ptr<NativeSession>> g_sessions;
int64_t g_session_counter = 1;
bool g_winsock_initialized = false;

using EncodableMap = flutter::EncodableMap;
using EncodableValue = flutter::EncodableValue;

std::string NextSessionId() {
  std::ostringstream out;
  out << "windows-session-" << g_session_counter++;
  return out.str();
}

void EnsureWinsock() {
  if (g_winsock_initialized) {
    return;
  }

  WSADATA data;
  int rc = WSAStartup(MAKEWORD(2, 2), &data);
  if (rc != 0) {
    throw std::runtime_error("Falha ao inicializar Winsock.");
  }

  g_winsock_initialized = true;
}

void CloseSession(NativeSession* session) {
  if (session == nullptr) {
    return;
  }

  if (session->socket != INVALID_SOCKET) {
    closesocket(session->socket);
    session->socket = INVALID_SOCKET;
  }

  if (session->handle != INVALID_HANDLE_VALUE) {
    CloseHandle(session->handle);
    session->handle = INVALID_HANDLE_VALUE;
  }
}

void CloseAllSessions() {
  std::unordered_map<std::string, std::unique_ptr<NativeSession>> local;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    local.swap(g_sessions);
  }

  for (auto& entry : local) {
    CloseSession(entry.second.get());
  }
}

const EncodableValue* FindArg(const EncodableMap& args, const char* key) {
  auto iterator = args.find(EncodableValue(key));
  if (iterator == args.end()) {
    return nullptr;
  }

  return &iterator->second;
}

std::string RequireString(const EncodableMap& args, const char* key) {
  const EncodableValue* raw = FindArg(args, key);
  if (raw == nullptr) {
    throw std::runtime_error(std::string("Campo obrigatorio ausente: ") + key);
  }

  if (const auto* value = std::get_if<std::string>(raw)) {
    if (!value->empty()) {
      return *value;
    }
  }

  throw std::runtime_error(std::string("Campo string invalido: ") + key);
}

int RequireInt(const EncodableMap& args, const char* key) {
  const EncodableValue* raw = FindArg(args, key);
  if (raw == nullptr) {
    throw std::runtime_error(std::string("Campo inteiro obrigatorio ausente: ") + key);
  }

  if (const auto* value = std::get_if<int32_t>(raw)) {
    return *value;
  }
  if (const auto* value64 = std::get_if<int64_t>(raw)) {
    return static_cast<int>(*value64);
  }

  throw std::runtime_error(std::string("Campo inteiro invalido: ") + key);
}

std::optional<int> ReadOptionalInt(const EncodableMap& args, const char* key) {
  const EncodableValue* raw = FindArg(args, key);
  if (raw == nullptr) {
    return std::nullopt;
  }

  if (const auto* value = std::get_if<int32_t>(raw)) {
    return *value;
  }
  if (const auto* value64 = std::get_if<int64_t>(raw)) {
    return static_cast<int>(*value64);
  }

  return std::nullopt;
}

std::vector<uint8_t> RequireBytes(const EncodableMap& args, const char* key) {
  const EncodableValue* raw = FindArg(args, key);
  if (raw == nullptr) {
    throw std::runtime_error(std::string("Campo bytes obrigatorio ausente: ") + key);
  }

  if (const auto* bytes = std::get_if<std::vector<uint8_t>>(raw)) {
    return *bytes;
  }

  throw std::runtime_error(std::string("Campo bytes invalido: ") + key);
}

EncodableMap BuildCapabilities(bool realtime_status = false) {
  return EncodableMap{{EncodableValue("supportsPartialCut"), EncodableValue(true)},
                      {EncodableValue("supportsFullCut"), EncodableValue(true)},
                      {EncodableValue("supportsDrawerKick"), EncodableValue(true)},
                      {EncodableValue("supportsRealtimeStatus"), EncodableValue(realtime_status)},
                      {EncodableValue("supportsQrCode"), EncodableValue(true)},
                      {EncodableValue("supportsBarcode"), EncodableValue(true)},
                      {EncodableValue("supportsImage"), EncodableValue(true)}};
}

EncodableMap BuildUnknownStatus() {
  return EncodableMap{{EncodableValue("paperOut"), EncodableValue("unknown")},
                      {EncodableValue("paperNearEnd"), EncodableValue("unknown")},
                      {EncodableValue("coverOpen"), EncodableValue("unknown")},
                      {EncodableValue("cutterError"), EncodableValue("unknown")},
                      {EncodableValue("offline"), EncodableValue("unknown")},
                      {EncodableValue("drawerSignal"), EncodableValue("unknown")}};
}

std::string LastSocketErrorText(const char* context) {
  std::ostringstream out;
  out << context << " (WSA " << WSAGetLastError() << ")";
  return out.str();
}

SOCKET ConnectTcpSocket(const std::string& host, int port) {
  EnsureWinsock();

  struct addrinfo hints;
  std::memset(&hints, 0, sizeof(hints));
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = AF_UNSPEC;

  char port_buffer[16];
  std::snprintf(port_buffer, sizeof(port_buffer), "%d", port);

  struct addrinfo* results = nullptr;
  int rc = getaddrinfo(host.c_str(), port_buffer, &hints, &results);
  if (rc != 0) {
    throw std::runtime_error("Falha ao resolver host TCP.");
  }

  SOCKET socket_fd = INVALID_SOCKET;
  for (struct addrinfo* addr = results; addr != nullptr; addr = addr->ai_next) {
    socket_fd = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
    if (socket_fd == INVALID_SOCKET) {
      continue;
    }

    if (connect(socket_fd, addr->ai_addr, static_cast<int>(addr->ai_addrlen)) == 0) {
      break;
    }

    closesocket(socket_fd);
    socket_fd = INVALID_SOCKET;
  }

  freeaddrinfo(results);

  if (socket_fd == INVALID_SOCKET) {
    throw std::runtime_error(LastSocketErrorText("Falha ao conectar TCP"));
  }

  return socket_fd;
}

ULONGLONG ParseBluetoothAddress(const std::string& address) {
  std::string cleaned;
  cleaned.reserve(address.size());
  for (char c : address) {
    if (c == ':' || c == '-') {
      continue;
    }
    cleaned.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(c))));
  }

  if (cleaned.size() != 12) {
    throw std::runtime_error("Endereco Bluetooth invalido.");
  }

  ULONGLONG value = 0;
  for (char c : cleaned) {
    value <<= 4;
    if (c >= '0' && c <= '9') {
      value += static_cast<ULONGLONG>(c - '0');
    } else if (c >= 'A' && c <= 'F') {
      value += static_cast<ULONGLONG>(10 + c - 'A');
    } else {
      throw std::runtime_error("Endereco Bluetooth invalido.");
    }
  }

  return value;
}

SOCKET ConnectBluetoothSocket(const std::string& address) {
  EnsureWinsock();

  SOCKET socket_fd = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
  if (socket_fd == INVALID_SOCKET) {
    throw std::runtime_error(LastSocketErrorText("Falha ao criar socket Bluetooth"));
  }

  SOCKADDR_BTH remote = {};
  remote.addressFamily = AF_BTH;
  remote.btAddr = ParseBluetoothAddress(address);
  remote.port = 1;

  if (connect(socket_fd, reinterpret_cast<SOCKADDR*>(&remote), sizeof(remote)) != 0) {
    std::string error = LastSocketErrorText("Falha ao conectar Bluetooth RFCOMM");
    closesocket(socket_fd);
    throw std::runtime_error(error);
  }

  return socket_fd;
}

HANDLE OpenUsbFileHandle(const std::string& serial_or_path) {
  std::string path = serial_or_path;
  if (path.rfind("\\\\.\\", 0) != 0 && path.rfind("COM", 0) == 0) {
    path = "\\\\.\\" + path;
  }

  HANDLE handle = CreateFileA(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    std::ostringstream out;
    out << "Falha ao abrir dispositivo USB/serial em " << path;
    throw std::runtime_error(out.str());
  }

  return handle;
}

}  // namespace

EscposPrinterPlugin::EscposPrinterPlugin() {}
EscposPrinterPlugin::~EscposPrinterPlugin() {
  CloseAllSessions();
}

void EscposPrinterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "escpos_printer/native_transport",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<EscposPrinterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

void EscposPrinterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  try {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    const std::string& method = method_call.method_name();

    if (method == "openConnection") {
      if (args == nullptr) {
        result->Error("invalid_args", "openConnection requer payload map.");
        return;
      }

      std::string transport = RequireString(*args, "transport");
      auto session = std::make_unique<NativeSession>();

      if (transport == "wifi") {
        std::string host = RequireString(*args, "host");
        int port = ReadOptionalInt(*args, "port").value_or(9100);
        session->kind = SessionKind::kWifi;
        session->socket = ConnectTcpSocket(host, port);
      } else if (transport == "bluetooth") {
        std::string address = RequireString(*args, "address");
        session->kind = SessionKind::kBluetooth;
        session->socket = ConnectBluetoothSocket(address);
      } else if (transport == "usb") {
        std::string serial_or_path = RequireString(*args, "serialNumber");
        session->kind = SessionKind::kUsbFile;
        session->handle = OpenUsbFileHandle(serial_or_path);
      } else {
        result->Error("invalid_args", "Transporte invalido. Use wifi, usb ou bluetooth.");
        return;
      }

      std::string session_id;
      {
        std::lock_guard<std::mutex> lock(g_mutex);
        session_id = NextSessionId();
        g_sessions[session_id] = std::move(session);
      }

      EncodableMap response{
          {EncodableValue("sessionId"), EncodableValue(session_id)},
          {EncodableValue("capabilities"), EncodableValue(BuildCapabilities(false))},
      };
      result->Success(EncodableValue(response));
      return;
    }

    if (method == "write") {
      if (args == nullptr) {
        result->Error("invalid_args", "write requer payload map.");
        return;
      }

      std::string session_id = RequireString(*args, "sessionId");
      std::vector<uint8_t> bytes = RequireBytes(*args, "bytes");

      std::lock_guard<std::mutex> lock(g_mutex);
      auto iterator = g_sessions.find(session_id);
      if (iterator == g_sessions.end()) {
        result->Error("invalid_session", "Sessao nao encontrada.");
        return;
      }

      NativeSession* session = iterator->second.get();
      if (session->kind == SessionKind::kUsbFile) {
        DWORD written = 0;
        BOOL ok = WriteFile(session->handle, bytes.data(), static_cast<DWORD>(bytes.size()),
                            &written, nullptr);
        if (!ok || written != bytes.size()) {
          result->Error("write_failed", "Falha ao enviar bytes no dispositivo USB.");
          return;
        }
      } else {
        int sent = send(session->socket, reinterpret_cast<const char*>(bytes.data()),
                        static_cast<int>(bytes.size()), 0);
        if (sent <= 0 || sent != static_cast<int>(bytes.size())) {
          result->Error("write_failed", LastSocketErrorText("Falha ao enviar bytes"));
          return;
        }
      }

      result->Success();
      return;
    }

    if (method == "readStatus") {
      if (args == nullptr) {
        result->Error("invalid_args", "readStatus requer payload map.");
        return;
      }

      std::string session_id = RequireString(*args, "sessionId");
      std::lock_guard<std::mutex> lock(g_mutex);
      if (g_sessions.find(session_id) == g_sessions.end()) {
        result->Error("invalid_session", "Sessao nao encontrada.");
        return;
      }

      result->Success(EncodableValue(BuildUnknownStatus()));
      return;
    }

    if (method == "closeConnection") {
      if (args == nullptr) {
        result->Error("invalid_args", "closeConnection requer payload map.");
        return;
      }

      std::string session_id = RequireString(*args, "sessionId");
      std::unique_ptr<NativeSession> session;
      {
        std::lock_guard<std::mutex> lock(g_mutex);
        auto iterator = g_sessions.find(session_id);
        if (iterator != g_sessions.end()) {
          session = std::move(iterator->second);
          g_sessions.erase(iterator);
        }
      }

      CloseSession(session.get());
      result->Success();
      return;
    }

    if (method == "getCapabilities") {
      if (args == nullptr) {
        result->Error("invalid_args", "getCapabilities requer payload map.");
        return;
      }

      std::string session_id = RequireString(*args, "sessionId");
      std::lock_guard<std::mutex> lock(g_mutex);
      if (g_sessions.find(session_id) == g_sessions.end()) {
        result->Error("invalid_session", "Sessao nao encontrada.");
        return;
      }

      EncodableMap response{{EncodableValue("capabilities"),
                             EncodableValue(BuildCapabilities(false))}};
      result->Success(EncodableValue(response));
      return;
    }

    result->NotImplemented();
  } catch (const std::exception& error) {
    result->Error("transport_error", error.what());
  }
}

}  // namespace escpos_printer

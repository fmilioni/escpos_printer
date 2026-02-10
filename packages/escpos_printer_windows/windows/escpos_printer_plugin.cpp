#include "include/escpos_printer_windows/escpos_printer_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winsock2.h>
#include <ws2bth.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <bluetoothapis.h>
#include <setupapi.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <iomanip>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace escpos_printer
{
namespace
{

enum class SessionKind
{
    kWifi,
    kBluetooth,
    kUsbFile,
};

struct NativeSession
{
    SessionKind kind;
    SOCKET socket = INVALID_SOCKET;
    HANDLE handle = INVALID_HANDLE_VALUE;
};

std::mutex g_mutex;
std::unordered_map<std::string, std::unique_ptr<NativeSession>> g_sessions;
int64_t g_session_counter = 1;
bool g_winsock_initialized = false;

using EncodableMap = flutter::EncodableMap;
using EncodableList = flutter::EncodableList;
using EncodableValue = flutter::EncodableValue;

std::string NextSessionId()
{
    std::ostringstream out;
    out << "windows-session-" << g_session_counter++;
    return out.str();
}

void EnsureWinsock()
{
    if (g_winsock_initialized)
    {
        return;
    }

    WSADATA data;
    int rc = WSAStartup(MAKEWORD(2, 2), &data);
    if (rc != 0)
    {
        throw std::runtime_error("Failed to initialize Winsock.");
    }

    g_winsock_initialized = true;
}

void CloseSession(NativeSession *session)
{
    if (session == nullptr)
    {
        return;
    }

    if (session->socket != INVALID_SOCKET)
    {
        closesocket(session->socket);
        session->socket = INVALID_SOCKET;
    }

    if (session->handle != INVALID_HANDLE_VALUE)
    {
        CloseHandle(session->handle);
        session->handle = INVALID_HANDLE_VALUE;
    }
}

void CloseAllSessions()
{
    std::unordered_map<std::string, std::unique_ptr<NativeSession>> local;
    {
        std::lock_guard<std::mutex> lock(g_mutex);
        local.swap(g_sessions);
    }

    for (auto &entry : local)
    {
        CloseSession(entry.second.get());
    }
}

const EncodableValue *FindArg(const EncodableMap &args, const char *key)
{
    auto iterator = args.find(EncodableValue(key));
    if (iterator == args.end())
    {
        return nullptr;
    }

    return &iterator->second;
}

std::string RequireString(const EncodableMap &args, const char *key)
{
    const EncodableValue *raw = FindArg(args, key);
    if (raw == nullptr)
    {
        throw std::runtime_error(std::string("Missing required field: ") + key);
    }

    if (const auto *value = std::get_if<std::string>(raw))
    {
        if (!value->empty())
        {
            return *value;
        }
    }

    throw std::runtime_error(std::string("Invalid string field: ") + key);
}

int RequireInt(const EncodableMap &args, const char *key)
{
    const EncodableValue *raw = FindArg(args, key);
    if (raw == nullptr)
    {
        throw std::runtime_error(std::string("Missing required integer field: ") + key);
    }

    if (const auto *value = std::get_if<int32_t>(raw))
    {
        return *value;
    }
    if (const auto *value64 = std::get_if<int64_t>(raw))
    {
        return static_cast<int>(*value64);
    }

    throw std::runtime_error(std::string("Invalid integer field: ") + key);
}

std::optional<int> ReadOptionalInt(const EncodableMap &args, const char *key)
{
    const EncodableValue *raw = FindArg(args, key);
    if (raw == nullptr)
    {
        return std::nullopt;
    }

    if (const auto *value = std::get_if<int32_t>(raw))
    {
        return *value;
    }
    if (const auto *value64 = std::get_if<int64_t>(raw))
    {
        return static_cast<int>(*value64);
    }

    return std::nullopt;
}

bool ShouldDiscoverTransport(const EncodableMap *args, const char *transport)
{
    if (args == nullptr)
    {
        return true;
    }

    const EncodableValue *raw = FindArg(*args, "transports");
    if (raw == nullptr)
    {
        return true;
    }

    const auto *list = std::get_if<EncodableList>(raw);
    if (list == nullptr || list->empty())
    {
        return true;
    }

    for (const auto &value : *list)
    {
        const auto *item = std::get_if<std::string>(&value);
        if (item != nullptr && *item == transport)
        {
            return true;
        }
    }
    return false;
}

std::vector<uint8_t> RequireBytes(const EncodableMap &args, const char *key)
{
    const EncodableValue *raw = FindArg(args, key);
    if (raw == nullptr)
    {
        throw std::runtime_error(std::string("Missing required bytes field: ") + key);
    }

    if (const auto *bytes = std::get_if<std::vector<uint8_t>>(raw))
    {
        return *bytes;
    }

    throw std::runtime_error(std::string("Invalid bytes field: ") + key);
}

EncodableMap BuildCapabilities(bool realtime_status = false)
{
    return EncodableMap{
        {EncodableValue("supportsPartialCut"), EncodableValue(true)}, {EncodableValue("supportsFullCut"), EncodableValue(true)},
        {EncodableValue("supportsDrawerKick"), EncodableValue(true)}, {EncodableValue("supportsRealtimeStatus"), EncodableValue(realtime_status)},
        {EncodableValue("supportsQrCode"), EncodableValue(true)},     {EncodableValue("supportsBarcode"), EncodableValue(true)},
        {EncodableValue("supportsImage"), EncodableValue(true)}};
}

EncodableMap BuildUnknownStatus()
{
    return EncodableMap{{EncodableValue("paperOut"), EncodableValue("unknown")},  {EncodableValue("paperNearEnd"), EncodableValue("unknown")},
                        {EncodableValue("coverOpen"), EncodableValue("unknown")}, {EncodableValue("cutterError"), EncodableValue("unknown")},
                        {EncodableValue("offline"), EncodableValue("unknown")},   {EncodableValue("drawerSignal"), EncodableValue("unknown")}};
}

std::string LastSocketErrorText(const char *context)
{
    std::ostringstream out;
    out << context << " (WSA " << WSAGetLastError() << ")";
    return out.str();
}

std::string WideToUtf8(const std::wstring &input)
{
    if (input.empty())
    {
        return {};
    }
    int size = WideCharToMultiByte(CP_UTF8, 0, input.c_str(), static_cast<int>(input.size()), nullptr, 0, nullptr, nullptr);
    if (size <= 0)
    {
        return {};
    }
    std::string output(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, input.c_str(), static_cast<int>(input.size()), output.data(), size, nullptr, nullptr);
    return output;
}

SOCKET ConnectTcpSocket(const std::string &host, int port)
{
    EnsureWinsock();

    struct addrinfo hints;
    std::memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;

    char port_buffer[16];
    std::snprintf(port_buffer, sizeof(port_buffer), "%d", port);

    struct addrinfo *results = nullptr;
    int rc = getaddrinfo(host.c_str(), port_buffer, &hints, &results);
    if (rc != 0)
    {
        throw std::runtime_error("Failed to resolve TCP host.");
    }

    SOCKET socket_fd = INVALID_SOCKET;
    for (struct addrinfo *addr = results; addr != nullptr; addr = addr->ai_next)
    {
        socket_fd = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
        if (socket_fd == INVALID_SOCKET)
        {
            continue;
        }

        if (connect(socket_fd, addr->ai_addr, static_cast<int>(addr->ai_addrlen)) == 0)
        {
            break;
        }

        closesocket(socket_fd);
        socket_fd = INVALID_SOCKET;
    }

    freeaddrinfo(results);

    if (socket_fd == INVALID_SOCKET)
    {
        throw std::runtime_error(LastSocketErrorText("Failed to connect TCP"));
    }

    return socket_fd;
}

ULONGLONG ParseBluetoothAddress(const std::string &address)
{
    std::string cleaned;
    cleaned.reserve(address.size());
    for (char c : address)
    {
        if (c == ':' || c == '-')
        {
            continue;
        }
        cleaned.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(c))));
    }

    if (cleaned.size() != 12)
    {
        throw std::runtime_error("Invalid Bluetooth address.");
    }

    ULONGLONG value = 0;
    for (char c : cleaned)
    {
        value <<= 4;
        if (c >= '0' && c <= '9')
        {
            value += static_cast<ULONGLONG>(c - '0');
        }
        else if (c >= 'A' && c <= 'F')
        {
            value += static_cast<ULONGLONG>(10 + c - 'A');
        }
        else
        {
            throw std::runtime_error("Invalid Bluetooth address.");
        }
    }

    return value;
}

SOCKET ConnectBluetoothSocket(const std::string &address)
{
    EnsureWinsock();

    SOCKET socket_fd = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
    if (socket_fd == INVALID_SOCKET)
    {
        throw std::runtime_error(LastSocketErrorText("Failed to create Bluetooth socket"));
    }

    SOCKADDR_BTH remote = {};
    remote.addressFamily = AF_BTH;
    remote.btAddr = ParseBluetoothAddress(address);
    remote.port = 1;

    if (connect(socket_fd, reinterpret_cast<SOCKADDR *>(&remote), sizeof(remote)) != 0)
    {
        std::string error = LastSocketErrorText("Failed to connect Bluetooth RFCOMM");
        closesocket(socket_fd);
        throw std::runtime_error(error);
    }

    return socket_fd;
}

std::string BluetoothAddressToString(ULONGLONG value)
{
    std::ostringstream out;
    for (int i = 5; i >= 0; --i)
    {
        if (i != 5)
        {
            out << ":";
        }
        uint8_t byte = static_cast<uint8_t>((value >> (i * 8)) & 0xFF);
        out << std::uppercase << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(byte);
    }
    return out.str();
}

std::optional<std::string> ReadDevicePropertyString(HDEVINFO device_info_set, SP_DEVINFO_DATA *device_info_data, DWORD property)
{
    DWORD required_size = 0;
    SetupDiGetDeviceRegistryPropertyA(device_info_set, device_info_data, property, nullptr, nullptr, 0, &required_size);
    if (required_size == 0)
    {
        return std::nullopt;
    }

    std::vector<BYTE> buffer(required_size);
    DWORD property_type = 0;
    if (!SetupDiGetDeviceRegistryPropertyA(device_info_set, device_info_data, property, &property_type, buffer.data(), static_cast<DWORD>(buffer.size()),
                                           nullptr))
    {
        return std::nullopt;
    }

    if (property_type != REG_SZ && property_type != REG_MULTI_SZ)
    {
        return std::nullopt;
    }

    const char *value = reinterpret_cast<const char *>(buffer.data());
    if (value == nullptr || *value == '\0')
    {
        return std::nullopt;
    }
    return std::string(value);
}

std::optional<std::string> ReadPortName(HDEVINFO device_info_set, SP_DEVINFO_DATA *device_info_data)
{
    HKEY key = SetupDiOpenDevRegKey(device_info_set, device_info_data, DICS_FLAG_GLOBAL, 0, DIREG_DEV, KEY_READ);
    if (key == INVALID_HANDLE_VALUE)
    {
        return std::nullopt;
    }

    char value[256] = {0};
    DWORD type = 0;
    DWORD size = sizeof(value);
    LONG status = RegQueryValueExA(key, "PortName", nullptr, &type, reinterpret_cast<LPBYTE>(value), &size);
    RegCloseKey(key);
    if (status != ERROR_SUCCESS || type != REG_SZ || value[0] == '\0')
    {
        return std::nullopt;
    }
    return std::string(value);
}

bool ExtractComPort(const std::string &text, std::string *com_port)
{
    std::string upper = text;
    std::transform(upper.begin(), upper.end(), upper.begin(), [](char c) { return static_cast<char>(std::toupper(static_cast<unsigned char>(c))); });
    size_t com_index = upper.find("COM");
    if (com_index == std::string::npos)
    {
        return false;
    }

    size_t digit_start = com_index + 3;
    size_t digit_end = digit_start;
    while (digit_end < upper.size() && std::isdigit(static_cast<unsigned char>(upper[digit_end])))
    {
        digit_end++;
    }
    if (digit_end == digit_start)
    {
        return false;
    }

    *com_port = upper.substr(com_index, digit_end - com_index);
    return true;
}

std::pair<std::optional<int>, std::optional<int>> ParseVidPid(const std::string &hardware_id)
{
    std::string upper = hardware_id;
    std::transform(upper.begin(), upper.end(), upper.begin(), [](char c) { return static_cast<char>(std::toupper(static_cast<unsigned char>(c))); });

    auto parse_hex = [&](const char *token) -> std::optional<int> {
        size_t index = upper.find(token);
        if (index == std::string::npos || index + 8 > upper.size())
        {
            return std::nullopt;
        }
        std::string hex = upper.substr(index + 4, 4);
        char *end = nullptr;
        long value = std::strtol(hex.c_str(), &end, 16);
        if (end == nullptr || *end != '\0')
        {
            return std::nullopt;
        }
        return static_cast<int>(value);
    };

    return {parse_hex("VID_"), parse_hex("PID_")};
}

struct UsbCandidate
{
    std::string id;
    std::string name;
    std::optional<int> vendor_id;
    std::optional<int> product_id;
    std::optional<std::string> com_port;
    std::optional<std::string> serial_path;
    std::string hardware_id;
};

std::vector<UsbCandidate> EnumerateUsbCandidates()
{
    std::vector<UsbCandidate> candidates;

    HDEVINFO device_info_set = SetupDiGetClassDevsA(nullptr, nullptr, nullptr, DIGCF_PRESENT | DIGCF_ALLCLASSES);
    if (device_info_set == INVALID_HANDLE_VALUE)
    {
        return candidates;
    }

    SP_DEVINFO_DATA device_info_data = {};
    device_info_data.cbSize = sizeof(device_info_data);
    for (DWORD index = 0; SetupDiEnumDeviceInfo(device_info_set, index, &device_info_data); ++index)
    {
        std::optional<std::string> hardware_id = ReadDevicePropertyString(device_info_set, &device_info_data, SPDRP_HARDWAREID);
        std::optional<std::string> friendly_name = ReadDevicePropertyString(device_info_set, &device_info_data, SPDRP_FRIENDLYNAME);
        std::optional<std::string> description = ReadDevicePropertyString(device_info_set, &device_info_data, SPDRP_DEVICEDESC);

        std::string hw = hardware_id.value_or("");
        auto [vendor_id, product_id] = ParseVidPid(hw);

        std::optional<std::string> com_port;
        if (friendly_name.has_value())
        {
            std::string parsed;
            if (ExtractComPort(*friendly_name, &parsed))
            {
                com_port = parsed;
            }
        }
        if (!com_port.has_value())
        {
            com_port = ReadPortName(device_info_set, &device_info_data);
        }

        if (!vendor_id.has_value() && !product_id.has_value() && !com_port.has_value())
        {
            continue;
        }

        std::string name = friendly_name.value_or(description.value_or("USB Device"));
        std::string id = "usb:";
        if (com_port.has_value())
        {
            id += *com_port;
        }
        else if (vendor_id.has_value() && product_id.has_value())
        {
            id += std::to_string(*vendor_id) + ":" + std::to_string(*product_id);
        }
        else
        {
            id += name;
        }

        UsbCandidate candidate;
        candidate.id = id;
        candidate.name = name;
        candidate.vendor_id = vendor_id;
        candidate.product_id = product_id;
        candidate.com_port = com_port;
        candidate.serial_path = com_port;
        candidate.hardware_id = hw;
        candidates.push_back(std::move(candidate));
    }

    SetupDiDestroyDeviceInfoList(device_info_set);
    return candidates;
}

std::optional<std::string> ResolveComPortByVidPid(int vendor_id, int product_id)
{
    auto candidates = EnumerateUsbCandidates();
    for (const auto &candidate : candidates)
    {
        if (candidate.vendor_id == vendor_id && candidate.product_id == product_id && candidate.com_port.has_value())
        {
            return candidate.com_port;
        }
    }
    return std::nullopt;
}

void AppendUsbDiscoveryDevices(EncodableList *list)
{
    auto candidates = EnumerateUsbCandidates();
    for (const auto &candidate : candidates)
    {
        EncodableMap map{
            {EncodableValue("id"), EncodableValue(candidate.id)},
            {EncodableValue("name"), EncodableValue(candidate.name)},
            {EncodableValue("transport"), EncodableValue("usb")},
        };

        if (candidate.vendor_id.has_value())
        {
            map[EncodableValue("vendorId")] = EncodableValue(*candidate.vendor_id);
        }
        if (candidate.product_id.has_value())
        {
            map[EncodableValue("productId")] = EncodableValue(*candidate.product_id);
        }
        if (candidate.com_port.has_value())
        {
            map[EncodableValue("comPort")] = EncodableValue(*candidate.com_port);
            map[EncodableValue("serialNumber")] = EncodableValue(*candidate.com_port);
        }

        EncodableMap metadata;
        if (!candidate.hardware_id.empty())
        {
            metadata[EncodableValue("hardwareId")] = EncodableValue(candidate.hardware_id);
        }
        map[EncodableValue("metadata")] = EncodableValue(metadata);

        list->push_back(EncodableValue(map));
    }
}

void AppendBluetoothDiscoveryDevices(EncodableList *list)
{
    BLUETOOTH_DEVICE_SEARCH_PARAMS params = {};
    params.dwSize = sizeof(BLUETOOTH_DEVICE_SEARCH_PARAMS);
    params.fReturnAuthenticated = TRUE;
    params.fReturnRemembered = TRUE;
    params.fReturnConnected = TRUE;
    params.fReturnUnknown = FALSE;
    params.fIssueInquiry = FALSE;
    params.cTimeoutMultiplier = 1;
    params.hRadio = nullptr;

    BLUETOOTH_DEVICE_INFO info = {};
    info.dwSize = sizeof(BLUETOOTH_DEVICE_INFO);

    HBLUETOOTH_DEVICE_FIND handle = BluetoothFindFirstDevice(&params, &info);
    if (handle == nullptr)
    {
        return;
    }

    do
    {
        std::string address = BluetoothAddressToString(info.Address.ullLong);
        std::wstring wide_name(info.szName);
        std::string name = WideToUtf8(wide_name);
        if (name.empty())
        {
            name = address;
        }

        EncodableMap map{
            {EncodableValue("id"), EncodableValue("bluetooth:" + address)},
            {EncodableValue("name"), EncodableValue(name)},
            {EncodableValue("transport"), EncodableValue("bluetooth")},
            {EncodableValue("address"), EncodableValue(address)},
            {EncodableValue("mode"), EncodableValue("classic")},
            {EncodableValue("isPaired"), EncodableValue(true)},
        };
        list->push_back(EncodableValue(map));
    } while (BluetoothFindNextDevice(handle, &info));

    BluetoothFindDeviceClose(handle);
}

HANDLE OpenUsbFileHandle(const std::string &serial_or_path)
{
    std::string path = serial_or_path;
    if (path.rfind("\\\\.\\", 0) != 0 && path.rfind("COM", 0) == 0)
    {
        path = "\\\\.\\" + path;
    }

    HANDLE handle = CreateFileA(path.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle == INVALID_HANDLE_VALUE)
    {
        std::ostringstream out;
        out << "Failed to open USB/serial device at " << path;
        throw std::runtime_error(out.str());
    }

    return handle;
}

} // namespace

EscposPrinterPlugin::EscposPrinterPlugin()
{
}
EscposPrinterPlugin::~EscposPrinterPlugin()
{
    CloseAllSessions();
}

void EscposPrinterPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar)
{
    auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(registrar->messenger(), "escpos_printer/native_transport",
                                                                                     &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<EscposPrinterPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result) { plugin_pointer->HandleMethodCall(call, std::move(result)); });

    registrar->AddPlugin(std::move(plugin));
}

void EscposPrinterPlugin::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                                           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    try
    {
        const auto *args = std::get_if<EncodableMap>(method_call.arguments());
        const std::string &method = method_call.method_name();

        if (method == "openConnection")
        {
            if (args == nullptr)
            {
                result->Error("invalid_args", "openConnection requires a map payload.");
                return;
            }

            std::string transport = RequireString(*args, "transport");
            auto session = std::make_unique<NativeSession>();

            if (transport == "wifi")
            {
                std::string host = RequireString(*args, "host");
                int port = ReadOptionalInt(*args, "port").value_or(9100);
                session->kind = SessionKind::kWifi;
                session->socket = ConnectTcpSocket(host, port);
            }
            else if (transport == "bluetooth")
            {
                std::string address = RequireString(*args, "address");
                session->kind = SessionKind::kBluetooth;
                session->socket = ConnectBluetoothSocket(address);
            }
            else if (transport == "usb")
            {
                std::optional<std::string> serial_or_path;
                const EncodableValue *serial_raw = FindArg(*args, "serialNumber");
                if (serial_raw != nullptr)
                {
                    if (const auto *serial_value = std::get_if<std::string>(serial_raw))
                    {
                        if (!serial_value->empty())
                        {
                            serial_or_path = *serial_value;
                        }
                    }
                }

                std::optional<int> vendor_id = ReadOptionalInt(*args, "vendorId");
                std::optional<int> product_id = ReadOptionalInt(*args, "productId");
                if (!serial_or_path.has_value() && vendor_id.has_value() && product_id.has_value())
                {
                    serial_or_path = ResolveComPortByVidPid(*vendor_id, *product_id);
                }

                if (!serial_or_path.has_value())
                {
                    result->Error("invalid_args", "For USB, provide serialNumber/COM or vendorId+productId with a resolvable port.");
                    return;
                }

                session->kind = SessionKind::kUsbFile;
                session->handle = OpenUsbFileHandle(*serial_or_path);
            }
            else
            {
                result->Error("invalid_args", "Invalid transport. Use wifi, usb, or bluetooth.");
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

        if (method == "write")
        {
            if (args == nullptr)
            {
                result->Error("invalid_args", "write requires a map payload.");
                return;
            }

            std::string session_id = RequireString(*args, "sessionId");
            std::vector<uint8_t> bytes = RequireBytes(*args, "bytes");

            std::lock_guard<std::mutex> lock(g_mutex);
            auto iterator = g_sessions.find(session_id);
            if (iterator == g_sessions.end())
            {
                result->Error("invalid_session", "Session not found.");
                return;
            }

            NativeSession *session = iterator->second.get();
            if (session->kind == SessionKind::kUsbFile)
            {
                DWORD written = 0;
                BOOL ok = WriteFile(session->handle, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
                if (!ok || written != bytes.size())
                {
                    result->Error("write_failed", "Failed to send bytes on USB device.");
                    return;
                }
            }
            else
            {
                int sent = send(session->socket, reinterpret_cast<const char *>(bytes.data()), static_cast<int>(bytes.size()), 0);
                if (sent <= 0 || sent != static_cast<int>(bytes.size()))
                {
                    result->Error("write_failed", LastSocketErrorText("Failed to send bytes"));
                    return;
                }
            }

            result->Success();
            return;
        }

        if (method == "readStatus")
        {
            if (args == nullptr)
            {
                result->Error("invalid_args", "readStatus requires a map payload.");
                return;
            }

            std::string session_id = RequireString(*args, "sessionId");
            std::lock_guard<std::mutex> lock(g_mutex);
            if (g_sessions.find(session_id) == g_sessions.end())
            {
                result->Error("invalid_session", "Session not found.");
                return;
            }

            result->Success(EncodableValue(BuildUnknownStatus()));
            return;
        }

        if (method == "closeConnection")
        {
            if (args == nullptr)
            {
                result->Error("invalid_args", "closeConnection requires a map payload.");
                return;
            }

            std::string session_id = RequireString(*args, "sessionId");
            std::unique_ptr<NativeSession> session;
            {
                std::lock_guard<std::mutex> lock(g_mutex);
                auto iterator = g_sessions.find(session_id);
                if (iterator != g_sessions.end())
                {
                    session = std::move(iterator->second);
                    g_sessions.erase(iterator);
                }
            }

            CloseSession(session.get());
            result->Success();
            return;
        }

        if (method == "getCapabilities")
        {
            if (args == nullptr)
            {
                result->Error("invalid_args", "getCapabilities requires a map payload.");
                return;
            }

            std::string session_id = RequireString(*args, "sessionId");
            std::lock_guard<std::mutex> lock(g_mutex);
            if (g_sessions.find(session_id) == g_sessions.end())
            {
                result->Error("invalid_session", "Session not found.");
                return;
            }

            EncodableMap response{{EncodableValue("capabilities"), EncodableValue(BuildCapabilities(false))}};
            result->Success(EncodableValue(response));
            return;
        }

        if (method == "searchPrinters")
        {
            EncodableList devices;
            if (ShouldDiscoverTransport(args, "usb"))
            {
                AppendUsbDiscoveryDevices(&devices);
            }
            if (ShouldDiscoverTransport(args, "bluetooth"))
            {
                AppendBluetoothDiscoveryDevices(&devices);
            }
            result->Success(EncodableValue(devices));
            return;
        }

        result->NotImplemented();
    }
    catch (const std::exception &error)
    {
        result->Error("transport_error", error.what());
    }
}

} // namespace escpos_printer

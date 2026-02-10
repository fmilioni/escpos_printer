#include "include/escpos_printer/escpos_printer_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <libusb-1.0/libusb.h>
#include <sys/socket.h>
#include <unistd.h>

#include <bluetooth/bluetooth.h>
#include <bluetooth/rfcomm.h>

#include <arpa/inet.h>
#include <netdb.h>

#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

#define ESCPOS_PRINTER_PLUGIN(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), escpos_printer_plugin_get_type(), EscposPrinterPlugin))

struct _EscposPrinterPlugin
{
    GObject parent_instance;
};

G_DEFINE_TYPE(EscposPrinterPlugin, escpos_printer_plugin, g_object_get_type())

namespace
{

enum class SessionKind
{
    kWifi,
    kBluetooth,
    kUsb,
};

struct NativeConnection
{
    SessionKind kind;
    int fd = -1;

    libusb_context *usb_context = nullptr;
    libusb_device_handle *usb_handle = nullptr;
    int usb_interface_number = -1;
    uint8_t usb_endpoint_out = 0;
};

std::unordered_map<std::string, std::unique_ptr<NativeConnection>> g_sessions;
std::mutex g_sessions_mutex;
std::atomic<int64_t> g_session_counter{1};

FlMethodResponse *MakeErrorResponse(const std::string &code, const std::string &message)
{
    return FL_METHOD_RESPONSE(fl_method_error_response_new(code.c_str(), message.c_str(), nullptr));
}

FlValue *MakeCapabilitiesValue(bool realtime_status = false)
{
    g_autoptr(FlValue) caps = fl_value_new_map();
    fl_value_set_string(caps, "supportsPartialCut", fl_value_new_bool(true));
    fl_value_set_string(caps, "supportsFullCut", fl_value_new_bool(true));
    fl_value_set_string(caps, "supportsDrawerKick", fl_value_new_bool(true));
    fl_value_set_string(caps, "supportsRealtimeStatus", fl_value_new_bool(realtime_status));
    fl_value_set_string(caps, "supportsQrCode", fl_value_new_bool(true));
    fl_value_set_string(caps, "supportsBarcode", fl_value_new_bool(true));
    fl_value_set_string(caps, "supportsImage", fl_value_new_bool(true));

    return fl_value_ref(caps);
}

FlValue *MakeUnknownStatusValue()
{
    g_autoptr(FlValue) status = fl_value_new_map();
    fl_value_set_string(status, "paperOut", fl_value_new_string("unknown"));
    fl_value_set_string(status, "paperNearEnd", fl_value_new_string("unknown"));
    fl_value_set_string(status, "coverOpen", fl_value_new_string("unknown"));
    fl_value_set_string(status, "cutterError", fl_value_new_string("unknown"));
    fl_value_set_string(status, "offline", fl_value_new_string("unknown"));
    fl_value_set_string(status, "drawerSignal", fl_value_new_string("unknown"));

    return fl_value_ref(status);
}

std::string BuildSessionId()
{
    std::ostringstream out;
    out << "linux-session-" << g_session_counter.fetch_add(1);
    return out.str();
}

bool IsNullValue(FlValue *value)
{
    return value == nullptr || fl_value_get_type(value) == FL_VALUE_TYPE_NULL;
}

bool ReadRequiredString(FlValue *map, const char *key, std::string *out, std::string *error)
{
    FlValue *value = fl_value_lookup_string(map, key);
    if (IsNullValue(value) || fl_value_get_type(value) != FL_VALUE_TYPE_STRING)
    {
        *error = std::string("Missing or invalid required field: ") + key;
        return false;
    }

    const gchar *raw = fl_value_get_string(value);
    if (raw == nullptr || std::strlen(raw) == 0)
    {
        *error = std::string("Required field is empty: ") + key;
        return false;
    }

    *out = raw;
    return true;
}

bool ReadOptionalInt(FlValue *map, const char *key, int *out)
{
    FlValue *value = fl_value_lookup_string(map, key);
    if (IsNullValue(value))
    {
        return false;
    }
    if (fl_value_get_type(value) != FL_VALUE_TYPE_INT)
    {
        return false;
    }

    *out = static_cast<int>(fl_value_get_int(value));
    return true;
}

bool ShouldDiscoverTransport(FlValue *args, const char *transport)
{
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    {
        return true;
    }

    FlValue *raw_transports = fl_value_lookup_string(args, "transports");
    if (IsNullValue(raw_transports))
    {
        return true;
    }
    if (fl_value_get_type(raw_transports) != FL_VALUE_TYPE_LIST)
    {
        return false;
    }

    size_t count = fl_value_get_length(raw_transports);
    if (count == 0)
    {
        return true;
    }

    for (size_t i = 0; i < count; i++)
    {
        FlValue *item = fl_value_get_list_value(raw_transports, i);
        if (item == nullptr || fl_value_get_type(item) != FL_VALUE_TYPE_STRING)
        {
            continue;
        }
        const gchar *value = fl_value_get_string(item);
        if (value != nullptr && std::strcmp(value, transport) == 0)
        {
            return true;
        }
    }

    return false;
}

bool FindUsbBulkOutInConfig(const libusb_config_descriptor *config, int preferred_interface, int *interface_number, uint8_t *endpoint_out)
{
    if (config == nullptr)
    {
        return false;
    }

    for (int i = 0; i < config->bNumInterfaces; i++)
    {
        const libusb_interface &ifc = config->interface[i];
        for (int j = 0; j < ifc.num_altsetting; j++)
        {
            const libusb_interface_descriptor &alt = ifc.altsetting[j];
            if (preferred_interface >= 0 && alt.bInterfaceNumber != preferred_interface)
            {
                continue;
            }

            for (int k = 0; k < alt.bNumEndpoints; k++)
            {
                const libusb_endpoint_descriptor &ep = alt.endpoint[k];
                bool is_bulk = (ep.bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK;
                bool is_out = (ep.bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_OUT;
                if (is_bulk && is_out)
                {
                    *interface_number = alt.bInterfaceNumber;
                    *endpoint_out = ep.bEndpointAddress;
                    return true;
                }
            }
        }
    }

    return false;
}

std::string LastErrnoText(const char *context)
{
    std::ostringstream out;
    out << context << ": " << std::strerror(errno);
    return out.str();
}

bool FindUsbBulkOutEndpoint(libusb_device_handle *handle, int preferred_interface, int *interface_number, uint8_t *endpoint_out)
{
    libusb_device *device = libusb_get_device(handle);
    if (device == nullptr)
    {
        return false;
    }

    libusb_config_descriptor *config = nullptr;
    int rc = libusb_get_active_config_descriptor(device, &config);
    if (rc != 0 || config == nullptr)
    {
        return false;
    }

    bool found = FindUsbBulkOutInConfig(config, preferred_interface, interface_number, endpoint_out);

    libusb_free_config_descriptor(config);
    return found;
}

bool FindUsbBulkOutOnDevice(libusb_device *device, int *interface_number, uint8_t *endpoint_out)
{
    if (device == nullptr)
    {
        return false;
    }

    libusb_config_descriptor *config = nullptr;
    int rc = libusb_get_active_config_descriptor(device, &config);
    if (rc != 0 || config == nullptr)
    {
        rc = libusb_get_config_descriptor(device, 0, &config);
        if (rc != 0 || config == nullptr)
        {
            return false;
        }
    }

    bool found = FindUsbBulkOutInConfig(config, -1, interface_number, endpoint_out);
    libusb_free_config_descriptor(config);
    return found;
}

std::string FormatHex4(uint16_t value)
{
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%04x", value);
    return std::string(buffer);
}

std::string BuildUsbId(libusb_device *device, uint16_t vendor_id, uint16_t product_id)
{
    std::ostringstream out;
    out << "usb:" << FormatHex4(vendor_id) << ":" << FormatHex4(product_id) << ":" << static_cast<int>(libusb_get_bus_number(device)) << ":"
        << static_cast<int>(libusb_get_device_address(device));
    return out.str();
}

void AppendUsbDiscoveryDevices(FlValue *list)
{
    libusb_context *context = nullptr;
    if (libusb_init(&context) != 0 || context == nullptr)
    {
        return;
    }

    libusb_device **devices = nullptr;
    ssize_t count = libusb_get_device_list(context, &devices);
    if (count < 0 || devices == nullptr)
    {
        libusb_exit(context);
        return;
    }

    for (ssize_t i = 0; i < count; i++)
    {
        libusb_device *device = devices[i];
        libusb_device_descriptor desc;
        if (libusb_get_device_descriptor(device, &desc) != 0)
        {
            continue;
        }

        int interface_number = -1;
        uint8_t endpoint_out = 0;
        if (!FindUsbBulkOutOnDevice(device, &interface_number, &endpoint_out))
        {
            continue;
        }

        std::ostringstream name;
        name << "USB VID:" << FormatHex4(desc.idVendor) << " PID:" << FormatHex4(desc.idProduct);

        g_autoptr(FlValue) item = fl_value_new_map();
        fl_value_set_string(item, "id", fl_value_new_string(BuildUsbId(device, desc.idVendor, desc.idProduct).c_str()));
        fl_value_set_string(item, "name", fl_value_new_string(name.str().c_str()));
        fl_value_set_string(item, "transport", fl_value_new_string("usb"));
        fl_value_set_string(item, "vendorId", fl_value_new_int(desc.idVendor));
        fl_value_set_string(item, "productId", fl_value_new_int(desc.idProduct));
        fl_value_set_string(item, "interfaceNumber", fl_value_new_int(interface_number));
        fl_value_set_string(item, "metadata", fl_value_new_map());
        fl_value_append_take(list, fl_value_ref(item));
    }

    libusb_free_device_list(devices, 1);
    libusb_exit(context);
}

void AppendBluetoothDiscoveryDevices(FlValue *list)
{
    g_autoptr(GError) error = nullptr;
    g_autoptr(GDBusConnection) connection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
    if (connection == nullptr)
    {
        return;
    }

    g_autoptr(GVariant) reply = g_dbus_connection_call_sync(connection, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", nullptr,
                                                            G_VARIANT_TYPE("(a{oa{sa{sv}}})"), G_DBUS_CALL_FLAGS_NONE, 2500, nullptr, &error);
    if (reply == nullptr)
    {
        return;
    }

    GVariantIter *objects_iter = nullptr;
    g_variant_get(reply, "(a{oa{sa{sv}}})", &objects_iter);
    if (objects_iter == nullptr)
    {
        return;
    }

    const gchar *object_path = nullptr;
    GVariant *interfaces = nullptr;

    while (g_variant_iter_next(objects_iter, "{&oa{sa{sv}}}", &object_path, &interfaces))
    {
        g_autoptr(GVariant) device_props = g_variant_lookup_value(interfaces, "org.bluez.Device1", G_VARIANT_TYPE("a{sv}"));
        if (device_props == nullptr)
        {
            g_variant_unref(interfaces);
            continue;
        }

        g_autoptr(GVariant) paired_var = g_variant_lookup_value(device_props, "Paired", G_VARIANT_TYPE_BOOLEAN);
        bool paired = paired_var != nullptr && g_variant_get_boolean(paired_var);
        if (!paired)
        {
            g_variant_unref(interfaces);
            continue;
        }

        const gchar *address = nullptr;
        const gchar *name = nullptr;

        g_autoptr(GVariant) address_var = g_variant_lookup_value(device_props, "Address", G_VARIANT_TYPE_STRING);
        if (address_var != nullptr)
        {
            address = g_variant_get_string(address_var, nullptr);
        }

        g_autoptr(GVariant) name_var = g_variant_lookup_value(device_props, "Name", G_VARIANT_TYPE_STRING);
        if (name_var != nullptr)
        {
            name = g_variant_get_string(name_var, nullptr);
        }

        if (address != nullptr && std::strlen(address) > 0)
        {
            std::string default_name = address;
            std::string id = std::string("bluetooth:") + address;

            g_autoptr(FlValue) item = fl_value_new_map();
            fl_value_set_string(item, "id", fl_value_new_string(id.c_str()));
            fl_value_set_string(item, "name", fl_value_new_string(name != nullptr ? name : default_name.c_str()));
            fl_value_set_string(item, "transport", fl_value_new_string("bluetooth"));
            fl_value_set_string(item, "address", fl_value_new_string(address));
            fl_value_set_string(item, "mode", fl_value_new_string("classic"));
            fl_value_set_string(item, "isPaired", fl_value_new_bool(true));
            g_autoptr(FlValue) metadata = fl_value_new_map();
            fl_value_set_string(metadata, "objectPath", fl_value_new_string(object_path != nullptr ? object_path : ""));
            fl_value_set_string(item, "metadata", fl_value_ref(metadata));
            fl_value_append_take(list, fl_value_ref(item));
        }

        g_variant_unref(interfaces);
    }

    g_variant_iter_free(objects_iter);
}

int OpenTcpSocket(const std::string &host, int port, std::string *error)
{
    struct addrinfo hints;
    std::memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;

    char port_buffer[16];
    std::snprintf(port_buffer, sizeof(port_buffer), "%d", port);

    struct addrinfo *result = nullptr;
    int rc = getaddrinfo(host.c_str(), port_buffer, &hints, &result);
    if (rc != 0)
    {
        *error = std::string("Failed to resolve host: ") + gai_strerror(rc);
        return -1;
    }

    int socket_fd = -1;
    for (struct addrinfo *addr = result; addr != nullptr; addr = addr->ai_next)
    {
        socket_fd = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
        if (socket_fd < 0)
        {
            continue;
        }

        if (connect(socket_fd, addr->ai_addr, addr->ai_addrlen) == 0)
        {
            break;
        }

        close(socket_fd);
        socket_fd = -1;
    }

    freeaddrinfo(result);

    if (socket_fd < 0)
    {
        *error = LastErrnoText("Failed to connect TCP socket");
    }

    return socket_fd;
}

void CloseNativeConnection(NativeConnection *connection)
{
    if (connection == nullptr)
    {
        return;
    }

    if (connection->fd >= 0)
    {
        close(connection->fd);
        connection->fd = -1;
    }

    if (connection->usb_handle != nullptr)
    {
        if (connection->usb_interface_number >= 0)
        {
            libusb_release_interface(connection->usb_handle, connection->usb_interface_number);
        }
        libusb_close(connection->usb_handle);
        connection->usb_handle = nullptr;
    }

    if (connection->usb_context != nullptr)
    {
        libusb_exit(connection->usb_context);
        connection->usb_context = nullptr;
    }
}

FlMethodResponse *HandleOpenConnection(FlValue *args)
{
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    {
        return MakeErrorResponse("invalid_args", "openConnection requires a map payload.");
    }

    std::string transport;
    std::string parse_error;
    if (!ReadRequiredString(args, "transport", &transport, &parse_error))
    {
        return MakeErrorResponse("invalid_args", parse_error);
    }

    std::unique_ptr<NativeConnection> connection = std::make_unique<NativeConnection>();

    if (transport == "wifi")
    {
        std::string host;
        if (!ReadRequiredString(args, "host", &host, &parse_error))
        {
            return MakeErrorResponse("invalid_args", parse_error);
        }

        int port = 9100;
        ReadOptionalInt(args, "port", &port);

        std::string socket_error;
        int fd = OpenTcpSocket(host, port, &socket_error);
        if (fd < 0)
        {
            return MakeErrorResponse("connect_failed", socket_error);
        }

        connection->kind = SessionKind::kWifi;
        connection->fd = fd;
    }
    else if (transport == "bluetooth")
    {
        std::string address;
        if (!ReadRequiredString(args, "address", &address, &parse_error))
        {
            return MakeErrorResponse("invalid_args", parse_error);
        }

        int channel = 1;
        int socket_fd = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
        if (socket_fd < 0)
        {
            return MakeErrorResponse("connect_failed", LastErrnoText("Failed to create Bluetooth socket"));
        }

        sockaddr_rc addr = {};
        addr.rc_family = AF_BLUETOOTH;
        addr.rc_channel = static_cast<uint8_t>(channel);
        if (str2ba(address.c_str(), &addr.rc_bdaddr) != 0)
        {
            close(socket_fd);
            return MakeErrorResponse("invalid_args", "Invalid Bluetooth address.");
        }

        if (connect(socket_fd, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) != 0)
        {
            std::string err = LastErrnoText("Failed to connect Bluetooth RFCOMM");
            close(socket_fd);
            return MakeErrorResponse("connect_failed", err);
        }

        connection->kind = SessionKind::kBluetooth;
        connection->fd = socket_fd;
    }
    else if (transport == "usb")
    {
        int vendor_id = 0;
        int product_id = 0;
        if (!ReadOptionalInt(args, "vendorId", &vendor_id) || !ReadOptionalInt(args, "productId", &product_id))
        {
            return MakeErrorResponse("invalid_args", "vendorId and productId are required for USB.");
        }

        int preferred_interface = -1;
        ReadOptionalInt(args, "interfaceNumber", &preferred_interface);

        libusb_context *usb_context = nullptr;
        int rc = libusb_init(&usb_context);
        if (rc != 0 || usb_context == nullptr)
        {
            return MakeErrorResponse("connect_failed", "Failed to initialize libusb.");
        }

        libusb_device_handle *usb_handle = libusb_open_device_with_vid_pid(usb_context, vendor_id, product_id);
        if (usb_handle == nullptr)
        {
            libusb_exit(usb_context);
            return MakeErrorResponse("connect_failed", "USB device not found (vendorId/productId).");
        }

        int interface_number = -1;
        uint8_t endpoint_out = 0;
        if (!FindUsbBulkOutEndpoint(usb_handle, preferred_interface, &interface_number, &endpoint_out))
        {
            libusb_close(usb_handle);
            libusb_exit(usb_context);
            return MakeErrorResponse("connect_failed", "BULK OUT endpoint not found for USB.");
        }

        if (libusb_kernel_driver_active(usb_handle, interface_number) == 1)
        {
            libusb_detach_kernel_driver(usb_handle, interface_number);
        }

        rc = libusb_claim_interface(usb_handle, interface_number);
        if (rc != 0)
        {
            libusb_close(usb_handle);
            libusb_exit(usb_context);
            return MakeErrorResponse("connect_failed", "Failed to claim USB interface.");
        }

        connection->kind = SessionKind::kUsb;
        connection->usb_context = usb_context;
        connection->usb_handle = usb_handle;
        connection->usb_interface_number = interface_number;
        connection->usb_endpoint_out = endpoint_out;
    }
    else
    {
        return MakeErrorResponse("invalid_args", "Invalid transport. Use wifi, usb, or bluetooth.");
    }

    std::string session_id = BuildSessionId();
    {
        std::lock_guard<std::mutex> lock(g_sessions_mutex);
        g_sessions[session_id] = std::move(connection);
    }

    g_autoptr(FlValue) response_map = fl_value_new_map();
    fl_value_set_string(response_map, "sessionId", fl_value_new_string(session_id.c_str()));
    fl_value_set_string(response_map, "capabilities", MakeCapabilitiesValue(false));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(response_map));
}

FlMethodResponse *HandleWrite(FlValue *args)
{
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    {
        return MakeErrorResponse("invalid_args", "write requires a map payload.");
    }

    std::string session_id;
    std::string parse_error;
    if (!ReadRequiredString(args, "sessionId", &session_id, &parse_error))
    {
        return MakeErrorResponse("invalid_args", parse_error);
    }

    FlValue *bytes_value = fl_value_lookup_string(args, "bytes");
    if (IsNullValue(bytes_value) || fl_value_get_type(bytes_value) != FL_VALUE_TYPE_UINT8_LIST)
    {
        return MakeErrorResponse("invalid_args", "bytes field must be Uint8List.");
    }

    const uint8_t *bytes = fl_value_get_uint8_list(bytes_value);
    size_t length = fl_value_get_length(bytes_value);

    std::lock_guard<std::mutex> lock(g_sessions_mutex);
    auto iterator = g_sessions.find(session_id);
    if (iterator == g_sessions.end())
    {
        return MakeErrorResponse("invalid_session", "Session not found.");
    }

    NativeConnection *connection = iterator->second.get();
    if (connection->kind == SessionKind::kUsb)
    {
        int transferred = 0;
        int rc = libusb_bulk_transfer(connection->usb_handle, connection->usb_endpoint_out, const_cast<unsigned char *>(bytes), static_cast<int>(length),
                                      &transferred, 4000);
        if (rc != 0 || transferred != static_cast<int>(length))
        {
            return MakeErrorResponse("write_failed", "Failed to send bytes over USB.");
        }
    }
    else
    {
        ssize_t written = send(connection->fd, bytes, length, 0);
        if (written < 0 || static_cast<size_t>(written) != length)
        {
            return MakeErrorResponse("write_failed", LastErrnoText("Failed to send bytes"));
        }
    }

    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

FlMethodResponse *HandleReadStatus(FlValue *args)
{
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    {
        return MakeErrorResponse("invalid_args", "readStatus requires a map payload.");
    }

    std::string session_id;
    std::string parse_error;
    if (!ReadRequiredString(args, "sessionId", &session_id, &parse_error))
    {
        return MakeErrorResponse("invalid_args", parse_error);
    }

    std::lock_guard<std::mutex> lock(g_sessions_mutex);
    auto iterator = g_sessions.find(session_id);
    if (iterator == g_sessions.end())
    {
        return MakeErrorResponse("invalid_session", "Session not found.");
    }

    return FL_METHOD_RESPONSE(fl_method_success_response_new(MakeUnknownStatusValue()));
}

FlMethodResponse *HandleCloseConnection(FlValue *args)
{
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    {
        return MakeErrorResponse("invalid_args", "closeConnection requires a map payload.");
    }

    std::string session_id;
    std::string parse_error;
    if (!ReadRequiredString(args, "sessionId", &session_id, &parse_error))
    {
        return MakeErrorResponse("invalid_args", parse_error);
    }

    std::unique_ptr<NativeConnection> connection;
    {
        std::lock_guard<std::mutex> lock(g_sessions_mutex);
        auto iterator = g_sessions.find(session_id);
        if (iterator == g_sessions.end())
        {
            return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
        }

        connection = std::move(iterator->second);
        g_sessions.erase(iterator);
    }

    CloseNativeConnection(connection.get());
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

FlMethodResponse *HandleGetCapabilities(FlValue *args)
{
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP)
    {
        return MakeErrorResponse("invalid_args", "getCapabilities requires a map payload.");
    }

    std::string session_id;
    std::string parse_error;
    if (!ReadRequiredString(args, "sessionId", &session_id, &parse_error))
    {
        return MakeErrorResponse("invalid_args", parse_error);
    }

    std::lock_guard<std::mutex> lock(g_sessions_mutex);
    auto iterator = g_sessions.find(session_id);
    if (iterator == g_sessions.end())
    {
        return MakeErrorResponse("invalid_session", "Session not found.");
    }

    g_autoptr(FlValue) result_map = fl_value_new_map();
    fl_value_set_string(result_map, "capabilities", MakeCapabilitiesValue(false));
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result_map));
}

FlMethodResponse *HandleSearchPrinters(FlValue *args)
{
    g_autoptr(FlValue) devices = fl_value_new_list();

    if (ShouldDiscoverTransport(args, "usb"))
    {
        AppendUsbDiscoveryDevices(devices);
    }
    if (ShouldDiscoverTransport(args, "bluetooth"))
    {
        AppendBluetoothDiscoveryDevices(devices);
    }

    return FL_METHOD_RESPONSE(fl_method_success_response_new(devices));
}

void CloseAllSessions()
{
    std::unordered_map<std::string, std::unique_ptr<NativeConnection>> current;
    {
        std::lock_guard<std::mutex> lock(g_sessions_mutex);
        current.swap(g_sessions);
    }

    for (auto &entry : current)
    {
        CloseNativeConnection(entry.second.get());
    }
}

} // namespace

static void escpos_printer_plugin_handle_method_call(EscposPrinterPlugin *self, FlMethodCall *method_call)
{
    const gchar *method = fl_method_call_get_name(method_call);
    FlValue *args = fl_method_call_get_args(method_call);

    g_autoptr(FlMethodResponse) response = nullptr;

    if (strcmp(method, "openConnection") == 0)
    {
        response = HandleOpenConnection(args);
    }
    else if (strcmp(method, "write") == 0)
    {
        response = HandleWrite(args);
    }
    else if (strcmp(method, "readStatus") == 0)
    {
        response = HandleReadStatus(args);
    }
    else if (strcmp(method, "closeConnection") == 0)
    {
        response = HandleCloseConnection(args);
    }
    else if (strcmp(method, "getCapabilities") == 0)
    {
        response = HandleGetCapabilities(args);
    }
    else if (strcmp(method, "searchPrinters") == 0)
    {
        response = HandleSearchPrinters(args);
    }
    else
    {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    fl_method_call_respond(method_call, response, nullptr);
}

static void escpos_printer_plugin_dispose(GObject *object)
{
    CloseAllSessions();
    G_OBJECT_CLASS(escpos_printer_plugin_parent_class)->dispose(object);
}

static void escpos_printer_plugin_class_init(EscposPrinterPluginClass *klass)
{
    G_OBJECT_CLASS(klass)->dispose = escpos_printer_plugin_dispose;
}

static void escpos_printer_plugin_init(EscposPrinterPlugin *self)
{
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call, gpointer user_data)
{
    EscposPrinterPlugin *plugin = ESCPOS_PRINTER_PLUGIN(user_data);
    escpos_printer_plugin_handle_method_call(plugin, method_call);
}

void escpos_printer_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
    EscposPrinterPlugin *plugin = ESCPOS_PRINTER_PLUGIN(g_object_new(escpos_printer_plugin_get_type(), nullptr));

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    g_autoptr(FlMethodChannel) channel =
        fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar), "escpos_printer/native_transport", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(channel, method_call_cb, g_object_ref(plugin), g_object_unref);

    g_object_unref(plugin);
}

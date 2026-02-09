cmake_minimum_required(VERSION 3.10)
project(escpos_printer_library VERSION 0.0.1 LANGUAGES CXX)

set(PLUGIN_NAME "escpos_printer_plugin")
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBUSB REQUIRED libusb-1.0)
pkg_check_modules(BLUEZ REQUIRED bluez)
pkg_check_modules(GIO REQUIRED gio-2.0)

add_library(${PLUGIN_NAME} SHARED
  "escpos_printer_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} PRIVATE
  ${LIBUSB_INCLUDE_DIRS}
  ${BLUEZ_INCLUDE_DIRS}
  ${GIO_INCLUDE_DIRS}
)
target_compile_options(${PLUGIN_NAME} PRIVATE
  ${LIBUSB_CFLAGS_OTHER}
  ${BLUEZ_CFLAGS_OTHER}
  ${GIO_CFLAGS_OTHER}
)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  ${LIBUSB_LIBRARIES}
  ${BLUEZ_LIBRARIES}
  ${GIO_LIBRARIES}
)

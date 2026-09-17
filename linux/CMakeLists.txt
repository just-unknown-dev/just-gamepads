# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "just_gamepads")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "just_gamepads_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "just_gamepads_plugin.cc"
  "evdev_gamepad_source.cc"
  "evdev_gamepad_source.h"
)

# libudev — hot-plug detection for evdev_gamepad_source.cc. A system
# dependency (`libudev-dev` on Debian/Ubuntu, `systemd-devel` on Fedora) the
# eventual Linux-hardware builder must have installed; this plugin can't be
# verified on this machine (no Linux desktop toolchain), so this requirement
# is untested here.
find_package(PkgConfig REQUIRED)
pkg_check_modules(UDEV REQUIRED libudev)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_include_directories(${PLUGIN_NAME} PRIVATE ${UDEV_INCLUDE_DIRS})
target_link_libraries(${PLUGIN_NAME} PRIVATE ${UDEV_LIBRARIES})

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(just_gamepads_bundled_libraries
  ""
  PARENT_SCOPE
)

# No unit test target: the plugin's evdev/libudev logic is exercised
# end-to-end against real hardware, not mocked ioctl/libudev calls — the
# shared wire-protocol parsing logic that WOULD be worth unit testing
# already is, in Dart (see gamepad_wire_protocol_test.dart in the parent
# package), which every backend's output feeds into identically.
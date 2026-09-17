#include "include/just_gamepads/just_gamepads_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "just_gamepads_plugin.h"

void JustGamepadsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  just_gamepads::JustGamepadsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

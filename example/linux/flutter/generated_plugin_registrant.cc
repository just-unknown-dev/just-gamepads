//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <just_gamepads/just_gamepads_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) just_gamepads_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "JustGamepadsPlugin");
  just_gamepads_plugin_register_with_registrar(just_gamepads_registrar);
}

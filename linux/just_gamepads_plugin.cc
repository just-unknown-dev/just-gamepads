#include "include/just_gamepads/just_gamepads_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include "evdev_gamepad_source.h"

#define JUST_GAMEPADS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), just_gamepads_plugin_get_type(), \
                              JustGamepadsPlugin))

struct _JustGamepadsPlugin {
  GObject parent_instance;
  FlEventChannel* channel;
  just_gamepads::EvdevGamepadSource* source;
};

G_DEFINE_TYPE(JustGamepadsPlugin, just_gamepads_plugin, g_object_get_type())

static FlMethodErrorResponse* on_listen_cb(FlEventChannel* channel,
                                           FlValue* args, gpointer user_data) {
  JustGamepadsPlugin* self = JUST_GAMEPADS_PLUGIN(user_data);
  // Start() restarts cleanly, so a second listen (e.g. after a hot restart)
  // reports every connected controller again.
  self->source->Start([self](FlValue* event) {
    g_autoptr(GError) error = nullptr;
    if (!fl_event_channel_send(self->channel, event, nullptr, &error) &&
        error) {
      g_warning("just_gamepads: failed to send event: %s", error->message);
    }
  });
  return nullptr;
}

static FlMethodErrorResponse* on_cancel_cb(FlEventChannel* channel,
                                           FlValue* args, gpointer user_data) {
  JustGamepadsPlugin* self = JUST_GAMEPADS_PLUGIN(user_data);
  self->source->Stop();
  return nullptr;
}

static void just_gamepads_plugin_dispose(GObject* object) {
  JustGamepadsPlugin* self = JUST_GAMEPADS_PLUGIN(object);
  if (self->source) {
    delete self->source;
    self->source = nullptr;
  }
  G_OBJECT_CLASS(just_gamepads_plugin_parent_class)->dispose(object);
}

static void just_gamepads_plugin_class_init(JustGamepadsPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = just_gamepads_plugin_dispose;
}

static void just_gamepads_plugin_init(JustGamepadsPlugin* self) {
  self->source = new just_gamepads::EvdevGamepadSource();
}

void just_gamepads_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  JustGamepadsPlugin* plugin = JUST_GAMEPADS_PLUGIN(
      g_object_new(just_gamepads_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel =
      fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                           "just_gamepads/events", FL_METHOD_CODEC(codec));
  // The handlers keep the plugin alive for as long as the channel is.
  fl_event_channel_set_stream_handlers(plugin->channel, on_listen_cb,
                                       on_cancel_cb, g_object_ref(plugin),
                                       g_object_unref);

  g_object_unref(plugin);
}

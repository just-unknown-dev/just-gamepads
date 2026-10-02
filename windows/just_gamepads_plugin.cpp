#include "just_gamepads_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

namespace just_gamepads {

namespace {
constexpr UINT kWmGamepadEvent = WM_APP + 1;
constexpr wchar_t kWindowClassName[] = L"JustGamepadsMessageWindow";
}  // namespace

// static
void JustGamepadsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<JustGamepadsPlugin>();

  plugin->channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "just_gamepads/events",
          &flutter::StandardMethodCodec::GetInstance());

  auto* plugin_pointer = plugin.get();
  plugin->channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [plugin_pointer](
              const flutter::EncodableValue* arguments,
              std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                  events)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            plugin_pointer->sink_ = std::move(events);
            plugin_pointer->watcher_.Start(
                [plugin_pointer](flutter::EncodableValue event) {
                  std::lock_guard<std::mutex> lock(
                      plugin_pointer->queue_mutex_);
                  // One wake-up drains everything queued before it runs, so
                  // only the first event of a batch needs to post one.
                  const bool was_empty =
                      plugin_pointer->pending_events_.empty();
                  plugin_pointer->pending_events_.push_back(std::move(event));
                  if (was_empty && plugin_pointer->message_window_) {
                    PostMessage(plugin_pointer->message_window_,
                                kWmGamepadEvent, 0, 0);
                  }
                });
            return nullptr;
          },
          [plugin_pointer](const flutter::EncodableValue* arguments)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            plugin_pointer->watcher_.Stop();
            plugin_pointer->sink_ = nullptr;
            return nullptr;
          }));

  registrar->AddPlugin(std::move(plugin));
}

JustGamepadsPlugin::JustGamepadsPlugin() { CreateMessageWindow(); }

JustGamepadsPlugin::~JustGamepadsPlugin() {
  watcher_.Stop();
  if (message_window_) {
    DestroyWindow(message_window_);
    message_window_ = nullptr;
  }
}

void JustGamepadsPlugin::CreateMessageWindow() {
  WNDCLASSEX window_class = {};
  window_class.cbSize = sizeof(WNDCLASSEX);
  window_class.lpfnWndProc = &JustGamepadsPlugin::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kWindowClassName;
  // RegisterClassEx is safe to call more than once per process with the
  // same class name in practice (fails with ERROR_CLASS_ALREADY_EXISTS,
  // which is fine to ignore) — relevant if a hot-restart ever re-registers
  // this plugin within the same process.
  RegisterClassEx(&window_class);

  message_window_ = CreateWindowEx(0, kWindowClassName, L"", 0, 0, 0, 0, 0,
                                    HWND_MESSAGE, nullptr,
                                    GetModuleHandle(nullptr), this);
}

// static
LRESULT CALLBACK JustGamepadsPlugin::WndProc(HWND hwnd, UINT message,
                                              WPARAM wparam, LPARAM lparam) {
  if (message == WM_CREATE) {
    auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
    return 0;
  }
  auto* plugin = reinterpret_cast<JustGamepadsPlugin*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == kWmGamepadEvent && plugin) {
    plugin->DrainQueue();
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void JustGamepadsPlugin::DrainQueue() {
  std::deque<flutter::EncodableValue> batch;
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    batch.swap(pending_events_);
  }
  if (!sink_) return;
  for (auto& event : batch) {
    sink_->Success(event);
  }
}

}  // namespace just_gamepads

#ifndef FLUTTER_PLUGIN_JUST_GAMEPADS_PLUGIN_H_
#define FLUTTER_PLUGIN_JUST_GAMEPADS_PLUGIN_H_

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/plugin_registrar_windows.h>

#include <deque>
#include <memory>
#include <mutex>

#include "gamepad_watcher.h"

namespace just_gamepads {

// Owns the `EventChannel('just_gamepads/events')` and the GamepadWatcher.
// GamepadWatcher delivers events from a background polling thread and from
// WinRT's own event-callback thread — neither is the Flutter platform
// thread, and EventSink::Success must only ever be called from there. This
// class marshals onto it via a hidden message-only window: background
// threads push encoded events into a mutex-protected queue and PostMessage a
// wake-up signal; the window's WndProc (which only ever runs pumped on the
// platform thread, since that's where this plugin is constructed and
// Flutter's own Win32 message loop runs) drains the queue and calls
// EventSink::Success for each — the standard, dependency-free Win32 pattern
// for background-thread-to-UI-thread marshaling.
class JustGamepadsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  JustGamepadsPlugin();
  virtual ~JustGamepadsPlugin();

  JustGamepadsPlugin(const JustGamepadsPlugin&) = delete;
  JustGamepadsPlugin& operator=(const JustGamepadsPlugin&) = delete;

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                   LPARAM lparam);
  void CreateMessageWindow();
  void DrainQueue();

  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  GamepadWatcher watcher_;

  HWND message_window_ = nullptr;
  std::mutex queue_mutex_;
  std::deque<flutter::EncodableValue> pending_events_;
};

}  // namespace just_gamepads

#endif  // FLUTTER_PLUGIN_JUST_GAMEPADS_PLUGIN_H_

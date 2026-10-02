#ifndef FLUTTER_PLUGIN_JUST_GAMEPADS_GAMEPAD_WATCHER_H_
#define FLUTTER_PLUGIN_JUST_GAMEPADS_GAMEPAD_WATCHER_H_

#include <windows.gaming.input.h>
#include <wrl/client.h>

#include <flutter/encodable_value.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace just_gamepads {

// Watches controllers through Windows.Gaming.Input and emits one
// flutter::EncodableValue event map per connect, disconnect and state
// change (see gamepad_wire_protocol.dart for the shape).
//
// Uses the classic WinRT ABI (<windows.gaming.input.h>, WRL ComPtr) rather
// than C++/WinRT, whose projection headers need the C++/WinRT NuGet package
// that the Flutter plugin template doesn't set up. The ABI headers ship with
// the Windows SDK.
//
// Every controller is discovered once, through RawGameController. For each
// one, Gamepad::FromGameController says whether it is also an Xbox/XInput
// gamepad:
//  - yes: read through IGamepad, whose readings are already semantic
//    (sent as 'axes'/'buttons').
//  - no (PlayStation, Switch, generic HID pads): read through
//    IRawGameController (sent as 'rawAxes'/'rawButtons' for the shared Dart
//    positional mapper).
// Discovering through one API means a controller is never reported twice,
// whatever order Windows raises its events in.
class GamepadWatcher {
 public:
  using EventCallback = std::function<void(flutter::EncodableValue)>;

  GamepadWatcher();
  ~GamepadWatcher();

  GamepadWatcher(const GamepadWatcher&) = delete;
  GamepadWatcher& operator=(const GamepadWatcher&) = delete;

  // Subscribes to controller events, reports controllers already connected
  // and starts the polling thread. Does nothing if already started.
  //
  // `on_event` is called from the calling thread, WinRT's event threads and
  // the polling thread; callers must marshal to the platform thread
  // themselves (see JustGamepadsPlugin).
  void Start(EventCallback on_event);

  // Stops polling and unsubscribes. Safe to call when not started.
  void Stop();

 private:
  struct TrackedController {
    std::string id;
    Microsoft::WRL::ComPtr<ABI::Windows::Gaming::Input::IRawGameController>
        raw;
    // Set when the controller is an Xbox/XInput gamepad.
    Microsoft::WRL::ComPtr<ABI::Windows::Gaming::Input::IGamepad> gamepad;
    UINT32 button_count = 0;
    UINT32 axis_count = 0;
    UINT32 switch_count = 0;
    UINT16 vendor_id = 0;
    UINT16 product_id = 0;
  };

  void OnControllerAdded(
      ABI::Windows::Gaming::Input::IRawGameController* raw);
  void OnControllerRemoved(
      ABI::Windows::Gaming::Input::IRawGameController* raw);
  void PollLoop();
  flutter::EncodableValue ReadGamepad(const TrackedController& tracked);
  flutter::EncodableValue ReadRawController(const TrackedController& tracked);
  void EmitConnected(const TrackedController& tracked,
                     const std::wstring& name);
  void EmitDisconnected(const std::string& id);

  EventCallback on_event_;
  std::atomic<bool> running_{false};
  std::thread poll_thread_;
  bool ro_initialized_ = false;

  Microsoft::WRL::ComPtr<
      ABI::Windows::Gaming::Input::IRawGameControllerStatics>
      raw_statics_;
  Microsoft::WRL::ComPtr<ABI::Windows::Gaming::Input::IGamepadStatics2>
      gamepad_statics_;
  EventRegistrationToken raw_added_token_{};
  EventRegistrationToken raw_removed_token_{};

  // Keyed by COM identity (the controller's IUnknown pointer), the one
  // pointer COM guarantees is the same for every reference to an object.
  std::mutex controllers_mutex_;
  std::unordered_map<IUnknown*, TrackedController> controllers_;
  uint64_t next_id_ = 1;
};

}  // namespace just_gamepads

#endif  // FLUTTER_PLUGIN_JUST_GAMEPADS_GAMEPAD_WATCHER_H_

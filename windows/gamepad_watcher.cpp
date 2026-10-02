#include "gamepad_watcher.h"

// Must be included before other Windows headers.
#include <windows.h>

#include <roapi.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

#include <algorithm>
#include <chrono>
#include <vector>

#include "raw_layout.h"

using ABI::Windows::Foundation::IEventHandler;
using ABI::Windows::Foundation::Collections::IVectorView;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Down;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_DownLeft;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_DownRight;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Left;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Right;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Up;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_UpLeft;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_UpRight;
using ABI::Windows::Gaming::Input::GamepadButtons;
using ABI::Windows::Gaming::Input::GamepadButtons_A;
using ABI::Windows::Gaming::Input::GamepadButtons_B;
using ABI::Windows::Gaming::Input::GamepadButtons_DPadDown;
using ABI::Windows::Gaming::Input::GamepadButtons_DPadLeft;
using ABI::Windows::Gaming::Input::GamepadButtons_DPadRight;
using ABI::Windows::Gaming::Input::GamepadButtons_DPadUp;
using ABI::Windows::Gaming::Input::GamepadButtons_LeftShoulder;
using ABI::Windows::Gaming::Input::GamepadButtons_LeftThumbstick;
using ABI::Windows::Gaming::Input::GamepadButtons_Menu;
using ABI::Windows::Gaming::Input::GamepadButtons_RightShoulder;
using ABI::Windows::Gaming::Input::GamepadButtons_RightThumbstick;
using ABI::Windows::Gaming::Input::GamepadButtons_View;
using ABI::Windows::Gaming::Input::GamepadButtons_X;
using ABI::Windows::Gaming::Input::GamepadButtons_Y;
using ABI::Windows::Gaming::Input::GamepadReading;
using ABI::Windows::Gaming::Input::IGameController;
using ABI::Windows::Gaming::Input::IGamepad;
using ABI::Windows::Gaming::Input::IRawGameController;
using ABI::Windows::Gaming::Input::IRawGameController2;
using ABI::Windows::Gaming::Input::RawGameController;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HString;
using Microsoft::WRL::Wrappers::HStringReference;

namespace just_gamepads {

namespace {

constexpr auto kPollInterval = std::chrono::milliseconds(8);

std::string WideToUtf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                       static_cast<int>(wide.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

// COM guarantees one IUnknown pointer per object, whichever interface the
// object was reached through, so it identifies a controller across the
// Added and Removed events.
IUnknown* IdentityOf(IRawGameController* raw) {
  ComPtr<IUnknown> unknown;
  if (FAILED(raw->QueryInterface(IID_PPV_ARGS(&unknown)))) return nullptr;
  return unknown.Get();
}

// IRawGameController2 (Windows 10 1709 and later) has the device's display
// name, e.g. "Xbox Wireless Controller".
std::wstring DisplayNameFor(IRawGameController* raw, bool is_gamepad) {
  ComPtr<IRawGameController2> as_v2;
  if (SUCCEEDED(raw->QueryInterface(IID_PPV_ARGS(&as_v2)))) {
    HString name;
    if (SUCCEEDED(as_v2->get_DisplayName(name.GetAddressOf()))) {
      UINT32 length = 0;
      const wchar_t* buffer = WindowsGetStringRawBuffer(name.Get(), &length);
      if (buffer && length > 0) return std::wstring(buffer, length);
    }
  }
  return is_gamepad ? L"Xbox Controller" : L"Generic Controller";
}

flutter::EncodableValue ButtonsToEncodableList(GamepadButtons buttons) {
  std::vector<flutter::EncodableValue> result;
  auto add_if = [&](GamepadButtons flag, int index) {
    if ((buttons & flag) != 0) result.emplace_back(index);
  };
  add_if(GamepadButtons_A, 0);
  add_if(GamepadButtons_B, 1);
  add_if(GamepadButtons_X, 2);
  add_if(GamepadButtons_Y, 3);
  add_if(GamepadButtons_LeftShoulder, 4);
  add_if(GamepadButtons_RightShoulder, 5);
  // 6/7 (trigger buttons) are derived from the analog triggers in Dart:
  // GamepadReading has no discrete trigger flag.
  add_if(GamepadButtons_View, 8);
  add_if(GamepadButtons_Menu, 9);
  add_if(GamepadButtons_LeftThumbstick, 10);
  add_if(GamepadButtons_RightThumbstick, 11);
  add_if(GamepadButtons_DPadUp, 12);
  add_if(GamepadButtons_DPadDown, 13);
  add_if(GamepadButtons_DPadLeft, 14);
  add_if(GamepadButtons_DPadRight, 15);
  return flutter::EncodableValue(result);
}

flutter::EncodableValue StateEvent(const std::string& id) {
  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string("state"));
  event[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  return flutter::EncodableValue(event);
}

}  // namespace

GamepadWatcher::GamepadWatcher() {}

GamepadWatcher::~GamepadWatcher() { Stop(); }

void GamepadWatcher::Start(EventCallback on_event) {
  if (running_.exchange(true)) return;
  on_event_ = std::move(on_event);

  // WinRT activation needs a COM apartment on this thread. Flutter's
  // Windows runner already made the platform thread STA, so this normally
  // returns S_FALSE. Either success code must be balanced in Stop(); a
  // failure must not be.
  ro_initialized_ = SUCCEEDED(RoInitialize(RO_INIT_SINGLETHREADED));

  RoGetActivationFactory(
      HStringReference(RuntimeClass_Windows_Gaming_Input_RawGameController)
          .Get(),
      IID_PPV_ARGS(&raw_statics_));
  RoGetActivationFactory(
      HStringReference(RuntimeClass_Windows_Gaming_Input_Gamepad).Get(),
      IID_PPV_ARGS(&gamepad_statics_));

  if (raw_statics_) {
    // Subscribe before listing what's already connected, so nothing that
    // arrives in between is missed. A controller seen twice is deduplicated
    // in OnControllerAdded.
    auto added = Callback<IEventHandler<RawGameController*>>(
        [this](IInspectable*, IRawGameController* raw) -> HRESULT {
          OnControllerAdded(raw);
          return S_OK;
        });
    raw_statics_->add_RawGameControllerAdded(added.Get(), &raw_added_token_);

    auto removed = Callback<IEventHandler<RawGameController*>>(
        [this](IInspectable*, IRawGameController* raw) -> HRESULT {
          OnControllerRemoved(raw);
          return S_OK;
        });
    raw_statics_->add_RawGameControllerRemoved(removed.Get(),
                                               &raw_removed_token_);

    ComPtr<IVectorView<RawGameController*>> existing;
    if (SUCCEEDED(raw_statics_->get_RawGameControllers(&existing)) &&
        existing) {
      unsigned size = 0;
      existing->get_Size(&size);
      for (unsigned i = 0; i < size; i++) {
        ComPtr<IRawGameController> raw;
        if (SUCCEEDED(existing->GetAt(i, &raw))) OnControllerAdded(raw.Get());
      }
    }
  }

  poll_thread_ = std::thread(&GamepadWatcher::PollLoop, this);
}

void GamepadWatcher::Stop() {
  if (!running_.exchange(false)) return;
  if (poll_thread_.joinable()) poll_thread_.join();

  if (raw_statics_) {
    raw_statics_->remove_RawGameControllerAdded(raw_added_token_);
    raw_statics_->remove_RawGameControllerRemoved(raw_removed_token_);
  }
  {
    std::lock_guard<std::mutex> lock(controllers_mutex_);
    controllers_.clear();
  }
  raw_statics_.Reset();
  gamepad_statics_.Reset();

  if (ro_initialized_) {
    RoUninitialize();
    ro_initialized_ = false;
  }
}

void GamepadWatcher::OnControllerAdded(IRawGameController* raw) {
  if (!raw || !running_) return;
  IUnknown* key = IdentityOf(raw);
  if (!key) return;
  {
    std::lock_guard<std::mutex> lock(controllers_mutex_);
    if (controllers_.count(key) > 0) return;
  }

  TrackedController tracked;
  tracked.raw = raw;
  ComPtr<IGameController> as_game_controller;
  if (gamepad_statics_ &&
      SUCCEEDED(raw->QueryInterface(IID_PPV_ARGS(&as_game_controller)))) {
    ComPtr<IGamepad> gamepad;
    if (SUCCEEDED(gamepad_statics_->FromGameController(
            as_game_controller.Get(), &gamepad)) &&
        gamepad) {
      tracked.gamepad = gamepad;
    }
  }
  INT32 buttons = 0, axes = 0, switches = 0;
  raw->get_ButtonCount(&buttons);
  raw->get_AxisCount(&axes);
  raw->get_SwitchCount(&switches);
  tracked.button_count = buttons > 0 ? static_cast<UINT32>(buttons) : 0;
  tracked.axis_count = axes > 0 ? static_cast<UINT32>(axes) : 0;
  tracked.switch_count = switches > 0 ? static_cast<UINT32>(switches) : 0;
  raw->get_HardwareVendorId(&tracked.vendor_id);
  raw->get_HardwareProductId(&tracked.product_id);
  const std::wstring name = DisplayNameFor(raw, tracked.gamepad != nullptr);

  {
    std::lock_guard<std::mutex> lock(controllers_mutex_);
    // Re-check: the initial listing and the Added event can race.
    if (controllers_.count(key) > 0) return;
    tracked.id = "wgi-" + std::to_string(next_id_++);
    controllers_[key] = tracked;
  }
  EmitConnected(tracked, name);
}

void GamepadWatcher::OnControllerRemoved(IRawGameController* raw) {
  if (!raw) return;
  IUnknown* key = IdentityOf(raw);
  std::string id;
  {
    std::lock_guard<std::mutex> lock(controllers_mutex_);
    auto it = controllers_.find(key);
    if (it == controllers_.end()) return;
    id = it->second.id;
    controllers_.erase(it);
  }
  EmitDisconnected(id);
}

void GamepadWatcher::PollLoop() {
  // Apartment state is per thread. MTA: this thread only makes synchronous
  // calls and never pumps messages.
  const bool ro_initialized = SUCCEEDED(RoInitialize(RO_INIT_MULTITHREADED));

  // Only changed states are sent, so an idle controller costs no channel
  // traffic.
  std::unordered_map<std::string, flutter::EncodableValue> last_states;

  while (running_) {
    std::vector<TrackedController> snapshot;
    {
      std::lock_guard<std::mutex> lock(controllers_mutex_);
      snapshot.reserve(controllers_.size());
      for (const auto& entry : controllers_) snapshot.push_back(entry.second);
    }

    for (const auto& tracked : snapshot) {
      flutter::EncodableValue state =
          tracked.gamepad ? ReadGamepad(tracked) : ReadRawController(tracked);
      if (state.IsNull()) continue;
      auto it = last_states.find(tracked.id);
      if (it != last_states.end() && it->second == state) continue;
      last_states[tracked.id] = state;
      on_event_(std::move(state));
    }

    for (auto it = last_states.begin(); it != last_states.end();) {
      const bool present = std::any_of(
          snapshot.begin(), snapshot.end(),
          [&](const TrackedController& t) { return t.id == it->first; });
      it = present ? std::next(it) : last_states.erase(it);
    }

    std::this_thread::sleep_for(kPollInterval);
  }

  if (ro_initialized) RoUninitialize();
}

flutter::EncodableValue GamepadWatcher::ReadGamepad(
    const TrackedController& tracked) {
  GamepadReading reading;
  if (FAILED(tracked.gamepad->GetCurrentReading(&reading))) {
    return flutter::EncodableValue();
  }

  // GamepadReading's thumbstick Y is up-positive; the wire protocol is
  // down-positive (the W3C Standard Gamepad convention), so Y is negated.
  flutter::EncodableMap axes;
  axes[flutter::EncodableValue("leftStickX")] =
      flutter::EncodableValue(reading.LeftThumbstickX);
  axes[flutter::EncodableValue("leftStickY")] =
      flutter::EncodableValue(-reading.LeftThumbstickY);
  axes[flutter::EncodableValue("rightStickX")] =
      flutter::EncodableValue(reading.RightThumbstickX);
  axes[flutter::EncodableValue("rightStickY")] =
      flutter::EncodableValue(-reading.RightThumbstickY);
  axes[flutter::EncodableValue("leftTrigger")] =
      flutter::EncodableValue(reading.LeftTrigger);
  axes[flutter::EncodableValue("rightTrigger")] =
      flutter::EncodableValue(reading.RightTrigger);

  flutter::EncodableValue event = StateEvent(tracked.id);
  auto& map = std::get<flutter::EncodableMap>(event);
  map[flutter::EncodableValue("axes")] = flutter::EncodableValue(axes);
  map[flutter::EncodableValue("buttons")] =
      ButtonsToEncodableList(reading.Buttons);
  return event;
}

flutter::EncodableValue GamepadWatcher::ReadRawController(
    const TrackedController& tracked) {
  std::vector<boolean> button_array(tracked.button_count);
  std::vector<GameControllerSwitchPosition> switch_array(tracked.switch_count);
  std::vector<double> axis_array(tracked.axis_count);
  UINT64 timestamp = 0;
  const HRESULT hr = tracked.raw->GetCurrentReading(
      static_cast<UINT32>(button_array.size()),
      button_array.empty() ? nullptr : button_array.data(),
      static_cast<UINT32>(switch_array.size()),
      switch_array.empty() ? nullptr : switch_array.data(),
      static_cast<UINT32>(axis_array.size()),
      axis_array.empty() ? nullptr : axis_array.data(), &timestamp);
  if (FAILED(hr)) return flutter::EncodableValue();

  std::vector<bool> buttons;
  buttons.reserve(button_array.size());
  for (boolean value : button_array) buttons.push_back(value != 0);
  ApplyVendorLayout(tracked.vendor_id, &axis_array, &buttons);

  std::vector<flutter::EncodableValue> raw_axes;
  for (double value : ToWireAxes(axis_array)) raw_axes.emplace_back(value);
  std::vector<flutter::EncodableValue> raw_buttons;
  for (bool value : buttons) raw_buttons.emplace_back(value);

  bool up = false, down = false, left = false, right = false;
  if (!switch_array.empty()) {
    switch (switch_array[0]) {
      case GameControllerSwitchPosition_Up: up = true; break;
      case GameControllerSwitchPosition_UpRight: up = right = true; break;
      case GameControllerSwitchPosition_Right: right = true; break;
      case GameControllerSwitchPosition_DownRight: down = right = true; break;
      case GameControllerSwitchPosition_Down: down = true; break;
      case GameControllerSwitchPosition_DownLeft: down = left = true; break;
      case GameControllerSwitchPosition_Left: left = true; break;
      case GameControllerSwitchPosition_UpLeft: up = left = true; break;
      default: break;
    }
  }

  flutter::EncodableValue event = StateEvent(tracked.id);
  auto& map = std::get<flutter::EncodableMap>(event);
  map[flutter::EncodableValue("rawAxes")] = flutter::EncodableValue(raw_axes);
  map[flutter::EncodableValue("rawButtons")] =
      flutter::EncodableValue(raw_buttons);
  map[flutter::EncodableValue("dpadUp")] = flutter::EncodableValue(up);
  map[flutter::EncodableValue("dpadDown")] = flutter::EncodableValue(down);
  map[flutter::EncodableValue("dpadLeft")] = flutter::EncodableValue(left);
  map[flutter::EncodableValue("dpadRight")] = flutter::EncodableValue(right);
  return event;
}

void GamepadWatcher::EmitConnected(const TrackedController& tracked,
                                   const std::wstring& name) {
  auto id_or_null = [](UINT16 value) {
    return value == 0 ? flutter::EncodableValue()
                      : flutter::EncodableValue(static_cast<int32_t>(value));
  };
  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string("connected"));
  event[flutter::EncodableValue("id")] = flutter::EncodableValue(tracked.id);
  event[flutter::EncodableValue("name")] =
      flutter::EncodableValue(WideToUtf8(name));
  event[flutter::EncodableValue("vendorId")] = id_or_null(tracked.vendor_id);
  event[flutter::EncodableValue("productId")] = id_or_null(tracked.product_id);
  if (tracked.gamepad) {
    // Third-party XInput pads (PowerA, PDP, Hori...) carry their own vendor
    // ids but the Xbox layout; the hint lets the Dart classifier say so.
    event[flutter::EncodableValue("typeHint")] =
        flutter::EncodableValue(std::string("XInput"));
  }
  on_event_(flutter::EncodableValue(event));
}

void GamepadWatcher::EmitDisconnected(const std::string& id) {
  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string("disconnected"));
  event[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  on_event_(flutter::EncodableValue(event));
}

}  // namespace just_gamepads

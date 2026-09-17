#include "gamepad_watcher.h"

// Must be included before other Windows headers.
#include <windows.h>

#include <roapi.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>

#include <chrono>
#include <sstream>

using ABI::Windows::Foundation::IEventHandler;
using ABI::Windows::Foundation::Collections::IVectorView;
using ABI::Windows::Gaming::Input::Gamepad;
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
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Center;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Down;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_DownLeft;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_DownRight;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Left;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Right;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_Up;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_UpLeft;
using ABI::Windows::Gaming::Input::GameControllerSwitchPosition_UpRight;
using ABI::Windows::Gaming::Input::IGameController;
using ABI::Windows::Gaming::Input::IGamepad;
using ABI::Windows::Gaming::Input::IGamepadStatics;
using ABI::Windows::Gaming::Input::IRawGameController;
using ABI::Windows::Gaming::Input::IRawGameController2;
using ABI::Windows::Gaming::Input::IRawGameControllerStatics;
using ABI::Windows::Gaming::Input::RawGameController;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HString;
using Microsoft::WRL::Wrappers::HStringReference;

namespace just_gamepads {

namespace {

// Xbox/XInput-compatible pads (the only kind Windows.Gaming.Input's primary
// Gamepad API surfaces) always carry Microsoft's USB-IF vendor id — Gamepad
// itself exposes no vendor/product id getters (unlike RawGameController), so
// this is hardcoded rather than queried, matching the shared Dart classifier
// (GamepadDatabase)'s Xbox entry exactly.
constexpr int kMicrosoftVendorId = 0x045E;

std::string PointerToId(const wchar_t* prefix, void* pointer) {
  std::ostringstream stream;
  stream << prefix << pointer;
  return stream.str();
}

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

std::wstring HStringToWstring(HSTRING value) {
  UINT32 length = 0;
  const wchar_t* buffer = WindowsGetStringRawBuffer(value, &length);
  return buffer ? std::wstring(buffer, length) : std::wstring();
}

// IRawGameController itself has no display-name getter; IRawGameController2
// (available since UniversalApiContract 5.0 — every currently-supported
// Windows 10/11 release) does, via get_DisplayName(). Falls back to a
// generic label when the QueryInterface fails (an old OS) or the name comes
// back empty.
std::wstring DisplayNameForRawController(IRawGameController* raw_controller) {
  ComPtr<IRawGameController2> as_v2;
  if (SUCCEEDED(raw_controller->QueryInterface(IID_PPV_ARGS(&as_v2)))) {
    HString name;
    if (SUCCEEDED(as_v2->get_DisplayName(name.GetAddressOf()))) {
      std::wstring result = HStringToWstring(name.Get());
      if (!result.empty()) return result;
    }
  }
  return L"Generic Controller";
}

flutter::EncodableValue ButtonsToEncodableList(GamepadButtons buttons) {
  std::vector<flutter::EncodableValue> result;
  auto add_if = [&](bool held, int index) {
    if (held) result.emplace_back(index);
  };
  add_if((buttons & GamepadButtons_A) != 0, 0);
  add_if((buttons & GamepadButtons_B) != 0, 1);
  add_if((buttons & GamepadButtons_X) != 0, 2);
  add_if((buttons & GamepadButtons_Y) != 0, 3);
  add_if((buttons & GamepadButtons_LeftShoulder) != 0, 4);
  add_if((buttons & GamepadButtons_RightShoulder) != 0, 5);
  // Indices 6/7 (trigger buttons) are intentionally never set here — WGI has
  // no discrete trigger-button flag, only the analog LeftTrigger/RightTrigger
  // reading. The shared Dart `normalizeTriggerButtons` step derives them
  // from that analog value on the Dart side.
  add_if((buttons & GamepadButtons_View) != 0, 8);
  add_if((buttons & GamepadButtons_Menu) != 0, 9);
  add_if((buttons & GamepadButtons_LeftThumbstick) != 0, 10);
  add_if((buttons & GamepadButtons_RightThumbstick) != 0, 11);
  add_if((buttons & GamepadButtons_DPadUp) != 0, 12);
  add_if((buttons & GamepadButtons_DPadDown) != 0, 13);
  add_if((buttons & GamepadButtons_DPadLeft) != 0, 14);
  add_if((buttons & GamepadButtons_DPadRight) != 0, 15);
  return flutter::EncodableValue(result);
}

}  // namespace

GamepadWatcher::GamepadWatcher() {}

GamepadWatcher::~GamepadWatcher() { Stop(); }

void GamepadWatcher::Start(EventCallback on_event) {
  if (running_.exchange(true)) return;
  on_event_ = std::move(on_event);

  // WinRT activation requires the calling thread to be in a WinRT-aware COM
  // apartment. This is normally called from the platform thread (via the
  // plugin's EventChannel OnListen), which Flutter's Windows runner already
  // initializes as STA via CoInitializeEx — RoInitialize with a matching
  // apartment type is a safe, cheap no-op in that case (returns S_FALSE),
  // so failure here is deliberately not treated as fatal: if activation
  // genuinely didn't succeed, `gamepad_statics_`/`raw_statics_` below stay
  // null and every subsequent call already null-checks them.
  RoInitialize(RO_INIT_SINGLETHREADED);

  RoGetActivationFactory(
      HStringReference(RuntimeClass_Windows_Gaming_Input_Gamepad).Get(),
      IID_PPV_ARGS(&gamepad_statics_));
  RoGetActivationFactory(
      HStringReference(RuntimeClass_Windows_Gaming_Input_RawGameController)
          .Get(),
      IID_PPV_ARGS(&raw_statics_));

  if (gamepad_statics_) {
    ComPtr<IVectorView<Gamepad*>> existing;
    if (SUCCEEDED(gamepad_statics_->get_Gamepads(&existing)) && existing) {
      unsigned size = 0;
      existing->get_Size(&size);
      for (unsigned i = 0; i < size; i++) {
        ComPtr<IGamepad> gamepad;
        if (SUCCEEDED(existing->GetAt(i, &gamepad))) {
          EmitConnected(PointerToId(L"gamepad-", gamepad.Get()), L"Xbox Controller",
                        kMicrosoftVendorId, 0);
          std::lock_guard<std::mutex> lock(controllers_mutex_);
          gamepads_[gamepad.Get()] = {PointerToId(L"gamepad-", gamepad.Get()), gamepad};
        }
      }
    }

    auto added = Callback<IEventHandler<Gamepad*>>(
        [this](IInspectable*, IGamepad* args) -> HRESULT {
          if (!args) return S_OK;
          const auto id = PointerToId(L"gamepad-", args);
          {
            std::lock_guard<std::mutex> lock(controllers_mutex_);
            ComPtr<IGamepad> owned = args;
            gamepads_[args] = {id, owned};
          }
          EmitConnected(id, L"Xbox Controller", kMicrosoftVendorId, 0);
          return S_OK;
        });
    gamepad_statics_->add_GamepadAdded(added.Get(), &gamepad_added_token_);

    auto removed = Callback<IEventHandler<Gamepad*>>(
        [this](IInspectable*, IGamepad* args) -> HRESULT {
          if (!args) return S_OK;
          const auto id = PointerToId(L"gamepad-", args);
          {
            std::lock_guard<std::mutex> lock(controllers_mutex_);
            gamepads_.erase(args);
          }
          EmitDisconnected(id);
          return S_OK;
        });
    gamepad_statics_->add_GamepadRemoved(removed.Get(), &gamepad_removed_token_);
  }

  if (raw_statics_) {
    ComPtr<IVectorView<RawGameController*>> existing;
    if (SUCCEEDED(raw_statics_->get_RawGameControllers(&existing)) &&
        existing) {
      unsigned size = 0;
      existing->get_Size(&size);
      for (unsigned i = 0; i < size; i++) {
        ComPtr<IRawGameController> raw;
        if (SUCCEEDED(existing->GetAt(i, &raw)) &&
            !IsCorrelatedWithGamepad(raw.Get())) {
          INT32 buttons = 0, axes = 0, switches = 0;
          raw->get_ButtonCount(&buttons);
          raw->get_AxisCount(&axes);
          raw->get_SwitchCount(&switches);
          UINT16 vendor_id = 0, product_id = 0;
          raw->get_HardwareVendorId(&vendor_id);
          raw->get_HardwareProductId(&product_id);
          const auto id = PointerToId(L"raw-", raw.Get());
          {
            std::lock_guard<std::mutex> lock(controllers_mutex_);
            raw_controllers_[raw.Get()] = {
                id, raw, static_cast<UINT32>(buttons),
                static_cast<UINT32>(axes), static_cast<UINT32>(switches),
                vendor_id, product_id};
          }
          EmitConnected(id, DisplayNameForRawController(raw.Get()), vendor_id,
                        product_id);
        }
      }
    }

    auto raw_added = Callback<IEventHandler<RawGameController*>>(
        [this](IInspectable*, IRawGameController* args) -> HRESULT {
          if (!args || IsCorrelatedWithGamepad(args)) return S_OK;
          INT32 buttons = 0, axes = 0, switches = 0;
          args->get_ButtonCount(&buttons);
          args->get_AxisCount(&axes);
          args->get_SwitchCount(&switches);
          UINT16 vendor_id = 0, product_id = 0;
          args->get_HardwareVendorId(&vendor_id);
          args->get_HardwareProductId(&product_id);
          const auto id = PointerToId(L"raw-", args);
          {
            std::lock_guard<std::mutex> lock(controllers_mutex_);
            ComPtr<IRawGameController> owned = args;
            raw_controllers_[args] = {
                id, owned, static_cast<UINT32>(buttons),
                static_cast<UINT32>(axes), static_cast<UINT32>(switches),
                vendor_id, product_id};
          }
          EmitConnected(id, DisplayNameForRawController(args), vendor_id,
                        product_id);
          return S_OK;
        });
    raw_statics_->add_RawGameControllerAdded(raw_added.Get(),
                                              &raw_added_token_);

    auto raw_removed = Callback<IEventHandler<RawGameController*>>(
        [this](IInspectable*, IRawGameController* args) -> HRESULT {
          if (!args) return S_OK;
          const auto id = PointerToId(L"raw-", args);
          bool was_tracked;
          {
            std::lock_guard<std::mutex> lock(controllers_mutex_);
            was_tracked = raw_controllers_.erase(args) > 0;
          }
          if (was_tracked) EmitDisconnected(id);
          return S_OK;
        });
    raw_statics_->add_RawGameControllerRemoved(raw_removed.Get(),
                                                &raw_removed_token_);
  }

  poll_thread_ = std::thread(&GamepadWatcher::PollLoop, this);
}

void GamepadWatcher::Stop() {
  if (!running_.exchange(false)) return;
  if (poll_thread_.joinable()) poll_thread_.join();

  if (gamepad_statics_) {
    gamepad_statics_->remove_GamepadAdded(gamepad_added_token_);
    gamepad_statics_->remove_GamepadRemoved(gamepad_removed_token_);
  }
  if (raw_statics_) {
    raw_statics_->remove_RawGameControllerAdded(raw_added_token_);
    raw_statics_->remove_RawGameControllerRemoved(raw_removed_token_);
  }

  {
    std::lock_guard<std::mutex> lock(controllers_mutex_);
    gamepads_.clear();
    raw_controllers_.clear();
  }

  RoUninitialize();
}

bool GamepadWatcher::IsCorrelatedWithGamepad(IRawGameController* raw_controller) {
  if (!raw_statics_ || !raw_controller) return false;
  ComPtr<IGameController> as_game_controller;
  // IRawGameController -> IGameController fails (returns nullptr) for a raw
  // controller that isn't also exposed as a Gamepad, which is the common
  // case (e.g. PlayStation pads) — that's expected, not an error.
  if (FAILED(raw_controller->QueryInterface(IID_PPV_ARGS(&as_game_controller)))) {
    return false;
  }
  ComPtr<IRawGameController> reverse;
  // FromGameController itself only accepts controllers that expose
  // IGameController, which every RawGameController does — the real question
  // is whether the *matching* Gamepad-path entry exists, checked via the
  // already-tracked gamepads_ map instead of a second WinRT round-trip.
  std::lock_guard<std::mutex> lock(controllers_mutex_);
  for (const auto& [key, tracked] : gamepads_) {
    ComPtr<IGameController> tracked_as_controller;
    if (SUCCEEDED(tracked.gamepad.As(&tracked_as_controller)) &&
        tracked_as_controller.Get() == as_game_controller.Get()) {
      return true;
    }
  }
  return false;
}

void GamepadWatcher::PollLoop() {
  // COM/WinRT apartment state is per-thread — this background thread has
  // none until it initializes its own, independent of Start()'s call on the
  // platform thread. MTA (not STA) since this thread only ever makes
  // synchronous property/method calls and never pumps a message loop.
  const bool com_initialized =
      SUCCEEDED(RoInitialize(RO_INIT_MULTITHREADED));

  while (running_) {
    std::vector<TrackedGamepad> gamepad_snapshot;
    std::vector<TrackedRawController> raw_snapshot;
    {
      std::lock_guard<std::mutex> lock(controllers_mutex_);
      for (const auto& [key, tracked] : gamepads_) gamepad_snapshot.push_back(tracked);
      for (const auto& [key, tracked] : raw_controllers_) raw_snapshot.push_back(tracked);
    }
    for (const auto& tracked : gamepad_snapshot) PollGamepad(tracked);
    for (const auto& tracked : raw_snapshot) PollRawController(tracked);
    std::this_thread::sleep_for(std::chrono::milliseconds(16));
  }

  if (com_initialized) RoUninitialize();
}

void GamepadWatcher::PollGamepad(const TrackedGamepad& tracked) {
  GamepadReading reading;
  if (FAILED(tracked.gamepad->GetCurrentReading(&reading))) return;

  flutter::EncodableMap axes;
  axes[flutter::EncodableValue("leftStickX")] =
      flutter::EncodableValue(reading.LeftThumbstickX);
  // WGI's thumbstick Y is +1 = up, -1 = down; just_inputs' convention
  // (matching its keyboard digital fallback, and the W3C Standard Gamepad
  // axes the Web backend passes straight through unmodified) is
  // down-positive — negate to match.
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

  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string("state"));
  event[flutter::EncodableValue("id")] = flutter::EncodableValue(tracked.id);
  event[flutter::EncodableValue("axes")] = flutter::EncodableValue(axes);
  event[flutter::EncodableValue("buttons")] =
      ButtonsToEncodableList(reading.Buttons);
  on_event_(flutter::EncodableValue(event));
}

void GamepadWatcher::PollRawController(const TrackedRawController& tracked) {
  std::vector<boolean> button_array(tracked.button_count);
  std::vector<GameControllerSwitchPosition> switch_array(tracked.switch_count);
  std::vector<double> axis_array(tracked.axis_count);
  UINT64 timestamp = 0;
  HRESULT hr = tracked.raw_controller->GetCurrentReading(
      static_cast<UINT32>(button_array.size()),
      button_array.empty() ? nullptr : button_array.data(),
      static_cast<UINT32>(switch_array.size()),
      switch_array.empty() ? nullptr : switch_array.data(),
      static_cast<UINT32>(axis_array.size()),
      axis_array.empty() ? nullptr : axis_array.data(), &timestamp);
  if (FAILED(hr)) return;

  std::vector<flutter::EncodableValue> raw_buttons;
  raw_buttons.reserve(button_array.size());
  for (boolean value : button_array) raw_buttons.emplace_back(value != 0);

  // IRawGameController::GetCurrentReading documents *every* axis as
  // normalized to [0.0, 1.0] regardless of role — RawGameController has no
  // concept of "this axis is a stick" vs. "this axis is a trigger" (that's
  // exactly why it's "raw"), unlike Gamepad's semantic thumbstick values,
  // which already arrive as [-1.0, 1.0] (see PollGamepad above). Sony's
  // DualSense/DualShock (and other non-XInput pads) only ever reach the game
  // through this path, so without remapping here a centered stick reads as
  // a constant ~0.5 "half tilted" value — well outside ControllerInput's
  // 0.15 deadzone — and full deflection only ever spans one side of the
  // expected range, exactly the "joystick doesn't work right" symptom this
  // fixes. The shared Dart generic-HID mapper (generic_hid_mapper.dart)
  // expects the first four axes (assumed left/right stick X/Y, the common
  // HID gamepad declaration order) in [-1.0, 1.0] and any trigger axes
  // after that in their native [0.0, 1.0] — so only the first four are
  // remapped here, triggers are passed through unchanged.
  //
  // Y-axis sign is deliberately left alone (unlike PollGamepad's explicit
  // negation): standard HID joystick usage convention already reports Y
  // increasing *downward* (0.0 = up, 1.0 = down), so after the same 2*v-1
  // remap applied to X, Y already lands in just_inputs' down-positive
  // convention with no separate negation needed.
  //
  // Sony's DualShock4/DualSense report descriptor assigns HID usage tags to
  // its analog fields in a well-known non-obvious order (right stick on
  // Z/Rz, triggers on Rx/Ry, rather than the "expected" Rx/Ry for the right
  // stick), and RawGameController's axis array follows that usage-tag order
  // rather than physical stick/trigger role. Verified against a real
  // DualSense unit: the raw order comes through as [LX, LY, RX, L2, R2, RY]
  // — not the canonical [LX, LY, RX, RY, L2, R2] every other path (and the
  // shared Dart generic-HID mapper) assumes. Reordered into canonical form
  // here, at the one point where the device's identity (vendor id) is still
  // known, rather than teaching the shared cross-platform mapper about one
  // vendor's quirk.
  std::vector<double> axis_values(axis_array.begin(), axis_array.end());
  const bool is_sony_dualshock_layout =
      tracked.vendor_id == 0x054C &&  // Sony — matches
                                       // gamepad_database.dart's _sonyVendorId
      axis_values.size() >= 6;
  if (is_sony_dualshock_layout) {
    axis_values = {axis_values[0], axis_values[1], axis_values[2],
                    axis_values[5], axis_values[3], axis_values[4]};
  } else if (axis_values.size() >= 2) {
    // Several non-Sony generic/unbranded HID gamepads report the left
    // stick's X and Y usage tags physically swapped, *and* Y's usage tag
    // increasing in the opposite direction from the generic-HID-convention
    // assumption above (0.0 = down, 1.0 = up, rather than the usual
    // 0.0 = up, 1.0 = down) — both confirmed against a real "generic
    // Windows-compatible controller" unit: pushing the stick left/right
    // originally moved the character up/down (fixed by the swap), and
    // after that fix, up/down was inverted (fixed by the negation below).
    // Sony's pads don't have either quirk (handled separately above), and
    // Xbox-compatible pads never reach this function at all — they're read
    // through the Gamepad/XInput path in PollGamepad, which has no such
    // bug. Swap the first two raw values so index 0 is genuinely X and
    // index 1 is genuinely Y, then flip Y's direction — `1.0 - v` inverts
    // it the same way the later `v * 2.0 - 1.0` remap works, so the sign
    // comes out right once that remap runs.
    const double x = axis_values[0];
    axis_values[0] = axis_values[1];
    axis_values[1] = 1.0 - x;
  }

  std::vector<flutter::EncodableValue> raw_axes;
  raw_axes.reserve(axis_values.size());
  for (size_t i = 0; i < axis_values.size(); i++) {
    const double value =
        (i < 4) ? (axis_values[i] * 2.0 - 1.0) : axis_values[i];
    raw_axes.emplace_back(value);
  }

  bool dpad_up = false, dpad_down = false, dpad_left = false, dpad_right = false;
  if (!switch_array.empty()) {
    switch (switch_array[0]) {
      case GameControllerSwitchPosition_Up: dpad_up = true; break;
      case GameControllerSwitchPosition_UpRight: dpad_up = dpad_right = true; break;
      case GameControllerSwitchPosition_Right: dpad_right = true; break;
      case GameControllerSwitchPosition_DownRight: dpad_down = dpad_right = true; break;
      case GameControllerSwitchPosition_Down: dpad_down = true; break;
      case GameControllerSwitchPosition_DownLeft: dpad_down = dpad_left = true; break;
      case GameControllerSwitchPosition_Left: dpad_left = true; break;
      case GameControllerSwitchPosition_UpLeft: dpad_up = dpad_left = true; break;
      case GameControllerSwitchPosition_Center:
      default: break;
    }
  }

  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string("state"));
  event[flutter::EncodableValue("id")] = flutter::EncodableValue(tracked.id);
  event[flutter::EncodableValue("rawAxes")] = flutter::EncodableValue(raw_axes);
  event[flutter::EncodableValue("rawButtons")] =
      flutter::EncodableValue(raw_buttons);
  event[flutter::EncodableValue("dpadUp")] = flutter::EncodableValue(dpad_up);
  event[flutter::EncodableValue("dpadDown")] = flutter::EncodableValue(dpad_down);
  event[flutter::EncodableValue("dpadLeft")] = flutter::EncodableValue(dpad_left);
  event[flutter::EncodableValue("dpadRight")] = flutter::EncodableValue(dpad_right);
  on_event_(flutter::EncodableValue(event));
}

void GamepadWatcher::EmitConnected(const std::string& id, const std::wstring& name,
                                    int vendor_id, int product_id) {
  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string("connected"));
  event[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  event[flutter::EncodableValue("name")] = flutter::EncodableValue(WideToUtf8(name));
  event[flutter::EncodableValue("vendorId")] = flutter::EncodableValue(vendor_id);
  event[flutter::EncodableValue("productId")] = flutter::EncodableValue(product_id);
  on_event_(flutter::EncodableValue(event));
}

void GamepadWatcher::EmitDisconnected(const std::string& id) {
  flutter::EncodableMap event;
  event[flutter::EncodableValue("event")] =
      flutter::EncodableValue(std::string("disconnected"));
  event[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  event[flutter::EncodableValue("name")] = flutter::EncodableValue(std::string());
  on_event_(flutter::EncodableValue(event));
}

}  // namespace just_gamepads

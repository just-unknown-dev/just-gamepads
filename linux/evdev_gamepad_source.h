#ifndef FLUTTER_PLUGIN_JUST_GAMEPADS_EVDEV_GAMEPAD_SOURCE_H_
#define FLUTTER_PLUGIN_JUST_GAMEPADS_EVDEV_GAMEPAD_SOURCE_H_

// NOTE: unverified/uncompiled on this machine (no Linux desktop toolchain on
// Windows) — written from documented evdev/libudev/GLib APIs, matching
// SDL2's own Linux joystick backend conventions where a choice had to be
// made (axis ordering, gamepad-capability heuristic). Needs a first real
// build + real-hardware smoke test on Linux, and `libudev-dev` installed
// (see CMakeLists.txt's pkg_check_modules) before shipping.

#include <flutter_linux/flutter_linux.h>
#include <glib.h>
#include <libudev.h>

#include <functional>
#include <map>
#include <string>

namespace just_gamepads {

// Enumerates /dev/input/event* gamepad-capable devices (evdev), watches for
// hot-plug via a libudev monitor integrated into the GLib main loop (no
// dedicated polling thread — everything here runs on the platform thread's
// existing GLib main loop, unlike the Windows backend which genuinely needs
// a background thread + message marshaling), and emits one
// flutter::EncodableValue-equivalent `FlValue*` event map per
// connect/disconnect/state change via a callback, matching the shared wire
// protocol every backend speaks (see gamepad_wire_protocol.dart).
class EvdevGamepadSource {
 public:
  using EventCallback = std::function<void(FlValue* event)>;

  EvdevGamepadSource();
  ~EvdevGamepadSource();

  EvdevGamepadSource(const EvdevGamepadSource&) = delete;
  EvdevGamepadSource& operator=(const EvdevGamepadSource&) = delete;

  void Start(EventCallback on_event);
  void Stop();

 private:
  struct TrackedDevice {
    std::string id;
    int fd = -1;
    guint io_watch_id = 0;
    // Raw evdev axis codes -> [min, max], from EVIOCGABS — needed to
    // normalize each device's raw integer axis range to -1.0..1.0 (evdev
    // does not report pre-normalized floats the way
    // Windows.Gaming.Input/Android MotionEvent/the browser Gamepad API do).
    std::map<int, std::pair<int32_t, int32_t>> axis_ranges;
    // Accumulated state between SYN_REPORT markers — evdev delivers
    // individual EV_KEY/EV_ABS events, batched into one full snapshot per
    // sync, matching every other backend's "push one snapshot per tick"
    // model.
    std::map<std::string, double> axes;
    std::map<int, bool> buttons_down;  // keyed by raw BTN_* evdev code
  };

  static gboolean OnUdevMonitorReadable(GIOChannel* source,
                                         GIOCondition condition,
                                         gpointer user_data);
  static gboolean OnDeviceReadable(GIOChannel* source, GIOCondition condition,
                                    gpointer user_data);

  void ScanExistingDevices();
  void TryAddDevice(const std::string& syspath);
  void RemoveDevice(const std::string& syspath);
  bool IsGamepadCapable(int fd);
  void ReadAbsInfo(TrackedDevice& device);
  void HandleInputEvents(const std::string& syspath);
  void EmitSnapshot(const TrackedDevice& device);
  void EmitConnected(const std::string& id, const std::string& name,
                      int vendor_id, int product_id);
  void EmitDisconnected(const std::string& id);

  EventCallback on_event_;
  struct udev* udev_ = nullptr;
  struct udev_monitor* udev_monitor_ = nullptr;
  GIOChannel* udev_channel_ = nullptr;
  guint udev_watch_id_ = 0;

  // Keyed by udev syspath (stable per physical connection) rather than the
  // /dev/input/eventN name, since Linux can reassign event-node numbers
  // across reconnects.
  std::map<std::string, TrackedDevice> devices_;
};

}  // namespace just_gamepads

#endif  // FLUTTER_PLUGIN_JUST_GAMEPADS_EVDEV_GAMEPAD_SOURCE_H_

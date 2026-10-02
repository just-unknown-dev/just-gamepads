#ifndef FLUTTER_PLUGIN_JUST_GAMEPADS_EVDEV_GAMEPAD_SOURCE_H_
#define FLUTTER_PLUGIN_JUST_GAMEPADS_EVDEV_GAMEPAD_SOURCE_H_

#include <flutter_linux/flutter_linux.h>
#include <glib.h>

#include <cstdint>
#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace just_gamepads {

// Reports game controllers from the kernel's evdev interface
// (/dev/input/event*) and emits one FlValue event map per connect,
// disconnect and state change (see gamepad_wire_protocol.dart for the
// shape).
//
// Hot-plug comes from inotify on /dev/input, so the plugin needs no
// libraries beyond GLib. Everything runs on the GLib main loop of the
// platform thread; no extra threads.
//
// Controllers the kernel exposes with the standard gamepad buttons
// (BTN_GAMEPAD) are reported in the semantic shape. Other joysticks are
// reported in the raw positional shape for the shared Dart mapper.
//
// The app needs read access to /dev/input/event*. Desktop distributions
// grant it to the logged-in user for joysticks (systemd-logind's uaccess);
// sandboxes such as Flatpak or Snap must allow device access.
class EvdevGamepadSource {
 public:
  using EventCallback = std::function<void(FlValue* event)>;

  EvdevGamepadSource();
  ~EvdevGamepadSource();

  EvdevGamepadSource(const EvdevGamepadSource&) = delete;
  EvdevGamepadSource& operator=(const EvdevGamepadSource&) = delete;

  // Starts watching and reports controllers already connected. Restarts
  // cleanly if already started.
  void Start(EventCallback on_event);

  // Stops watching and closes every device. Safe to call when not started.
  void Stop();

 private:
  struct AxisRange {
    int32_t min = 0;
    int32_t max = 0;
  };

  // Which evdev codes play which role, decided once per device from its
  // capabilities (-1 = not present).
  struct Layout {
    bool generic = false;
    int left_x = -1;
    int left_y = -1;
    int right_x = -1;
    int right_y = -1;
    int left_trigger = -1;
    int right_trigger = -1;
    // Face buttons: evdev's BTN_X/BTN_Y codes mean different positions on
    // different drivers (see ButtonIndexFor in the .cc).
    bool positional_face_buttons = false;
    // Generic devices only: codes in report order.
    std::vector<int> raw_axes;
    std::vector<int> raw_buttons;
  };

  struct TrackedDevice {
    std::string id;  // device node path, e.g. /dev/input/event5
    int fd = -1;
    guint watch_id = 0;
    Layout layout;
    // Between SYN_DROPPED and the next SYN_REPORT: events are discarded and
    // state is re-read from the kernel.
    bool dropping = false;
    std::map<int, AxisRange> ranges;     // ABS code -> range
    std::map<int, int32_t> abs_values;   // ABS code -> latest raw value
    std::set<int> keys_down;             // KEY/BTN codes held
  };

  static gboolean OnInotifyReadable(GIOChannel* source,
                                    GIOCondition condition,
                                    gpointer user_data);
  static gboolean OnDeviceReadable(GIOChannel* source, GIOCondition condition,
                                   gpointer user_data);

  void ScanExistingDevices();
  void TryAddDevice(const std::string& path);
  void RemoveDevice(const std::string& path);
  // Returns false once the device is gone.
  bool ReadEvents(TrackedDevice& device);
  void Resync(TrackedDevice& device);
  void EmitSnapshot(const TrackedDevice& device);
  void EmitConnected(const TrackedDevice& device, const std::string& name,
                     int vendor_id, int product_id);
  void EmitDisconnected(const std::string& id);

  EventCallback on_event_;
  int inotify_fd_ = -1;
  guint inotify_watch_id_ = 0;
  std::map<std::string, TrackedDevice> devices_;
};

}  // namespace just_gamepads

#endif  // FLUTTER_PLUGIN_JUST_GAMEPADS_EVDEV_GAMEPAD_SOURCE_H_

#include "evdev_gamepad_source.h"

#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cstring>

namespace just_gamepads {

namespace {

bool TestBit(const unsigned char* bitmask, int bit) {
  return (bitmask[bit / 8] >> (bit % 8)) & 1;
}

// A device qualifies as a gamepad by the kernel's own recommended
// heuristic (matching SDL2's Linux joystick backend): it reports the
// BTN_GAMEPAD key (the base of the standard controller button range) and
// has at least one analog axis. This deliberately excludes plain
// button-only remotes/keyboards that happen to share the "input" udev
// subsystem.
bool ProbeIsGamepad(int fd) {
  unsigned char key_bits[(KEY_MAX + 7) / 8 + 1] = {};
  unsigned char abs_bits[(ABS_MAX + 7) / 8 + 1] = {};
  if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key_bits)), key_bits) < 0) return false;
  if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs_bits)), abs_bits) < 0) return false;
  return TestBit(key_bits, BTN_GAMEPAD) && TestBit(abs_bits, ABS_X);
}

// leftStickX/Y = ABS_X/ABS_Y, rightStickX/Y = ABS_RX/ABS_RY,
// leftTrigger/rightTrigger = ABS_Z/ABS_RZ — the common modern evdev/xpad
// axis ordering (matching SDL2's default Linux gamecontroller mapping for
// XInput-compatible pads); genuinely varies by kernel driver for other
// devices, a documented risk flagged in the plan for real-hardware
// verification.
const char* AxisNameForCode(int code) {
  switch (code) {
    case ABS_X: return "leftStickX";
    case ABS_Y: return "leftStickY";
    case ABS_RX: return "rightStickX";
    case ABS_RY: return "rightStickY";
    case ABS_Z: return "leftTrigger";
    case ABS_RZ: return "rightTrigger";
    default: return nullptr;
  }
}

// evdev's Xbox-canonical button naming describes *physical position*, not
// necessarily what's printed on a given device — BTN_SOUTH/EAST/NORTH/WEST
// is the kernel's own convention regardless of controller brand, matching
// this project's standard layout (a=south, b=east, x=west, y=north) exactly
// as intended, but a documented easy-to-get-backwards detail worth real
// hardware verification.
int ButtonIndexForCode(int code) {
  switch (code) {
    case BTN_SOUTH: return 0;   // BTN_A
    case BTN_EAST: return 1;    // BTN_B
    case BTN_WEST: return 2;    // BTN_X
    case BTN_NORTH: return 3;   // BTN_Y
    case BTN_TL: return 4;
    case BTN_TR: return 5;
    case BTN_TL2: return 6;     // present only on drivers that expose a
                                 // digital trigger button in addition to
                                 // the analog ABS_Z/ABS_RZ axis.
    case BTN_TR2: return 7;
    case BTN_SELECT: return 8;
    case BTN_START: return 9;
    case BTN_THUMBL: return 10;
    case BTN_THUMBR: return 11;
    default: return -1;
  }
}

}  // namespace

EvdevGamepadSource::EvdevGamepadSource() {}

EvdevGamepadSource::~EvdevGamepadSource() { Stop(); }

void EvdevGamepadSource::Start(EventCallback on_event) {
  on_event_ = std::move(on_event);

  udev_ = udev_new();
  if (!udev_) return;

  ScanExistingDevices();

  udev_monitor_ = udev_monitor_new_from_netlink(udev_, "udev");
  if (udev_monitor_) {
    udev_monitor_filter_add_match_subsystem_devtype(udev_monitor_, "input", nullptr);
    udev_monitor_enable_receiving(udev_monitor_);
    int fd = udev_monitor_get_fd(udev_monitor_);
    udev_channel_ = g_io_channel_unix_new(fd);
    udev_watch_id_ = g_io_add_watch(udev_channel_, G_IO_IN,
                                     &EvdevGamepadSource::OnUdevMonitorReadable, this);
  }
}

void EvdevGamepadSource::Stop() {
  if (udev_watch_id_ != 0) {
    g_source_remove(udev_watch_id_);
    udev_watch_id_ = 0;
  }
  if (udev_channel_) {
    g_io_channel_unref(udev_channel_);
    udev_channel_ = nullptr;
  }
  if (udev_monitor_) {
    udev_monitor_unref(udev_monitor_);
    udev_monitor_ = nullptr;
  }
  for (auto& [syspath, device] : devices_) {
    if (device.io_watch_id != 0) g_source_remove(device.io_watch_id);
    if (device.fd >= 0) close(device.fd);
  }
  devices_.clear();
  if (udev_) {
    udev_unref(udev_);
    udev_ = nullptr;
  }
  on_event_ = nullptr;
}

void EvdevGamepadSource::ScanExistingDevices() {
  struct udev_enumerate* enumerate = udev_enumerate_new(udev_);
  if (!enumerate) return;
  udev_enumerate_add_match_subsystem(enumerate, "input");
  udev_enumerate_scan_devices(enumerate);

  struct udev_list_entry* entry;
  struct udev_list_entry* devices = udev_enumerate_get_list_entry(enumerate);
  udev_list_entry_foreach(entry, devices) {
    const char* syspath = udev_list_entry_get_name(entry);
    struct udev_device* device = udev_device_new_from_syspath(udev_, syspath);
    if (!device) continue;
    const char* devnode = udev_device_get_devnode(device);
    if (devnode && std::strncmp(devnode, "/dev/input/event", 17) == 0) {
      TryAddDevice(syspath);
    }
    udev_device_unref(device);
  }
  udev_enumerate_unref(enumerate);
}

// static
gboolean EvdevGamepadSource::OnUdevMonitorReadable(GIOChannel* source,
                                                     GIOCondition condition,
                                                     gpointer user_data) {
  auto* self = static_cast<EvdevGamepadSource*>(user_data);
  struct udev_device* device = udev_monitor_receive_device(self->udev_monitor_);
  if (!device) return TRUE;

  const char* action = udev_device_get_action(device);
  const char* devnode = udev_device_get_devnode(device);
  const char* syspath = udev_device_get_syspath(device);
  if (action && devnode && syspath &&
      std::strncmp(devnode, "/dev/input/event", 17) == 0) {
    if (std::strcmp(action, "add") == 0) {
      self->TryAddDevice(syspath);
    } else if (std::strcmp(action, "remove") == 0) {
      self->RemoveDevice(syspath);
    }
  }
  udev_device_unref(device);
  return TRUE;
}

void EvdevGamepadSource::TryAddDevice(const std::string& syspath) {
  if (devices_.count(syspath) > 0) return;

  struct udev_device* udev_device = udev_device_new_from_syspath(udev_, syspath.c_str());
  if (!udev_device) return;
  const char* devnode = udev_device_get_devnode(udev_device);
  std::string devnode_str = devnode ? devnode : "";
  udev_device_unref(udev_device);
  if (devnode_str.empty()) return;

  int fd = open(devnode_str.c_str(), O_RDONLY | O_NONBLOCK);
  if (fd < 0) return;
  if (!ProbeIsGamepad(fd)) {
    close(fd);
    return;
  }

  TrackedDevice device;
  device.id = syspath;
  device.fd = fd;
  ReadAbsInfo(device);

  char name_buf[256] = {};
  std::string name;
  if (ioctl(fd, EVIOCGNAME(sizeof(name_buf)), name_buf) >= 0) name = name_buf;

  struct input_id id_info = {};
  int vendor_id = 0, product_id = 0;
  if (ioctl(fd, EVIOCGID, &id_info) >= 0) {
    vendor_id = id_info.vendor;
    product_id = id_info.product;
  }

  GIOChannel* channel = g_io_channel_unix_new(fd);
  device.io_watch_id = g_io_add_watch(channel, G_IO_IN,
                                       &EvdevGamepadSource::OnDeviceReadable, this);
  g_io_channel_unref(channel);  // the watch itself holds a reference

  devices_[syspath] = std::move(device);
  EmitConnected(syspath, name, vendor_id, product_id);
}

void EvdevGamepadSource::RemoveDevice(const std::string& syspath) {
  auto it = devices_.find(syspath);
  if (it == devices_.end()) return;
  if (it->second.io_watch_id != 0) g_source_remove(it->second.io_watch_id);
  if (it->second.fd >= 0) close(it->second.fd);
  devices_.erase(it);
  EmitDisconnected(syspath);
}

void EvdevGamepadSource::ReadAbsInfo(TrackedDevice& device) {
  for (int code : {ABS_X, ABS_Y, ABS_RX, ABS_RY, ABS_Z, ABS_RZ}) {
    struct input_absinfo info = {};
    if (ioctl(device.fd, EVIOCGABS(code), &info) >= 0) {
      device.axis_ranges[code] = {info.minimum, info.maximum};
    }
  }
}

// static
gboolean EvdevGamepadSource::OnDeviceReadable(GIOChannel* source,
                                               GIOCondition condition,
                                               gpointer user_data) {
  auto* self = static_cast<EvdevGamepadSource*>(user_data);
  int fd = g_io_channel_unix_get_fd(source);

  std::string syspath;
  for (auto& [path, device] : self->devices_) {
    if (device.fd == fd) {
      syspath = path;
      break;
    }
  }
  if (syspath.empty()) return TRUE;

  self->HandleInputEvents(syspath);
  return TRUE;
}

void EvdevGamepadSource::HandleInputEvents(const std::string& syspath) {
  auto it = devices_.find(syspath);
  if (it == devices_.end()) return;
  TrackedDevice& device = it->second;

  struct input_event events[64];
  ssize_t bytes_read;
  while ((bytes_read = read(device.fd, events, sizeof(events))) > 0) {
    size_t count = bytes_read / sizeof(struct input_event);
    for (size_t i = 0; i < count; i++) {
      const struct input_event& event = events[i];
      if (event.type == EV_KEY) {
        int index = ButtonIndexForCode(event.code);
        if (index >= 0) device.buttons_down[event.code] = (event.value != 0);
      } else if (event.type == EV_ABS) {
        if (event.code == ABS_HAT0X) {
          device.axes["__hatX"] = event.value;
        } else if (event.code == ABS_HAT0Y) {
          device.axes["__hatY"] = event.value;
        } else {
          const char* name = AxisNameForCode(event.code);
          if (name != nullptr) {
            auto range_it = device.axis_ranges.find(event.code);
            double normalized = 0.0;
            if (range_it != device.axis_ranges.end()) {
              const auto [min_value, max_value] = range_it->second;
              if (max_value > min_value) {
                const double fraction =
                    static_cast<double>(event.value - min_value) /
                    (max_value - min_value);
                const bool is_trigger =
                    event.code == ABS_Z || event.code == ABS_RZ;
                normalized = is_trigger ? fraction : (fraction * 2.0 - 1.0);
              }
            }
            device.axes[name] = normalized;
          }
        }
      } else if (event.type == EV_SYN && event.code == SYN_REPORT) {
        EmitSnapshot(device);
      }
    }
  }
}

void EvdevGamepadSource::EmitSnapshot(const TrackedDevice& device) {
  if (!on_event_) return;

  g_autoptr(FlValue) axes = fl_value_new_map();
  for (const auto& [name, value] : device.axes) {
    if (name == "__hatX" || name == "__hatY") continue;
    fl_value_set_take(axes, fl_value_new_string(name.c_str()),
                       fl_value_new_float(value));
  }

  g_autoptr(FlValue) buttons = fl_value_new_list();
  for (const auto& [code, held] : device.buttons_down) {
    if (!held) continue;
    int index = ButtonIndexForCode(code);
    if (index >= 0) fl_value_append_take(buttons, fl_value_new_int(index));
  }
  const double hat_x = device.axes.count("__hatX") ? device.axes.at("__hatX") : 0.0;
  const double hat_y = device.axes.count("__hatY") ? device.axes.at("__hatY") : 0.0;
  const bool dpad_up = hat_y < 0;
  const bool dpad_down = hat_y > 0;
  const bool dpad_left = hat_x < 0;
  const bool dpad_right = hat_x > 0;

  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_take(event, fl_value_new_string("event"), fl_value_new_string("state"));
  fl_value_set_take(event, fl_value_new_string("id"), fl_value_new_string(device.id.c_str()));
  fl_value_set_take(event, fl_value_new_string("axes"), fl_value_ref(axes));
  fl_value_set_take(event, fl_value_new_string("buttons"), fl_value_ref(buttons));
  fl_value_set_take(event, fl_value_new_string("dpadUp"), fl_value_new_bool(dpad_up));
  fl_value_set_take(event, fl_value_new_string("dpadDown"), fl_value_new_bool(dpad_down));
  fl_value_set_take(event, fl_value_new_string("dpadLeft"), fl_value_new_bool(dpad_left));
  fl_value_set_take(event, fl_value_new_string("dpadRight"), fl_value_new_bool(dpad_right));
  on_event_(event);
}

void EvdevGamepadSource::EmitConnected(const std::string& id, const std::string& name,
                                        int vendor_id, int product_id) {
  if (!on_event_) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_take(event, fl_value_new_string("event"), fl_value_new_string("connected"));
  fl_value_set_take(event, fl_value_new_string("id"), fl_value_new_string(id.c_str()));
  fl_value_set_take(event, fl_value_new_string("name"), fl_value_new_string(name.c_str()));
  fl_value_set_take(event, fl_value_new_string("vendorId"), fl_value_new_int(vendor_id));
  fl_value_set_take(event, fl_value_new_string("productId"), fl_value_new_int(product_id));
  on_event_(event);
}

void EvdevGamepadSource::EmitDisconnected(const std::string& id) {
  if (!on_event_) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_take(event, fl_value_new_string("event"), fl_value_new_string("disconnected"));
  fl_value_set_take(event, fl_value_new_string("id"), fl_value_new_string(id.c_str()));
  fl_value_set_take(event, fl_value_new_string("name"), fl_value_new_string(""));
  on_event_(event);
}

}  // namespace just_gamepads

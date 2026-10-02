#include "evdev_gamepad_source.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/inotify.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cstring>

namespace just_gamepads {

namespace {

constexpr char kInputDir[] = "/dev/input/";
constexpr char kEventPrefix[] = "event";
constexpr int kSonyVendorId = 0x054C;
constexpr int kNintendoVendorId = 0x057E;

constexpr size_t BitsToBytes(size_t bits) { return (bits + 7) / 8; }

bool TestBit(const unsigned char* bits, int bit) {
  return (bits[bit / 8] >> (bit % 8)) & 1;
}

bool IsEventNodeName(const char* name) {
  // sizeof - 1: compare the prefix only, not its terminating NUL.
  return std::strncmp(name, kEventPrefix, sizeof(kEventPrefix) - 1) == 0;
}

// Standard-layout index for a key code, or -1.
//
// evdev names its face buttons both by position (BTN_SOUTH/EAST/NORTH/WEST)
// and by Xbox letter (BTN_A/B/X/Y), but BTN_X is the same code as BTN_NORTH
// and BTN_Y the same as BTN_WEST. Drivers disagree on which meaning they
// use: xpad and Xbox-over-Bluetooth report the Xbox X button (left) as
// BTN_X, while the PlayStation and Nintendo drivers report positions. This
// is the same rule as SDL's Linux backend.
int ButtonIndexFor(int code, bool positional_face_buttons) {
  switch (code) {
    case BTN_SOUTH: return 0;
    case BTN_EAST: return 1;
    case BTN_NORTH: return positional_face_buttons ? 3 : 2;  // == BTN_X
    case BTN_WEST: return positional_face_buttons ? 2 : 3;   // == BTN_Y
    case BTN_TL: return 4;
    case BTN_TR: return 5;
    case BTN_TL2: return 6;
    case BTN_TR2: return 7;
    case BTN_SELECT: return 8;
    case BTN_START: return 9;
    case BTN_THUMBL: return 10;
    case BTN_THUMBR: return 11;
    case BTN_DPAD_UP: return 12;
    case BTN_DPAD_DOWN: return 13;
    case BTN_DPAD_LEFT: return 14;
    case BTN_DPAD_RIGHT: return 15;
    default: return -1;
  }
}

// Maps a raw value into -1..1 (sticks) or 0..1 (triggers) using the
// device's reported range; evdev reports integers in device units.
double Normalize(int32_t value, int32_t min, int32_t max, bool signed_axis) {
  if (max <= min) return 0.0;
  double fraction = static_cast<double>(value - min) / (max - min);
  if (fraction < 0.0) fraction = 0.0;
  if (fraction > 1.0) fraction = 1.0;
  return signed_axis ? fraction * 2.0 - 1.0 : fraction;
}

}  // namespace

EvdevGamepadSource::EvdevGamepadSource() {}

EvdevGamepadSource::~EvdevGamepadSource() { Stop(); }

void EvdevGamepadSource::Start(EventCallback on_event) {
  Stop();
  on_event_ = std::move(on_event);

  // Watch before scanning so a device plugged in between is not missed;
  // TryAddDevice ignores devices it already tracks.
  inotify_fd_ = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (inotify_fd_ >= 0) {
    if (inotify_add_watch(inotify_fd_, kInputDir,
                          IN_CREATE | IN_ATTRIB | IN_DELETE | IN_MOVED_TO |
                              IN_MOVED_FROM) < 0) {
      close(inotify_fd_);
      inotify_fd_ = -1;
    } else {
      GIOChannel* channel = g_io_channel_unix_new(inotify_fd_);
      inotify_watch_id_ =
          g_io_add_watch(channel, G_IO_IN, &EvdevGamepadSource::OnInotifyReadable,
                         this);
      g_io_channel_unref(channel);  // the watch holds its own reference
    }
  }

  ScanExistingDevices();
}

void EvdevGamepadSource::Stop() {
  if (inotify_watch_id_ != 0) {
    g_source_remove(inotify_watch_id_);
    inotify_watch_id_ = 0;
  }
  if (inotify_fd_ >= 0) {
    close(inotify_fd_);
    inotify_fd_ = -1;
  }
  for (auto& entry : devices_) {
    if (entry.second.watch_id != 0) g_source_remove(entry.second.watch_id);
    if (entry.second.fd >= 0) close(entry.second.fd);
  }
  devices_.clear();
  on_event_ = nullptr;
}

void EvdevGamepadSource::ScanExistingDevices() {
  DIR* dir = opendir(kInputDir);
  if (!dir) return;
  while (struct dirent* entry = readdir(dir)) {
    if (IsEventNodeName(entry->d_name)) {
      TryAddDevice(std::string(kInputDir) + entry->d_name);
    }
  }
  closedir(dir);
}

// static
gboolean EvdevGamepadSource::OnInotifyReadable(GIOChannel* source,
                                               GIOCondition condition,
                                               gpointer user_data) {
  auto* self = static_cast<EvdevGamepadSource*>(user_data);
  alignas(struct inotify_event) char buffer[4096];
  ssize_t length;
  while ((length = read(self->inotify_fd_, buffer, sizeof(buffer))) > 0) {
    for (char* p = buffer; p < buffer + length;) {
      const auto* event = reinterpret_cast<const struct inotify_event*>(p);
      p += sizeof(struct inotify_event) + event->len;
      if (event->mask & IN_Q_OVERFLOW) {
        self->ScanExistingDevices();
        continue;
      }
      if (event->len == 0 || !IsEventNodeName(event->name)) continue;
      const std::string path = std::string(kInputDir) + event->name;
      if (event->mask & (IN_DELETE | IN_MOVED_FROM)) {
        self->RemoveDevice(path);
      } else {
        // IN_CREATE fires before udev has set the node's permissions, so
        // opening can fail then; the following IN_ATTRIB retries.
        self->TryAddDevice(path);
      }
    }
  }
  return G_SOURCE_CONTINUE;
}

void EvdevGamepadSource::TryAddDevice(const std::string& path) {
  if (devices_.count(path) > 0) return;

  const int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) return;

  unsigned char key_bits[BitsToBytes(KEY_MAX + 1)] = {};
  unsigned char abs_bits[BitsToBytes(ABS_MAX + 1)] = {};
  unsigned char prop_bits[BitsToBytes(INPUT_PROP_MAX + 1)] = {};
  if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key_bits)), key_bits) < 0 ||
      ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs_bits)), abs_bits) < 0) {
    close(fd);
    return;
  }
  ioctl(fd, EVIOCGPROP(sizeof(prop_bits)), prop_bits);

  bool has_joystick_buttons = false;
  for (int code = BTN_JOYSTICK; code < BTN_GAMEPAD; code++) {
    if (TestBit(key_bits, code)) has_joystick_buttons = true;
  }
  const bool has_gamepad_buttons = TestBit(key_bits, BTN_GAMEPAD);
  // Motion-sensor nodes (DualSense, Joy-Con) share the controller's name
  // and have axes but are not controllers.
  const bool is_sensor = TestBit(prop_bits, INPUT_PROP_ACCELEROMETER);
  if (is_sensor || !TestBit(abs_bits, ABS_X) ||
      (!has_gamepad_buttons && !has_joystick_buttons)) {
    close(fd);
    return;
  }

  TrackedDevice device;
  device.id = path;
  device.fd = fd;

  for (int code = 0; code <= ABS_MAX; code++) {
    if (!TestBit(abs_bits, code)) continue;
    struct input_absinfo info = {};
    if (ioctl(fd, EVIOCGABS(code), &info) < 0) continue;
    device.ranges[code] = {info.minimum, info.maximum};
    device.abs_values[code] = info.value;
  }
  auto has_abs = [&](int code) { return device.ranges.count(code) > 0; };

  struct input_id id_info = {};
  int vendor_id = 0, product_id = 0;
  if (ioctl(fd, EVIOCGID, &id_info) >= 0) {
    vendor_id = id_info.vendor;
    product_id = id_info.product;
  }

  Layout& layout = device.layout;
  layout.generic = !has_gamepad_buttons;
  if (layout.generic) {
    // Positional, in code order: the shape the shared Dart mapper expects.
    // Hats are reported as the d-pad instead.
    for (int code = 0; code < ABS_HAT0X; code++) {
      if (has_abs(code)) layout.raw_axes.push_back(code);
    }
    for (int code = BTN_JOYSTICK; code < BTN_GAMEPAD; code++) {
      if (TestBit(key_bits, code)) layout.raw_buttons.push_back(code);
    }
  } else {
    // Sticks and triggers sit on different codes per driver; same guesses
    // as SDL. xpad and the PlayStation drivers use RX/RY for the right
    // stick and Z/RZ for the triggers; Xbox controllers over Bluetooth use
    // Z/RZ for the right stick and BRAKE/GAS for the triggers.
    layout.left_x = ABS_X;
    layout.left_y = has_abs(ABS_Y) ? ABS_Y : -1;
    const bool right_on_rx = has_abs(ABS_RX) && has_abs(ABS_RY);
    if (right_on_rx) {
      layout.right_x = ABS_RX;
      layout.right_y = ABS_RY;
    } else if (has_abs(ABS_Z) && has_abs(ABS_RZ)) {
      layout.right_x = ABS_Z;
      layout.right_y = ABS_RZ;
    }
    if (right_on_rx && has_abs(ABS_Z)) {
      layout.left_trigger = ABS_Z;
    } else if (has_abs(ABS_BRAKE)) {
      layout.left_trigger = ABS_BRAKE;
    }
    if (right_on_rx && has_abs(ABS_RZ)) {
      layout.right_trigger = ABS_RZ;
    } else if (has_abs(ABS_GAS)) {
      layout.right_trigger = ABS_GAS;
    }
    layout.positional_face_buttons =
        vendor_id == kSonyVendorId || vendor_id == kNintendoVendorId;
  }

  char name_buffer[256] = {};
  std::string name;
  if (ioctl(fd, EVIOCGNAME(sizeof(name_buffer) - 1), name_buffer) >= 0) {
    name = name_buffer;
  }

  Resync(device);

  GIOChannel* channel = g_io_channel_unix_new(fd);
  device.watch_id = g_io_add_watch(
      channel,
      static_cast<GIOCondition>(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
      &EvdevGamepadSource::OnDeviceReadable, this);
  g_io_channel_unref(channel);  // the watch holds its own reference

  auto& stored = devices_[path] = std::move(device);
  EmitConnected(stored, name, vendor_id, product_id);
  EmitSnapshot(stored);
}

void EvdevGamepadSource::RemoveDevice(const std::string& path) {
  auto it = devices_.find(path);
  if (it == devices_.end()) return;
  if (it->second.watch_id != 0) g_source_remove(it->second.watch_id);
  if (it->second.fd >= 0) close(it->second.fd);
  devices_.erase(it);
  EmitDisconnected(path);
}

// static
gboolean EvdevGamepadSource::OnDeviceReadable(GIOChannel* source,
                                              GIOCondition condition,
                                              gpointer user_data) {
  auto* self = static_cast<EvdevGamepadSource*>(user_data);
  const int fd = g_io_channel_unix_get_fd(source);

  TrackedDevice* device = nullptr;
  for (auto& entry : self->devices_) {
    if (entry.second.fd == fd) {
      device = &entry.second;
      break;
    }
  }
  if (!device) return G_SOURCE_REMOVE;

  bool alive = (condition & (G_IO_HUP | G_IO_ERR | G_IO_NVAL)) == 0;
  if (alive) alive = self->ReadEvents(*device);
  if (alive) return G_SOURCE_CONTINUE;

  // Unplugged. Returning G_SOURCE_REMOVE destroys this watch, so
  // RemoveDevice must not remove it a second time. The id is copied because
  // RemoveDevice erases the entry it lives in.
  device->watch_id = 0;
  const std::string id = device->id;
  self->RemoveDevice(id);
  return G_SOURCE_REMOVE;
}

bool EvdevGamepadSource::ReadEvents(TrackedDevice& device) {
  struct input_event events[64];
  while (true) {
    const ssize_t bytes = read(device.fd, events, sizeof(events));
    if (bytes < 0) {
      if (errno == EINTR) continue;
      return errno == EAGAIN;  // drained; anything else means it's gone
    }
    if (bytes == 0) return false;

    const size_t count = static_cast<size_t>(bytes) / sizeof(events[0]);
    for (size_t i = 0; i < count; i++) {
      const struct input_event& event = events[i];
      if (event.type == EV_SYN) {
        if (event.code == SYN_DROPPED) {
          // The kernel's buffer overflowed: events were lost, so state is
          // re-read from the kernel at the next report.
          device.dropping = true;
        } else if (event.code == SYN_REPORT) {
          if (device.dropping) {
            device.dropping = false;
            Resync(device);
          }
          EmitSnapshot(device);
        }
      } else if (device.dropping) {
        continue;
      } else if (event.type == EV_KEY) {
        if (event.value != 0) {
          device.keys_down.insert(event.code);
        } else {
          device.keys_down.erase(event.code);
        }
      } else if (event.type == EV_ABS) {
        device.abs_values[event.code] = event.value;
      }
    }
  }
}

void EvdevGamepadSource::Resync(TrackedDevice& device) {
  unsigned char key_state[BitsToBytes(KEY_MAX + 1)] = {};
  if (ioctl(device.fd, EVIOCGKEY(sizeof(key_state)), key_state) >= 0) {
    device.keys_down.clear();
    for (int code = BTN_JOYSTICK; code <= KEY_MAX; code++) {
      if (TestBit(key_state, code)) device.keys_down.insert(code);
    }
  }
  for (auto& entry : device.abs_values) {
    struct input_absinfo info = {};
    if (ioctl(device.fd, EVIOCGABS(entry.first), &info) >= 0) {
      entry.second = info.value;
    }
  }
}

void EvdevGamepadSource::EmitSnapshot(const TrackedDevice& device) {
  if (!on_event_) return;
  const Layout& layout = device.layout;

  auto value_of = [&](int code, bool signed_axis) {
    const auto range = device.ranges.find(code);
    const auto value = device.abs_values.find(code);
    if (range == device.ranges.end() || value == device.abs_values.end()) {
      return 0.0;
    }
    return Normalize(value->second, range->second.min, range->second.max,
                     signed_axis);
  };
  auto hat = [&](int code) {
    const auto value = device.abs_values.find(code);
    return value == device.abs_values.end() ? 0 : value->second;
  };
  const int hat_x = hat(ABS_HAT0X);
  const int hat_y = hat(ABS_HAT0Y);

  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "event", fl_value_new_string("state"));
  fl_value_set_string_take(event, "id", fl_value_new_string(device.id.c_str()));

  if (layout.generic) {
    FlValue* raw_axes = fl_value_new_list();
    for (size_t i = 0; i < layout.raw_axes.size(); i++) {
      // Sticks first (-1..1), anything after them as triggers (0..1),
      // matching the Windows raw path.
      fl_value_append_take(
          raw_axes, fl_value_new_float(value_of(layout.raw_axes[i], i < 4)));
    }
    FlValue* raw_buttons = fl_value_new_list();
    for (int code : layout.raw_buttons) {
      fl_value_append_take(raw_buttons,
                           fl_value_new_bool(device.keys_down.count(code) > 0));
    }
    fl_value_set_string_take(event, "rawAxes", raw_axes);
    fl_value_set_string_take(event, "rawButtons", raw_buttons);
    fl_value_set_string_take(event, "dpadUp", fl_value_new_bool(hat_y < 0));
    fl_value_set_string_take(event, "dpadDown", fl_value_new_bool(hat_y > 0));
    fl_value_set_string_take(event, "dpadLeft", fl_value_new_bool(hat_x < 0));
    fl_value_set_string_take(event, "dpadRight", fl_value_new_bool(hat_x > 0));
  } else {
    FlValue* axes = fl_value_new_map();
    auto put_axis = [&](const char* name, int code, bool signed_axis) {
      if (code < 0) return;
      fl_value_set_string_take(axes, name,
                               fl_value_new_float(value_of(code, signed_axis)));
    };
    // evdev sticks are already down-positive, like the wire protocol.
    put_axis("leftStickX", layout.left_x, true);
    put_axis("leftStickY", layout.left_y, true);
    put_axis("rightStickX", layout.right_x, true);
    put_axis("rightStickY", layout.right_y, true);
    put_axis("leftTrigger", layout.left_trigger, false);
    put_axis("rightTrigger", layout.right_trigger, false);

    bool down[16] = {};
    for (int code : device.keys_down) {
      const int index = ButtonIndexFor(code, layout.positional_face_buttons);
      if (index >= 0) down[index] = true;
    }
    // Most drivers report the d-pad as a hat; some as BTN_DPAD_* keys
    // (mapped above). Either way it ends up as buttons 12-15.
    if (hat_y < 0) down[12] = true;
    if (hat_y > 0) down[13] = true;
    if (hat_x < 0) down[14] = true;
    if (hat_x > 0) down[15] = true;

    FlValue* buttons = fl_value_new_list();
    for (int index = 0; index < 16; index++) {
      if (down[index]) fl_value_append_take(buttons, fl_value_new_int(index));
    }
    fl_value_set_string_take(event, "axes", axes);
    fl_value_set_string_take(event, "buttons", buttons);
  }

  on_event_(event);
}

void EvdevGamepadSource::EmitConnected(const TrackedDevice& device,
                                       const std::string& name, int vendor_id,
                                       int product_id) {
  if (!on_event_) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "event", fl_value_new_string("connected"));
  fl_value_set_string_take(event, "id", fl_value_new_string(device.id.c_str()));
  fl_value_set_string_take(event, "name", fl_value_new_string(name.c_str()));
  if (vendor_id != 0) {
    fl_value_set_string_take(event, "vendorId", fl_value_new_int(vendor_id));
    fl_value_set_string_take(event, "productId", fl_value_new_int(product_id));
  }
  on_event_(event);
}

void EvdevGamepadSource::EmitDisconnected(const std::string& id) {
  if (!on_event_) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "event", fl_value_new_string("disconnected"));
  fl_value_set_string_take(event, "id", fl_value_new_string(id.c_str()));
  on_event_(event);
}

}  // namespace just_gamepads

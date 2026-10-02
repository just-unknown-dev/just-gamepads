#ifndef FLUTTER_PLUGIN_JUST_GAMEPADS_RAW_LAYOUT_H_
#define FLUTTER_PLUGIN_JUST_GAMEPADS_RAW_LAYOUT_H_

// Pure helpers for the RawGameController path, kept free of WinRT and
// Flutter so they can be unit tested on their own (see test/).

#include <cstdint>
#include <vector>

namespace just_gamepads {

constexpr uint16_t kSonyVendorId = 0x054C;

// Reorders one raw reading into the positional order the shared Dart
// mapper (generic_hid_mapper.dart) assumes:
//   axes:    left X, left Y, right X, right Y, left trigger, right trigger
//   buttons: bottom, right, left, top face; LB, RB, LT, RT; back, start;
//            left stick, right stick
//
// Only devices whose raw layout is known to differ are touched, keyed by
// vendor id; everything else passes through unchanged.
//
// Sony (DualShock 4, DualSense): RawGameController lists axes in HID usage
// order X, Y, Z, Rx, Ry, Rz, which for these pads is
// [LX, LY, RX, L2, R2, RY], and buttons as Square, Cross, Circle, Triangle,
// L1, R1, L2, R2, Share/Create, Options, L3, R3, PS, Touchpad. This matches
// SDL's mapping for these controllers on Windows.
inline void ApplyVendorLayout(uint16_t vendor_id, std::vector<double>* axes,
                              std::vector<bool>* buttons) {
  if (vendor_id != kSonyVendorId) return;
  if (axes->size() >= 6) {
    const std::vector<double> a = *axes;
    (*axes)[3] = a[5];  // right stick Y
    (*axes)[4] = a[3];  // L2
    (*axes)[5] = a[4];  // R2
  }
  if (buttons->size() >= 4) {
    const bool square = (*buttons)[0];
    const bool cross = (*buttons)[1];
    const bool circle = (*buttons)[2];
    (*buttons)[0] = cross;   // bottom
    (*buttons)[1] = circle;  // right
    (*buttons)[2] = square;  // left
    // [3] Triangle is already the top face button.
  }
}

// RawGameController reports every axis in 0.0..1.0. The wire protocol wants
// sticks (the first four axes) in -1.0..1.0 with Y down-positive, which HID
// joysticks already use, and triggers left in 0.0..1.0.
inline std::vector<double> ToWireAxes(const std::vector<double>& unit_axes) {
  std::vector<double> result(unit_axes);
  for (size_t i = 0; i < result.size() && i < 4; i++) {
    result[i] = result[i] * 2.0 - 1.0;
  }
  return result;
}

}  // namespace just_gamepads

#endif  // FLUTTER_PLUGIN_JUST_GAMEPADS_RAW_LAYOUT_H_

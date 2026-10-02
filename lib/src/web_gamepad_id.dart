/// What a browser's `Gamepad.id` string says about the device.
typedef WebGamepadId = ({String name, int? vendorId, int? productId});

// Chromium: "DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c
// Product: 0ce6)", "Xbox 360 Controller (XInput STANDARD GAMEPAD)".
final _chromiumIds = RegExp(
  r'vendor:\s*([0-9a-f]{1,4})\s+product:\s*([0-9a-f]{1,4})',
  caseSensitive: false,
);
final _chromiumSuffix = RegExp(
  r'\s*\([^()]*(?:gamepad|vendor:)[^()]*\)\s*$',
  caseSensitive: false,
);

// Firefox: "054c-0ce6-DualSense Wireless Controller".
final _firefoxPrefix = RegExp(
  r'^([0-9a-f]{1,4})-([0-9a-f]{1,4})-',
  caseSensitive: false,
);

/// Splits a browser's `Gamepad.id` into a display name and the USB
/// vendor/product ids embedded in it.
///
/// Safari, and Chromium for XInput devices, embed no ids; both are `null`
/// then. The name falls back to the whole string when nothing is left after
/// stripping.
WebGamepadId parseWebGamepadId(String id) {
  int hex(String digits) => int.parse(digits, radix: 16);

  final firefox = _firefoxPrefix.firstMatch(id);
  if (firefox != null) {
    final name = id.substring(firefox.end).trim();
    return (
      name: name.isEmpty ? id : name,
      vendorId: hex(firefox.group(1)!),
      productId: hex(firefox.group(2)!),
    );
  }

  final ids = _chromiumIds.firstMatch(id);
  final name = id.replaceFirst(_chromiumSuffix, '').trim();
  return (
    name: name.isEmpty ? id : name,
    vendorId: ids == null ? null : hex(ids.group(1)!),
    productId: ids == null ? null : hex(ids.group(2)!),
  );
}

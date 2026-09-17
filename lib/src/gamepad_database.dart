import 'models/gamepad_type.dart';

class _VidPidEntry {
  const _VidPidEntry(this.vendorId, this.productId, this.type);

  final int vendorId;

  /// `null` matches any product from [vendorId].
  final int? productId;
  final GamepadType type;
}

/// Classifies a controller into a [GamepadType] for UI presentation only —
/// input resolution never depends on this, it always goes through the
/// standard axis/button layout (`GamepadAxis`/`GamepadButton`) regardless of
/// brand.
///
/// This is the single shared classifier every native backend defers to
/// instead of re-implementing a device table per platform (C++/Kotlin/Swift/
/// C): a backend's only job is to enumerate devices and, for anything the
/// OS/browser didn't already normalize to a standard gamepad, pass up raw
/// `vendorId`/`productId`/`name` for this to classify.
///
/// Deliberately a small, curated list (not attempting SDL_GameControllerDB's
/// exhaustive scope) — covers the controller families this project was
/// asked to support (Xbox, PlayStation, generic) plus Switch Pro and a couple
/// of common third-party entries, with a documented, permissive fallback for
/// everything else.
abstract final class GamepadDatabase {
  // USB-IF vendor ids.
  static const _microsoftVendorId = 0x045E;
  static const _sonyVendorId = 0x054C;
  static const _nintendoVendorId = 0x057E;
  static const _eightBitDoVendorId = 0x2DC8;

  static const List<_VidPidEntry> _entries = [
    _VidPidEntry(_microsoftVendorId, null, GamepadType.xbox),
    // Covers DualShock 4 (0x05C4, 0x09CC), DualSense (0x0CE6), and DualSense
    // Edge (0x0DF2) alike — all classified identically, no need to
    // distinguish individual PlayStation pad generations for UI purposes.
    _VidPidEntry(_sonyVendorId, null, GamepadType.playStation),
    _VidPidEntry(_nintendoVendorId, 0x2009, GamepadType.nintendoSwitchPro),
    // 8BitDo controllers' reported layout varies by device/mode switch; safest
    // default is generic rather than guessing a specific brand's glyphs.
    _VidPidEntry(_eightBitDoVendorId, null, GamepadType.generic),
  ];

  /// Classifies a controller from whatever identifying information a backend
  /// was able to obtain. At least one of [vendorId] or [nameHint] should
  /// normally be provided for a connected device; passing neither (e.g. "no
  /// controller connected") returns [GamepadType.unknown].
  static GamepadType classify({int? vendorId, int? productId, String? nameHint}) {
    if (vendorId != null) {
      for (final entry in _entries) {
        if (entry.vendorId == vendorId &&
            (entry.productId == null || entry.productId == productId)) {
          return entry.type;
        }
      }
    }
    final byName = _classifyByName(nameHint);
    if (byName != null) return byName;
    if (vendorId == null && nameHint == null) return GamepadType.unknown;
    return GamepadType.generic;
  }

  /// Name-substring fallback for platforms with no numeric vendor/product id
  /// (Darwin's `vendorName`/`productCategory` on older OS versions, Web's
  /// `gamepad.id` string) — also used as a secondary check even when a vendor
  /// id was matched to nothing above, since some backends only have a name.
  static GamepadType? _classifyByName(String? nameHint) {
    if (nameHint == null || nameHint.isEmpty) return null;
    final lower = nameHint.toLowerCase();
    if (lower.contains('xbox') ||
        lower.contains('xinput') ||
        lower.contains('045e')) {
      return GamepadType.xbox;
    }
    if (lower.contains('dualsense') ||
        lower.contains('dualshock') ||
        lower.contains('playstation') ||
        lower.contains('sony') ||
        lower.contains('054c')) {
      return GamepadType.playStation;
    }
    if (lower.contains('switch pro') ||
        lower.contains('nintendo') ||
        lower.contains('057e')) {
      return GamepadType.nintendoSwitchPro;
    }
    return null;
  }
}

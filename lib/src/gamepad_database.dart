import 'models/gamepad_type.dart';

class _VidPidEntry {
  const _VidPidEntry(this.vendorId, this.productId, this.type);

  final int vendorId;

  /// `null` matches any product from [vendorId].
  final int? productId;
  final GamepadType type;
}

/// Classifies a controller into a [GamepadType], for presentation only.
///
/// Every backend sends up whatever identifying information its platform has
/// (USB vendor/product id, device name) and this one shared table decides
/// the family, so the device list isn't duplicated per platform.
///
/// The list is deliberately small: Xbox, PlayStation and Nintendo by vendor
/// id, then a name-based fallback. Anything else is [GamepadType.generic].
abstract final class GamepadDatabase {
  // USB-IF vendor ids.
  static const _microsoftVendorId = 0x045E;
  static const _sonyVendorId = 0x054C;
  static const _nintendoVendorId = 0x057E;
  static const _eightBitDoVendorId = 0x2DC8;

  static const List<_VidPidEntry> _entries = [
    _VidPidEntry(_microsoftVendorId, null, GamepadType.xbox),
    // DualShock 4 (0x05C4, 0x09CC), DualSense (0x0CE6) and DualSense Edge
    // (0x0DF2) all share one family.
    _VidPidEntry(_sonyVendorId, null, GamepadType.playStation),
    _VidPidEntry(_nintendoVendorId, 0x2009, GamepadType.nintendoSwitchPro),
    // 8BitDo layouts change with the controller's mode switch, so their
    // glyphs can't be guessed from the vendor id alone.
    _VidPidEntry(_eightBitDoVendorId, null, GamepadType.generic),
  ];

  /// Classifies a controller from whatever a backend could identify.
  ///
  /// Matches [vendorId]/[productId] first, then falls back to well-known
  /// words in [nameHint]. Returns [GamepadType.generic] for an unrecognized
  /// controller and [GamepadType.unknown] when both [vendorId] and
  /// [nameHint] are `null`.
  static GamepadType classify({
    int? vendorId,
    int? productId,
    String? nameHint,
  }) {
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

  /// Name fallback for platforms without numeric ids (Apple's
  /// GameController framework, some browsers), and for ids missing from the
  /// table above.
  static GamepadType? _classifyByName(String? nameHint) {
    if (nameHint == null || nameHint.isEmpty) return null;
    final lower = nameHint.toLowerCase();
    if (lower.contains('xbox') || lower.contains('xinput')) {
      return GamepadType.xbox;
    }
    if (lower.contains('dualsense') ||
        lower.contains('dualshock') ||
        lower.contains('playstation') ||
        lower.contains('sony')) {
      return GamepadType.playStation;
    }
    if (lower.contains('switch pro') || lower.contains('nintendo')) {
      return GamepadType.nintendoSwitchPro;
    }
    return null;
  }
}

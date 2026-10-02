import 'package:flutter/foundation.dart';

import 'gamepad_type.dart';

/// Identity of one connected controller, stable for the lifetime of that
/// connection. A controller that disconnects and reconnects may get a new
/// [id].
@immutable
class GamepadInfo {
  /// Creates the identity of one connected controller.
  const GamepadInfo({
    required this.id,
    required this.name,
    required this.type,
    this.vendorId,
    this.productId,
  });

  /// A backend-assigned identifier, unique among connected controllers.
  ///
  /// Not a hardware serial: most platforms expose no stable hardware id.
  final String id;

  /// The device name reported by the OS or browser, for display only.
  ///
  /// Use [type] rather than this name to pick button glyphs.
  final String name;

  /// The controller family, for button glyphs and prompts.
  final GamepadType type;

  /// The USB vendor id, when the platform reports one.
  final int? vendorId;

  /// The USB product id, when the platform reports one.
  final int? productId;

  @override
  bool operator ==(Object other) =>
      other is GamepadInfo &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.vendorId == vendorId &&
      other.productId == productId;

  @override
  int get hashCode => Object.hash(id, name, type, vendorId, productId);

  @override
  String toString() {
    String hex(int? v) =>
        v == null ? 'null' : '0x${v.toRadixString(16).padLeft(4, '0')}';
    return 'GamepadInfo(id: $id, name: $name, type: ${type.name}, '
        'vendorId: ${hex(vendorId)}, productId: ${hex(productId)})';
  }
}

import 'gamepad_type.dart';

/// Identity of one connected controller — stable for the lifetime of that
/// connection (a reconnect gets a new [id]).
class GamepadInfo {
  const GamepadInfo({
    required this.id,
    required this.name,
    required this.type,
    this.vendorId,
    this.productId,
  });

  /// A backend-assigned, per-connection-stable identifier (not necessarily a
  /// hardware serial — some platforms have no stable hardware id at all).
  final String id;

  /// Raw vendor/OS-supplied device name — secondary/tooltip use, not for
  /// brand classification (that's already baked into [type]).
  final String name;

  final GamepadType type;

  final int? vendorId;
  final int? productId;
}

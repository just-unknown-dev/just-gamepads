import 'package:flutter/foundation.dart';

import 'gamepad_info.dart';
import 'gamepad_state.dart';

/// Fired whenever a controller connects or disconnects.
@immutable
class GamepadConnectionEvent {
  /// Creates a connection event.
  const GamepadConnectionEvent({required this.info, required this.connected});

  /// The controller that connected or disconnected.
  final GamepadInfo info;

  /// `true` for a connect, `false` for a disconnect.
  final bool connected;

  @override
  bool operator ==(Object other) =>
      other is GamepadConnectionEvent &&
      other.info == info &&
      other.connected == connected;

  @override
  int get hashCode => Object.hash(info, connected);

  @override
  String toString() =>
      'GamepadConnectionEvent(${connected ? 'connected' : 'disconnected'}: '
      '$info)';
}

/// Fired whenever a connected controller's state changes.
@immutable
class GamepadStateEvent {
  /// Creates a state event.
  const GamepadStateEvent({required this.gamepadId, required this.state});

  /// The [GamepadInfo.id] of the controller.
  final String gamepadId;

  /// The controller's full current state.
  final GamepadState state;

  @override
  bool operator ==(Object other) =>
      other is GamepadStateEvent &&
      other.gamepadId == gamepadId &&
      other.state == state;

  @override
  int get hashCode => Object.hash(gamepadId, state);

  @override
  String toString() => 'GamepadStateEvent($gamepadId, $state)';
}

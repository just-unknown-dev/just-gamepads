import 'gamepad_info.dart';
import 'gamepad_state.dart';

/// Fired whenever a controller connects or disconnects.
class GamepadConnectionEvent {
  const GamepadConnectionEvent({required this.info, required this.connected});

  final GamepadInfo info;
  final bool connected;
}

/// Fired whenever a connected controller's full state changes.
class GamepadStateEvent {
  const GamepadStateEvent({required this.gamepadId, required this.state});

  final String gamepadId;
  final GamepadState state;
}

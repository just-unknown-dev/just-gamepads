import 'gamepad_layout.dart';

/// One full snapshot of a single controller's axes/buttons — backends push
/// one of these per device per tick (not per-axis/per-button deltas), so
/// consumers always see internally-consistent state.
class GamepadState {
  GamepadState({Map<String, double>? axes, Set<int>? buttonsDown})
    : axes = Map.unmodifiable(axes ?? const {}),
      buttonsDown = Set.unmodifiable(buttonsDown ?? const {});

  /// Keyed by [GamepadAxis] string constants. An axis absent from this map
  /// (rather than present at `0.0`) means the backend never reports it for
  /// this device at all (e.g. a controller with no analog triggers) — most
  /// callers should just treat both the same way via `?? 0.0`.
  final Map<String, double> axes;

  /// [GamepadButton] int constants currently held down.
  final Set<int> buttonsDown;

  static final empty = GamepadState();
}

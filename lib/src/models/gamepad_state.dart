import 'package:flutter/foundation.dart';

import 'gamepad_layout.dart';

/// One full snapshot of a single controller's axes and buttons.
///
/// Backends push one of these per device per change (never per-axis or
/// per-button deltas), so consumers always see internally consistent state.
@immutable
class GamepadState {
  /// Creates a snapshot. Both collections are copied into unmodifiable ones.
  GamepadState({Map<String, double>? axes, Set<int>? buttonsDown})
    : axes = Map.unmodifiable(axes ?? const {}),
      buttonsDown = Set.unmodifiable(buttonsDown ?? const {});

  /// Axis values keyed by [GamepadAxis] constants.
  ///
  /// Sticks range from -1.0 to 1.0 with positive X to the right and positive
  /// Y *down*. Triggers range from 0.0 (released) to 1.0 (fully pressed).
  ///
  /// An axis missing from this map means the backend never reports it for
  /// this device (for example a controller without analog triggers). Most
  /// callers can treat a missing axis as `0.0`.
  final Map<String, double> axes;

  /// The [GamepadButton] constants currently held down.
  final Set<int> buttonsDown;

  /// A snapshot with no axes and no buttons held.
  static final empty = GamepadState();

  @override
  bool operator ==(Object other) =>
      other is GamepadState &&
      setEquals(other.buttonsDown, buttonsDown) &&
      mapEquals(other.axes, axes);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(buttonsDown),
    Object.hashAllUnordered(
      axes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'GamepadState(axes: $axes, buttonsDown: $buttonsDown)';
}

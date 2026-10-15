import 'models/gamepad_layout.dart';
import 'models/gamepad_state.dart';

/// Positional mapping for a controller the platform couldn't map to the
/// standard layout itself.
///
/// Every backend's raw fallback path goes through this one function, so the
/// guess is made in exactly one place. It assumes the most common HID
/// gamepad report shape, the same assumption SDL and browsers make for
/// unknown devices:
///
///  * axes: left stick X, left stick Y, right stick X, right stick Y, then
///    (if present) left and right trigger. Sticks are expected in -1.0..1.0
///    and triggers in 0.0..1.0.
///  * buttons: the four face buttons (bottom, right, left, top), bumpers,
///    triggers, back, start, then the two stick clicks.
///
/// Extra axes and buttons are ignored. The d-pad is passed separately because
/// raw devices report it as a hat switch rather than buttons.
///
/// Raw axes are best passed through a [RawAxisRest] first: an unknown device
/// can report its axes pinned at one end until it is used.
GamepadState mapGenericHid({
  required List<double> rawAxes,
  required List<bool> rawButtons,
  bool dpadUp = false,
  bool dpadDown = false,
  bool dpadLeft = false,
  bool dpadRight = false,
}) {
  double axisAt(int index) => index < rawAxes.length ? rawAxes[index] : 0.0;

  final axes = <String, double>{
    GamepadAxis.leftStickX: axisAt(0),
    GamepadAxis.leftStickY: axisAt(1),
    GamepadAxis.rightStickX: axisAt(2),
    GamepadAxis.rightStickY: axisAt(3),
    if (rawAxes.length > 4) GamepadAxis.leftTrigger: axisAt(4),
    if (rawAxes.length > 5) GamepadAxis.rightTrigger: axisAt(5),
  };

  const positionalButtonOrder = [
    GamepadButton.a,
    GamepadButton.b,
    GamepadButton.x,
    GamepadButton.y,
    GamepadButton.leftBumper,
    GamepadButton.rightBumper,
    GamepadButton.leftTriggerButton,
    GamepadButton.rightTriggerButton,
    GamepadButton.back,
    GamepadButton.start,
    GamepadButton.leftStick,
    GamepadButton.rightStick,
  ];

  final buttons = <int>{
    for (
      var i = 0;
      i < rawButtons.length && i < positionalButtonOrder.length;
      i++
    )
      if (rawButtons[i]) positionalButtonOrder[i],
    if (dpadUp) GamepadButton.dpadUp,
    if (dpadDown) GamepadButton.dpadDown,
    if (dpadLeft) GamepadButton.dpadLeft,
    if (dpadRight) GamepadButton.dpadRight,
  };

  return GamepadState(axes: axes, buttonsDown: buttons);
}

/// Holds a raw device's axes at rest until they are used — SDL's rule for
/// joysticks it does not know.
///
/// An unknown device can report every axis pinned at one end before it is
/// touched: a wireless receiver whose pad is off or asleep reads 0 on
/// Windows' 0..1 scale, which is -1 on a stick, so the stick would read as
/// pushed fully over and a game would walk its player off on its own. So
/// each axis reads 0 until it first moves away from the value it was first
/// read at; from then on it reads as reported. One per connected device.
final class RawAxisRest {
  /// How far an axis must move from its first value to count as used.
  static const double moved = 0.05;

  List<double>? _first;
  final List<bool> _live = [];

  /// [axes] with every axis not yet used read as 0.
  List<double> apply(List<double> axes) {
    final first = _first ??= List.of(axes);
    while (_live.length < axes.length) {
      _live.add(false);
    }
    final out = List<double>.filled(axes.length, 0);
    for (var i = 0; i < axes.length; i++) {
      final resting =
          !_live[i] && i < first.length && (axes[i] - first[i]).abs() <= moved;
      if (resting) continue;
      _live[i] = true;
      out[i] = axes[i];
    }
    return out;
  }
}

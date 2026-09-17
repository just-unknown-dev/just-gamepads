import 'models/gamepad_layout.dart';
import 'models/gamepad_state.dart';

/// Positional remap heuristic for a raw HID device the OS/browser didn't
/// already normalize to a standard gamepad (i.e. whatever `GamepadDatabase`
/// couldn't help with either) — every native backend's raw-HID fallback path
/// funnels through this one shared implementation rather than each platform
/// guessing its own positional layout.
///
/// Assumes the common, by-far-most-frequent HID gamepad report shape: axes
/// declared left-stick-X/Y, right-stick-X/Y, then (if present) left/right
/// trigger; buttons declared face buttons, then bumpers/triggers, then
/// back/start, then stick-clicks, in that order. Real unrecognized devices
/// won't all match this exactly, but it's a strictly better default than
/// reporting nothing, and matches what most consumer HID gamepads actually
/// do — the same assumption SDL and the browser Gamepad API's own generic
/// fallback path make.
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
    for (var i = 0; i < rawButtons.length && i < positionalButtonOrder.length; i++)
      if (rawButtons[i]) positionalButtonOrder[i],
    if (dpadUp) GamepadButton.dpadUp,
    if (dpadDown) GamepadButton.dpadDown,
    if (dpadLeft) GamepadButton.dpadLeft,
    if (dpadRight) GamepadButton.dpadRight,
  };

  return GamepadState(axes: axes, buttonsDown: buttons);
}

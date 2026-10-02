/// Axis identifiers of the standard gamepad layout, used as the keys of
/// `GamepadState.axes`.
///
/// Sticks range from -1.0 to 1.0 with positive X to the right and positive Y
/// *down* (the W3C Standard Gamepad convention). Triggers range from 0.0 to
/// 1.0.
abstract final class GamepadAxis {
  /// Left stick, horizontal. Positive is right.
  static const String leftStickX = 'leftStickX';

  /// Left stick, vertical. Positive is down.
  static const String leftStickY = 'leftStickY';

  /// Right stick, horizontal. Positive is right.
  static const String rightStickX = 'rightStickX';

  /// Right stick, vertical. Positive is down.
  static const String rightStickY = 'rightStickY';

  /// Left trigger (L2/LT/ZL), 0.0 to 1.0.
  static const String leftTrigger = 'leftTrigger';

  /// Right trigger (R2/RT/ZR), 0.0 to 1.0.
  static const String rightTrigger = 'rightTrigger';

  /// Every axis, in a stable order.
  static const List<String> values = [
    leftStickX,
    leftStickY,
    rightStickX,
    rightStickY,
    leftTrigger,
    rightTrigger,
  ];
}

/// Button identifiers of the standard gamepad layout, used in
/// `GamepadState.buttonsDown`.
///
/// The indices are the W3C Standard Gamepad button order, which is also what
/// browsers report for any controller whose `mapping` is `'standard'`. Face
/// buttons are named by *position* using Xbox labels: [a] is the bottom face
/// button on every controller (Cross on PlayStation, B on Nintendo).
abstract final class GamepadButton {
  /// Bottom face button (Xbox A, PlayStation Cross, Nintendo B).
  static const int a = 0;

  /// Right face button (Xbox B, PlayStation Circle, Nintendo A).
  static const int b = 1;

  /// Left face button (Xbox X, PlayStation Square, Nintendo Y).
  static const int x = 2;

  /// Top face button (Xbox Y, PlayStation Triangle, Nintendo X).
  static const int y = 3;

  /// Left bumper (LB/L1/L).
  static const int leftBumper = 4;

  /// Right bumper (RB/R1/R).
  static const int rightBumper = 5;

  /// Left trigger as a button (LT/L2/ZL). Derived from the analog trigger
  /// when the platform only reports an axis; see `triggerButtonThreshold`.
  static const int leftTriggerButton = 6;

  /// Right trigger as a button (RT/R2/ZR). Derived from the analog trigger
  /// when the platform only reports an axis; see `triggerButtonThreshold`.
  static const int rightTriggerButton = 7;

  /// Back/View/Share/Create/Minus.
  static const int back = 8;

  /// Start/Menu/Options/Plus.
  static const int start = 9;

  /// Left stick click (L3).
  static const int leftStick = 10;

  /// Right stick click (R3).
  static const int rightStick = 11;

  /// D-pad up.
  static const int dpadUp = 12;

  /// D-pad down.
  static const int dpadDown = 13;

  /// D-pad left.
  static const int dpadLeft = 14;

  /// D-pad right.
  static const int dpadRight = 15;

  /// Every button, in index order.
  static const List<int> values = [
    a,
    b,
    x,
    y,
    leftBumper,
    rightBumper,
    leftTriggerButton,
    rightTriggerButton,
    back,
    start,
    leftStick,
    rightStick,
    dpadUp,
    dpadDown,
    dpadLeft,
    dpadRight,
  ];
}

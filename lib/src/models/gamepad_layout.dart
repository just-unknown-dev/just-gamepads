/// Canonical gamepad axis identifiers — the single source of truth for this
/// layout. `package:just_inputs`' `GamepadAxis` (in `controller_input.dart`)
/// mirrors these string-for-string; a parity test in that package
/// (`gamepad_layout_parity_test.dart`) guards against the two drifting apart,
/// since `just_inputs` intentionally doesn't import this package's models
/// directly for its low-level `ControllerInput` state (kept dependency-free
/// for testability — see that package's doc comments).
class GamepadAxis {
  static const String leftStickX = 'leftStickX';
  static const String leftStickY = 'leftStickY';
  static const String rightStickX = 'rightStickX';
  static const String rightStickY = 'rightStickY';
  static const String leftTrigger = 'leftTrigger';
  static const String rightTrigger = 'rightTrigger';
}

/// Canonical gamepad button identifiers (the W3C Standard Gamepad layout —
/// also the order the Web Gamepad API reports for any device whose
/// `mapping == 'standard'`). See [GamepadAxis]'s doc comment for why this
/// isn't shared by direct import with `just_inputs`.
class GamepadButton {
  static const int a = 0;
  static const int b = 1;
  static const int x = 2;
  static const int y = 3;
  static const int leftBumper = 4;
  static const int rightBumper = 5;
  static const int leftTriggerButton = 6;
  static const int rightTriggerButton = 7;
  static const int back = 8;
  static const int start = 9;
  static const int leftStick = 10;
  static const int rightStick = 11;
  static const int dpadUp = 12;
  static const int dpadDown = 13;
  static const int dpadLeft = 14;
  static const int dpadRight = 15;
}

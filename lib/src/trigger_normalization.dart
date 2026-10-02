import 'models/gamepad_layout.dart';
import 'models/gamepad_state.dart';

/// Analog trigger value above which the trigger also counts as a pressed
/// [GamepadButton.leftTriggerButton]/[GamepadButton.rightTriggerButton].
///
/// Follows the W3C Standard Gamepad guidance for deriving a button from an
/// analog-only trigger.
const double triggerButtonThreshold = 0.5;

/// Adds [GamepadButton.leftTriggerButton]/[GamepadButton.rightTriggerButton]
/// to [state] when the analog trigger is past [triggerButtonThreshold] and
/// the backend didn't report the button itself.
///
/// Several platforms only report triggers as axes (Android, Linux, Windows'
/// Xbox path); others also report a discrete press (Apple's GameController).
/// Applying this everywhere keeps the threshold in one place. Returns [state]
/// unchanged when nothing needs adding.
GamepadState normalizeTriggerButtons(GamepadState state) {
  final needsLeft =
      !state.buttonsDown.contains(GamepadButton.leftTriggerButton) &&
      (state.axes[GamepadAxis.leftTrigger] ?? 0) > triggerButtonThreshold;
  final needsRight =
      !state.buttonsDown.contains(GamepadButton.rightTriggerButton) &&
      (state.axes[GamepadAxis.rightTrigger] ?? 0) > triggerButtonThreshold;

  if (!needsLeft && !needsRight) return state;

  return GamepadState(
    axes: state.axes,
    buttonsDown: {
      ...state.buttonsDown,
      if (needsLeft) GamepadButton.leftTriggerButton,
      if (needsRight) GamepadButton.rightTriggerButton,
    },
  );
}

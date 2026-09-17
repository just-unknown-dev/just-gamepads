import 'models/gamepad_layout.dart';
import 'models/gamepad_state.dart';

/// Threshold above which an analog trigger counts as "pressed" for the
/// digital `leftTriggerButton`/`rightTriggerButton` slots — matches the W3C
/// Standard Gamepad spec's own guidance for deriving a button value from an
/// analog-only trigger.
const double triggerButtonThreshold = 0.5;

/// Derives [GamepadButton.leftTriggerButton]/[GamepadButton.rightTriggerButton]
/// from the analog trigger axes whenever a backend didn't already report
/// them natively as discrete buttons.
///
/// Several platforms (Android generic motion events, Linux evdev, Windows'
/// `RawGameController` fallback path) only ever deliver triggers as analog
/// axes with no discrete keycode; Windows' primary `Gamepad` (WGI) path and
/// Darwin's `GCExtendedGamepad` both report a real discrete `.isPressed`, so
/// this is a no-op there (the button will already be present in
/// [state.buttonsDown] and this function won't touch it). Shared here so the
/// analog-threshold policy lives in exactly one place instead of being
/// re-decided per native backend.
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

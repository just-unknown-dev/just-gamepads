import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';

void main() {
  test(
    'derives the digital trigger button from an analog value above threshold',
    () {
      final state = GamepadState(axes: {GamepadAxis.leftTrigger: 0.75});

      final normalized = normalizeTriggerButtons(state);

      expect(normalized.buttonsDown, contains(GamepadButton.leftTriggerButton));
    },
  );

  test('does not derive a trigger button below threshold', () {
    final state = GamepadState(axes: {GamepadAxis.rightTrigger: 0.3});

    final normalized = normalizeTriggerButtons(state);

    expect(
      normalized.buttonsDown,
      isNot(contains(GamepadButton.rightTriggerButton)),
    );
  });

  test(
    'is a no-op when the backend already reports the trigger button natively',
    () {
      final state = GamepadState(
        axes: {GamepadAxis.leftTrigger: 0.9},
        buttonsDown: {GamepadButton.leftTriggerButton},
      );

      final normalized = normalizeTriggerButtons(state);

      expect(identical(normalized, state), isTrue);
    },
  );

  test('leaves unrelated buttons/axes untouched', () {
    final state = GamepadState(
      axes: {GamepadAxis.leftTrigger: 0.9, GamepadAxis.leftStickX: 0.4},
      buttonsDown: {GamepadButton.a},
    );

    final normalized = normalizeTriggerButtons(state);

    expect(normalized.axes, state.axes);
    expect(normalized.buttonsDown, {
      GamepadButton.a,
      GamepadButton.leftTriggerButton,
    });
  });
}

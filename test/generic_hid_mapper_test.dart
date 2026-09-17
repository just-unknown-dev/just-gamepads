import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';

void main() {
  test('maps the first 6 axes positionally to sticks and triggers', () {
    final state = mapGenericHid(
      rawAxes: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
      rawButtons: const [],
    );

    expect(state.axes[GamepadAxis.leftStickX], 0.1);
    expect(state.axes[GamepadAxis.leftStickY], 0.2);
    expect(state.axes[GamepadAxis.rightStickX], 0.3);
    expect(state.axes[GamepadAxis.rightStickY], 0.4);
    expect(state.axes[GamepadAxis.leftTrigger], 0.5);
    expect(state.axes[GamepadAxis.rightTrigger], 0.6);
  });

  test('omits trigger axes entirely when the device reports fewer than 5 axes', () {
    final state = mapGenericHid(rawAxes: [0.1, 0.2], rawButtons: const []);

    expect(state.axes.containsKey(GamepadAxis.leftTrigger), isFalse);
    expect(state.axes.containsKey(GamepadAxis.rightTrigger), isFalse);
    expect(state.axes[GamepadAxis.rightStickX], 0.0);
  });

  test('maps buttons positionally in declaration order', () {
    final state = mapGenericHid(
      rawAxes: const [],
      rawButtons: [true, false, false, true],
    );

    expect(state.buttonsDown, {GamepadButton.a, GamepadButton.y});
  });

  test('extra raw buttons beyond the known positional slots are ignored', () {
    final state = mapGenericHid(
      rawAxes: const [],
      rawButtons: List.filled(20, true),
    );

    expect(state.buttonsDown.every((b) => b <= GamepadButton.rightStick), isTrue);
  });

  test('dpad booleans map to the standard dpad button constants', () {
    final state = mapGenericHid(
      rawAxes: const [],
      rawButtons: const [],
      dpadUp: true,
      dpadRight: true,
    );

    expect(state.buttonsDown, {GamepadButton.dpadUp, GamepadButton.dpadRight});
  });
}

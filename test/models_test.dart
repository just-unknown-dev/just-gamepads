import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';

void main() {
  test('states with the same axes and buttons are equal', () {
    final a = GamepadState(
      axes: {GamepadAxis.leftStickX: 0.5, GamepadAxis.leftStickY: -1},
      buttonsDown: {GamepadButton.a, GamepadButton.start},
    );
    final b = GamepadState(
      axes: {GamepadAxis.leftStickY: -1, GamepadAxis.leftStickX: 0.5},
      buttonsDown: {GamepadButton.start, GamepadButton.a},
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('states differing in one axis are not equal', () {
    expect(
      GamepadState(axes: {GamepadAxis.leftStickX: 0.5}),
      isNot(GamepadState(axes: {GamepadAxis.leftStickX: 0.6})),
    );
  });

  test('a state copies its collections and cannot be modified', () {
    final buttons = {GamepadButton.a};
    final state = GamepadState(buttonsDown: buttons);
    buttons.add(GamepadButton.b);

    expect(state.buttonsDown, {GamepadButton.a});
    expect(
      () => state.buttonsDown.add(GamepadButton.x),
      throwsUnsupportedError,
    );
  });

  test('info equality and readable toString', () {
    const a = GamepadInfo(
      id: '1',
      name: 'Pad',
      type: GamepadType.xbox,
      vendorId: 0x045E,
    );
    const b = GamepadInfo(
      id: '1',
      name: 'Pad',
      type: GamepadType.xbox,
      vendorId: 0x045E,
    );

    expect(a, b);
    expect(a.toString(), contains('0x045e'));
  });

  test('layout value lists cover every constant once', () {
    expect(GamepadButton.values, List.generate(16, (i) => i));
    expect(GamepadAxis.values.toSet(), hasLength(6));
  });
}

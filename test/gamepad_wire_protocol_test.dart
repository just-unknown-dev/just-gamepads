import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';
import 'package:just_gamepads/src/wire/gamepad_wire_protocol.dart';

void main() {
  group('parseConnectionEvent', () {
    test('classifies a known vendor id via the shared database', () {
      final event = parseConnectionEvent(const {
        'event': 'connected',
        'id': 'dev-1',
        'name': 'Xbox Wireless Controller',
        'vendorId': 0x045E,
        'productId': 0x0B12,
      });

      expect(event.connected, isTrue);
      expect(event.info.id, 'dev-1');
      expect(event.info.type, GamepadType.xbox);
      expect(event.info.vendorId, 0x045E);
    });

    test('a disconnected event carries connected=false', () {
      final event = parseConnectionEvent(const {
        'event': 'disconnected',
        'id': 'dev-1',
        'name': 'Xbox Wireless Controller',
      });

      expect(event.connected, isFalse);
    });
  });

  group('parseStateEvent', () {
    test('uses semantic axes/buttons directly when present', () {
      final event = parseStateEvent(const {
        'id': 'dev-1',
        'axes': {GamepadAxis.leftStickX: 0.5, GamepadAxis.leftStickY: -0.5},
        'buttons': [GamepadButton.a, GamepadButton.leftBumper],
      });

      expect(event.gamepadId, 'dev-1');
      expect(event.state.axes[GamepadAxis.leftStickX], 0.5);
      expect(event.state.buttonsDown, {
        GamepadButton.a,
        GamepadButton.leftBumper,
      });
    });

    test('falls back to the generic positional mapper for raw arrays', () {
      final event = parseStateEvent(const {
        'id': 'dev-2',
        'rawAxes': [0.1, 0.2],
        'rawButtons': [true, false],
      });

      expect(event.state.axes[GamepadAxis.leftStickX], 0.1);
      expect(event.state.buttonsDown, {GamepadButton.a});
    });

    test('always applies trigger-button normalization', () {
      final event = parseStateEvent(const {
        'id': 'dev-1',
        'axes': {GamepadAxis.leftTrigger: 0.9},
        'buttons': <int>[],
      });

      expect(
        event.state.buttonsDown,
        contains(GamepadButton.leftTriggerButton),
      );
    });
  });
}

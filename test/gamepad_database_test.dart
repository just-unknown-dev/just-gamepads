import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';

void main() {
  group('GamepadDatabase.classify by vendor id', () {
    test('Microsoft vendor id classifies as xbox', () {
      expect(GamepadDatabase.classify(vendorId: 0x045E), GamepadType.xbox);
    });

    test('Sony vendor id classifies as playStation regardless of product', () {
      expect(
        GamepadDatabase.classify(vendorId: 0x054C, productId: 0x05C4),
        GamepadType.playStation,
      );
      expect(
        GamepadDatabase.classify(vendorId: 0x054C, productId: 0x0CE6),
        GamepadType.playStation,
      );
    });

    test('Nintendo Switch Pro requires the exact product id', () {
      expect(
        GamepadDatabase.classify(vendorId: 0x057E, productId: 0x2009),
        GamepadType.nintendoSwitchPro,
      );
      expect(
        GamepadDatabase.classify(vendorId: 0x057E, productId: 0x9999),
        GamepadType.generic,
      );
    });

    test('an unrecognized vendor id with no name hint is generic', () {
      expect(GamepadDatabase.classify(vendorId: 0x1234), GamepadType.generic);
    });
  });

  group('GamepadDatabase.classify by name hint fallback', () {
    test('name substrings classify when no vendor id is available', () {
      expect(
        GamepadDatabase.classify(nameHint: 'Xbox Wireless Controller'),
        GamepadType.xbox,
      );
      expect(
        GamepadDatabase.classify(nameHint: 'DualSense Wireless Controller'),
        GamepadType.playStation,
      );
      expect(
        GamepadDatabase.classify(nameHint: 'Nintendo Switch Pro Controller'),
        GamepadType.nintendoSwitchPro,
      );
    });

    test('an unrecognized name is generic', () {
      expect(
        GamepadDatabase.classify(nameHint: 'Some Random USB Pad'),
        GamepadType.generic,
      );
    });
  });

  test('no identifying information at all is unknown', () {
    expect(GamepadDatabase.classify(), GamepadType.unknown);
  });
}

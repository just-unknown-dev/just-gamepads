import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/src/web_gamepad_id.dart';

void main() {
  test('Chromium ids carry vendor and product', () {
    final parsed = parseWebGamepadId(
      'DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c '
      'Product: 0ce6)',
    );

    expect(parsed.name, 'DualSense Wireless Controller');
    expect(parsed.vendorId, 0x054C);
    expect(parsed.productId, 0x0CE6);
  });

  test('Chromium XInput ids carry no numbers', () {
    final parsed = parseWebGamepadId(
      'Xbox 360 Controller (XInput STANDARD GAMEPAD)',
    );

    expect(parsed.name, 'Xbox 360 Controller');
    expect(parsed.vendorId, isNull);
    expect(parsed.productId, isNull);
  });

  test('Firefox ids lead with vendor and product', () {
    final parsed = parseWebGamepadId('45e-2fd-Xbox Wireless Controller');

    expect(parsed.name, 'Xbox Wireless Controller');
    expect(parsed.vendorId, 0x045E);
    expect(parsed.productId, 0x02FD);
  });

  test('a bare name is kept whole', () {
    final parsed = parseWebGamepadId('Pro Controller');

    expect(parsed.name, 'Pro Controller');
    expect(parsed.vendorId, isNull);
  });

  test('a name that is only a suffix falls back to the whole id', () {
    const id = '(STANDARD GAMEPAD Vendor: 1234 Product: 5678)';

    expect(parseWebGamepadId(id).name, id);
    expect(parseWebGamepadId(id).vendorId, 0x1234);
  });
}

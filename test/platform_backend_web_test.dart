// Run with `flutter test --platform chrome` and again with `--wasm`: the
// backend must be the browser one under both compilers.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';
import 'package:just_gamepads/src/backend/gamepad_backend_web.dart'
    show WebGamepadBackend;
import 'package:just_gamepads/src/backend/platform_backend.dart' as platform;

void main() {
  test('web builds use the browser Gamepad API backend', () {
    expect(platform.createPlatformBackend(), isA<WebGamepadBackend>());
  });

  test('the browser backend starts and stops cleanly', () async {
    final manager = GamepadManager();
    await manager.start();
    // No controller is exposed to an automated browser.
    expect(manager.connected, isEmpty);
    manager.dispose();
  });
}

@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/src/backend/gamepad_backend_native.dart';
import 'package:just_gamepads/src/backend/platform_backend.dart';

void main() {
  test('native builds use the EventChannel backend', () {
    expect(createPlatformBackend(), isA<NativeGamepadBackend>());
  });
}

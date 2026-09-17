/// Parses the `EventChannel('just_gamepads/events')` message shape every
/// native backend sends, kept as pure functions (no platform-channel
/// dependency) so the parsing/normalization logic is unit-testable without
/// mocking a channel.
///
/// Wire shape (a `Map` per event, `StandardMessageCodec`-compatible types
/// only):
/// ```
/// {'event': 'connected', 'id': String, 'name': String,
///  'vendorId': int?, 'productId': int?}
/// {'event': 'disconnected', 'id': String}
/// {'event': 'state', 'id': String,
///   // Either semantic (native side already knows what each axis/button
///   // means — true for Windows' primary Gamepad(WGI) path, Android's
///   // KeyEvent/MotionEvent constants, and Darwin's GCExtendedGamepad):
///   'axes': Map<String, double>?, 'buttons': List<int>?,
///   // ...or raw/positional (native side enumerated a HID device it
///   // couldn't semantically identify — Windows' RawGameController
///   // fallback, or an unrecognized Linux evdev device):
///   'rawAxes': List<double>?, 'rawButtons': List<bool>?,
///   'dpadUp': bool?, 'dpadDown': bool?, 'dpadLeft': bool?, 'dpadRight': bool?}
/// ```
/// A 'state' message always carries exactly one of the two shapes; whichever
/// is present is used, then [normalizeTriggerButtons] is always applied.
library;

import '../gamepad_database.dart';
import '../generic_hid_mapper.dart';
import '../models/gamepad_events.dart';
import '../models/gamepad_info.dart';
import '../models/gamepad_state.dart';
import '../trigger_normalization.dart';

// TEMP DEBUG: see the throttled print in parseStateEvent below.
int _debugLogThrottleCounter = 0;

GamepadInfo parseGamepadInfo(Map<dynamic, dynamic> raw) {
  final vendorId = (raw['vendorId'] as num?)?.toInt();
  final productId = (raw['productId'] as num?)?.toInt();
  final name = raw['name'] as String? ?? '';
  return GamepadInfo(
    id: raw['id'] as String,
    name: name,
    type: GamepadDatabase.classify(
      vendorId: vendorId,
      productId: productId,
      nameHint: name,
    ),
    vendorId: vendorId,
    productId: productId,
  );
}

GamepadConnectionEvent parseConnectionEvent(Map<dynamic, dynamic> raw) {
  return GamepadConnectionEvent(
    info: parseGamepadInfo(raw),
    connected: raw['event'] == 'connected',
  );
}

GamepadStateEvent parseStateEvent(Map<dynamic, dynamic> raw) {
  final id = raw['id'] as String;
  final rawAxes = raw['axes'] as Map<dynamic, dynamic>?;
  final rawButtons = raw['buttons'] as List<dynamic>?;

  GamepadState state;
  if (rawAxes != null || rawButtons != null) {
    // TEMP DEBUG (remove once the Windows-controller left-stick bug is
    // diagnosed): confirms whether this device is using the *semantic*
    // path (native side already knows what each axis means — WGI's Gamepad
    // class for real XInput/Xbox-compatible hardware) rather than the raw/
    // positional fallback, and dumps the actual values.
    _debugLogThrottleCounter++;
    if (_debugLogThrottleCounter % 30 == 0) {
      // ignore: avoid_print
      print('[just_gamepads] SEMANTIC axes=$rawAxes buttons=$rawButtons');
    }
    state = GamepadState(
      axes: rawAxes?.map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      ),
      buttonsDown: rawButtons?.map((e) => (e as num).toInt()).toSet(),
    );
  } else {
    final parsedRawAxes = (raw['rawAxes'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    final parsedRawButtons = (raw['rawButtons'] as List<dynamic>?)
            ?.map((e) => e as bool)
            .toList() ??
        const <bool>[];
    _debugLogThrottleCounter++;
    if (_debugLogThrottleCounter % 30 == 0) {
      // ignore: avoid_print
      print(
        '[just_gamepads] RAW rawAxes=$parsedRawAxes rawButtons=$parsedRawButtons',
      );
    }
    state = mapGenericHid(
      rawAxes: parsedRawAxes,
      rawButtons: parsedRawButtons,
      dpadUp: raw['dpadUp'] as bool? ?? false,
      dpadDown: raw['dpadDown'] as bool? ?? false,
      dpadLeft: raw['dpadLeft'] as bool? ?? false,
      dpadRight: raw['dpadRight'] as bool? ?? false,
    );
  }

  return GamepadStateEvent(
    gamepadId: id,
    state: normalizeTriggerButtons(state),
  );
}

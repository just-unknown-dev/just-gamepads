/// Parses the messages every native backend sends over the
/// `EventChannel('just_gamepads/events')`.
///
/// Kept as pure functions with no platform-channel dependency so the
/// parsing and normalization can be unit tested without a channel.
///
/// Wire shape (one `Map` per event, `StandardMessageCodec` types only):
/// ```
/// {'event': 'connected', 'id': String, 'name': String,
///  'vendorId': int?, 'productId': int?,
///  // Extra words for classification only, never shown (Apple's
///  // productCategory, e.g. "DualSense").
///  'typeHint': String?}
/// {'event': 'disconnected', 'id': String}
/// {'event': 'state', 'id': String,
///   // Either semantic (the platform already knows what each control is:
///   // Windows' Xbox path, Android, Apple, Linux gamepad drivers):
///   'axes': Map<String, double>?, 'buttons': List<int>?,
///   // ...or raw/positional (an unrecognized device: Windows' raw path,
///   // generic Linux joysticks), mapped by mapGenericHid:
///   'rawAxes': List<double>?, 'rawButtons': List<bool>?,
///   // Optional with either shape; ORed into the d-pad buttons.
///   'dpadUp': bool?, 'dpadDown': bool?, 'dpadLeft': bool?, 'dpadRight': bool?}
/// ```
/// Semantic fields win when both shapes are present. Trigger buttons are
/// always derived with [normalizeTriggerButtons].
library;

import '../gamepad_database.dart';
import '../generic_hid_mapper.dart';
import '../models/gamepad_events.dart';
import '../models/gamepad_info.dart';
import '../models/gamepad_layout.dart';
import '../models/gamepad_state.dart';
import '../trigger_normalization.dart';

/// Parses the identity part of a `connected`/`disconnected` message.
GamepadInfo parseGamepadInfo(Map<dynamic, dynamic> raw) {
  final vendorId = (raw['vendorId'] as num?)?.toInt();
  final productId = (raw['productId'] as num?)?.toInt();
  final name = raw['name'] as String? ?? '';
  final typeHint = raw['typeHint'] as String?;
  return GamepadInfo(
    id: raw['id'] as String,
    name: name,
    type: GamepadDatabase.classify(
      vendorId: vendorId,
      productId: productId,
      nameHint: typeHint == null ? name : '$typeHint $name',
    ),
    vendorId: vendorId,
    productId: productId,
  );
}

/// Parses a `connected` or `disconnected` message.
GamepadConnectionEvent parseConnectionEvent(Map<dynamic, dynamic> raw) {
  return GamepadConnectionEvent(
    info: parseGamepadInfo(raw),
    connected: raw['event'] == 'connected',
  );
}

/// Parses a `state` message into a normalized [GamepadStateEvent].
///
/// [rest] is the device's [RawAxisRest], for the raw path: its axes read 0
/// until they are used.
GamepadStateEvent parseStateEvent(
  Map<dynamic, dynamic> raw, {
  RawAxisRest? rest,
}) {
  final id = raw['id'] as String;
  final axes = raw['axes'] as Map<dynamic, dynamic>?;
  final buttons = raw['buttons'] as List<dynamic>?;
  final dpadUp = raw['dpadUp'] as bool? ?? false;
  final dpadDown = raw['dpadDown'] as bool? ?? false;
  final dpadLeft = raw['dpadLeft'] as bool? ?? false;
  final dpadRight = raw['dpadRight'] as bool? ?? false;

  GamepadState state;
  if (axes != null || buttons != null) {
    state = GamepadState(
      axes: axes?.map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      ),
      buttonsDown: {
        ...?buttons?.map((e) => (e as num).toInt()),
        if (dpadUp) GamepadButton.dpadUp,
        if (dpadDown) GamepadButton.dpadDown,
        if (dpadLeft) GamepadButton.dpadLeft,
        if (dpadRight) GamepadButton.dpadRight,
      },
    );
  } else {
    final rawAxes = [
      for (final e in raw['rawAxes'] as List<dynamic>? ?? const [])
        (e as num).toDouble(),
    ];
    state = mapGenericHid(
      rawAxes: rest?.apply(rawAxes) ?? rawAxes,
      rawButtons: [
        for (final e in raw['rawButtons'] as List<dynamic>? ?? const [])
          e as bool,
      ],
      dpadUp: dpadUp,
      dpadDown: dpadDown,
      dpadLeft: dpadLeft,
      dpadRight: dpadRight,
    );
  }

  return GamepadStateEvent(
    gamepadId: id,
    state: normalizeTriggerButtons(state),
  );
}

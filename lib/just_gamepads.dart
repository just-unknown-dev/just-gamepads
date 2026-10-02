/// Cross-platform gamepad input for Flutter: Xbox, PlayStation, Nintendo
/// and generic controllers on Android, iOS, macOS, Windows, Linux and the
/// web (including WebAssembly), all reported in one standard button and
/// axis layout.
///
/// Start with [GamepadManager.instance].
library;

export 'src/backend/gamepad_backend.dart' show GamepadBackend;
export 'src/gamepad_database.dart' show GamepadDatabase;
export 'src/gamepad_manager.dart' show GamepadManager;
export 'src/generic_hid_mapper.dart' show mapGenericHid;
export 'src/models/gamepad_events.dart';
export 'src/models/gamepad_info.dart';
export 'src/models/gamepad_layout.dart' show GamepadAxis, GamepadButton;
export 'src/models/gamepad_state.dart';
export 'src/models/gamepad_type.dart';
export 'src/trigger_normalization.dart'
    show normalizeTriggerButtons, triggerButtonThreshold;

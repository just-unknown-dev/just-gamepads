/// Cross-platform gamepad/controller input — Xbox, PlayStation, and generic
/// controllers on Windows, Android, Web, macOS, iOS, and Linux, normalized to
/// one standard button/axis layout regardless of brand.
///
/// Low-level and dependency-free by design: this package knows nothing about
/// `just_inputs`' action-binding layer — see `just_inputs`'
/// `GamepadInputAdapter` for how it's consumed by this project's input
/// system.
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

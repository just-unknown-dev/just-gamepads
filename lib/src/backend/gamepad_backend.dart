import '../models/gamepad_events.dart';
import '../models/gamepad_info.dart';

/// The per-platform implementation [GamepadManager] delegates to — one
/// concrete backend per platform family:
///  - native (Windows/Android/iOS/macOS/Linux): `EventChannel`-backed, the
///    native side polls its own OS API and pushes full-snapshot events.
///  - web: talks to the browser Gamepad API directly in pure Dart, no
///    platform channel involved at all.
///
/// Selected via conditional import (`gamepad_backend_native.dart` vs.
/// `gamepad_backend_web.dart`), the same pattern `just_inputs` already uses
/// for its own dart:io-vs-web split — see that package's
/// `lib/src/actions/_io_native.dart`/`_io_stub.dart`.
abstract class GamepadBackend {
  /// Idempotent — safe to call more than once.
  Future<void> start();

  List<GamepadInfo> get connected;

  Stream<GamepadConnectionEvent> get connections;
  Stream<GamepadStateEvent> get stateChanges;

  void dispose();
}

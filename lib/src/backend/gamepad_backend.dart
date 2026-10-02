import '../models/gamepad_events.dart';
import '../models/gamepad_info.dart';

/// The platform implementation behind `GamepadManager`.
///
/// The package ships two:
///  * native (Android, iOS, macOS, Windows, Linux): an `EventChannel` fed by
///    the platform plugin.
///  * web (dart2js and dart2wasm): the browser Gamepad API, in pure Dart.
///
/// The right one is chosen at compile time. Implement this only to inject a
/// fake into `GamepadManager` in tests.
abstract class GamepadBackend {
  /// Starts reporting controllers. Safe to call more than once.
  Future<void> start();

  /// The controllers connected right now.
  List<GamepadInfo> get connected;

  /// Connects and disconnects, as they happen.
  Stream<GamepadConnectionEvent> get connections;

  /// State changes of connected controllers, as they happen.
  Stream<GamepadStateEvent> get stateChanges;

  /// Stops reporting and closes both streams. The backend can't be started
  /// again afterwards.
  void dispose();
}

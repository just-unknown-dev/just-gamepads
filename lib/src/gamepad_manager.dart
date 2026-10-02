import 'dart:async';

import 'backend/gamepad_backend.dart';
import 'backend/platform_backend.dart' as platform;
import 'models/gamepad_events.dart';
import 'models/gamepad_info.dart';
import 'models/gamepad_state.dart';

/// The entry point: tracks every connected controller and its latest state.
///
/// ```dart
/// final pads = GamepadManager.instance;
/// pads.connections.listen((e) => print(e));
/// pads.stateChanges.listen((e) => print(e.state.buttonsDown));
/// await pads.start();
/// ```
///
/// Every controller is reported separately, so local multiplayer can give
/// each its own player. Single-player games can follow
/// [mostRecentlyActiveId] instead.
class GamepadManager {
  /// Creates a manager over [backend], or over this platform's backend when
  /// none is given. Production code should normally use [instance]; passing a
  /// backend is meant for tests.
  GamepadManager({GamepadBackend? backend})
    : _backend = backend ?? platform.createPlatformBackend() {
    _connectionsSubscription = _backend.connections.listen(_onConnection);
    _stateSubscription = _backend.stateChanges.listen(_onState);
  }

  static GamepadManager? _instance;

  /// The shared manager. Created on first use; [dispose] clears it so the
  /// next access creates a fresh one.
  static GamepadManager get instance => _instance ??= GamepadManager();

  // How far an axis must be pushed to count as a player touching the pad.
  // Sticks drift and jitter around rest; this keeps an idle pad on the
  // table from taking over [mostRecentlyActiveId].
  static const double _activeAxisThreshold = 0.25;

  final GamepadBackend _backend;
  late final StreamSubscription<GamepadConnectionEvent>
  _connectionsSubscription;
  late final StreamSubscription<GamepadStateEvent> _stateSubscription;

  final Map<String, GamepadState> _latestState = {};
  // Which pad was touched last is an ordering, not a time: a counter that
  // only goes up. Wall-clock stamps can tie (two pads inside one tick) and
  // can go backwards when the system clock is adjusted.
  final Map<String, int> _lastInputAt = {};
  int _inputSequence = 0;
  String? _mostRecentlyActiveId;
  bool _disposed = false;

  final _connectionsController =
      StreamController<GamepadConnectionEvent>.broadcast();
  final _stateChangesController =
      StreamController<GamepadStateEvent>.broadcast();

  /// Starts reporting controllers. Safe to call more than once.
  ///
  /// Controllers already connected are reported on [connections] and then
  /// listed in [connected]; subscribe before calling this to see them as
  /// events.
  Future<void> start() => _backend.start();

  /// The controllers connected right now.
  List<GamepadInfo> get connected => _backend.connected;

  /// The latest state of the controller with [gamepadId], or `null` if it
  /// hasn't reported any yet.
  GamepadState? latestState(String gamepadId) => _latestState[gamepadId];

  /// The id of the controller a player touched most recently, or `null` if
  /// no connected controller has been touched yet.
  ///
  /// "Touched" means a button was pressed or a stick or trigger was pushed
  /// past a small deadzone. Connecting doesn't count, so an idle controller
  /// reconnecting (a Bluetooth blip, say) never steals focus from the one in
  /// use. When this controller disconnects, the previous one takes over.
  String? get mostRecentlyActiveId => _mostRecentlyActiveId;

  /// Connects and disconnects, as they happen.
  Stream<GamepadConnectionEvent> get connections =>
      _connectionsController.stream;

  /// State changes of connected controllers, as they happen.
  Stream<GamepadStateEvent> get stateChanges => _stateChangesController.stream;

  void _onConnection(GamepadConnectionEvent event) {
    if (!event.connected) {
      _latestState.remove(event.info.id);
      _lastInputAt.remove(event.info.id);
      if (_mostRecentlyActiveId == event.info.id) {
        _mostRecentlyActiveId = _mostRecentActiveIdAmongRemaining();
      }
    }
    _connectionsController.add(event);
  }

  String? _mostRecentActiveIdAmongRemaining() {
    if (_lastInputAt.isEmpty) return null;
    return (_lastInputAt.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  void _onState(GamepadStateEvent event) {
    // The first snapshot of a pad is compared against rest, so a pad that
    // connects untouched doesn't count as input.
    final previous = _latestState[event.gamepadId] ?? GamepadState.empty;
    _latestState[event.gamepadId] = event.state;
    if (_isPlayerInput(previous, event.state)) {
      _lastInputAt[event.gamepadId] = ++_inputSequence;
      _mostRecentlyActiveId = event.gamepadId;
    }
    _stateChangesController.add(event);
  }

  static bool _isPlayerInput(GamepadState previous, GamepadState next) {
    for (final button in next.buttonsDown) {
      if (!previous.buttonsDown.contains(button)) return true;
    }
    for (final MapEntry(:key, :value) in next.axes.entries) {
      if (value.abs() >= _activeAxisThreshold &&
          value != (previous.axes[key] ?? 0.0)) {
        return true;
      }
    }
    return false;
  }

  /// Stops reporting, closes both streams and disposes the backend. If this
  /// is [instance], the next access to [instance] creates a new manager.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectionsSubscription.cancel();
    _stateSubscription.cancel();
    _connectionsController.close();
    _stateChangesController.close();
    _backend.dispose();
    if (identical(_instance, this)) _instance = null;
  }
}

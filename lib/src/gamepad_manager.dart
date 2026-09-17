import 'dart:async';

import 'backend/gamepad_backend.dart';
import 'backend/gamepad_backend_native.dart'
    if (dart.library.html) 'backend/gamepad_backend_web.dart' as platform;
import 'models/gamepad_events.dart';
import 'models/gamepad_info.dart';
import 'models/gamepad_state.dart';

/// Public entry point: tracks every connected controller (so nothing about
/// this API precludes future local-co-op support) and picks one *active* id
/// — the controller that most recently produced real input — for callers
/// (namely `just_inputs`' `GamepadInputAdapter`) that only want a single
/// surfaced controller, this game being single-player.
///
/// Delegates all platform-specific work to a [GamepadBackend], selected via
/// conditional import (native `EventChannel` plugin vs. the pure-Dart Web
/// Gamepad API backend) unless one is injected — injection exists purely for
/// tests; production code should just use [instance].
class GamepadManager {
  GamepadManager({GamepadBackend? backend})
    : _backend = backend ?? platform.createPlatformBackend() {
    _connectionsSubscription = _backend.connections.listen(_onConnection);
    _stateSubscription = _backend.stateChanges.listen(_onState);
  }

  static GamepadManager? _instance;
  static GamepadManager get instance => _instance ??= GamepadManager();

  final GamepadBackend _backend;
  late final StreamSubscription<GamepadConnectionEvent>
  _connectionsSubscription;
  late final StreamSubscription<GamepadStateEvent> _stateSubscription;

  final Map<String, GamepadState> _latestState = {};
  final Map<String, DateTime> _lastInputAt = {};
  String? _mostRecentlyActiveId;

  final _connectionsController =
      StreamController<GamepadConnectionEvent>.broadcast();
  final _stateChangesController =
      StreamController<GamepadStateEvent>.broadcast();

  Future<void> start() => _backend.start();

  List<GamepadInfo> get connected => _backend.connected;

  GamepadState? latestState(String gamepadId) => _latestState[gamepadId];

  /// The id of the controller that most recently produced real input (a
  /// button/axis actually changed from neutral) — `null` if no connected
  /// controller has been touched yet. Deliberately *not* "most recently
  /// connected": an idle pad reconnecting (e.g. a Bluetooth blip) must not
  /// silently steal input focus from a pad the player is actively using —
  /// see [_onState].
  String? get mostRecentlyActiveId => _mostRecentlyActiveId;

  Stream<GamepadConnectionEvent> get connections =>
      _connectionsController.stream;
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
    // Compare against neutral (not "always differs") when this is the first
    // snapshot seen for this id — otherwise a reconnecting-but-untouched pad
    // would unconditionally steal activation on its very first post-connect
    // snapshot, exactly the "idle pad steals focus" case this heuristic
    // exists to avoid.
    final previous = _latestState[event.gamepadId] ?? GamepadState.empty;
    _latestState[event.gamepadId] = event.state;
    if (_stateDiffersFromNeutral(previous, event.state)) {
      _lastInputAt[event.gamepadId] = DateTime.now();
      _mostRecentlyActiveId = event.gamepadId;
    }
    _stateChangesController.add(event);
  }

  bool _stateDiffersFromNeutral(GamepadState previous, GamepadState next) {
    if (next.buttonsDown.length != previous.buttonsDown.length) return true;
    if (!next.buttonsDown.containsAll(previous.buttonsDown)) return true;
    for (final entry in next.axes.entries) {
      if ((previous.axes[entry.key] ?? 0) != entry.value) return true;
    }
    return false;
  }

  void dispose() {
    _connectionsSubscription.cancel();
    _stateSubscription.cancel();
    _connectionsController.close();
    _stateChangesController.close();
    _backend.dispose();
    if (identical(_instance, this)) _instance = null;
  }
}

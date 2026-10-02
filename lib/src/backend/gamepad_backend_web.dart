import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../gamepad_database.dart';
import '../generic_hid_mapper.dart';
import '../models/gamepad_events.dart';
import '../models/gamepad_info.dart';
import '../models/gamepad_layout.dart';
import '../models/gamepad_state.dart';
import '../trigger_normalization.dart';
import '../web_gamepad_id.dart';
import 'gamepad_backend.dart';

/// The backend for this platform.
GamepadBackend createPlatformBackend() => WebGamepadBackend();

/// Web backend (dart2js and dart2wasm): reads the browser Gamepad API
/// (`navigator.getGamepads()`) through `package:web`. No platform channel.
///
/// Controllers whose `mapping` is `'standard'` already use the package's
/// layout and pass straight through; anything else goes through the shared
/// positional mapper.
///
/// The Gamepad API has no "state changed" event, so it is polled once per
/// animation frame. Animation frames pause in background tabs, which avoids
/// wasted polling there. Only changed states are emitted.
///
/// Browsers expose a controller only after the user presses a button on it
/// while the page has focus.
class WebGamepadBackend implements GamepadBackend {
  final _connections = StreamController<GamepadConnectionEvent>.broadcast();
  final _stateChanges = StreamController<GamepadStateEvent>.broadcast();
  final Map<String, GamepadInfo> _connected = {};
  final Map<String, GamepadState> _lastState = {};

  bool _started = false;
  bool _disposed = false;
  int? _frameCallbackId;
  web.EventListener? _onConnectListener;
  web.EventListener? _onDisconnectListener;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('start() called on a disposed GamepadBackend.');
    }
    if (_started) return;
    _started = true;

    _onConnectListener = (web.Event event) {
      _connect((event as web.GamepadEvent).gamepad);
    }.toJS;
    _onDisconnectListener = (web.Event event) {
      _disconnect((event as web.GamepadEvent).gamepad.index.toString());
    }.toJS;
    web.window.addEventListener('gamepadconnected', _onConnectListener);
    web.window.addEventListener('gamepaddisconnected', _onDisconnectListener);

    // Pads that were exposed before start() never fire gamepadconnected
    // for this listener; the first poll picks them up.
    _poll();
    _scheduleNextFrame();
  }

  void _scheduleNextFrame() {
    _frameCallbackId = web.window.requestAnimationFrame(
      (num _) {
        _frameCallbackId = null;
        if (!_started) return;
        _poll();
        _scheduleNextFrame();
      }.toJS,
    );
  }

  void _poll() {
    final pads = web.window.navigator.getGamepads().toDart;
    for (final pad in pads) {
      if (pad == null || !pad.connected) continue;
      final id = pad.index.toString();
      if (!_connected.containsKey(id)) _connect(pad);
      final state = _readState(pad);
      if (state == _lastState[id]) continue;
      _lastState[id] = state;
      _stateChanges.add(GamepadStateEvent(gamepadId: id, state: state));
    }
  }

  void _connect(web.Gamepad pad) {
    final id = pad.index.toString();
    if (_connected.containsKey(id)) return;
    final parsed = parseWebGamepadId(pad.id);
    final info = GamepadInfo(
      id: id,
      name: parsed.name,
      type: GamepadDatabase.classify(
        vendorId: parsed.vendorId,
        productId: parsed.productId,
        nameHint: pad.id,
      ),
      vendorId: parsed.vendorId,
      productId: parsed.productId,
    );
    _connected[id] = info;
    _connections.add(GamepadConnectionEvent(info: info, connected: true));
  }

  void _disconnect(String id) {
    _lastState.remove(id);
    final info = _connected.remove(id);
    if (info == null) return;
    _connections.add(GamepadConnectionEvent(info: info, connected: false));
  }

  GamepadState _readState(web.Gamepad pad) {
    final buttons = pad.buttons.toDart;
    final axes = [for (final v in pad.axes.toDart) v.toDartDouble];

    GamepadState state;
    if (pad.mapping == 'standard') {
      double axisAt(int i) => i < axes.length ? axes[i] : 0.0;
      state = GamepadState(
        axes: {
          GamepadAxis.leftStickX: axisAt(0),
          GamepadAxis.leftStickY: axisAt(1),
          GamepadAxis.rightStickX: axisAt(2),
          GamepadAxis.rightStickY: axisAt(3),
          if (buttons.length > 6) GamepadAxis.leftTrigger: buttons[6].value,
          if (buttons.length > 7) GamepadAxis.rightTrigger: buttons[7].value,
        },
        buttonsDown: {
          for (var i = 0; i < buttons.length && i <= 15; i++)
            if (buttons[i].pressed) i,
        },
      );
    } else {
      state = mapGenericHid(
        rawAxes: axes,
        rawButtons: [for (final b in buttons) b.pressed],
      );
    }
    return normalizeTriggerButtons(state);
  }

  @override
  List<GamepadInfo> get connected => List.unmodifiable(_connected.values);

  @override
  Stream<GamepadConnectionEvent> get connections => _connections.stream;

  @override
  Stream<GamepadStateEvent> get stateChanges => _stateChanges.stream;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _started = false;
    final frame = _frameCallbackId;
    if (frame != null) web.window.cancelAnimationFrame(frame);
    _frameCallbackId = null;
    final onConnect = _onConnectListener;
    if (onConnect != null) {
      web.window.removeEventListener('gamepadconnected', onConnect);
    }
    final onDisconnect = _onDisconnectListener;
    if (onDisconnect != null) {
      web.window.removeEventListener('gamepaddisconnected', onDisconnect);
    }
    _onConnectListener = null;
    _onDisconnectListener = null;
    _connected.clear();
    _lastState.clear();
    _connections.close();
    _stateChanges.close();
  }
}

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
import 'gamepad_backend.dart';

GamepadBackend createPlatformBackend() => WebGamepadBackend();

/// Web backend: talks to the browser's Gamepad API directly
/// (`navigator.getGamepads()`) via `package:web`/`dart:js_interop` — no
/// platform channel, no native component at all, so this is pure Dart. The
/// first backend built (see the plan's sequencing rationale): most modern
/// controllers report `mapping == 'standard'`, which is already the exact
/// W3C Standard Gamepad layout `just_inputs`' own `GamepadButton` mirrors, so
/// this is a near-zero-remap pass-through for the common case.
///
/// The Gamepad API has no native "state changed" event (only
/// `gamepadconnected`/`gamepaddisconnected`), so state must be polled —
/// driven off `window.requestAnimationFrame` rather than `Timer.periodic`:
/// it naturally pauses when the tab is backgrounded, avoiding both wasted
/// polling and "stuck input" bugs on refocus (MDN's own recommended pattern
/// for this API).
class WebGamepadBackend implements GamepadBackend {
  final _connections = StreamController<GamepadConnectionEvent>.broadcast();
  final _stateChanges = StreamController<GamepadStateEvent>.broadcast();
  final Map<String, GamepadInfo> _connected = {};

  bool _started = false;
  int? _frameCallbackId;
  web.EventListener? _onConnectListener;
  web.EventListener? _onDisconnectListener;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _onConnectListener = (web.Event event) {
      final gamepad = (event as web.GamepadEvent).gamepad;
      _emitConnection(gamepad, connected: true);
    }.toJS;
    _onDisconnectListener = (web.Event event) {
      final gamepad = (event as web.GamepadEvent).gamepad;
      _emitConnection(gamepad, connected: false);
    }.toJS;
    web.window.addEventListener('gamepadconnected', _onConnectListener);
    web.window.addEventListener('gamepaddisconnected', _onDisconnectListener);

    // Some browsers only ever fire gamepadconnected for a pad that produces
    // input after the listener was attached — pick up anything already
    // connected (e.g. reported as part of a user gesture that preceded
    // start()) on the very first poll too.
    _pollOnce(initial: true);
    _scheduleNextFrame();
  }

  void _scheduleNextFrame() {
    _frameCallbackId = web.window.requestAnimationFrame(
      (num _) {
        _pollOnce(initial: false);
        if (_started) _scheduleNextFrame();
      }.toJS,
    );
  }

  void _pollOnce({required bool initial}) {
    final pads = web.window.navigator.getGamepads().toDart;
    for (final pad in pads) {
      if (pad == null) continue;
      final id = pad.index.toString();
      if (initial && !_connected.containsKey(id)) {
        _emitConnection(pad, connected: true);
      }
      _stateChanges.add(
        GamepadStateEvent(gamepadId: id, state: _readState(pad)),
      );
    }
  }

  void _emitConnection(web.Gamepad gamepad, {required bool connected}) {
    final id = gamepad.index.toString();
    final info = GamepadInfo(
      id: id,
      name: gamepad.id,
      type: GamepadDatabase.classify(nameHint: gamepad.id),
    );
    if (connected) {
      _connected[id] = info;
    } else {
      _connected.remove(id);
    }
    _connections.add(GamepadConnectionEvent(info: info, connected: connected));
  }

  GamepadState _readState(web.Gamepad pad) {
    final isStandard = pad.mapping == 'standard';
    final buttons = pad.buttons.toDart;
    final axes = pad.axes.toDart.map((v) => v.toDartDouble).toList();

    GamepadState state;
    if (isStandard) {
      final buttonsDown = <int>{
        for (var i = 0; i < buttons.length; i++)
          if (buttons[i].pressed) i,
      };
      final axesMap = <String, double>{
        GamepadAxis.leftStickX: axes.isNotEmpty ? axes[0] : 0.0,
        GamepadAxis.leftStickY: axes.length > 1 ? axes[1] : 0.0,
        GamepadAxis.rightStickX: axes.length > 2 ? axes[2] : 0.0,
        GamepadAxis.rightStickY: axes.length > 3 ? axes[3] : 0.0,
        if (buttons.length > 6) GamepadAxis.leftTrigger: buttons[6].value,
        if (buttons.length > 7) GamepadAxis.rightTrigger: buttons[7].value,
      };
      state = GamepadState(axes: axesMap, buttonsDown: buttonsDown);
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
    _started = false;
    if (_frameCallbackId != null) {
      web.window.cancelAnimationFrame(_frameCallbackId!);
      _frameCallbackId = null;
    }
    if (_onConnectListener != null) {
      web.window.removeEventListener('gamepadconnected', _onConnectListener);
    }
    if (_onDisconnectListener != null) {
      web.window.removeEventListener(
        'gamepaddisconnected',
        _onDisconnectListener,
      );
    }
    _connected.clear();
    _connections.close();
    _stateChanges.close();
  }
}

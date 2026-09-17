import 'dart:async';

import 'package:flutter/services.dart';

import '../models/gamepad_events.dart';
import '../models/gamepad_info.dart';
import '../wire/gamepad_wire_protocol.dart';
import 'gamepad_backend.dart';

const _channel = EventChannel('just_gamepads/events');

GamepadBackend createPlatformBackend() => NativeGamepadBackend();

/// Backend for every platform that ships a real native plugin (Windows,
/// Android, iOS, macOS, Linux) — subscribes once to a single shared
/// `EventChannel` that every native side pushes batched, one-snapshot-per-
/// device-per-tick connect/disconnect/state events into. All parsing lives
/// in `gamepad_wire_protocol.dart`; this class is just the channel plumbing.
class NativeGamepadBackend implements GamepadBackend {
  StreamSubscription<dynamic>? _subscription;
  final _connections = StreamController<GamepadConnectionEvent>.broadcast();
  final _stateChanges = StreamController<GamepadStateEvent>.broadcast();
  final Map<String, GamepadInfo> _connected = {};
  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = _channel.receiveBroadcastStream().listen(_handleMessage);
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) return;
    switch (message['event']) {
      case 'connected':
        final event = parseConnectionEvent(message);
        _connected[event.info.id] = event.info;
        _connections.add(event);
      case 'disconnected':
        final event = parseConnectionEvent(message);
        _connected.remove(event.info.id);
        _connections.add(event);
      case 'state':
        _stateChanges.add(parseStateEvent(message));
    }
  }

  @override
  List<GamepadInfo> get connected => List.unmodifiable(_connected.values);

  @override
  Stream<GamepadConnectionEvent> get connections => _connections.stream;

  @override
  Stream<GamepadStateEvent> get stateChanges => _stateChanges.stream;

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _connected.clear();
    _connections.close();
    _stateChanges.close();
    _started = false;
  }
}

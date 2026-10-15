import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../generic_hid_mapper.dart';
import '../models/gamepad_events.dart';
import '../models/gamepad_info.dart';
import '../wire/gamepad_wire_protocol.dart';
import 'gamepad_backend.dart';

const _channel = EventChannel('just_gamepads/events');

/// The backend for this platform.
GamepadBackend createPlatformBackend() => NativeGamepadBackend();

/// Backend for every platform with a native plugin (Android, iOS, macOS,
/// Windows, Linux).
///
/// Subscribes to one shared `EventChannel` that each native side feeds with
/// connect, disconnect and full-snapshot state messages. Parsing lives in
/// `gamepad_wire_protocol.dart`; this class is only the channel plumbing.
class NativeGamepadBackend implements GamepadBackend {
  /// Creates the backend. [channel] is replaceable for tests.
  NativeGamepadBackend({@visibleForTesting EventChannel channel = _channel})
    : _eventChannel = channel;

  final EventChannel _eventChannel;
  StreamSubscription<dynamic>? _subscription;
  final _connections = StreamController<GamepadConnectionEvent>.broadcast();
  final _stateChanges = StreamController<GamepadStateEvent>.broadcast();
  final Map<String, GamepadInfo> _connected = {};
  final Map<String, RawAxisRest> _rests = {};
  bool _started = false;
  bool _disposed = false;

  @override
  Future<void> start() async {
    if (_disposed) {
      throw StateError('start() called on a disposed GamepadBackend.');
    }
    if (_started) return;
    _started = true;
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      _handleMessage,
      onError: _report,
    );
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) return;
    try {
      switch (message['event']) {
        case 'connected':
          final event = parseConnectionEvent(message);
          _connected[event.info.id] = event.info;
          _rests[event.info.id] = RawAxisRest();
          _connections.add(event);
        case 'disconnected':
          // Report the identity seen at connect time; ignore ids that never
          // connected (a platform may report removal of any input device).
          final info = _connected.remove(message['id']);
          _rests.remove(message['id']);
          if (info != null) {
            _connections.add(
              GamepadConnectionEvent(info: info, connected: false),
            );
          }
        case 'state':
          final event = parseStateEvent(message, rest: _rests[message['id']]);
          if (_connected.containsKey(event.gamepadId)) {
            _stateChanges.add(event);
          }
      }
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  void _report(Object error, [StackTrace? stack]) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'just_gamepads',
        context: ErrorDescription('while handling a gamepad platform event'),
      ),
    );
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
    _subscription?.cancel();
    _subscription = null;
    _connected.clear();
    _rests.clear();
    _connections.close();
    _stateChanges.close();
  }
}

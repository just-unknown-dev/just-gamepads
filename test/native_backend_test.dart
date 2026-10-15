import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';
import 'package:just_gamepads/src/backend/gamepad_backend_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = EventChannel('just_gamepads/test_events');
  late MockStreamHandlerEventSink sink;
  late NativeGamepadBackend backend;
  late List<GamepadConnectionEvent> connections;
  late List<GamepadStateEvent> states;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(onListen: (_, events) => sink = events),
        );
    backend = NativeGamepadBackend(channel: channel);
    connections = [];
    states = [];
    backend.connections.listen(connections.add);
    backend.stateChanges.listen(states.add);
    await backend.start();
    await pumpEventQueue();
  });

  tearDown(() {
    backend.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, null);
  });

  test('a connect is reported and listed', () async {
    sink.success({
      'event': 'connected',
      'id': 'p1',
      'name': 'DualSense Wireless Controller',
      'vendorId': 0x054C,
      'productId': 0x0CE6,
    });
    await pumpEventQueue();

    expect(connections.single.connected, isTrue);
    expect(connections.single.info.type, GamepadType.playStation);
    expect(backend.connected.map((g) => g.id), ['p1']);
  });

  test('a disconnect reports the identity seen at connect time', () async {
    sink
      ..success({'event': 'connected', 'id': 'p1', 'name': 'Xbox Controller'})
      ..success({'event': 'disconnected', 'id': 'p1'});
    await pumpEventQueue();

    expect(connections.last.connected, isFalse);
    expect(connections.last.info.name, 'Xbox Controller');
    expect(connections.last.info.type, GamepadType.xbox);
    expect(backend.connected, isEmpty);
  });

  test('a disconnect of an id that never connected is ignored', () async {
    sink.success({'event': 'disconnected', 'id': 'keyboard-7'});
    await pumpEventQueue();

    expect(connections, isEmpty);
  });

  test('state of an id that never connected is ignored', () async {
    sink.success({
      'event': 'state',
      'id': 'ghost',
      'buttons': <int>[0],
    });
    await pumpEventQueue();

    expect(states, isEmpty);
  });

  test('state of a connected pad is parsed and forwarded', () async {
    sink
      ..success({'event': 'connected', 'id': 'p1', 'name': 'Pad'})
      ..success({
        'event': 'state',
        'id': 'p1',
        'axes': {GamepadAxis.leftStickX: 0.5},
        'buttons': <int>[GamepadButton.a],
      });
    await pumpEventQueue();

    expect(states.single.gamepadId, 'p1');
    expect(states.single.state.buttonsDown, {GamepadButton.a});
  });

  test('a raw pad pinned at one end reads at rest until it is used', () async {
    // A wireless receiver whose pad is off: Windows' raw path reads 0 on
    // every axis, -1 on the wire. Read as is, its stick is held fully left.
    Map<String, Object> reading(double x) => {
      'event': 'state',
      'id': 'p1',
      'rawAxes': [x, -1.0, -1.0, -1.0],
      'rawButtons': <bool>[],
    };
    sink
      ..success({'event': 'connected', 'id': 'p1', 'name': 'Receiver'})
      ..success(reading(-1))
      ..success(reading(-0.3));
    await pumpEventQueue();

    expect(states[0].state.axes[GamepadAxis.leftStickX], 0);
    expect(states[1].state.axes[GamepadAxis.leftStickX], -0.3);

    // A reconnect starts afresh.
    sink
      ..success({'event': 'disconnected', 'id': 'p1'})
      ..success({'event': 'connected', 'id': 'p1', 'name': 'Receiver'})
      ..success(reading(-1));
    await pumpEventQueue();
    expect(states[2].state.axes[GamepadAxis.leftStickX], 0);
  });

  test('a malformed message is reported, not thrown', () async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    sink.success({'event': 'connected', 'id': 42});
    await pumpEventQueue();

    expect(errors, hasLength(1));
    expect(errors.single.library, 'just_gamepads');
    expect(connections, isEmpty);
  });

  test('start after dispose throws', () async {
    backend.dispose();
    expect(backend.start, throwsStateError);
  });
}

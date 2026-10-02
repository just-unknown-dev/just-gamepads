import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_gamepads/just_gamepads.dart';

class _FakeBackend implements GamepadBackend {
  final _connections = StreamController<GamepadConnectionEvent>.broadcast();
  final _stateChanges = StreamController<GamepadStateEvent>.broadcast();
  final Map<String, GamepadInfo> _connected = {};

  @override
  Future<void> start() async {}

  @override
  List<GamepadInfo> get connected => List.unmodifiable(_connected.values);

  @override
  Stream<GamepadConnectionEvent> get connections => _connections.stream;

  @override
  Stream<GamepadStateEvent> get stateChanges => _stateChanges.stream;

  void connect(String id, {GamepadType type = GamepadType.generic}) {
    final info = GamepadInfo(id: id, name: id, type: type);
    _connected[id] = info;
    _connections.add(GamepadConnectionEvent(info: info, connected: true));
  }

  void disconnect(String id) {
    final info =
        _connected.remove(id) ??
        GamepadInfo(id: id, name: id, type: GamepadType.generic);
    _connections.add(GamepadConnectionEvent(info: info, connected: false));
  }

  void pushState(String id, GamepadState state) {
    _stateChanges.add(GamepadStateEvent(gamepadId: id, state: state));
  }

  @override
  void dispose() {
    _connections.close();
    _stateChanges.close();
  }
}

Future<void> flushMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeBackend backend;
  late GamepadManager manager;

  setUp(() {
    backend = _FakeBackend();
    manager = GamepadManager(backend: backend);
  });

  tearDown(() => manager.dispose());

  test('connected reflects the backend', () {
    backend.connect('a');
    expect(manager.connected.map((g) => g.id), ['a']);
  });

  test('mostRecentlyActiveId stays null until real input is seen', () async {
    backend.connect('a');
    backend.pushState('a', GamepadState.empty);
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, isNull);
  });

  test('mostRecentlyActiveId is set on the first non-neutral state', () async {
    backend.connect('a');
    backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, 'a');
  });

  test(
    'an idle reconnecting pad does not steal focus from an active one',
    () async {
      backend.connect('a');
      backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
      await flushMicrotasks();
      expect(manager.mostRecentlyActiveId, 'a');

      // Pad "b" reconnects (e.g. a Bluetooth blip) and its first snapshot is
      // neutral — must not steal activation from "a".
      backend.connect('b');
      backend.pushState('b', GamepadState.empty);
      await flushMicrotasks();

      expect(manager.mostRecentlyActiveId, 'a');
    },
  );

  test('activation follows genuine input to a second controller', () async {
    backend.connect('a');
    backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
    backend.connect('b');
    await flushMicrotasks();

    backend.pushState('b', GamepadState(buttonsDown: {GamepadButton.b}));
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, 'b');
  });

  test(
    'disconnecting the active controller falls back to the next most recent',
    () async {
      backend.connect('a');
      backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
      await flushMicrotasks();
      backend.connect('b');
      backend.pushState('b', GamepadState(buttonsDown: {GamepadButton.b}));
      await flushMicrotasks();
      expect(manager.mostRecentlyActiveId, 'b');

      backend.disconnect('b');
      await flushMicrotasks();

      expect(manager.mostRecentlyActiveId, 'a');
    },
  );

  test(
    'recency is an order, not a time: pads touched in one tick still rank',
    () async {
      // Three pads pressed with no gap between them — the same instant on a
      // wall clock. Taking the last one away must still hand focus to the one
      // touched just before it, not to whichever a tie happened to favour.
      backend
        ..connect('a')
        ..connect('b')
        ..connect('c')
        ..pushState('a', GamepadState(buttonsDown: {GamepadButton.a}))
        ..pushState('b', GamepadState(buttonsDown: {GamepadButton.a}))
        ..pushState('c', GamepadState(buttonsDown: {GamepadButton.a}));
      await flushMicrotasks();
      expect(manager.mostRecentlyActiveId, 'c');

      backend.disconnect('c');
      await flushMicrotasks();
      expect(manager.mostRecentlyActiveId, 'b');

      backend.disconnect('b');
      await flushMicrotasks();
      expect(manager.mostRecentlyActiveId, 'a');
    },
  );

  test(
    'disconnecting the only active controller clears mostRecentlyActiveId',
    () async {
      backend.connect('a');
      backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
      await flushMicrotasks();

      backend.disconnect('a');
      await flushMicrotasks();

      expect(manager.mostRecentlyActiveId, isNull);
    },
  );

  test('stick drift on an idle pad does not steal focus', () async {
    backend.connect('a');
    backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
    backend.connect('b');
    await flushMicrotasks();

    // Pad "b" lies on the table; its stick jitters around rest.
    for (final drift in [0.004, 0.012, -0.03, 0.08, 0.004]) {
      backend.pushState(
        'b',
        GamepadState(
          axes: {GamepadAxis.leftStickX: drift, GamepadAxis.rightStickY: drift},
        ),
      );
    }
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, 'a');
  });

  test('pushing a stick past the deadzone activates the pad', () async {
    backend.connect('a');
    backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
    backend.connect('b');
    backend.pushState('b', GamepadState(axes: {GamepadAxis.leftStickX: 0.9}));
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, 'b');
  });

  test('releasing a button is not new input', () async {
    backend
      ..connect('a')
      ..connect('b')
      ..pushState('b', GamepadState(buttonsDown: {GamepadButton.x}))
      ..pushState('a', GamepadState(buttonsDown: {GamepadButton.a}))
      ..pushState('b', GamepadState.empty);
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, 'a');
  });

  test('dispose is idempotent', () {
    manager.dispose();
    expect(manager.dispose, returnsNormally);
  });

  test(
    'latestState reflects the most recent snapshot for a given id',
    () async {
      backend.connect('a');
      final state = GamepadState(buttonsDown: {GamepadButton.x});
      backend.pushState('a', state);
      await flushMicrotasks();

      expect(manager.latestState('a')?.buttonsDown, {GamepadButton.x});
    },
  );
}

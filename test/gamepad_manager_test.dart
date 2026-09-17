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
    final info = _connected.remove(id) ?? GamepadInfo(id: id, name: id, type: GamepadType.generic);
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
    backend.pushState(
      'a',
      GamepadState(buttonsDown: {GamepadButton.a}),
    );
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, 'a');
  });

  test('an idle reconnecting pad does not steal focus from an active one', () async {
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
  });

  test('activation follows genuine input to a second controller', () async {
    backend.connect('a');
    backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
    backend.connect('b');
    await flushMicrotasks();

    backend.pushState('b', GamepadState(buttonsDown: {GamepadButton.b}));
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, 'b');
  });

  test('disconnecting the active controller falls back to the next most recent', () async {
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
  });

  test('disconnecting the only active controller clears mostRecentlyActiveId', () async {
    backend.connect('a');
    backend.pushState('a', GamepadState(buttonsDown: {GamepadButton.a}));
    await flushMicrotasks();

    backend.disconnect('a');
    await flushMicrotasks();

    expect(manager.mostRecentlyActiveId, isNull);
  });

  test('latestState reflects the most recent snapshot for a given id', () async {
    backend.connect('a');
    final state = GamepadState(buttonsDown: {GamepadButton.x});
    backend.pushState('a', state);
    await flushMicrotasks();

    expect(manager.latestState('a')?.buttonsDown, {GamepadButton.x});
  });
}

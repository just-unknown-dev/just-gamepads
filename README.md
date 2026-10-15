# Just Gamepads

Gamepad input for Flutter on Android, iOS, macOS, Windows, Linux and the web, including WebAssembly builds. Xbox, PlayStation, Nintendo and generic controllers all report in one standard button and axis layout, so game code never deals with per-brand or per-platform differences.

## Features

- Every connected controller, with connect and disconnect events, ready for local multiplayer.
- Full-state snapshots per controller: no deltas to reassemble.
- One layout everywhere: the W3C Standard Gamepad buttons and axes, with sticks in -1..1 (Y down-positive) and triggers in 0..1.
- `mostRecentlyActiveId`: the controller a player touched last, for single-player games. Stick drift on an idle controller doesn't count.
- Controller families (Xbox, PlayStation, Nintendo, generic) for picking button glyphs.

## Platform support

| Platform | Backend | Notes |
| --- | --- | --- |
| Android | Key and motion events | |
| iOS 13+ | GameController framework | Extended gamepads (Xbox, PlayStation, Switch Pro, MFi) |
| macOS 10.15+ | GameController framework | Extended gamepads (Xbox, PlayStation, Switch Pro, MFi) |
| Windows 10+ | Windows.Gaming.Input | Xbox controllers natively; others through RawGameController |
| Linux | evdev (`/dev/input`) | No extra system libraries |
| Web (JS and WASM) | Browser Gamepad API | Controllers appear after a button press |

## Getting started

```sh
flutter pub add just_gamepads
```

```dart
import 'package:just_gamepads/just_gamepads.dart';

final pads = GamepadManager.instance;

pads.connections.listen((event) {
  print('${event.info.name} (${event.info.type.name}) '
      '${event.connected ? 'connected' : 'disconnected'}');
});

pads.stateChanges.listen((event) {
  final state = event.state;
  final jump = state.buttonsDown.contains(GamepadButton.a);
  final moveX = state.axes[GamepadAxis.leftStickX] ?? 0.0;
  // ...
});

await pads.start();
```

Subscribe before calling `start()` to receive the controllers that are already connected as events; afterwards they are also listed in `pads.connected`. The latest state of any controller is available from `pads.latestState(id)` at any time.

Call `pads.dispose()` when the game shuts down.

## The standard layout

Face buttons are named by position, using Xbox letters: `GamepadButton.a` is the bottom face button on every controller.

| Index | `GamepadButton` | Xbox | PlayStation | Nintendo |
| --- | --- | --- | --- | --- |
| 0 | `a` | A | Cross | B |
| 1 | `b` | B | Circle | A |
| 2 | `x` | X | Square | Y |
| 3 | `y` | Y | Triangle | X |
| 4 | `leftBumper` | LB | L1 | L |
| 5 | `rightBumper` | RB | R1 | R |
| 6 | `leftTriggerButton` | LT | L2 | ZL |
| 7 | `rightTriggerButton` | RT | R2 | ZR |
| 8 | `back` | View | Share / Create | Minus |
| 9 | `start` | Menu | Options | Plus |
| 10 | `leftStick` | LS | L3 | Left stick |
| 11 | `rightStick` | RS | R3 | Right stick |
| 12-15 | `dpadUp`, `dpadDown`, `dpadLeft`, `dpadRight` | D-pad | D-pad | D-pad |

| `GamepadAxis` | Range |
| --- | --- |
| `leftStickX`, `rightStickX` | -1 (left) to 1 (right) |
| `leftStickY`, `rightStickY` | -1 (up) to 1 (down) |
| `leftTrigger`, `rightTrigger` | 0 (released) to 1 (fully pressed) |

The trigger buttons are derived from the analog triggers past `triggerButtonThreshold` (0.5) on platforms that only report an axis. Raw stick values are passed through as reported: apply your own deadzone.

`GamepadInfo.type` gives the controller family for glyphs. It is `GamepadType.generic` for controllers it can't identify.

## Platform notes

**Web.** Browsers expose a controller only after the user presses a button on it while the page has focus. Both `flutter build web` and `flutter build web --wasm` are supported.

**Linux.** The app reads `/dev/input/event*` directly. Desktop distributions give the logged-in user access to game controllers; sandboxed apps (Flatpak, Snap) need device access granted. Controllers without the kernel's standard gamepad mapping are reported positionally, like on the other platforms' fallback paths.

**Windows.** Xbox and XInput controllers are read through the Gamepad API; PlayStation, Switch and generic controllers through RawGameController. Windows may withhold controller input from apps that aren't in the foreground.

**Android.** Controller key events still reach Flutter as well, as `KeyEvent`s with `LogicalKeyboardKey.gameButton*` keys.

**iOS and macOS.** Controllers that only offer a micro gamepad profile (such as the Siri Remote) are not reported.

## Testing

`GamepadManager` accepts any `GamepadBackend`, so tests can drive it with a fake instead of real hardware:

```dart
final manager = GamepadManager(backend: FakeBackend());
```

The `example/` app is a live controller tester for checking a controller on real hardware.

## License

BSD 3-Clause. See [LICENSE](LICENSE).

# Changelog

All notable changes to just_gamepads will be documented in this file.

## [0.1.1] - 2026-10-13

- **A controller the platform does not recognise no longer reads as held over while it sits idle.** On the raw path (a generic HID pad, or a wireless receiver whose pad is off or asleep) every axis can read pinned at one end until the device is used — 0 on Windows' 0..1 scale, -1 on a stick — so a game saw the left stick held fully left and walked its player off on its own. Each raw axis now reads 0 until it first moves away from the value it was first read at, as SDL does for joysticks it does not know (`RawAxisRest`, applied per device by the native backend).

## [0.1.0] - 2026-10-02

First release.

- A hot restart starts the stream afresh: every connected pad is announced again, and on Windows nothing the last session had queued is delivered to the new listener.

- `GamepadManager` reports every connected controller, its connects and disconnects, and full-state snapshots, in one standard layout (`GamepadButton`, `GamepadAxis`) on every platform.
- `GamepadManager.mostRecentlyActiveId` follows the controller a player touched last, ignoring stick drift on idle controllers.
- `GamepadType` and `GamepadDatabase` tell Xbox, PlayStation and Nintendo controllers apart for button glyphs.
- Platforms:
  - **Android:** key and motion events; triggers on either the trigger or the gas/brake axes.
  - **iOS, macOS:** Apple's GameController framework.
  - **Windows:** Windows.Gaming.Input. Xbox controllers through the Gamepad API; PlayStation, Switch and generic controllers through RawGameController, with PlayStation face buttons and axes remapped.
  - **Linux:** evdev with inotify hot-plug; no libraries beyond GTK/GLib.
  - **Web:** the browser Gamepad API, under both dart2js and dart2wasm.

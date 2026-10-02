# Changelog

All notable changes to just_gamepads will be documented in this file.

## [0.1.0] - 2026-10-02

First release.

- `GamepadManager` reports every connected controller, its connects and
  disconnects, and full-state snapshots, in one standard layout
  (`GamepadButton`, `GamepadAxis`) on every platform.
- `GamepadManager.mostRecentlyActiveId` follows the controller a player
  touched last, ignoring stick drift on idle controllers.
- `GamepadType` and `GamepadDatabase` tell Xbox, PlayStation and Nintendo
  controllers apart for button glyphs.
- Platforms:
  - **Android:** key and motion events; triggers on either the trigger or
    the gas/brake axes.
  - **iOS, macOS:** Apple's GameController framework.
  - **Windows:** Windows.Gaming.Input. Xbox controllers through the Gamepad
    API; PlayStation, Switch and generic controllers through
    RawGameController, with PlayStation face buttons and axes remapped.
  - **Linux:** evdev with inotify hot-plug; no libraries beyond GTK/GLib.
  - **Web:** the browser Gamepad API, under both dart2js and dart2wasm.

# Contributing to Just Gamepads

Thank you for your interest in contributing to **Just Gamepads**. Bug fixes, controller support, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [How the Package Fits Together](#how-the-package-fits-together)
- [Running the Tests](#running-the-tests)
- [Testing on Real Controllers](#testing-on-real-controllers)
- [Coding Guidelines](#coding-guidelines)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Commit Message Convention](#commit-message-convention)
- [License](#license)

---

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to its terms. Please report unacceptable behaviour to the maintainers.

---

## Reporting Bugs and Suggesting Features

Before opening an issue, search the [existing issues](https://github.com/just-unknown-dev/just-gamepads/issues) and check that the problem happens on the latest version.

Controller bugs usually depend on the exact device, so a bug report should have:

- a clear title;
- steps to reproduce, and what you expected instead of what happened;
- the controller: its model, and how it is connected (USB, Bluetooth, or a wireless dongle);
- the vendor and product ids, name and family that the `example/` app shows for it;
- the platform and OS version (for the web, the browser and whether it was a JavaScript or a WebAssembly build), and the output of `flutter --version`;
- for a wrong mapping, which control you pressed and which cell lit up in the `example/` app.

For a feature, open an issue labelled **`enhancement`** that describes the problem it solves and how it should behave. The package's scope is reporting controllers and their state in one standard layout. Action mapping, rebinding and deadzones belong to the input layer built on top of it. A new capability (rumble or motion sensors, say) has to work, or be reported as unavailable, on all six platforms, so open the issue first and agree the approach before you write it.

---

## Development Setup

| Tool | Minimum version |
|------|-----------------|
| Flutter | 3.41 |
| Dart | 3.11 (comes with Flutter 3.41) |

```bash
git clone https://github.com/just-unknown-dev/just-gamepads.git
cd just-gamepads
flutter pub get
flutter test
```

Native changes also need that platform's toolchain: Android Studio for Android, Xcode for iOS and macOS, Visual Studio with the "Desktop development with C++" workload for Windows, and the packages from Flutter's Linux setup (such as `clang`, `cmake`, `ninja-build`, `pkg-config` and `libgtk-3-dev`) for Linux. The plugin needs no other system libraries.

---

## How the Package Fits Together

| Folder | Contents |
|--------|----------|
| `lib/` | The Dart API, the shared mapping code, and the web backend (browser Gamepad API) |
| `android/` | Kotlin: key and motion events |
| `ios/`, `macos/` | Swift: Apple's GameController framework |
| `windows/` | C++: Windows.Gaming.Input, through the classic WinRT ABI |
| `linux/` | C++: evdev, with inotify for hot-plug |
| `example/` | A live controller tester for every platform |
| `test/` | Dart tests; the Windows C++ tests are in `windows/test/` |

Every native backend sends the same messages over one `EventChannel('just_gamepads/events')`. The message shapes are documented at the top of `lib/src/wire/gamepad_wire_protocol.dart`, and all parsing happens in Dart. Keep it that way:

- **Changing a message** means changing the parser, its tests in `test/gamepad_wire_protocol_test.dart`, and every backend that sends it.
- **Brand classification** (Xbox, PlayStation, Nintendo) lives only in `lib/src/gamepad_database.dart`. Backends send the vendor id, product id and name; they do not decide the family.
- **Positional guessing** for unrecognized controllers lives only in `lib/src/generic_hid_mapper.dart`.
- **Device-specific remapping** belongs in the native backend only when it is keyed on the device, the way `windows/raw_layout.h` reorders PlayStation controllers by vendor id. Never change the layout of every controller to fix one.

The layout itself is fixed: sticks from -1 to 1 with Y positive *down*, triggers from 0 to 1, and face buttons named by position (`GamepadButton.a` is the bottom face button on every controller). A backend whose platform reports Y up-positive negates it.

---

## Running the Tests

Run every command from the repository root.

```bash
# The Dart tests.
flutter test

# The backend-selection test, in a browser, compiled to JavaScript and to WebAssembly.
flutter test --platform chrome test/platform_backend_web_test.dart
flutter test --platform chrome --wasm test/platform_backend_web_test.dart
```

The Windows C++ tests cover the pure layout helpers in `windows/raw_layout.h`. The example app turns them on, so build it for Windows and run the test binary:

```bash
cd example
flutter build windows --debug
build/windows/x64/plugins/just_gamepads/Debug/just_gamepads_test.exe
```

Android, iOS, macOS and Linux have no native unit tests. Changes there are checked with the example app on real controllers.

---

## Testing on Real Controllers

Unit tests can't tell you whether a controller works. Any change to a backend, a remap or the layout needs a run of the example app on the platform it touches, with the controllers it affects:

```bash
cd example
flutter run -d windows        # or macos, linux, android, ios, chrome
flutter run -d chrome --wasm
```

Check that:

- each physical controller shows exactly one card, with the right name and family;
- every button lights its own cell, with the bottom face button lighting **A**;
- the sticks read positive to the right and *down*, and the triggers run from 0 to 1;
- unplugging and plugging back in removes and re-adds the card, and nothing stays held afterwards.

On the web, press a button on the controller after the page has focus: browsers hide controllers until then. Say in your pull request which controllers and platforms you tested.

---

## Coding Guidelines

- **Formatting.** Dart code is formatted with `dart format`. This must report no changes:

  ```bash
  dart format --output=none --set-exit-if-changed lib test example/lib
  ```

- **Analysis.** `flutter analyze` must report no issues at all — errors, warnings or infos. The rules are in `analysis_options.yaml`: `flutter_lints`.
- **Web and WebAssembly.** Nothing in `lib/` may import `dart:io` or `dart:html`. The web backend uses `package:web` and `dart:js_interop`, and `lib/src/backend/platform_backend.dart` picks it with a conditional on `dart.library.js_interop`. Do not test `dart.library.html`: it is false under dart2wasm, so a wasm build would silently get the native backend. Check with `grep -rnE "import 'dart:(io|html)'" lib` before you open a pull request.
- **Windows.** The plugin builds with `/W4 /WX`, so every warning is an error. Use the classic WinRT ABI headers (`<windows.gaming.input.h>`, `Microsoft::WRL::ComPtr`), not C++/WinRT, which needs a NuGet package the Flutter plugin template doesn't set up. `<windows.h>` defines `min` and `max` macros, so avoid `std::min`/`std::max` there. Events from WinRT and the polling thread reach Dart only through the plugin's message window, never directly.
- **Linux.** Apps build plugins with `-Wall -Werror`. The plugin uses C++17 and links only GTK/GLib, which every Flutter Linux app already has; do not add `pkg-config` dependencies. Everything runs on the GLib main loop, with no extra threads.
- **iOS and macOS.** `GamepadController.swift` is identical in `ios/` and `macos/`; change both and check with `diff`. The minimums are iOS 13 and macOS 10.15: guard anything newer with `#available`.
- **Android.** The minimum is API 24. All plugin code runs on the main thread, and the window-callback wrapper only observes events; it never consumes them.
- **Documentation.** Give every public API you add a `///` doc comment. Describe user-visible changes in [CHANGELOG.md](CHANGELOG.md), and update the layout tables in [README.md](README.md) if a mapping changes.
- **Tests.** Add or update Dart tests for any behaviour you change. Native remapping that can be written as a pure function (like `windows/raw_layout.h`) should be, with a test.
- **Dependencies.** Do not add a dependency without discussing it in an issue first.
- **Structure.** Match the existing folders under `lib/src/`. Export new public API through `lib/just_gamepads.dart`; other code imports that library, not files under `lib/src/`.

---

## Submitting a Pull Request

1. Create a topic branch from `main`:
   ```bash
   git checkout -b fix/dualsense-triggers-linux
   ```
2. Make your change, following the [Coding Guidelines](#coding-guidelines).
3. Check that everything passes:
   ```bash
   dart format --output=none --set-exit-if-changed lib test example/lib
   flutter analyze
   flutter test
   ```
4. For a native or mapping change, run the example app as in [Testing on Real Controllers](#testing-on-real-controllers).
5. Commit with a [conventional commit message](#commit-message-convention).
6. Push to your fork and open a pull request against `main`. Say what changed and why, and list the controllers and platforms you tested.
7. Answer review feedback.

Small pull requests are easier to review.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

Use the platform as the scope for backend changes (`android`, `ios`, `macos`, `windows`, `linux`, `web`), and the area otherwise (`manager`, `layout`, `database`, `wire`, `example`).

**Examples:**
```
fix(windows): remap PlayStation face buttons on the raw path
feat(linux): report the d-pad from BTN_DPAD_* keys
docs(readme): document the trigger button threshold
```

---

## License

By contributing to Just Gamepads you agree that your contributions will be licensed under the [BSD-3-Clause License](LICENSE).

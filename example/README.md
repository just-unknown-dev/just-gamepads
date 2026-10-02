# just_gamepads example

A live controller tester. Each connected controller gets a card with its
name, family, USB ids and every button and axis of the standard layout;
press and push things to see them light up. The controller touched last is
outlined.

```sh
flutter run -d windows   # or macos, linux, android, ios, chrome
flutter run -d chrome --wasm
```

On the web, press a button on the controller after the page has focus;
browsers hide controllers until then.

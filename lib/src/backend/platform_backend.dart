// Picks the backend for the platform being compiled for.
//
// `dart.library.js_interop` is the web check that holds for both dart2js and
// dart2wasm; `dart.library.html` is false under dart2wasm and would silently
// select the native EventChannel backend there.
export 'gamepad_backend_native.dart'
    if (dart.library.js_interop) 'gamepad_backend_web.dart';

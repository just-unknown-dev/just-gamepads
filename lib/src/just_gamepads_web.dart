import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web plugin registration.
///
/// The web backend talks to the browser Gamepad API directly and needs no
/// channel, so there is nothing to register. Declaring the web platform
/// still matters: it is how Flutter tooling and pub.dev know this plugin
/// supports the web.
class JustGamepadsWeb {
  /// Called by the generated web plugin registrant.
  static void registerWith(Registrar registrar) {}
}

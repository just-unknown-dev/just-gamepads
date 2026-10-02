/// Coarse controller family, for presentation only (button glyphs and
/// prompts).
///
/// Input never depends on this: every controller reports through the same
/// standard `GamepadButton`/`GamepadAxis` layout regardless of brand.
enum GamepadType {
  /// Xbox and XInput-compatible controllers.
  xbox,

  /// PlayStation controllers (DualShock 4, DualSense).
  playStation,

  /// Nintendo controllers (Switch Pro and similar).
  nintendoSwitchPro,

  /// A connected controller that couldn't be identified by vendor/product id
  /// or name. Still fully usable through the standard layout; show generic
  /// glyphs.
  generic,

  /// No identifying information at all (for example, no controller
  /// connected). Distinct from [generic] so UI can fall back to a default
  /// brand when describing bindings with no controller present.
  unknown,
}

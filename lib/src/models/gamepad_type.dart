/// Coarse controller brand/family, used only for UI presentation (button
/// glyphs/prompts) — never for input resolution, which always goes through
/// the standard [GamepadButton]/[GamepadAxis] layout regardless of brand.
enum GamepadType {
  xbox,
  playStation,
  nintendoSwitchPro,

  /// A real, connected controller that the classifier couldn't identify by
  /// vendor/product id or name — still fully usable via the standard layout,
  /// just rendered with generic button glyphs.
  generic,

  /// No identifying information was available at all (e.g. no controller
  /// currently connected). Distinct from [generic] so callers can choose to
  /// fall back to a default brand for "describe all configured bindings
  /// regardless of momentary hardware presence" UI, rather than always
  /// showing generic glyphs.
  unknown,
}

# Mivu native design system

Current visual authority: **Precision Glass**, owner-selected direction 03,
approved for the native iPhone app on 2026-10-16. Its implementation-ready
reference is in [`precision-glass/`](precision-glass/).

## Authority and precedence

- [`precision-glass/DESIGN.md`](precision-glass/DESIGN.md) defines the approved
  visual language and material hierarchy.
- [`precision-glass/tokens.json`](precision-glass/tokens.json) is the structured
  source for color, spacing, type, motion and navigation tokens.
- [`precision-glass/specs/`](precision-glass/specs/) holds screen, state and
  reusable-component requirements.
- [`precision-glass/icons.json`](precision-glass/icons.json) and
  [`precision-glass/fixtures.json`](precision-glass/fixtures.json) define icon
  and example-data guidance. Selected illustrations are in
  [`precision-glass/assets/`](precision-glass/assets/).

If references disagree, follow the written design and structured specification
data. The supplied raster boards are concept illustrations: they communicate
visual intent, but native control geometry, exact symbols, chart rendering and
runtime materials must follow the written requirements and platform behavior.
Product flows, privacy, persistence, recovery and other product invariants stay
authoritative in their product specifications.

## Shared implementation principles

Use native SwiftUI navigation, controls, sheets, keyboard behavior and back
gestures. Keep content surfaces stable and legible; reserve Liquid Glass for
system navigation and controls. Respect Dynamic Type, VoiceOver, Increase
Contrast, Reduce Transparency and Reduce Motion. Food photographs document
meals rather than decorate backgrounds. Estimates and provenance remain clear,
and incomplete data stays explicitly unknown.

The MVP is English-only. Preserve existing profile, archive and stored language
values; Hebrew RTL behavior is outside the current acceptance scope.

## Verification boundary

Concept images support appearance review. They do not prove native interaction,
accessibility or runtime material behavior. Verify those in the actual app at
the supported device sizes and system accessibility settings, using the screen
and component acceptance criteria in `precision-glass/specs/`.

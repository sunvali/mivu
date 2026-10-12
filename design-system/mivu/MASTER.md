# Mivu native design system

Owner direction,2026-10-12: premium, smooth, easy to use, cheerful food colors,
and the native iOS27 glass design. Applies to every diary screen. The product
flows and privacy/recovery invariants remain authoritative.

## Character and hierarchy

Warm, appetizing and composed. Food photos supply personality. Typography,
spacing and a small set of semantic colors establish hierarchy. One prominent
capture action stays reachable without scrolling, including large Dynamic Type.
Use native tab navigation, sheets, keyboard behavior and back gestures.

Today: concise sample-mode label; waking-day context; recorded intake; two
secondary waking actions; recent meals. Empty, pending and error states receive
the same care as populated states. Details progressively disclose secondary
metadata; provenance remains accessible and synthetic estimates stay obvious.

## Semantic palette

| Role | Light | Dark |
|---|---|---|
| Canvas | Warm cream `#FFF8EF` | Deep green charcoal `#1D211E` |
| Surface | Near-white `#FFFDFA` | Raised charcoal `#292D29` |
| Primary text | Espresso `#2B231F` | Warm white `#FFF8EF` |
| Secondary text | Warm gray `#78675B` | Sand `#CABBAB` |
| Main action | Coral `#BB432B` | Apricot `#FFA988` |
| Text on main action | White `#FFFFFF` | Espresso `#261C18` |
| Supporting accent | Leaf green `#4C695B` | Sage `#ADCDB9` |

Python sRGB contrast calculation: main-action pairs5.32:1 and8.94:1;
secondary text on canvas5.12:1 and8.70:1; leaf accents on canvas5.73:1
and9.48:1. Measure actual composed glass states separately. Functional states
also use native text/icons, never color alone.

## Native glass, typography and motion

Use Apple's actual Liquid Glass for the navigation/action layer: standard TabView
and navigation bars, native glass button styles, and selective custom
glassEffect/GlassEffectContainer. Keep food/data surfaces clear and stable.
Respect system transparency/contrast preferences; add a solid accessible action
fallback if composed glass cannot meet readability. No custom blur framework.

Use system Dynamic Type text styles with SF Pro, tabular nutrition figures,
semibold headings and regular body copy. Native SF Symbols, consistent sizing,
44pt minimum targets. Spacing rhythm4/8/16/24/32pt; adaptive wrapping and semantic
leading/trailing support English LTR and landscape. The Hebrew selector is
disabled for this English-only MVP; preserve existing Hebrew profile/archive data
and stored language values, but Hebrew RTL is not an MVP acceptance requirement.
No hardcoded body font sizes.

Native interactive press feedback and sheet/navigation motion; interruptible,
brief value transitions only where they explain a saved change. Respect reduced
motion. At most one restrained confirmation haptic after durable capture.
Async save errors preserve input and stay close to the responsible action.

## Guidance and acceptance

UI/UX Pro Max's native pro-rules and SwiftUI navigation search apply. Its two
design-system searches returned a marketing storytelling layout, without a
verified native layout match; that output was not persisted or adopted. This
native direction is an owner-approved interpretation using the skill's app
guidance, not a claimed database layout recommendation.

Primary Apple references:
[Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[Liquid Glass custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

Acceptance: actual English, light/dark, small/large phone, landscape,
largest Dynamic Type, reduced motion/transparency and accessible semantic trees.
Native journeys must retain capture/review/edit/history/profile/backup behavior.
Screenshots prove appearance; native interaction and unit tests prove behavior.

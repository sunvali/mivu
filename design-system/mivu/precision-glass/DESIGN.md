# Precision Glass design language
Mode: Operate. Native iPhone. The interface should feel like an instrument for understanding one's own records: calm, exact and quietly tactile.

## What stays from direction 03
Aligned numbers, clear unit labels, strong typographic hierarchy, thin dividers, compact analytical sections and one teal/cyan interaction tint. Food photographs are evidence attached to meals, not decorative backgrounds.

## What changes
System navigation and action controls adopt Apple Liquid Glass. Content remains stable and legible. The soft capsule geometry of controls is deliberately balanced against precise ledger rows.

## Material hierarchy
1. Canvas: semantic system background, opaque.
2. Content: text, charts, photos, ledger rows, editable forms. Opaque surfaces; no arbitrary blur.
3. Navigation and controls: native TabView, toolbars, sheets and platform button treatments. Regular Liquid Glass is the default. Avoid mixing glass variants or nesting glass panels.
4. Modal focus: use system sheet transitions and adaptive backgrounds. Full-height forms become solid enough for reading. Do not override the material with a custom blur stack.

Native bars adapt to the content underneath. Do not hard-code reflection, blur radius, opacity or shadow recipes. The pictures show visual intent; runtime material comes from the OS. Clear glass is not needed for these data screens.

## Color
| Role | Light reference | Dark reference | Implementation |
|---|---|---|---|
| Canvas | #F5F8F8 | #111516 | semantic background or dynamic asset |
| Raised content | #FFFFFF | #1D2324 | grouped surface |
| Primary text | #142023 | #F4F7F6 | primary label |
| Secondary text | #53646B | #B7C4C8 | secondary label |
| Interactive tint | #136875 | #81D5DB | dynamic accent asset |
| On accent | #FFFFFF | #092126 | explicit contrast pair |
| Rule | #D5DFE1 | #374346 | separator; strengthen for Increase Contrast |

Hex values are reference tokens, not a substitute for semantic behavior. Destructive/error/warning roles use system semantic colors plus labels and symbols. Never use red/green to judge food or body weight. Chart series uses the accent; coverage is additionally encoded by labels/patterns.

## Typography
Use SF Pro system styles. Large title for roots; inline title for deep detail. Body 17 pt at default size, secondary text generally 15 pt, metadata 13 pt. Respect Dynamic Type instead of freezing point sizes. Display metric starts around 48 pt with a scalable relative metric; tabular digits for values, not monospaced prose. Weight is semibold for titles and key values, regular for reading. No all-caps navigation or motivational headlines.

At accessibility sizes, a metric's unit moves onto a separate line and paired numeric columns stack. Do not shrink important text to keep a screenshot's geometry.

## Spacing and geometry
4 pt rhythm: 4 / 8 / 12 / 16 / 20 / 24 / 32. Default content inset 20 pt; native Form/List insets take precedence. Ledger row minimum 56 pt, two-line row 72 pt, tappable control minimum 44x44 pt. Aim 52 pt for standalone primary actions. Food thumbnails use12 pt corners. Content grouping may use12-16 pt corners, never a different radius per item. System bars, buttons and sheets own their corner geometry.

## Navigation
Four stable labeled tabs: Today, Diary, Progress, Coach. Use independent native stacks. Keep the bar expanded for discoverability in v1. No central plus tab: actions are not destinations. Log meal sits in Today; Coach has one composer. Profile/settings opens from each root and returns to the originating section. Use native edge-swipe back.

Focused record details hide the tab bar consistently; returning restores it. Editing is a sheet with Cancel/Save. Dismiss with unsaved changes offers Keep editing / Discard changes. Canceling an editor never deletes the saved record.

## App identity
A three-bar measurement mark with a shared baseline; short/tall/medium bars evoke an M rhythm without becoming a generic heartbeat. App name Mivu. One wordmark, one symbol family. The home-screen icon is the only branded glass object; do not repeat the mark in every header. See icons.json and identity board.

## Things to reject
Glass behind every food row; glowing neon; decorative gradient backgrounds; random accent colors; dashboard tile grids for simple forms; fake health scores; streak pressure; giant empty greetings; ornamental sparklines; tiny text; mixed icon libraries; custom fake system controls; web-style sidebars on iPhone; duplicated primary actions.

## Image interpretation
All screenshots are generated concept illustrations. Native control geometry, SF Symbol glyphs and exact chart plotting must be verified in the real build. Use fixture data to render charts; never trace the generated chart pixels. Support screens documented in specs/SCREENS.md use the same reusable components even when no separate board is supplied.

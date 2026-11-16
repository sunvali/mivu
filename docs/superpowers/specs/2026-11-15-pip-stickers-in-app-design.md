# Pip stickers in the apps: design

Date: 2026-11-15. Follows the sticker pack merged in sunvali/mivu#138
([pack design](2026-11-15-pip-stickers-design.md), files in `design-system/mivu/stickers/exports/`).

## Why

The owner wants people to share Pip in WhatsApp, Messages and other chat apps. Sharing should be
friendly, low-effort and the same on both platforms. The 12 stickers already exist as checked
files. This round puts them in the apps.

## What gets built (owner's decisions)

- **Platforms:** iOS and Android in the same round.
- **Where:** a quiet **"Pip stickers"** row in Settings on both apps. It opens a sheet. No prompts
  on Today, no milestone pop-ups.
- **The sheet:**
  - A grid of all 12 stickers. The 3 animated ones play.
  - Tapping a sticker opens the system share sheet, so it works in Telegram, Signal, Mail and anywhere else.
  - Two buttons: **Add "Pip" to WhatsApp** (9 stills) and **Add "Pip moves" to WhatsApp** (3 animated).
    WhatsApp won't put still and animated stickers in the same pack.
  - On iOS only, a short line says the stickers are also in Messages, under Stickers.
- **iOS Messages:** a sticker pack extension, so all 12 show in the Messages sticker drawer.
  It has no code.

## Goals

- One tap adds a pack to WhatsApp, on both platforms.
- Any sticker can go to any app through the share sheet.
- On iPhone, Messages shows the stickers without opening Mivu.
- The stickers in the apps are byte-for-byte the checked exports from #138. No re-rendering on device.

## Non-goals

- No new stickers, art or poses. No change to the packer.
- No "pack already added" state. WhatsApp's check for that is Android-only and optional.
- No analytics, no sharing prompts, no stickers on Today or in Coach.
- No web download page, and no listing in any public sticker store.

## Anti-goals (a failure even if it works)

- A Settings change that disturbs existing rows, their identifiers or their order.
- Android reading anything from `ios/`. Android keeps its own copy of the files
  (owner rule: the two apps are decoupled).
- Publishing anything publicly. Shipping happens only through the owner's normal app release.
  Nothing goes out before the App Store launch.
- A button that silently does nothing, for example when WhatsApp is missing.

## Constraints

- **WhatsApp on iOS** (from `github.com/WhatsApp/stickers` iOS README, read 2026-11-15):
  - Put a JSON pack on `UIPasteboard`, then open `whatsapp://stickerPack`.
  - The JSON holds `identifier`, `name`, `publisher`, `tray_image` (base64 PNG) and
    `stickers[]` with `image_data` (base64 WebP), `emojis` (1–3) and `accessibility_text`.
  - Animated stickers must be WebP.
  - `whatsapp` goes in `LSApplicationQueriesSchemes`.
  - Only one pack can be sent at a time, which is another reason for two buttons.
  - The builder should copy the exact pasteboard type and the animated flag from WhatsApp's
    official iOS sample. The README doesn't spell them out.
- **WhatsApp on Android:** follow the official sample:
  - A `ContentProvider` that serves the pack metadata and files.
  - The `com.whatsapp.intent.action.ENABLE_STICKER_PACK` intent with the pack id, authority and name.
  - `<queries>` for `com.whatsapp` and `com.whatsapp.w4b`.
  - WebP files left uncompressed in the APK (`noCompress`).
- **Limits** are already met by the exports and enforced by `check.py`: 512 px, 100 KB still,
  500 KB animated, 96 px tray.
- **Identifiers** stay as already exported: `mivu-pip-still` and `mivu-pip-animated`.
- **Accessibility:**
  - Every sticker gets `accessibility_text` in the WhatsApp payload, and a VoiceOver/TalkBack
    label in the grid. Both come from one short description per sticker, for example "Pip waving hello".
  - Animations show their first frame under Reduce Motion or Android's animator-off setting.
  - Targets are at least 44 pt (48 dp on Android). Dynamic Type works in the sheet.
- **English only:** iOS strings go in the existing `.xcstrings`.
- **Tests:** synthetic only, focused runs, per AGENTS.md and the owner's targeted-test rule.
  New native code gets a failing test first.

## Builder's calls (made by me, the designer; the owner can override)

1. **Settings placement:**
   - iOS: the row goes in the existing companion section of `SettingsView`
     (`ios/Mivu/Diary/SettingsView.swift`), next to the Pip choice.
   - Android: the matching place in `SettingsScreen.kt`.
   - The row shows even before a profile exists.
2. **WhatsApp missing:** each Add button stays visible. Tapping it explains that WhatsApp isn't
   installed and offers its store page. Grid sharing works as normal.
3. **Share file:** stills share the 512 px PNG from `exports/png`. Animated stickers share the GIF
   from `exports/gif`, the one format every chat app animates.
4. **Bundled files:**
   - iOS bundles `exports/whatsapp/*` and `exports/png` / `exports/gif`.
   - The Messages extension bundles `exports/imessage` in its sticker catalog.
   - Android copies the same set into `android/app/src/main/assets/stickers/`.
   - A small script or README step refreshes both copies from `exports/`.
   - A test fails if a copy drifts from the export (hash compare).
5. **Grid animation:** use the platform image decoders: ImageIO's animated image API on iOS, and
   `ImageDecoder`/`AnimatedImageDrawable` on Android (minSdk is 31). No new dependencies.
6. **Messages extension:**
   - Display name "Pip by Mivu".
   - Its icon set is rendered from the existing Pip art, same look as the stickers.
   - It ships inside the next app version.
7. **Optional WhatsApp fields:**
   - `publisher_website` and `privacy_policy_website` use the existing `MivuLinks` URLs, where WhatsApp accepts them.
   - `ios_app_store_link` and `android_play_store_link` stay empty until the store pages are public.
8. **Extension identity and signing:**
   - Bundle ID: `<app bundle id>.Stickers`.
   - Same team and automatic signing as the app and the widget extension.
   - Same deployment target as the app.
   - The signed archive is checked in the owner's normal local release step, not in this PR.
9. **Payload metadata:**
   - "Byte-for-byte" covers the image files only.
   - Each app builds the WhatsApp payload at runtime from the exported `contents.json` (order, emoji,
     identifiers) and the exported images.
   - It adds its own fields on top: the accessibility text and the website fields. These come from one
     small sticker-description list per app, and the two lists hold the same words.
   - `pack.py` stays unchanged.
10. **Tests:**
   - A unit test for the iOS pasteboard payload: fields, base64 that round-trips, emoji counts, the animated flag.
   - A unit test for the Android provider's metadata and file listing.
   - A drift test for the bundled copies.
   - One focused UI test per platform: Settings row → sheet → buttons present.
   - No full UI suite unless the owner asks.

## Left to the builder

- Code structure, file names, and how the sticker list is shared between the sheet and the payload.
- The exact grid layout and spacing, following Apple HIG and the app's existing sheet style.
- How the store link opens when WhatsApp is missing.

## Not verified

- The exact WhatsApp iOS pasteboard type and animated flag. Take them from the official sample, not memory.
- Apple's current limits for sticker extensions (408 px, 500 KB per file). These weren't re-checked online in #138.
- A real import on a phone with WhatsApp installed. Simulators don't have WhatsApp,
  so the owner's device check is the only true end-to-end test.

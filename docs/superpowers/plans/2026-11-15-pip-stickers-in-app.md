# Pip Stickers in the Apps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On iOS and Android, a "Pip stickers" row in Settings opens a sheet. The sheet shares any sticker through the system share sheet and adds either pack to WhatsApp. On iPhone the stickers also appear in the Messages drawer.

**Architecture:**
- The checked exports from #138 are copied unchanged into each app. One script, `sync.py`, does the copying and also checks the copies for drift.
- Each app has a small sticker list holding id, accessibility text and whether the sticker is animated. Emoji and pack identifiers come from the copied pack JSON.
- iOS hands a pack to WhatsApp through `UIPasteboard`. Android uses an exported read-only `ContentProvider`.
- The Messages extension is a no-code sticker-pack target.

**Tech Stack:**
- iOS: SwiftUI, UIKit (`UIPasteboard`, `UIActivityViewController`), ImageIO (`CGAnimateImageAtURLWithBlock`).
- Android: Jetpack Compose, `ContentProvider`, `ImageDecoder` / `AnimatedImageDrawable`, the existing `FileProvider`.
- Python 3 from the repo `.venv`, for the copy and drift check.

**Spec:** `docs/superpowers/specs/2026-11-15-pip-stickers-in-app-design.md`

## Global Constraints

- Android never reads anything from `ios/`. It keeps its own copies under `android/app/src/main/assets/stickers/`.
- The image files are byte-for-byte the files in `design-system/mivu/stickers/exports/`. `pack.py` is not changed.
- Pack identifiers are `mivu-pip-still` (name "Pip") and `mivu-pip-animated` (name "Pip moves"). The publisher is "Mivu".
- `publisher_website` is `https://mivuapp.com` and `privacy_policy_website` is `https://mivuapp.com/privacy`. The store-link fields stay empty.
- No new dependencies on either platform.
- Settings: existing rows, their accessibility identifiers and their order stay unchanged. The new row is added, nothing is moved.
- Accessibility:
  - Every sticker has accessibility text, and the same text is its VoiceOver/TalkBack label.
  - Under Reduce Motion (iOS) or animator scale 0 (Android), only the first frame shows.
  - Targets are at least 44 pt / 48 dp, and Dynamic Type works.
- English only. iOS strings go in `ios/Mivu/Localizable.xcstrings`.
- Tests use synthetic data only. Run focused tests, never the full UI suite. Write a failing test before native behaviour code.
- Nothing is published. Shipping happens only through the owner's normal release.
- Commits and PR use Conventional Commit titles and contain no assistant or AI wording.
- Prefix shell commands with `rtk`.
- The pre-push hook needs `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"` and `ANDROID_HOME=$HOME/Library/Android/sdk`.

Sticker accessibility text, used on both platforms with these exact words:

| id | text |
|---|---|
| hi | Pip waving hello |
| thanks | Pip saying thank you |
| love-it | Pip hugging a fluffy tail, with hearts |
| lol | Pip laughing |
| ok | Pip winking with a paw raised |
| oops | Pip blushing, oops |
| good-night | Pip curled up asleep |
| yum | Pip enjoying a salad bowl |
| hungry | Pip holding an empty bowl |
| hydrate | Pip sipping water |
| snack | Pip holding up an apple |
| you-got-it | Pip cheering and hopping |

UI copy, with these exact words on both platforms:
- Row: `Pip stickers`.
- Sheet title: `Pip stickers`.
- Hint: `Tap a sticker to share it.`
- Buttons: `Add “Pip” to WhatsApp` and `Add “Pip moves” to WhatsApp`.
- iOS only, under the buttons: `Also in Messages: tap + then Stickers.`
- Missing-WhatsApp alert: title `WhatsApp isn't installed`, message `Install WhatsApp to add Pip stickers.`, buttons `Get WhatsApp` and `Cancel`.

## Review Focus

1. **WhatsApp missing.** Tapping an Add button shows the alert, and `Get WhatsApp` opens the store page. It never does nothing.
   Pinned in Task 3 (iOS: `canOpenURL` false → alert state) and Task 6 (Android: package not visible → alert).
2. **A bad or hostile provider URI.**
   - The Android provider is exported, so any app can query it.
   - An unknown pack id or a path such as `../fndds.sqlite` must return nothing, or throw `FileNotFoundException`.
   - It must never open a file outside `assets/stickers/`.
   - Pinned in Task 5.
3. **Clipboard leaking.** The iOS payload must stay off Universal Clipboard and must expire. Use the `.localOnly` option and a 60 s `.expirationDate`.
   Pinned in Task 2 (the options returned with the payload).
4. **Reduce Motion.** The grid shows a still first frame for the 3 animated stickers.
   Pinned in Task 3 and Task 6 (the view exposes whether it is animating).
5. **Stale copies.** Re-exporting the stickers without syncing must fail a test, not ship old art.
   Pinned in Task 1 (`sync.py --check` inside `test_pack.py`).

---

### Task 1: Bundled copies and drift check

**Files:**
- Create: `design-system/mivu/stickers/sync.py`
- Modify: `design-system/mivu/stickers/test_pack.py`, `design-system/mivu/stickers/README.md`, `android/app/build.gradle.kts` (`noCompress`)
- Create (generated by the script, committed):
  - `ios/Mivu/Resources/Stickers/*`
  - `android/app/src/main/assets/stickers/*`
  - `ios/MivuStickers/Stickers.xcstickers/Sticker Pack.stickerpack/<id>.sticker/<id>.png`

**Interfaces:**
- Produces: a flat folder layout, the same in both apps.
  - `<id>.webp`: all 12 stickers, from `whatsapp/still|animated/`.
  - `<id>.png`: the 9 stills, from `png/`.
  - `<id>.gif`: the 3 animated stickers, from `gif/`.
  - `tray.png`: from `whatsapp/still/tray.png`. The two trays are identical; the script asserts it.
  - `pip-still.json` and `pip-animated.json`: the two `contents.json` files.
  - The iMessage `<id>.png` files go only into the Messages sticker pack.
- Produces: `sync.copies(exports: Path, repo: Path) -> list[tuple[Path, Path]]`, `sync.drift(exports, repo) -> list[str]`, and the CLI `sync.py [--check]`.

- [ ] **Step 1: Failing test.** In `test_pack.py`, add `SyncTests.test_bundled_copies_match_exports`:
  - It calls `sync.drift(EXPORTS, REPO)` and asserts the result equals `[]`.
  - Add `test_drift_names_a_changed_copy`: copy the exports to a temp repo tree, sync it, flip one byte in the temp Android `ok.webp`, and assert that a drift line names `ok.webp`.
- [ ] **Step 2:** Run `rtk .venv/bin/python design-system/mivu/stickers/test_pack.py`. Expect FAIL (`No module named sync`).
- [ ] **Step 3: Write `sync.py`.**
  - `copies()` lists (source, destination) pairs for the iOS app folder, the Android assets folder and the Messages sticker pack.
  - `drift()` compares sha256 values and reports missing or changed files, plus extra files in the destination folders.
  - Without `--check`, the CLI copies the files. With `--check`, it exits 1 on drift.
  - Each `.sticker` folder needs a `Contents.json`: `{"info":{"author":"xcode","version":1},"properties":{"filename":"<id>.png"}}`. The pack's `Contents.json` lists the 12 stickers in `LINEUP` order. The script writes these and leaves the iconset alone.
- [ ] **Step 4:** Run `rtk .venv/bin/python design-system/mivu/stickers/sync.py`, then the test file. Expect PASS (12 + 2 tests).
- [ ] **Step 5:**
  - Add `noCompress += "webp"` next to the existing `"sqlite"` in `android/app/build.gradle.kts`; WhatsApp opens the files through `openAssetFd`.
  - Add a `sync.py` step to the README rebuild block.
- [ ] **Step 6: Commit** `feat(stickers): bundle the sticker exports in both apps`.

### Task 2: iOS sticker list and WhatsApp payload

**Files:**
- Create: `ios/Mivu/Stickers/PipStickers.swift`, `ios/MivuTests/PipStickersTests.swift`
- Modify: `ios/Config/Info.plist` (add `LSApplicationQueriesSchemes`: `whatsapp`)

**Interfaces:**
- Produces:
  ```swift
  struct PipStickerItem: Identifiable { let id: String; let accessibilityText: String; let animated: Bool
      var shareURL: URL? { get }   // bundled <id>.png or <id>.gif
  }
  enum PipStickers {
      static let all: [PipStickerItem]               // lineup order, texts from Global Constraints
      static let pasteboardType: String              // copied from WhatsApp's official iOS sample
      static func whatsAppPayload(animated: Bool, bundle: Bundle = .main) throws -> Data
      static func sendToWhatsApp(animated: Bool) throws -> Bool   // false when WhatsApp can't be opened
  }
  ```

- [ ] **Step 1: Take the exact pasteboard type and payload keys from WhatsApp's official sample.**
  - Fetch `https://github.com/WhatsApp/stickers` → `iOS/` → the interoperability / sticker-pack source files.
  - Record the pasteboard type string and the JSON key for the animated flag.
  - Record any keys missing from the spec's list.
  - Put the source URL in a one-line comment above `pasteboardType`.
- [ ] **Step 2: Failing test `whatsAppPayloadMatchesThePack` in `PipStickersTests` (Swift Testing).** For both packs, decode the JSON and assert:
  - `identifier` and `name` match the Global Constraints.
  - `publisher == "Mivu"`.
  - The website fields are as given.
  - The sticker count is 9 or 3.
  - Each `image_data` base64-decodes to bytes equal to the bundled `<id>.webp`, which starts with `RIFF`.
  - `emojis.count` is in 1...3.
  - `accessibility_text` equals `PipStickers.all` text.
  - The animated flag is correct.
  - `tray_image` decodes to a 96×96 PNG.
- [ ] **Step 3: Test `stickerListMatchesTheLineup`.** Ids in order, as in `pip-still.json` + `pip-animated.json`, and each `shareURL` is non-nil.
- [ ] **Step 4: Test `pasteboardStaysLocalAndExpires`.**
  - Factor the pasteboard options into `static func pasteboardOptions(now: Date) -> [UIPasteboard.OptionsKey: Any]`.
  - Assert `.localOnly == true` and `.expirationDate == now + 60`.
- [ ] **Step 5:** Run `xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu -destination 'platform=iOS Simulator,name=iPhone Air' -only-testing:MivuTests/PipStickersTests`. Expect FAIL: it doesn't compile.
  - Run `xcrun simctl bootstatus <id> -b` first if the simulator reports Busy.
- [ ] **Step 6: Implement.**
  - The payload reads the bundled `pip-*.json` (order, emoji, identifier), base64-encodes the bundled files, and adds the accessibility text and website fields.
  - `sendToWhatsApp`:
    1. Returns false when `canOpenURL(whatsapp://stickerPack)` fails.
    2. Otherwise calls `UIPasteboard.general.setItems([[pasteboardType: data]], options: pasteboardOptions(now: .now))`.
    3. Opens the URL and returns true.
- [ ] **Step 7:** Run the tests again. Expect PASS (3).
- [ ] **Step 8: Commit** `feat(stickers): WhatsApp sticker handoff on iOS`.

### Task 3: iOS sheet and Settings row

**Files:**
- Create: `ios/Mivu/Stickers/PipStickerSheet.swift`, `ios/MivuUITests/PipStickerUITests.swift`
- Modify:
  - `ios/Mivu/Diary/SettingsView.swift`: add the row at the end of `companionSection`, outside the `if`, so it shows with or without a chooser and before a profile exists.
  - `ios/Mivu/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PipStickers.all`, `PipStickerItem.shareURL`, `PipStickers.sendToWhatsApp(animated:)` from Task 2.
- Produces: `struct PipStickerSheet: View`. Accessibility identifiers:
  - `pipStickers` (the Settings row)
  - `pipSticker-<id>` (each grid cell)
  - `addPipToWhatsApp`, `addPipMovesToWhatsApp`
  - `whatsAppMissing` (the alert)

- [ ] **Step 1: Failing UI test `testStickerSheetOpensFromSettings`.**
  - Launch with the existing UI-test fixture used by `CompanionUITests`.
  - Open Settings, tap `pipStickers`, and assert there are 12 `pipSticker-*` buttons and that both add buttons exist.
  - Tap `addPipToWhatsApp`. The simulator has no WhatsApp, so assert the `whatsAppMissing` alert shows `Get WhatsApp` and `Cancel`.
  - Tap `Cancel`.
- [ ] **Step 2:** Run `-only-testing:MivuUITests/PipStickerUITests`. Expect FAIL (no `pipStickers`).
- [ ] **Step 3: Implement the row.** Use `settingsRow(String(localized: "Pip stickers"), symbol: "face.smiling", color: .diaryProtein)` inside a `Button` that presents the sheet.
- [ ] **Step 4: Implement the sheet.**
  - A `NavigationStack` with the title, a `LazyVGrid` of 4 adaptive columns (minimum cell 72 pt), the hint, the two buttons (`.borderedProminent` and `.bordered`) and the Messages line.
  - Each cell is a `ShareLink(item: shareURL)` labelled with the accessibility text.
  - Animated cells draw with `CGAnimateImageAtURLWithBlock` on the bundled GIF.
  - Under `accessibilityReduceMotion`, cells show the first frame through `CGImageSourceCreateImageAtIndex(…, 0)`.
  - The add buttons call `sendToWhatsApp`. On false, they show the alert. `Get WhatsApp` opens `https://apps.apple.com/app/id310633997`.
  - Expose `.accessibilityValue("animated")` only while a cell is animating, for the Reduce Motion check.
- [ ] **Step 5: Add test `testReduceMotionShowsStillStickers`.**
  - Launch with the `-UIAccessibilityReduceMotionEnabled YES` launch argument.
  - Open the sheet and assert `pipSticker-hi` has no `animated` value.
- [ ] **Step 6:** Run both UI tests. Expect PASS (2).
  - Also run the existing `MivuUITests/CompanionUITests/testSettingsReturnKeepsCoachSendReachable` to catch Settings regressions. Expect PASS.
- [ ] **Step 7: Look at it.** Take simulator screenshots of the sheet at default size and at accessibility XL text size, in light and dark mode. Fix clipping and overlap.
  - The bar is Apple-level polish.
- [ ] **Step 8: Commit** `feat(stickers): Pip stickers sheet in iOS Settings`.

### Task 4: iOS Messages sticker extension

**Files:**
- Create: `ios/MivuStickers/Stickers.xcstickers/iMessage App Icon.stickersiconset/*`, `ios/Config/Stickers.xcconfig`, `ios/Config/Stickers-Info.plist`
- Modify: `ios/Mivu.xcodeproj/project.pbxproj`
  - A new target `MivuStickers`, product type `com.apple.product-type.app-extension.messages-sticker-pack`.
  - Embedded in `Mivu` through the existing "Embed App Extensions" copy phase that the widget uses.

**Interfaces:**
- Consumes: the sticker pack folder from Task 1.
- Produces: `MivuStickers.appex`, bundle ID `com.yakov103.mivu.Stickers`, display name `Pip by Mivu`, deployment target 26.0, the same team and automatic signing as `MivuWidgets` (inherited through `Shared.xcconfig`).

- [ ] **Step 1: Render the icon set** from the `hi` sticker's first frame (`exports/png` doesn't hold it, so use `exports/gif/hi.gif` frame 0) on the cream app background.
  - Produce every size the `stickersiconset` asks for, including 1024×768 for the App Store, with a short Python script in the scratchpad. Don't commit the script.
  - Commit the PNGs and `Contents.json`.
- [ ] **Step 2: Add the target, config and plist.**
  - `Stickers.xcconfig` includes `Shared.xcconfig`, sets `PRODUCT_BUNDLE_IDENTIFIER = com.yakov103.mivu.Stickers` and `INFOPLIST_KEY_CFBundleDisplayName = Pip by Mivu`, and copies `SKIP_INSTALL` from `Widgets.xcconfig`.
  - The plist's `NSExtension` has `NSExtensionPointIdentifier` = `com.apple.message-payload-provider` and `NSExtensionPrincipalClass` = `StickerBrowserViewController`.
- [ ] **Step 3: Verify.**
  - `xcodebuild build -project ios/Mivu.xcodeproj -scheme Mivu -destination 'platform=iOS Simulator,name=iPhone Air'` succeeds.
  - `ls` of the built `Mivu.app/PlugIns/` shows `MivuStickers.appex` with 12 stickers.
  - Install on the simulator, open Messages, start a new message → + → Stickers, and take a screenshot of the pack.
- [ ] **Step 4:** Run the Task 2 and Task 3 tests again. Expect PASS. This confirms the project edit broke nothing.
- [ ] **Step 5: Commit** `feat(stickers): Messages sticker pack extension`.

### Task 5: Android sticker list and WhatsApp provider

**Files:**
- Create:
  - `android/app/src/main/java/com/yakov103/mivu/stickers/PipStickers.kt`
  - `android/app/src/main/java/com/yakov103/mivu/stickers/PipStickerProvider.kt`
  - `android/app/src/androidTest/java/com/yakov103/mivu/stickers/PipStickerProviderTest.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
  - A `<provider>` with authority `${applicationId}.stickers`, `exported="true"`, and read-only use.
  - `<queries>`: `<package android:name="com.whatsapp"/>` and `<package android:name="com.whatsapp.w4b"/>`.

**Interfaces:**
- Produces:
  ```kotlin
  data class PipStickerItem(val id: String, val accessibilityText: String, val animated: Boolean) {
      val shareAsset: String   // "stickers/<id>.png" or "stickers/<id>.gif"
  }
  object PipStickers {
      val all: List<PipStickerItem>                                  // texts from Global Constraints
      fun enableIntent(context: Context, animated: Boolean): Intent  // com.whatsapp.intent.action.ENABLE_STICKER_PACK
      fun whatsAppInstalled(context: Context): Boolean
  }
  ```
- Produces: provider URIs and column names copied from WhatsApp's official Android sample `StickerContentProvider`:
  - `metadata`
  - `metadata/<id>`
  - `stickers/<id>`
  - `stickers_asset/<id>/<file>`

- [ ] **Step 1: Copy the URI matcher paths and column names exactly** from `https://github.com/WhatsApp/stickers` → `Android/app/src/main/java/.../StickerContentProvider.java`, with the URL in a comment.
- [ ] **Step 2: Failing instrumented test `PipStickerProviderTest`.**
  - `metadataListsBothPacks`: query `metadata` and assert 2 rows. Assert the identifiers, names, publisher, websites, and the `animated_sticker_pack` values 0 and 1.
  - `stickersCarryEmojiAndAccessibilityText`: query `stickers/mivu-pip-still` and assert 9 rows in lineup order. Each row has 1–3 emoji, and its accessibility text equals `PipStickers.all`.
  - `assetsOpenOnlyInsideStickers`:
    - `openAssetFile` on `stickers_asset/mivu-pip-still/ok.webp` returns the same bytes as `assets/stickers/ok.webp`.
    - `stickers_asset/mivu-pip-still/../fndds.sqlite`, `stickers_asset/nope/ok.webp` and a file from the wrong pack (`hi.webp` in the still pack) each throw `FileNotFoundException`.
  - `stickerListMatchesTheLineup`: the ids in order, and each `shareAsset` opens.
- [ ] **Step 3:** Run with an emulator booted: `cd android && ./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.stickers.PipStickerProviderTest`. Expect FAIL: it doesn't compile.
- [ ] **Step 4: Implement.**
  - The provider parses `assets/stickers/pip-still.json` and `pip-animated.json` with `org.json`, adds the accessibility text and website fields, and serves rows through `MatrixCursor`.
  - Assets are served only when the file name appears in that pack's `stickers` list or equals its `tray_image_file`.
  - `insert`, `update` and `delete` throw `UnsupportedOperationException`.
- [ ] **Step 5:** Run again. Expect PASS (4).
- [ ] **Step 6: Commit** `feat(stickers): WhatsApp sticker provider on Android`.

### Task 6: Android sheet and Settings row

**Files:**
- Create:
  - `android/app/src/main/java/com/yakov103/mivu/ui/settings/PipStickerSheet.kt`
  - `android/app/src/androidTest/java/com/yakov103/mivu/ui/settings/PipStickerSheetTest.kt`
- Modify:
  - `android/app/src/main/java/com/yakov103/mivu/ui/settings/SettingsScreen.kt`: add the row in the Setup card, right after `Redo setup with Pip`, and keep the existing rows.
  - `android/app/src/main/res/xml/report_paths.xml`: add `<cache-path name="stickers" path="stickers/" />`, and update its comment.
  - A drawable for the row icon, matching the existing `ic_*` style.

**Interfaces:**
- Consumes: `PipStickers` from Task 5. The existing `FileProvider` authority is `${applicationId}.reports`.
- Produces: `@Composable fun PipStickerSheet(onDismiss: () -> Unit)`, a `ModalBottomSheet`. Test tags:
  - `pipStickers` (the Settings row)
  - `pipSticker-<id>`
  - `addPipToWhatsApp`, `addPipMovesToWhatsApp`
  - `whatsAppMissing`

- [ ] **Step 1: Failing Compose test `sheetShowsStickersAndHandlesMissingWhatsApp`.**
  - Set `SettingsScreen` content and click `pipStickers`.
  - Assert 12 `pipSticker-*` nodes, each with its accessibility text as content description, and both add buttons.
  - Click `addPipToWhatsApp`. The emulator has no WhatsApp, so assert that `whatsAppMissing` shows `Get WhatsApp` and `Cancel`.
- [ ] **Step 2: Test `reducedMotionShowsStillStickers`.**
  - Make the animation choice a parameter: `PipStickerSheet(onDismiss, animate: Boolean = animatorsEnabled())`.
  - Set `animate = false` and assert `pipSticker-hi` has no `stateDescription` of "animated". The sheet sets that only while a GIF drawable is running.
- [ ] **Step 3:** Run `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.yakov103.mivu.ui.settings.PipStickerSheetTest`. Expect FAIL.
- [ ] **Step 4: Implement.**
  - The grid uses `LazyVerticalGrid(GridCells.Adaptive(72.dp))`.
  - Animated cells use an `AndroidView` `ImageView` with an `AnimatedImageDrawable` from `ImageDecoder.createSource(assets, "stickers/<id>.gif")`. It is started only when `animate` is true.
  - `animatorsEnabled()` reads `Settings.Global.ANIMATOR_DURATION_SCALE != 0f`.
  - Tapping a cell copies the asset to `cacheDir/stickers/` and sends `ACTION_SEND` with the `FileProvider` URI, `image/png` or `image/gif`, and read permission.
  - Each add button:
    - If WhatsApp is installed, launches `enableIntent` with `startActivity`. It catches `ActivityNotFoundException` and shows the alert.
    - Otherwise shows the alert. `Get WhatsApp` opens `market://details?id=com.whatsapp`, falling back to `https://play.google.com/store/apps/details?id=com.whatsapp`.
- [ ] **Step 5:** Run the sheet tests and the existing `OnDeviceSettingsTest`. Expect PASS.
- [ ] **Step 6: Look at it.** Take emulator screenshots at default size and at the largest font size, in light and dark mode, and fix any issues.
- [ ] **Step 7: Commit** `feat(stickers): Pip stickers sheet in Android Settings`.

### Task 7: Docs and wrap-up

**Files:** `design-system/mivu/stickers/README.md`, `.agents/skills/mivu-animation/SKILL.md` (only if it lists sticker owners)

- [ ] **Step 1: Update the README.**
  - Add a short "In the apps" section: where the copies live, that `sync.py` refreshes them, and that the drift test enforces them.
  - Name the owners: `PipStickers.swift`, `PipStickerSheet.swift`, `MivuStickers` target, `PipStickers.kt`, `PipStickerProvider.kt`, `PipStickerSheet.kt`.
- [ ] **Step 2: Run the final focused set.**
  - `test_pack.py`
  - `PipStickersTests`
  - `PipStickerUITests`
  - `PipStickerProviderTest`
  - `PipStickerSheetTest`
  - Record the SHA and counts in the PR body.
- [ ] **Step 3: Commit** `docs(stickers): in-app sticker owners`.
- [ ] **Step 4:** Run Ponytail Review on the branch, then push and open the PR. State that the true end-to-end check is a real WhatsApp import on the owner's phone.

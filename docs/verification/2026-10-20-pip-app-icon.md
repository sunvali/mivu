# Pip app icon verification — 2026-10-20

Owner revised the selected Pip portrait on 2026-10-20 to remove all lettering,
using the Home Screen's Mivu label for the app name. Current source master:
`output/imagegen/mivu-pip-icon/no-text/icon-default.png` in the parent workspace.
The former wordmark version is archived in that workspace under
`output/imagegen/mivu-pip-icon/with-wordmark/`. All three current appearances use
the same text-free head-and-shoulders composition. Source hashes and complete
prompts are recorded in `design-system/mivu/precision-glass/icon/provenance.json`.

## Checks

- All three catalog images: 1024 × 1024, 8-bit RGB PNG, no alpha channel,
  embedded sRGB IEC61966-2.1 profile. Catalog references match supplied files.
- Re-running the documented renderer produces identical SHA-256 hashes.
- XcodeBuildMCP simulator build: succeeded after the text-free asset update,
  zero reported warnings/errors. Build log: `build_sim_2026-10-20T16-30-24-300Z_pid27223_cdd5e318.log`.
  iPhone 17e, iOS 27.0, Debug, signing disabled for simulator; base revision
  `f771cc3e68cbda33340e86cd80bbaf9d22eecd27` plus local icon changes and concurrent
  work in the shared checkout. This is working-tree evidence, not clean-revision
  release acceptance.
- Installed in an iPhone 17e simulator and reviewed on the actual Home Screen.
  Default, Dark, Tinted (neutral gray) and system-derived Clear were selected
  through native Home Screen customization. Pip's face, ear tips and scarf fit
  the system mask and remain recognizable beside system icons. No lettering is
  baked into the icon; the native Mivu label remains beneath it.
- Default icons remain visible when only interface dark mode changes; selecting
  Dark icon styling uses the custom dark asset, as intended by iOS customization.
- No physical iPhone installation, App Store upload, full native unit suite, or
  custom layered Icon Composer acceptance is claimed for this asset-only change.
  Colored user tints were not separately exercised; the neutral tinted style was.

## Native Home Screen screenshots

- [Default](pip-app-icon/home-light.jpg)
- [Dark](pip-app-icon/home-dark-icon.jpg)
- [Tinted](pip-app-icon/home-tinted-icon.jpg)
- [System-derived clear](pip-app-icon/home-clear-icon.jpg)

## Export hashes

- `AppIcon-dark.png`: `7bebaffa9cbad99e7592ea4c22d19526d3cdd9dea3ea718ee7a352729aca68b9`
- `AppIcon-tinted.png`: `a1e3a01318c856323825d6b612f5a677a998c5387645bc35721f9312d4f2d275`
- `AppIcon.png`: `e2fdd00c0c5dfad95bbac9bc7b26702a7ad784f671ebc9c19862b6330f2f9b7d`

## Apple references

- [App icon design guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Configuring app icons using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)

The existing asset catalog provides the three custom appearances. Clear uses
system derivation; there is no new layered `.icon` file or baked corner mask.

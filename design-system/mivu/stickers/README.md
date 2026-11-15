# Pip stickers

Twelve text-free Pip stickers (nine still, three animated) for WhatsApp, iMessage and
anywhere else. Design: [spec](../../../docs/superpowers/specs/2026-11-15-pip-stickers-design.md).

The poses live in `ios/MivuTests/PipStickerCatalog.swift` and are drawn by the app's own
rig (`PipRigView`), so a sticker always matches the Pip in the app. The z's for *Good night*
are `fx-z-*@curled` parts in `../characters/pip/rig/pip.svg`.

## Rebuild

```sh
mkdir -p build/pip-stickers/frames                      # turns the frame export on
xcodebuild test -project ios/Mivu.xcodeproj -scheme Mivu -testPlan Mivu \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  -only-testing:MivuTests/PipStickerExportTests         # writes build/pip-stickers/frames/<id>/
.venv/bin/python design-system/mivu/stickers/pack.py build/pip-stickers/frames design-system/mivu/stickers/exports
.venv/bin/python design-system/mivu/stickers/check.py design-system/mivu/stickers/exports
```

`pack.py` needs `pillow`, `numpy` and `opencv-python-headless` in the repo `.venv`.
Tests: `.venv/bin/python design-system/mivu/stickers/test_pack.py` (synthetic images only).

## Exports

| Folder | What | Use |
|---|---|---|
| `exports/whatsapp/still/` | 512 px WebP stills, `tray.png`, `contents.json` | WhatsApp pack *Pip* |
| `exports/whatsapp/animated/` | 512 px animated WebP, `tray.png`, `contents.json` | WhatsApp pack *Pip moves* (WhatsApp keeps still and animated packs apart) |
| `exports/imessage/` | 408 px PNG (stills) and APNG (animated, `.png`) | a Messages sticker pack |
| `exports/png/`, `exports/gif/` | 512 px PNG stills, GIF animations | anywhere else |

Every sticker gets a 14 px white die-cut outline (at the rig's 512 artboard) and a 16 px
margin. An animated sticker uses one crop for all its frames. If a file goes over a size
limit, `pack.py` first lowers the quality and then drops every other frame.

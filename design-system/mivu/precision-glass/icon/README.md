# Mivu app icon source

The owner-selected icon is Pip's illustrated portrait, revised on 2026-10-20
without lettering because the Home Screen label supplies the app name. The three
`icon-*.png` files are its source masters. Default uses a pale background; dark
preserves Pip's orange/cream fur and teal scarf on a charcoal background; tinted
supplies neutral grayscale artwork on a dark background for the system's tint.
See `provenance.json` for source hashes and complete generation prompts.

The older three-bar SVG concepts remain historical references; the renderer
does not consume them.

Render the catalog PNGs from the repository root with:

```sh
swift -module-cache-path /private/tmp/mivu-icon-swift-cache design-system/mivu/precision-glass/icon/render-icons.swift
```

The Swift/AppKit renderer resamples each source master to an opaque, alpha-free
1024 × 1024 sRGB PNG. Preserve the source masters when regenerating. The App
Icon asset catalog declares default, dark and tinted appearances without
pre-rounding the canvas or adding a shadow; iOS owns the icon mask.

The catalog does not provide a custom clear-appearance layer stack. A clear
icon can use the native system-derived appearance from the supplied variants;
custom foreground/background layering remains future Icon Composer work.

Review Pip's ears, face and scarf through the system mask at small
home-screen sizes in each appearance. Light/dark icon choices are controlled by
Home Screen customization and can differ from the app's interface appearance.

# Mivu app icon source

The three SVG files are original flat vector artwork for the Mivu measurement
mark: short, tall and medium rounded bars share a baseline. They use the
approved Precision Glass colors for default and dark appearances; the tinted
version uses two neutral grays so the system can apply its tint treatment.

Render the catalog PNGs from the repository root with:

```sh
swift -module-cache-path /private/tmp/mivu-icon-swift-cache design-system/mivu/precision-glass/icon/render-icons.swift
```

The Swift/AppKit renderer loads each SVG as a vector image and rasterizes it to
an opaque 1024 × 1024 PNG. The SVG files remain the editable source. The App
Icon asset catalog declares default, dark and tinted appearances without
pre-rounding the canvas or adding a shadow; iOS owns the icon mask.

The catalog does not provide a custom clear-appearance layer stack. A clear
icon can use the native system-derived appearance from the supplied variants;
custom foreground/background layering remains future Icon Composer work.

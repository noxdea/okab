---
title: Graphics and images
description: Draw vector paths, scope graphics state, and embed PNG and JPEG images.
---

Start with a document and a page. The examples below share these variables:

```ruby
require "okab"

document = Okab::Document.new(title: "Graphics")
page = document.page(width: 595, height: 842)
```

Coordinates and line widths use PDF points. RGB colors contain three values
between `0` and `1`. See [getting started](index.md#understand-page-coordinates)
for the lower-left coordinate system.

<details class="guide-toc" open markdown="1">
<summary>On this page</summary>

* Table of contents
{:toc}

</details>

## Draw and paint paths

Path commands build geometry; a paint command fills or strokes it. Rectangles,
ellipses, lines, and cubic Bézier curves are supported:

```ruby
page.rect(48, 650, 180, 80).fill([0.1, 0.4, 0.7])
page.ellipse(280, 650, 120, 80).stroke([0.1, 0.4, 0.7], width: 2)
page.move_to(48, 620).line_to(400, 620)
  .stroke([0.2, 0.2, 0.2], width: 1, dash: [6, 3])

path = Okab::Path.new.move_to(48, 560)
  .curve_to(100, 640, 180, 480, 240, 560)
  .line_to(240, 520).line_to(48, 520).close
page.path(path).fill([0.3, 0.6, 0.8])
```

Painting consumes the current path. Build it again to paint it a second time,
or use `fill_and_stroke(color, width: 1)` to fill and stroke with the same color.
`fill` accepts `rule: :nonzero` (default) or `:evenodd` for overlapping contours.

`stroke` supports:

| Option | Values | Default |
| --- | --- | --- |
| `width` | Positive number in points | `1` |
| `cap` | `:butt`, `:round`, `:square` | `:butt` |
| `join` | `:miter`, `:round`, `:bevel` | `:miter` |
| `miter` | Positive miter limit | `10` |
| `dash` | Array of positive lengths, or `nil` for a solid line | `nil` |

## Clip drawing to a shape

`with_clip` confines drawing to an `Okab::Path` for the duration of the block
and restores the previous graphics state afterward:

```ruby
clip = Okab::Path.new.ellipse(48, 380, 180, 100)
page.with_clip(clip) do |p|
  p.rect(48, 380, 180, 100).fill([0.1, 0.4, 0.7])
  p.rect(48, 380, 90, 100).fill([0.2, 0.7, 0.6])
end
```

Use `rule: :evenodd` for an even-odd clip. Prefer `with_clip` for scoped
drawing; the lower-level `clip { |path| ... }` API keeps the clip active until
the end of the page.

## Translate, scale, and rotate

`transform(a, b, c, d, e, f)` applies the PDF affine matrix within a block:
`x' = a*x + c*y + e`, `y' = b*x + d*y + f`.

```ruby
# Move the local origin to (300, 380).
page.transform(1, 0, 0, 1, 300, 380) do |p|
  p.rect(0, 0, 100, 100).stroke([0.1, 0.4, 0.7], width: 2)
end

# Rotate 30 degrees counterclockwise around the local origin.
angle = Math::PI / 6
page.transform(Math.cos(angle), Math.sin(angle),
  -Math.sin(angle), Math.cos(angle), 100, 240) do |p|
  p.rect(0, 0, 120, 40).fill([0.2, 0.7, 0.6])
end
```

Transforms affect drawing, including text and images. Link rectangles are
annotations and still need coordinates in the page's original coordinate
system. The previous graphics state is restored when the block finishes.

## Apply opacity

Opacity ranges from `0` (transparent) to `1` (opaque) and applies to drawing
within its block:

```ruby
page.opacity(0.5) do |p|
  p.rect(280, 240, 100, 60).fill([0.1, 0.4, 0.7])
end
```

Blocks can nest with transforms and clipping. Opacity sets the current value;
nested values do not multiply automatically.

## Embed images

Pass binary PNG or JPEG bytes to `Page#image`. The format is detected by
default; `format: :png` or `format: :jpeg` selects it explicitly:

```ruby
image = Okab::Image.decode(File.binread("photo.jpg"))
width = 180
height = width * image.height.to_f / image.width
page.image(image, x: 48, y: 48, width: width, height: height)
```

Set both output dimensions. Okab stretches the image to that rectangle; the
calculation above preserves its aspect ratio. PNG alpha is embedded as a
soft mask. JPEG compressed bytes are embedded without re-encoding.

Reuse a decoded `Okab::Image` when placing the same image repeatedly to reuse
the document's image resource. Repeatedly passing raw bytes decodes separate
image objects. Images do not gain searchable text or OCR.

Write the result with `document.write("graphics.pdf")`. See
[image format limits](limits.md#images) for accepted PNG and JPEG inputs.

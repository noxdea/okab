---
title: Text and navigation
description: Place text, wrap paragraphs, and connect pages with links and outlines.
---

The examples on this page build on a document, a font, and a page:

```ruby
require "okab"

font = Okab::Font.load("/path/to/font.ttf")
document = Okab::Document.new(title: "Report", author: "Your team")
page = document.page(width: 595, height: 842)
```

<details class="guide-toc" open markdown="1">
<summary>On this page</summary>

* Table of contents
{:toc}

</details>

## Place and style text

`Page#text` places one run at a baseline. Use a valid UTF-8 Ruby string and a
font containing its glyphs. Font size and tracking use points; RGB color
components range from `0` to `1`.

```ruby
page.text("Quarterly report", x: 48, y: 790,
  font: font, size: 24, color: [0.1, 0.2, 0.4])
page.text("Draft", x: 48, y: 754,
  font: font, size: 12, tracking: 1, bold: true, italic: true)
```

`bold: true` thickens the glyph outlines; `italic: true` slants them. These
are synthetic styles using the same font. Load a separate bold or italic
font file when you need that typeface's designed style.

To write Japanese, load a font with Japanese glyphs and pass a UTF-8 string:

```ruby
japanese_font = Okab::Font.load("/path/to/japanese-font.ttf")
page.text("四半期報告", x: 48, y: 710, font: japanese_font, size: 18)
```

Fonts are subsetted and reused within a document. Unicode mappings are
written alongside the glyphs so PDF viewers can search and extract text.
Direct text placement maps characters to glyphs without complex-script
shaping or automatic font fallback.

## Measure text

`Font#measure` returns the sum of the font's glyph advance widths at the
requested size, in points. Use it for simple alignment:

```ruby
label = "Page 1"
width = font.measure(label, size: 10)
page.text(label, x: page.width - 48 - width, y: 32, font: font, size: 10)
```

Measurement does not include `tracking`, synthetic style effects, kerning,
or shaping. Account for those separately when designing a precise layout.

## Wrap paragraphs

`Page#text_block` wraps text to a width. Explicit newlines start new paragraphs,
and wrapped lines move down from `y` by `line_height` points:

```ruby
page.text_block("The report contains searchable text and embedded fonts. " \
  "Long paragraphs wrap within the specified width.",
  x: 48, y: 660, width: 400, font: font, size: 12,
  line_height: 18, align: :left, color: [0.2, 0.2, 0.2])
```

Available alignment values are `:left`, `:center`, `:right`, and `:justify`.
Justification adjusts character tracking on all but the final line of the
block. Width calculations use glyph advances, so keep custom
tracking small when wrapping.

Wrapping prefers whitespace and splits oversized tokens at grapheme
boundaries. It does not hyphenate words, apply Japanese line-breaking rules,
shape scripts, or paginate. A grapheme wider than the block can overflow it.
`text_block` returns the page, without reporting the block's height.

## Supply shaped glyphs

When another text engine has already shaped a run, `Page#glyph` accepts the
glyph ID and its Unicode source text. Position each glyph yourself:

```ruby
glyph_id = font.face.glyph_id("A".ord)
page.glyph(glyph_id, x: 48, y: 580, font: font, size: 18, unicode: "A")
```

Pass the glyph ID from the same font face. `unicode` may contain multiple
characters for a ligature or cluster. The
[Zaniah bridge](zaniah-vector.md) performs this mapping for recorded glyph runs.

## Add pages and outlines

Create pages in reading order. Each page can have its own dimensions, and
`Document#page` can yield the new page to a block:

```ruby
details = document.page(width: 595, height: 842) do |p|
  p.text("Details", x: 48, y: 790, font: font, size: 24)
end
document.outline("Report", page: page)
document.outline("Details", page: details, level: 1)
```

Outlines are PDF bookmarks. The first entry must have level `0`; subsequent
entries can move deeper by one level at a time. Destination pages must belong
to the same document.

## Make links

Links cover an explicit rectangle `[x, y, width, height]` and do not draw a
label or visible border. Draw the text or artwork yourself:

```ruby
page.text("Project website", x: 48, y: 520, font: font, size: 12)
page.link([48, 516, 100, 18], uri: "https://noxdea.github.io/okab/")
page.text("Read the details", x: 48, y: 488, font: font, size: 12)
page.link([48, 484, 100, 18], page: details)
```

Provide exactly one of `uri:` or `page:`. URI links accept `http`, `https`,
and `mailto`. Page links require a page from the same document.

## Write or render a document

`Document#write` writes a binary PDF to a path and returns that path:

```ruby
document.write("report.pdf")
```

`Document#render` returns the PDF as a binary Ruby string for an HTTP response
or other storage:

```ruby
pdf_bytes = document.render
File.binwrite("report.pdf", pdf_bytes)
```

Create at least one page before rendering. Parent directories must already
exist, and writing to an existing path overwrites it. Metadata accepts
`title:`, `author:`, and `creator:` (default: `"Okab"`).

The same font and image bytes, metadata, and drawing operations in the same
order produce deterministic output. Okab does not add creation timestamps.
For input restrictions and errors, see [formats and limits](limits.md).

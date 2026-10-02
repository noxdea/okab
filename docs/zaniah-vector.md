---
title: Zaniah vector documents
description: Export vector display lists while preserving paths, images, and searchable shaped text.
---

`require "okab/zaniah_vector"` loads the optional integration. Call
`Okab::ZaniahVector.draw(page, vector_document)` with an `Okab::Page` whose
dimensions match the `Zaniah::Vector::Document`. The method returns the page.
The core `require "okab"` path does not load or depend on Zaniah.

## Install and draw

Install Zaniah separately (`gem install zaniah`, or add `gem "zaniah"` to your
application's Gemfile). Given an existing `Zaniah::Vector::Document` named
`vector`, export it with:

```ruby
require "okab/zaniah_vector"

pdf = Okab::Document.new(title: "Vector export")
page = pdf.page(width: vector.width, height: vector.height)
Okab::ZaniahVector.draw(page, vector)
pdf.write("vector.pdf")
```

The bridge converts Zaniah's top-left coordinates to PDF's lower-left
coordinates. Pass matching page and vector dimensions in points; it does not
automatically scale the source. Zaniah performs layout and shaping before
Okab draws the recorded commands.

## Command mapping

| Zaniah command | PDF representation |
|---|---|
| Solid `Quad`, `Path`, plain `Underline` | PDF fill/stroke path with the source color, fill rule, line cap/join, and opacity |
| `GlyphRun` | Embedded `Okab::Font` CID glyphs at their shaped positions, with source clusters in `ToUnicode` |
| `Image`, `Raster` | Image XObject (including alpha and source cropping); raster tint is applied before embedding |
| Clip, transform, opacity | PDF graphics-state clip, transform, and `ExtGState` |
| Gradient `Quad`, `Shadow`, wavy underline, unsupported dashed-border combination | Local image XObject of that command only |

## Searchable text and limits

This is a drawing adapter, not a layout engine. Persisted or printed text stays
searchable when Zaniah records a `GlyphRun`, including multi-character clusters.
The original font must be embeddable by Okab: static TrueType and supported
static CFF1 are supported; CFF2 and variable CFF1 are not. An invalid or
unknown vector command raises an error instead of silently dropping content.
The PDF page uses points at 72 per inch; choose matching Zaniah document
dimensions when recording. The adapter does not automatically scale pages.

Unsupported paint effects are rasterized one command at a time, rather than
turning the entire page into a screenshot. Text recorded as `GlyphRun` remains
searchable; text already contained in a raster image does not. See
[formats and limits](limits.md) for supported fonts and core input restrictions.

## Validate the integration

To test the optional integration locally, make Zaniah available on Ruby's load
path and run `bundle exec rspec spec/zaniah_vector_spec.rb`. The image comparison
test uses `pdftoppm` when installed; the text extraction test uses `pdftotext`.
See [development](development.md) for the complete local setup.

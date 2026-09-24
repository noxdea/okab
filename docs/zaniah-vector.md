# Zaniah vector-document adapter

`require "okab/zaniah_vector"` loads the optional integration. Call
`Okab::ZaniahVector.draw(page, vector_document)` with an `Okab::Page` whose
dimensions match the `Zaniah::Vector::Document`. The method returns the page.
The core `require "okab"` path does not load or depend on Zaniah.

| Zaniah command | PDF representation |
|---|---|
| Solid `Quad`, `Path`, plain `Underline` | PDF fill/stroke path with the source color, fill rule, line cap/join, and opacity |
| `GlyphRun` | Embedded `Okab::Font` CID glyphs at their shaped positions, with source clusters in `ToUnicode` |
| `Image`, `Raster` | Image XObject (including alpha and source cropping); raster tint is applied before embedding |
| Clip, transform, opacity | PDF graphics-state clip, transform, and `ExtGState` |
| Gradient `Quad`, `Shadow`, wavy underline, unsupported dashed-border combination | Local image XObject of that command only |

This is a drawing adapter, not a layout engine. Persisted or printed text stays
searchable when Zaniah records a `GlyphRun`, including multi-character clusters.
The original font must be embeddable by Okab: static TrueType and supported
static CFF1 are supported; CFF2 and variable CFF1 are not. An invalid or
unknown vector command raises an error instead of silently dropping content.
The PDF page uses points at 72 per inch; choose matching Zaniah document
dimensions when recording. The adapter does not automatically scale pages.

To test the optional integration locally, make Zaniah available on Ruby's load
path and run `bundle exec rspec spec/zaniah_vector_spec.rb`. The image comparison
test uses `pdftoppm` when installed; the text extraction test uses `pdftotext`.

---
title: Formats and limits
description: Supported fonts and images, layout boundaries, and common errors.
---

Okab creates PDF 1.7 documents. It does not read or edit existing PDFs and
does not implement encryption, digital signatures, forms, PDF/A conformance,
or a general document layout engine.

## Fonts

| Input | Support |
| --- | --- |
| TrueType outlines | Embedded with subsets by default |
| Static, name-keyed CFF1 OpenType | Embedded as a CID-keyed subset |
| CFF2 | Unsupported |
| Variable CFF1 | Unsupported |
| Already CID-keyed CFF | Unsupported |

CFF1 embedding requires `subset: true`, the default for page text. Font
parsing and subsetting use [Alhena](https://github.com/noxdea/alhena).
Supported outlines alone do not guarantee support for every font container
or variation format; start with a standalone static `.ttf` or `.otf` file.

Text must be valid UTF-8 and the font must contain its glyphs. There is no
automatic fallback to another font. A missing glyph can display as the
font's missing-character symbol. One embedded PDF font can encode up to
65,535 character/glyph mappings.

`Page#text` does not shape complex scripts, apply kerning, or provide
bidirectional layout. Supply positioned shaped glyphs with `Page#glyph` or
use the [Zaniah bridge](zaniah-vector.md) for recorded glyph runs.

## Images

| Format | Accepted inputs | Notes |
| --- | --- | --- |
| PNG | Non-interlaced, 8-bit grayscale, RGB, indexed, grayscale with alpha, or RGBA | Alpha and transparency are preserved |
| JPEG | 8-bit grayscale or RGB; baseline, extended-sequential, or progressive | Compressed data is embedded directly |

Other PNG bit depths, interlaced PNGs, and CMYK or unsupported JPEG encodings
are rejected. Exif orientation is not applied. Rotate or normalize image
pixels before passing them to Okab when necessary.
Each image is limited to 50 million pixels (`width * height`).

## Layout and output

- Create at least one page before calling `render` or `write`.
- Page dimensions and font sizes must be positive and finite.
- Colors are RGB triples with finite components in the range `0..1`.
- Text blocks wrap within a width but do not create pages, enforce margins, or return a measured height.
- Content outside the page or a clip may be invisible. Okab does not warn about overflow.
- Documents and input image/font data are held in memory; rendering returns the complete PDF as a string.
- Deterministic output depends on identical source bytes, metadata, and operation order. It is not a guarantee across different library versions.

## Troubleshoot an error

| Symptom | What to check |
| --- | --- |
| `Okab::InvalidDocument: document has no pages` | Add a page before rendering |
| `text must be valid UTF-8` | Decode the source using its actual encoding, then convert it to UTF-8 |
| Missing or incorrect characters | Confirm the font contains the glyphs; use shaped runs for scripts requiring shaping |
| Unsupported font error | Use a supported static font and keep CFF subsetting enabled |
| Image decoding error | Check the file is complete and matches a supported encoding above |
| Invisible text or artwork | Check baseline position, lower-left coordinates, opacity, and clips |
| Invalid outline or link | Use pages from the same document; do not skip outline levels; supply exactly one link destination |
| File write error | Check the parent directory exists and is writable |

Invalid arguments generally raise `ArgumentError`. Invalid document and image
data can raise `Okab::InvalidDocument`; font errors come from Alhena. File
access errors retain Ruby's filesystem exceptions. Handle these at your
application's input and output boundaries.

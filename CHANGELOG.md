# Changelog

## Unreleased

- Render bold and italic text in embedded-font PDF content streams.
- Embed static name-keyed CFF1 OpenType subsets as searchable CIDFontType0C fonts.
- Declare BigDecimal as a runtime dependency for Ruby versions where it is no longer bundled.
- Add deterministic PDF generation with embedded TrueType and CFF1 subsets, CID/ToUnicode text, vector drawing, PNG/JPEG images, links, and outlines.
- CFF2, variable CFF1, and already CID-keyed source fonts are unsupported. PNG support is limited to non-interlaced 8-bit input; JPEG support is limited to 8-bit grayscale and RGB without Exif orientation.

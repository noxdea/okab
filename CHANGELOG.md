# Changelog

## Unreleased

- Declare BigDecimal as a runtime dependency for Ruby versions where it is no longer bundled.
- Add deterministic PDF generation with embedded TrueType subsets, CID/ToUnicode text, vector drawing, PNG/JPEG images, links, and outlines.
- CFF/CFF2 embedding remains unsupported pending CFF subsetting in Alhena. PNG support is limited to non-interlaced 8-bit input; JPEG support is limited to 8-bit grayscale and RGB without Exif orientation.

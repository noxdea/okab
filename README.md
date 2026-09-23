# Okab

Okab (ζ Aquilae) takes its name from Arabic *ʿuqāb*, “eagle”. It is a small Ruby library for creating searchable PDF 1.7 documents with embedded TrueType-outline fonts (including TrueType-flavored OpenType fonts).

## Features

- TrueType font subsetting through [Alhena](https://github.com/noxdea/alhena), with CID fonts and `ToUnicode` mappings for text search and copy
- Text, wrapped text, paths, clipping, transforms, opacity, links, and outlines
- PNG images with alpha and JPEG images embedded without re-encoding
- Stable output for the same document inputs; timestamps are omitted

PDF reading/editing, encryption, signatures, forms, and PDF/A are out of scope. CFF/CFF2 font embedding is not supported yet; `Alhena::Subset` currently repackages CFF fonts rather than reducing their glyph set. PNG input is limited to non-interlaced 8-bit images; JPEG input is limited to 8-bit grayscale or RGB images, and Exif orientation is not applied.

## Installation

```ruby
gem "okab"
```

Okab requires Ruby 3.2 or later and Alhena 0.3.0 or later.

## Usage

```ruby
require "okab"

font = Okab::Font.load("/path/to/font.ttf")
document = Okab::Document.new(title: "Quarterly report", author: "Yudai Takada")
page = document.page(width: 595, height: 842) # points
page.text("四半期報告", x: 48, y: 790, font: font, size: 24)
page.text_block("A searchable report with embedded fonts.", x: 48, y: 750,
  width: 360, font: font, size: 12, line_height: 18)
page.rect(48, 700, 120, 28).fill([0.2, 0.4, 0.8])
page.link([48, 700, 120, 28], uri: "https://example.com")
document.outline("Report", page: page)
document.write("report.pdf")
```

Coordinates use PDF points, with the origin at the lower-left corner. Text must be UTF-8. Supply a font that contains the characters you want to render.

## Development

Run `bundle exec rake` and `bundle exec rbs -I sig validate`. To exercise real Japanese extraction locally, set `OKAB_TEST_FONT` to a TrueType font containing Japanese characters and install Poppler's `pdftotext` utility:

```sh
OKAB_TEST_FONT=/path/to/japanese-font.ttf bundle exec rake
```

## License

MIT

<h1 align="center">Okab</h1>

<p align="center">
  <strong>Generate searchable PDFs with embedded TrueType and CFF1 fonts in pure Ruby</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/okab"><img src="https://img.shields.io/gem/v/okab.svg" alt="Gem version"></a>
  <a href="https://rubygems.org/gems/okab"><img src="https://img.shields.io/gem/dt/okab.svg" alt="Gem downloads"></a>
  <a href="https://github.com/noxdea/okab/actions/workflows/main.yml"><img src="https://github.com/noxdea/okab/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.2-cc342d.svg" alt="Ruby 3.2 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#limits">Limits</a> ·
  <a href="#development">Development</a>
</p>

---

Okab is a small Ruby library for generating PDF 1.7 documents. It embeds font
subsets through [Alhena](https://github.com/noxdea/alhena) and writes `ToUnicode`
mappings so text remains searchable and copyable. The same document inputs
produce stable output without timestamps. Its name comes from Arabic *ʿuqāb*,
“eagle” (ζ Aquilae).

## Features

- TrueType and supported static CFF1 font embedding, including Japanese text when the font contains the glyphs
- Text and wrapped text, vector paths, clipping, transforms, and opacity
- PNG images with alpha and JPEG images embedded without re-encoding
- Optional Zaniah vector-document bridge with searchable glyph runs
- Page links, document outlines, and deterministic PDF output

## Installation

```sh
gem install okab
```

Okab requires Ruby 3.2 or newer and Alhena 0.3.x. With Bundler, add `gem "okab"`
to your Gemfile.

## Quick start

Supply a TrueType font containing the text you want to render:

```ruby
require "okab"

font = Okab::Font.load("/path/to/font.ttf")
document = Okab::Document.new(title: "Quarterly report")
page = document.page(width: 595, height: 842) # PDF points
page.text("Quarterly report", x: 48, y: 790, font: font, size: 24)
page.text_block("A searchable report with embedded fonts.",
  x: 48, y: 750, width: 360, font: font, size: 12, line_height: 18)
document.outline("Report", page: page)
document.write("report.pdf")
```

Coordinates are in PDF points, with the origin at the lower-left corner. Text
must be valid UTF-8. Use a font with Japanese glyphs to render Japanese text.

### Zaniah vector documents

Install Zaniah separately, then load the optional bridge explicitly:

```ruby
require "okab/zaniah_vector"

vector = Zaniah::Vector.record(width: 595, height: 842) { slide_element }
pdf = Okab::Document.new
page = pdf.page(width: vector.width, height: vector.height)
Okab::ZaniahVector.draw(page, vector)
pdf.write("slide.pdf")
```

The bridge converts Zaniah's top-left coordinates to PDF's lower-left
coordinates. Solid quads and paths remain PDF vector operations, shaped glyph
IDs are embedded with `ToUnicode` mappings, and images remain PDF images.
Unsupported paint effects such as multi-stop gradients and shadows are
rasterized individually, never as a full-page screenshot. See
[the adapter notes](docs/zaniah-vector.md) for the mapping and limits.

## Limits

Okab generates PDFs; it does not read or edit them. Encryption, signatures,
forms, and PDF/A are out of scope.

- CFF2, variable CFF1, and already CID-keyed CFF fonts are unsupported. CFF embedding requires `subset: true`.
- PNG input must be non-interlaced and 8-bit.
- JPEG input must be 8-bit grayscale or RGB, using baseline, extended-sequential, or progressive encoding. Exif orientation is not applied.

## Development

```sh
bundle install
bundle exec rake
bundle exec rbs -I sig -r alhena validate
```

To test real Japanese text extraction, set `OKAB_TEST_FONT` to a TrueType font
with Japanese glyphs and install Poppler's `pdftotext` utility:

```sh
OKAB_TEST_FONT=/path/to/japanese-font.ttf bundle exec rake
```

## License

Okab is released under the [MIT License](LICENSE.txt).

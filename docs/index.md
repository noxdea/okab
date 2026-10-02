---
title: Getting started
description: Install Okab, choose a font, and write your first searchable PDF.
permalink: /docs/
---

Okab is a Ruby library for creating PDF 1.7 documents. You place text, graphics,
and images on pages, then write the finished document to a file or render it
as a binary Ruby string. Font subsets and Unicode mappings keep text
searchable and copyable.

<details class="guide-toc" open markdown="1">
<summary>On this page</summary>

* Table of contents
{:toc}

</details>

## Install Okab

You need Ruby 3.2 or newer:

```sh
gem install okab
```

For an application using Bundler, add this to your Gemfile and run
`bundle install`:

```ruby
gem "okab"
```

RubyGems installs Alhena 0.3.x for font parsing and subsetting, and BigDecimal
for PDF number formatting. Core PDF generation needs no external executable.
The [Zaniah integration](zaniah-vector.md) is optional and installed separately.

## Choose a font

Okab embeds a font you provide; it does not select a system font or download
one. Use a TrueType font (`.ttf`) or a supported static CFF1 OpenType font
(`.otf`). The font must contain the glyphs for your text, including Japanese
glyphs if you are writing Japanese. Check its license permits embedding.

Replace `/path/to/font.ttf` in the examples with an existing font file.
See [font format limits](limits.md#fonts) if a font cannot be loaded or embedded.

## Write your first PDF

Save this as `report.rb`:

```ruby
require "okab"

font = Okab::Font.load("/path/to/font.ttf")
document = Okab::Document.new(title: "Quarterly report")
page = document.page(width: 595, height: 842)
page.text("Quarterly report", x: 48, y: 790, font: font, size: 24)
page.text_block("A searchable report with embedded fonts.",
  x: 48, y: 750, width: 360, font: font, size: 12, line_height: 18)
document.outline("Report", page: page)
document.write("report.pdf")
```

Run `ruby report.rb`, or `bundle exec ruby report.rb` in a Bundler application.
Open `report.pdf` in a PDF viewer and try searching for “Quarterly report” or
selecting and copying the text.

For a complete page with a vector chart, run
[the report example](https://github.com/noxdea/okab/blob/main/examples/report.rb)
from a source checkout:

```sh
bundle exec ruby examples/report.rb /path/to/font.ttf report.pdf
```

[Open the generated sample PDF](media/report.pdf). The sample uses Source Sans 3,
licensed under the [SIL Open Font License](https://github.com/noxdea/okab/blob/main/spec/fixtures/SourceSans3-LICENSE.md).

## Understand page coordinates

All dimensions use PDF points: **72 points equal one inch**. The origin
`(0, 0)` is the lower-left corner. Increasing `x` moves right; increasing `y`
moves up. Text `y` positions its baseline, while an image or rectangle `y`
positions its lower edge.

| Page | Width | Height |
| --- | --- | --- |
| A4, rounded to whole points | 595 | 842 |
| US Letter | 612 | 792 |
| A4 landscape | 842 | 595 |

For an object measured from the top of the page, calculate its lower edge
with `page.height - top - height`. Paragraphs start at the supplied baseline
and continue downward by `line_height` points.

Okab does not manage margins or add pages when content reaches the bottom.
Choose your layout and create additional pages explicitly.

## Continue with the guide

- [Text and navigation](usage.md): paragraphs, font measurement, pages, links, and outlines.
- [Graphics and images](graphics.md): paths, transforms, clipping, opacity, PNG, and JPEG.
- [Zaniah vector documents](zaniah-vector.md): drawing an existing vector display list.
- [Formats and limits](limits.md): supported inputs and troubleshooting.
- [Development](development.md): tests, sample generation, and website previews.

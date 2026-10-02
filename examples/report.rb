# frozen_string_literal: true

require "okab"

# Usage: ruby examples/report.rb /path/to/font.ttf [report.pdf]
font = Okab::Font.load(ARGV.fetch(0))
document = Okab::Document.new(title: "Quarterly report", author: "Okab")
page = document.page(width: 595, height: 842)
ink = [0.06, 0.09, 0.16]
blue = [0.01, 0.52, 0.78]

page.text("Quarterly report", x: 48, y: 788, font: font, size: 14, color: ink)
page.text("Okab / PDF 1.7", x: 440, y: 788, font: font, size: 10, color: ink)
page.move_to(48, 770).line_to(547, 770).stroke(ink, width: 0.5)
page.text("Clarity on every page.", x: 48, y: 692, font: font, size: 36, color: ink)
page.text_block("Embedded fonts preserve the text behind the page. Search, select, " \
  "and copy the finished document. This page uses real PDF text and vector graphics.",
  x: 48, y: 648, width: 440, font: font, size: 14, line_height: 22, color: ink)

page.text("Example quarterly revenue", x: 48, y: 502, font: font, size: 16, color: ink)
[100, 160, 130, 210].each_with_index do |height, index|
  x = 48 + index * 126
  page.rect(x, 220, 90, height).fill(index == 3 ? blue : [0.2, 0.26, 0.33])
  page.text("Q#{index + 1}", x: x + 34, y: 196, font: font, size: 12, color: ink)
end
page.text("Illustrative data", x: 48, y: 156, font: font, size: 10, color: ink)
page.move_to(48, 76).line_to(547, 76).stroke(ink, width: 0.5)
page.text("Generated in pure Ruby", x: 48, y: 52, font: font, size: 10, color: ink)
page.text("1", x: 540, y: 52, font: font, size: 10, color: ink)
document.outline("Quarterly report", page: page)
document.write(ARGV.fetch(1, "report.pdf"))

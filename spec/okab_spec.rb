# frozen_string_literal: true

require "zlib"
require "tempfile"

RSpec.describe Okab do
  it "has a version number" do
    expect(Okab::VERSION).to eq("0.1.0")
  end

  it "renders deterministic PDF pages with links and outlines" do
    build = lambda do
      document = Okab::Document.new(title: "Quarterly report")
      cover = document.page(width: 595, height: 842) do |page|
        page.rect(20, 30, 100, 60).fill([0.2, 0.4, 0.8])
        page.clip { |path| path.rect(0, 0, 200, 200) }
        page.opacity(0.5) { page.transform(1, 0, 0, 1, 2, 3) { page.ellipse(30, 40, 12, 8).fill_and_stroke([0.1, 0.2, 0.3]) } }
        page.link([20, 30, 100, 60], uri: "https://example.com/report")
      end
      detail = document.page(width: 400, height: 300)
      cover.link([0, 0, 10, 10], page: detail)
      document.outline("Cover", page: cover)
      document.outline("Details", page: detail, level: 1)
      document.render
    end

    pdf = build.call
    expect(pdf).to start_with("%PDF-1.7\n".b)
    expect(pdf).to include("/Type /Pages /Count 2".b)
    expect(pdf).to include("/Subtype /Link".b)
    expect(pdf).to include("/Outlines".b)
    expect(pdf).to include("/GS1 gs".b)
    expect(pdf).to include("W n".b)
    expect(pdf).to include(" cm".b)
    expect(pdf).to end_with("%%EOF\n".b)
    expect(build.call).to eq(pdf)
  end

  it "rejects documents without pages and invalid links" do
    expect { Okab::Document.new.render }.to raise_error(Okab::InvalidDocument, /no pages/)
    page = Okab::Document.new.page(width: 100, height: 100)
    expect { page.link([0, 0, 10, 10], uri: "javascript:alert(1)") }.to raise_error(ArgumentError, /URI/)
    expect { page.link([0, 0, 10, 10], uri: "https://example.com", page: page) }.to raise_error(ArgumentError)
  end

  it "writes PDF decimal numbers without exponent notation" do
    document = Okab::Document.new
    page = document.page(width: 100, height: 100)
    page.move_to(1e-8, 0).line_to(1, 1).stroke([1e-8, 0, 0])
    expect(document.render).to include("0.00000001 0.0 m".b)
    expect(document.render).not_to include("1.0e-08".b)
  end

  it "decodes PNG color and alpha data and rejects corrupt chunks" do
    png = png_image(1, 1, 6, [0, 255, 10, 20, 128].pack("C*"))
    image = Okab::Image.decode(png)
    expect([image.width, image.height, image.color_space]).to eq([1, 1, :rgb])
    expect(image.data.bytes).to eq([255, 10, 20])
    expect(image.alpha.bytes).to eq([128])
    expect { Okab::Image.decode(png.sub("IHDR", "IXXX")) }.to raise_error(Okab::InvalidDocument, /checksum/)
  end

  it "places decoded PNGs in the page resource dictionary" do
    document = Okab::Document.new
    document.page(width: 100, height: 100) do |page|
      page.image(png_image(1, 1, 6, [0, 20, 30, 40, 128].pack("C*")), x: 0, y: 0, width: 50, height: 50)
    end
    pdf = document.render
    expect(pdf).to include("/XObject << /Im1".b)
    expect(pdf).to include("/SMask".b)
    expect(pdf).to include("/Filter /FlateDecode".b)
  end

  it "reads JPEG dimensions and preserves DCT data for direct embedding" do
    frame = "\xFF\xD8\xFF\xC0".b + [17].pack("n") + [8, 1, 2, 3].pack("CnnC") + [1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0].pack("C*")
    image = Okab::Image.decode(frame + "\xFF\xD9".b)
    expect([image.width, image.height, image.filter]).to eq([2, 1, :dct])

    document = Okab::Document.new
    document.page(width: 100, height: 100) { |page| page.image(image, x: 0, y: 0, width: 20, height: 10) }
    pdf = document.render
    expect(pdf).to include("/Filter /DCTDecode".b)
    expect(pdf).to include(frame)
  end

  it "rejects invalid text and page geometry" do
    expect { Okab::Document.new.page(width: Float::INFINITY, height: 10) }.to raise_error(ArgumentError, /dimensions/)
    page = Okab::Document.new.page(width: 100, height: 100)
    skip "Set OKAB_TEST_FONT to run font validation" unless ENV["OKAB_TEST_FONT"]
    font = Okab::Font.load(ENV.fetch("OKAB_TEST_FONT"))
    expect { page.text("invalid", x: 0, y: 0, font: font, size: 12) }.not_to raise_error
    expect { page.text("\xFF".b, x: 0, y: 0, font: font, size: 12) }.to raise_error(ArgumentError, /UTF-8/)
  end

  it "embeds a TrueType font and preserves Japanese text extraction" do
    skip "Set OKAB_TEST_FONT and install pdftotext to run PDF integration validation" unless
      ENV["OKAB_TEST_FONT"] && system("pdftotext", "-v", out: File::NULL, err: File::NULL)

    font = Okab::Font.load(ENV.fetch("OKAB_TEST_FONT"))
    document = Okab::Document.new
    document.page(width: 200, height: 100) do |page|
      page.text("四半期報告", x: 10, y: 60, font: font, size: 14)
    end
    Tempfile.create(["okab", ".pdf"]) do |file|
      file.binmode
      file.write(document.render)
      file.flush
      extracted = IO.popen(["pdftotext", file.path, "-"], &:read)
      expect(extracted).to include("四半期報告")
    end
  end

  def png_image(width, height, color_type, scanlines)
    chunk = lambda do |type, data|
      [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
    end
    header = [width, height, 8, color_type, 0, 0, 0].pack("NNC5")
    "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", header) +
      chunk.call("IDAT", Zlib::Deflate.deflate(scanlines)) + chunk.call("IEND", "".b)
  end
end

# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tempfile"
require "tmpdir"

ZANIAH_VECTOR_AVAILABLE = begin
  require "okab/zaniah_vector"
  require "zaniah/svg"
  true
rescue LoadError
  false
end
raise LoadError, "Zaniah vector integration must run in CI" if ENV["CI"] == "true" && !ZANIAH_VECTOR_AVAILABLE

RSpec.describe "Zaniah vector PDF bridge" do
  before { skip "install zaniah >= 0.9 to test the optional bridge" unless ZANIAH_VECTOR_AVAILABLE }

  let(:vector) { Zaniah::Vector }
  let(:font) { Alhena::Font.open(File.expand_path("fixtures/SourceSans3-Regular.otf", __dir__)) }

  def pdf_page(document)
    pdf = Okab::Document.new
    page = pdf.page(width: document.width, height: document.height)
    Okab::ZaniahVector.draw(page, document)
    [pdf, page]
  end

  it "rejects a page size mismatch before writing PDF operations" do
    document = vector::Document.new(60, 40, [])
    page = Okab::Document.new.page(width: 61, height: 40)
    expect { Okab::ZaniahVector.draw(page, document) }.to raise_error(ArgumentError, /dimensions/)
    expect(page.operations).to be_empty
  end

  it "keeps solid quads, outlines, clip/opacity, glyph IDs, and images as PDF operations" do
    recorder = vector::Recorder.new(width: 80, height: 60)
    scene = Zaniah::Scene.new
    scene.vector_sink = recorder
    scene.quad(0, 0, 80, 60, color: "#fff")
    scene.clip(Zaniah::Bounds.new(1, 2, 70, 50)) do
      scene.push_opacity(0.5) do
        scene.quad(4, 5, 20, 14, color: "#f00", radius: 3)
        scene.path("M30 8 Q35 3 40 8 L42 18 Z", fill: "#00f", stroke: "#0f0", width: 2)
      end
    end
    image = Zaniah::Image.from_bytes(Zaniah::PNG.encode(2, 2, "\x00\xff\x00\xff".b * 4))
    scene.image(50, 7, 12, 12, image: image, texture: image.texture)
    recorder.record(vector::GlyphRun.new(font: font, size: 14, glyphs: [[font.glyph_id("A".ord), 10, 40]],
      color: Zaniah::Color.parse("#000"), text: "A", clusters: [[0, 1]],
      transform: Zaniah::Transform.identity, clip: nil, opacity: 1.0, layer: 0, sequence: 50))

    pdf, page = pdf_page(recorder.document)
    expect(page.operations.count { |operation| operation.first == :image }).to eq(1)
    expect(page.operations.count { |operation| operation.first == :text }).to eq(1)
    content = page.content(fonts: pdf.instance_variable_get(:@fonts).values.to_h { |embedded| [embedded.object_id, "F1"] })
    expect(content).to include("W n", " gs", " rg", " c\n", " Tj ET", "/Im1 Do")
    expect(pdf.render).to start_with("%PDF-1.7")
    if system("which", "qpdf", out: File::NULL, err: File::NULL)
      Tempfile.create(["okab-vector-", ".pdf"]) do |file|
        file.binmode
        file.write(pdf.render)
        file.flush
        output, status = Open3.capture2e("qpdf", "--check", file.path)
        expect(status).to be_success, output
      end
    end
  end

  it "keeps the original Unicode searchable when rendering a shaped glyph run" do
    second_x = 8 + font.advance_width(font.glyph_id("A".ord)) * 20.0 / font.units_per_em
    command = vector::GlyphRun.new(font: font, size: 20,
      glyphs: [[font.glyph_id("A".ord), 8, 26], [font.glyph_id("B".ord), second_x, 26]],
      color: Zaniah::Color.parse("#000"), text: "AB", clusters: [[0, 1], [1, 2]],
      transform: Zaniah::Transform.identity, clip: nil, opacity: 1, layer: 0, sequence: 0)
    display_list = vector::Document.new(60, 40, [command])
    pdf, = pdf_page(display_list)
    Okab::ZaniahVector.draw(pdf.page(width: 60, height: 40), display_list)
    expect(pdf.instance_variable_get(:@fonts).length).to eq(1)
    next unless system("which", "pdftotext", out: File::NULL, err: File::NULL)

    Dir.mktmpdir("okab-vector") do |directory|
      input = File.join(directory, "document.pdf")
      output = File.join(directory, "document.txt")
      File.binwrite(input, pdf.render)
      message, status = Open3.capture2e("pdftotext", "-raw", input, output)
      expect(status).to be_success, message
      expect(File.read(output)).to include("AB")
    end
  end

  it "rasterizes only unsupported gradient and shadow commands locally" do
    recorder = vector::Recorder.new(width: 70, height: 50)
    scene = Zaniah::Scene.new
    scene.vector_sink = recorder
    scene.quad(1, 1, 10, 10, color: "#00f")
    gradient = Zaniah::Gradient.linear(stops: [[0, "#f00"], [0.5, "#0f0"], [1, "#00f"]])
    scene.quad(15, 3, 20, 12, color: gradient)
    scene.shadow(40, 5, 10, 10, blur: 3, color: "#0008")
    pdf, page = pdf_page(recorder.document)

    expect(page.operations.count { |operation| operation.first == :image }).to eq(2)
    expect(page.operations.map(&:first)).to include(:raw)
    expect(page.operations.count { |operation| operation.first == :image && operation[4] == 70 }).to eq(0)
    images = pdf.instance_variable_get(:@images).values.map(&:last)
    gradient_image = images.find { |image| image.width == 20 }
    expect(gradient_image.data.byteslice(0, 3)).not_to eq(gradient_image.data.byteslice((gradient_image.height - 1) * gradient_image.width * 3, 3))
    expect(images.any? { |image| image.alpha&.bytes&.any?(&:positive?) }).to be(true)
  end

  it "stays visually close for solid vector geometry and image placement" do
    skip "pdftoppm is unavailable" unless system("which", "pdftoppm", out: File::NULL, err: File::NULL)
    recorder = vector::Recorder.new(width: 64, height: 48)
    scene = Zaniah::Scene.new
    scene.vector_sink = recorder
    scene.quad(0, 0, 64, 48, color: "#fff")
    scene.push_opacity(0.5) { scene.quad(4, 5, 24, 18, color: "#f00") }
    scene.clip(Zaniah::Bounds.new(25, 16, 30, 28)) do
      scene.push_transform(Zaniah::Transform.translate(19, 9)) do
        scene.quad(10, 10, 32, 22, color: "#ff0")
      end
    end
    scene.push_transform(Zaniah::Transform.translate(42, 4).compose(Zaniah::Transform.rotate(20))) do
      scene.quad(0, 0, 12, 8, color: "#0ff")
    end
    scene.path("M35 7 L55 7 L45 30 Z", fill: "#00f")
    image = Zaniah::Image.from_bytes(Zaniah::PNG.encode(2, 2,
      "\xff\x00\x00\xff\x00\xff\x00\xff\x00\x00\xff\xff\xff\xff\x00\xff".b))
    scene.image(5, 30, 12, 12, image: image, texture: image.texture,
      source: Zaniah::Bounds.new(1, 0, 1, 1))
    source = Zaniah::GPU::Software.new(64, 48).render(scene, clear: "#fff")
    pdf, = pdf_page(recorder.document)

    Dir.mktmpdir("okab-vector-pdf-") do |directory|
      input = File.join(directory, "page.pdf")
      File.binwrite(input, pdf.render)
      output, status = Open3.capture2e("pdftoppm", "-f", "1", "-singlefile", "-r", "72", "-png",
        input, File.join(directory, "page"))
      expect(status).to be_success, output
      width, height, actual = Zaniah::PNG.decode(File.binread(File.join(directory, "page.png")))
      expect([width, height]).to eq([64, 48])
      errors = source.bytes.zip(actual.bytes).map { |left, right| (left - right).abs }
      expect(errors.sum.to_f / errors.length).to be < 5
    end
  end
end

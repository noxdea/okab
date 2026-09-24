# frozen_string_literal: true

require "uri"

module Okab
  class Path
    attr_reader :commands

    def initialize = (@commands = [])
    def move_to(x, y) = command("#{number(x)} #{number(y)} m")
    def line_to(x, y) = command("#{number(x)} #{number(y)} l")
    def curve_to(x1, y1, x2, y2, x3, y3) = command("#{[x1, y1, x2, y2, x3, y3].map { |v| number(v) }.join(' ')} c")
    def close = command("h")
    def rect(x, y, width, height) = command("#{[x, y, width, height].map { |v| number(v) }.join(' ')} re")

    def ellipse(x, y, width, height)
      k = 0.5522847498307936
      cx, cy, rx, ry = x + width / 2.0, y + height / 2.0, width / 2.0, height / 2.0
      move_to(cx + rx, cy)
      curve_to(cx + rx, cy + k * ry, cx + k * rx, cy + ry, cx, cy + ry)
      curve_to(cx - k * rx, cy + ry, cx - rx, cy + k * ry, cx - rx, cy)
      curve_to(cx - rx, cy - k * ry, cx - k * rx, cy - ry, cx, cy - ry)
      curve_to(cx + k * rx, cy - ry, cx + rx, cy - k * ry, cx + rx, cy)
      close
    end

    private

    def command(value)
      @commands << value
      self
    end

    def number(value)
      raise ArgumentError, "coordinates must be finite numbers" unless value.is_a?(Numeric) && !value.is_a?(Complex) && value.finite?
      PDF::Encoding.number(value)
    end
  end

  class Page
    attr_reader :width, :height, :operations, :annotations, :document

    def initialize(document, width:, height:)
      @document, @width, @height = document, Float(width), Float(height)
      raise ArgumentError, "page dimensions must be finite and positive" unless [@width, @height].all? { |value| value.finite? && value.positive? }
      @operations, @annotations, @open_clips = [], [], 0
    end

    def text(string, x:, y:, font:, size:, color: [0, 0, 0], tracking: 0, bold: false, italic: false)
      validate_text(string)
      size, tracking = finite(size, "font size"), finite(tracking, "tracking")
      raise ArgumentError, "font size must be positive" unless size.positive?
      raise ArgumentError, "bold and italic must be true or false" unless [bold, italic].all? { |value| value == true || value == false }
      embedded = @document.embed_font(font)
      encoded = embedded.encode(string)
      @operations << [:text, finite(x, "x"), finite(y, "y"), embedded, encoded, size, rgb(color), tracking, bold, italic]
      self
    end

    def glyph(glyph_id, x:, y:, font:, size:, unicode:, color: [0, 0, 0])
      size = finite(size, "font size")
      raise ArgumentError, "font size must be positive" unless size.positive?
      embedded = @document.embed_font(font)
      encoded = embedded.encode_glyph(glyph_id, unicode: unicode)
      @operations << [:text, finite(x, "x"), finite(y, "y"), embedded, encoded, size, rgb(color), 0.0, false, false]
      self
    end

    def text_block(string, x:, y:, width:, font:, size:, line_height:, align: :left, color: [0, 0, 0], tracking: 0)
      validate_text(string)
      x, y = finite(x, "x"), finite(y, "y")
      width, size, line_height = finite(width, "width"), finite(size, "font size"), finite(line_height, "line height")
      raise ArgumentError, "text block dimensions must be positive" unless width.positive? && size.positive? && line_height.positive?
      raise ArgumentError, "align must be left, center, right, or justify" unless %i[left center right justify].include?(align)
      face = font.is_a?(EmbeddedFont) ? font.font : normalize_font(font)
      lines = wrap_lines(string, face, size, width)
      lines.each_with_index do |line, index|
        line_width = face.measure(line, size: size)
        offset = case align
        when :center then (width - line_width) / 2.0
        when :right then width - line_width
        else 0
        end
        extra = align == :justify && index < lines.length - 1 ? (width - line_width) / [line.length, 1].max : 0
        text(line, x: x + offset, y: y - index * line_height, font: face, size: size,
          color: color, tracking: tracking + extra)
      end
      self
    end

    def move_to(x, y) = raw(Path.new.move_to(x, y).commands.last)
    def line_to(x, y) = raw(Path.new.line_to(x, y).commands.last)
    def curve_to(x1, y1, x2, y2, x3, y3) = raw(Path.new.curve_to(x1, y1, x2, y2, x3, y3).commands.last)
    def close = raw("h")
    def rect(x, y, width, height) = raw(Path.new.rect(x, y, width, height).commands.last)

    def ellipse(x, y, width, height)
      path = Path.new.ellipse(*[x, y, width, height].map { |value| finite(value, "ellipse bounds") })
      raw(path.commands.join("\n"))
    end

    def path(outline)
      raise ArgumentError, "path must not be empty" unless outline.is_a?(Path) && !outline.commands.empty?
      raw(outline.commands.join("\n"))
    end

    def fill(color, rule: :nonzero)
      raise ArgumentError, "fill rule must be nonzero or evenodd" unless %i[nonzero evenodd].include?(rule)
      raw("#{rgb(color).join(' ')} rg\n#{rule == :evenodd ? 'f*' : 'f'}")
    end

    def stroke(color, width: 1, cap: :butt, join: :miter, miter: 10, dash: nil)
      raise ArgumentError, "line cap must be butt, round, or square" unless %i[butt round square].include?(cap)
      raise ArgumentError, "line join must be miter, round, or bevel" unless %i[miter round bevel].include?(join)
      style = "#{rgb(color).join(' ')} RG\n#{positive(width, 'line width')} w\n#{ {butt: 0, round: 1, square: 2}.fetch(cap) } J\n#{ {miter: 0, round: 1, bevel: 2}.fetch(join) } j\n#{positive(miter, 'miter limit')} M"
      if dash
        raise ArgumentError, "dash must contain positive lengths" unless dash.is_a?(Array) && !dash.empty? && dash.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? }
        style << "\n[#{dash.map { |value| PDF::Encoding.number(value) }.join(' ')}] 0 d"
      else
        style << "\n[] 0 d"
      end
      raw("#{style}\nS")
    end
    def fill_and_stroke(color, width: 1) = raw("#{rgb(color).join(' ')} rg\n#{rgb(color).join(' ')} RG\n#{positive(width, 'line width')} w\nB")

    def clip
      raise ArgumentError, "clip requires a block" unless block_given?
      path = Path.new
      yield path
      raise ArgumentError, "clip path must not be empty" if path.commands.empty?
      @operations << [:raw, "q\n#{path.commands.join("\n")}\nW n"]
      @open_clips += 1
      self
    end

    def with_clip(path, rule: :nonzero)
      raise ArgumentError, "clip requires a block" unless block_given?
      raise ArgumentError, "clip path must not be empty" unless path.is_a?(Path) && !path.commands.empty?
      raise ArgumentError, "clip rule must be nonzero or evenodd" unless %i[nonzero evenodd].include?(rule)
      start = @operations.length
      @operations << [:raw, "q\n#{path.commands.join("\n")}\n#{rule == :evenodd ? 'W*' : 'W'} n"]
      begin
        yield self
      rescue StandardError
        @operations.slice!(start..)
        raise
      end
      @operations << [:raw, "Q"]
      self
    end

    def transform(a, b, c, d, e, f)
      raise ArgumentError, "transform requires a block" unless block_given?
      values = [a, b, c, d, e, f].map { |value| finite(value, 'transform') }
      start = @operations.length
      @operations << [:raw, "q\n#{values.map { |value| PDF::Encoding.number(value) }.join(' ')} cm"]
      begin
        yield self
      rescue StandardError
        @operations.slice!(start..)
        raise
      end
      @operations << [:raw, "Q"]
      self
    end

    def opacity(value)
      raise ArgumentError, "opacity requires a block" unless block_given?
      name = @document.opacity_name(value)
      start = @operations.length
      @operations << [:raw, "q\n/#{name} gs"]
      begin
        yield self
      rescue StandardError
        @operations.slice!(start..)
        raise
      end
      @operations << [:raw, "Q"]
      self
    end

    def image(data, x:, y:, width:, height:, format: :auto)
      image = data.is_a?(Image) ? data : Image.decode(data, format: format)
      name = @document.register_image(image)
      @operations << [:image, name, finite(x, "x"), finite(y, "y"), finite(width, "width"), finite(height, "height")]
      self
    end

    def link(bounds, uri: nil, page: nil)
      raise ArgumentError, "provide either uri or page" if (!!uri == !!page)
      x, y, width, height = normalize_bounds(bounds)
      action = if uri
        parsed = URI.parse(uri.to_s)
        valid = (parsed.is_a?(URI::HTTP) && parsed.host && %w[http https].include?(parsed.scheme)) ||
          (parsed.is_a?(URI::MailTo) && !parsed.to.empty?)
        raise ArgumentError, "link URI must use http, https, or mailto" unless valid
        [:uri, uri.to_s.freeze]
      else
        raise ArgumentError, "destination page belongs to another document" unless page.is_a?(Page) && @document.owns_page?(page)
        [:page, page]
      end
      @annotations << [x, y, width, height, *action]
      self
    rescue URI::InvalidURIError
      raise ArgumentError, "invalid link URI"
    end

    def content(fonts:)
      output = +"".b
      @operations.each do |operation|
        case operation[0]
        when :raw then output << operation[1].b << "\n".b
        when :text
          _, x, y, font, encoded, size, color, tracking, bold, italic = operation
          output << "#{color.join(' ')} rg\n"
          if bold
            output << "#{color.join(' ')} RG\n#{PDF::Encoding.number((size * 0.035).round(4))} w\n"
          end
          matrix = italic ? "1 0 0.2 1 #{PDF::Encoding.number(x)} #{PDF::Encoding.number(y)} Tm" : "#{PDF::Encoding.number(x)} #{PDF::Encoding.number(y)} Td"
          output << "BT /#{fonts.fetch(font.object_id)} #{PDF::Encoding.number(size)} Tf #{PDF::Encoding.number(tracking)} Tc #{bold ? 2 : 0} Tr #{matrix} #{PDF::Encoding.hex(encoded)} Tj ET\n".b
        when :image
          _, name, x, y, width, height = operation
          output << "q\n#{PDF::Encoding.number(width)} 0 0 #{PDF::Encoding.number(height)} #{PDF::Encoding.number(x)} #{PDF::Encoding.number(y)} cm\n/#{name} Do\nQ\n".b
        end
      end
      @open_clips.times { output << "Q\n".b }
      output
    end

    private

    def raw(value)
      @operations << [:raw, value]
      self
    end

    def validate_text(string)
      raise ArgumentError, "text must be valid UTF-8" unless string.is_a?(String) && string.encoding == Encoding::UTF_8 && string.valid_encoding?
    end

    def finite(value, label)
      raise ArgumentError, "#{label} must be finite" unless value.is_a?(Numeric) && !value.is_a?(Complex) && value.finite?
      value = value.to_f
      raise ArgumentError, "#{label} must be finite" unless value.finite?
      value
    end

    def positive(value, label)
      value = finite(value, label)
      raise ArgumentError, "#{label} must be positive" unless value.positive?
      value
    end

    def rgb(color)
      valid = color.is_a?(Array) && color.length == 3 && color.all? { |value| value.is_a?(Numeric) && !value.is_a?(Complex) && value.finite? && value.between?(0, 1) }
      raise ArgumentError, "color must contain three finite values between 0 and 1" unless valid
      color.map { |value| PDF::Encoding.number(value) }
    end

    def normalize_bounds(bounds)
      values = if bounds.is_a?(Array)
        bounds
      elsif %i[x y width height].all? { |name| bounds.respond_to?(name) }
        %i[x y width height].map { |name| bounds.public_send(name) }
      end
      raise ArgumentError, "bounds must be [x, y, width, height]" unless values.is_a?(Array) && values.length == 4
      x, y, width, height = values.map { |value| finite(value, "bounds") }
      raise ArgumentError, "bounds dimensions must be positive" unless width.positive? && height.positive?
      [x, y, width, height]
    end

    def normalize_font(font)
      return font if font.is_a?(Font)
      return Font.new(font) if font.is_a?(Alhena::Font)
      raise ArgumentError, "font must be an Okab::Font or Alhena::Font"
    end

    def wrap_lines(string, font, size, width)
      string.split("\n", -1).flat_map do |paragraph|
        tokens = paragraph.split(/(?<=\s)/)
        lines, line = [], +""
        tokens.each do |token|
          if !line.empty? && font.measure(line + token, size: size) > width
            lines << line.rstrip
            line = +""
          end
          if font.measure(token, size: size) > width
            token.grapheme_clusters.each do |cluster|
              lines << line if !line.empty? && font.measure(line + cluster, size: size) > width
              line = +"" if !line.empty? && font.measure(line + cluster, size: size) > width
              line << cluster
            end
          else
            line << token
          end
        end
        lines << line.rstrip unless line.empty?
        lines << "" if paragraph.empty? && lines.empty?
        lines
      end
    end
  end
end

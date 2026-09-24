# frozen_string_literal: true

require_relative "../okab"
require "zaniah/vector"

module Okab
  # Optional bridge: each display-list item remains a PDF path, glyph, or image.
  # Only effects without an equivalent PDF page operation are rasterized locally.
  class ZaniahVector
    KAPPA = 0.5522847498307936

    def self.draw(page, vector_document) = new(page, vector_document).draw

    def initialize(page, vector_document)
      unless page.is_a?(Page) && vector_document.is_a?(::Zaniah::Vector::Document)
        raise ArgumentError, "expected an Okab::Page and Zaniah::Vector::Document"
      end
      unless page.width == vector_document.width && page.height == vector_document.height
        raise ArgumentError, "PDF page and vector document dimensions must match"
      end
      @page, @vector, @fonts = page, vector_document, {}.compare_by_identity
    end

    def draw
      @vector.commands.each do |command|
        clipped(command) do
          transformed(command) { draw_command(command) }
        end
      end
      @page
    end

    private

    def clipped(command)
      return yield unless command.clip
      clip = command.clip
      path = Path.new.rect(clip.x, @page.height - clip.bottom, clip.width, clip.height)
      @page.with_clip(path) { yield }
    end

    def transformed(command)
      transform = command.transform
      return yield unless transform && transform != ::Zaniah::Transform.identity
      a, b, c, d, tx, ty = transform.to_a
      height = @page.height
      @page.transform(a, -b, -c, d, c * height + tx, height * (1 - d) - ty) { yield }
    end

    def draw_command(command)
      case command
      when ::Zaniah::Vector::Quad then draw_quad(command)
      when ::Zaniah::Vector::Path then draw_path(command)
      when ::Zaniah::Vector::GlyphRun then draw_glyph_run(command)
      when ::Zaniah::Vector::Image, ::Zaniah::Vector::Raster then draw_image(command)
      when ::Zaniah::Vector::Underline then draw_underline(command)
      when ::Zaniah::Vector::Shadow then draw_shadow(command)
      else raise ArgumentError, "unsupported vector command #{command.class}"
      end
    end

    def draw_quad(command)
      bounds = command.bounds
      return if bounds.width <= 0 || bounds.height <= 0
      unless command.fill.is_a?(::Zaniah::Color)
        return draw_raster_image(raster_quad(command), bounds, command.opacity)
      end
      widths, border_color = command.border
      if command.border_style == :dashed && widths.uniq.length != 1
        return draw_raster_image(raster_quad(command), bounds, command.opacity)
      end
      outer = rounded_rect(bounds, command.radii)
      paint_fill(outer, command.fill, command.opacity)
      return unless widths.any?(&:positive?) && border_color.a.positive?
      if command.border_style == :dashed
        inset = widths.first / 2.0
        center = rounded_rect(inset_bounds(bounds, [inset] * 4), command.radii.map { |radius| [radius - inset, 0].max })
        paint_stroke(center, border_color, widths.first, command.opacity, dash: [widths.first * 3, widths.first * 2])
      else
        inner = inset_bounds(bounds, widths)
        if inner.width.positive? && inner.height.positive?
          radii = command.radii.each_with_index.map do |radius, index|
            adjacent = [[widths[0], widths[3]], [widths[0], widths[1]],
              [widths[2], widths[1]], [widths[2], widths[3]]].fetch(index)
            [radius - adjacent.max, 0].max
          end
          ring = Path.new
          ring.commands.concat(outer.commands).concat(rounded_rect(inner, radii).commands)
          paint_fill(ring, border_color, command.opacity, rule: :evenodd)
        else
          paint_fill(outer, border_color, command.opacity)
        end
      end
    end

    def draw_path(command)
      path = outline_path(command.outline)
      paint_fill(path, command.fill, command.opacity, rule: command.fill_rule) if command.fill
      if command.stroke && command.stroke_width.positive?
        paint_stroke(path, command.stroke, command.stroke_width, command.opacity,
          cap: command.stroke_cap, join: command.stroke_join, miter: command.stroke_miter)
      end
    end

    def draw_glyph_run(command)
      font = (@fonts[command.font] ||= Font.new(command.font))
      color = command.color
      with_alpha(color.a * command.opacity) do
        command.glyphs.zip(command.clusters).each do |(glyph, x, y), cluster|
          unicode = command.text.byteslice(cluster[0]...cluster[1])
          unicode = "\uFFFD" unless unicode&.valid_encoding? && !unicode.empty?
          @page.glyph(glyph, x: x, y: @page.height - y, font: font,
            size: command.size, unicode: unicode, color: rgb(color))
        end
      end
    end

    def draw_image(command)
      image = pixel_image(command)
      draw_raster_image(image, command.bounds, command.opacity)
    end

    def draw_underline(command)
      if command.wave
        bounds = ::Zaniah::Bounds.new(command.x, command.y - command.thickness,
          command.width, command.thickness * 3)
        scene = ::Zaniah::Scene.new
        scene.underline(0, command.thickness, command.width, color: command.color,
          thickness: command.thickness, wave: true)
        draw_raster_image(raster_scene(scene, bounds), bounds, command.opacity)
      else
        bounds = ::Zaniah::Bounds.new(command.x, command.y, command.width, command.thickness)
        paint_fill(rounded_rect(bounds, [0] * 4), command.color, command.opacity)
      end
    end

    def draw_shadow(command)
      bounds = command.bounds
      margin = (command.blur * 3 + command.spread.abs + 2).ceil
      local = ::Zaniah::Bounds.new(bounds.x - margin, bounds.y - margin,
        bounds.width + margin * 2, bounds.height + margin * 2)
      scene = ::Zaniah::Scene.new
      scene.shadow(margin, margin, bounds.width, bounds.height, color: command.color,
        blur: command.blur, spread: command.spread, radius: command.radii, inset: command.inset)
      draw_raster_image(raster_scene(scene, local), local, command.opacity)
    end

    def raster_quad(command)
      bounds = command.bounds
      scene = ::Zaniah::Scene.new
      scene.quad(0, 0, bounds.width, bounds.height, color: command.fill,
        radius: command.radii, border_width: command.border.first,
        border_color: command.border.last, border_style: command.border_style)
      raster_scene(scene, ::Zaniah::Bounds.new(0, 0, bounds.width, bounds.height))
    end

    def raster_scene(scene, bounds)
      width, height = [bounds.width.ceil, 1].max, [bounds.height.ceil, 1].max
      rgba_image(::Zaniah::GPU::Software.new(width, height).render(scene, clear: "#0000"), width, height)
    end

    def draw_raster_image(image, bounds, opacity)
      with_alpha(opacity) do
        @page.image(image, x: bounds.x, y: @page.height - bounds.bottom,
          width: bounds.width, height: bounds.height)
      end
    end

    def pixel_image(command)
      width, height = command.pixel_width, command.pixel_height
      source = command.source || ::Zaniah::Bounds.new(0, 0, width, height)
      tint = command.is_a?(::Zaniah::Vector::Raster) ? command.color : ::Zaniah::Color.new(1, 1, 1, 1)
      if [source.x, source.y, source.width, source.height].all? { |value| value.is_a?(Integer) } &&
          source.x >= 0 && source.y >= 0 && source.right <= width && source.bottom <= height
        rgba = +"".b
        channels = command.format == :r8 ? 1 : 4
        source.height.times do |row|
          offset = ((source.y + row) * width + source.x) * channels
          slice = command.pixels.byteslice(offset, source.width * channels)
          if channels == 1
            slice.each_byte do |coverage|
              rgba << [(tint.r * 255).round, (tint.g * 255).round, (tint.b * 255).round,
                (coverage * tint.a).round].pack("C4")
            end
          else
            slice.bytes.each_slice(4) do |red, green, blue, alpha|
              rgba << [(red * tint.r).round, (green * tint.g).round,
                (blue * tint.b).round, (alpha * tint.a).round].pack("C4")
            end
          end
        end
        rgba_image(rgba, source.width, source.height)
      else
        texture = ::Zaniah::GPU::Texture.new(width, height, format: command.format, data: command.pixels)
        scene = ::Zaniah::Scene.new
        scene.sprite(0, 0, command.bounds.width, command.bounds.height,
          texture: texture, source: source, color: tint)
        raster_scene(scene, ::Zaniah::Bounds.new(0, 0, command.bounds.width, command.bounds.height))
      end
    end

    def rgba_image(pixels, width, height)
      rgb, alpha = +"".b, +"".b
      pixels.bytes.each_slice(4) do |red, green, blue, opacity|
        rgb << [red, green, blue].pack("C3")
        alpha << opacity.chr
      end
      Image.new(width: width, height: height, color_space: :rgb,
        data: rgb, alpha: alpha.each_byte.all? { |value| value == 255 } ? nil : alpha)
    end

    def outline_path(outline)
      path = Path.new
      current = start = [0.0, 0.0]
      outline.each do |operation, *values|
        case operation
        when :move_to
          current = start = values
          path.move_to(values[0], @page.height - values[1])
        when :line_to
          current = values
          path.line_to(values[0], @page.height - values[1])
        when :quad_to
          cx, cy, x, y = values
          x1 = current[0] + (cx - current[0]) * 2 / 3.0
          y1 = current[1] + (cy - current[1]) * 2 / 3.0
          x2 = x + (cx - x) * 2 / 3.0
          y2 = y + (cy - y) * 2 / 3.0
          path.curve_to(x1, @page.height - y1, x2, @page.height - y2, x, @page.height - y)
          current = [x, y]
        when :cubic_to
          x1, y1, x2, y2, x, y = values
          path.curve_to(x1, @page.height - y1, x2, @page.height - y2, x, @page.height - y)
          current = [x, y]
        when :close
          path.close
          current = start
        else raise ArgumentError, "unsupported outline command #{operation}"
        end
      end
      path
    end

    def rounded_rect(bounds, radii)
      x, y, width, height = bounds.x, bounds.y, bounds.width, bounds.height
      tl, tr, br, bl = radii.map { |radius| radius.clamp(0, [width, height].min / 2.0) }
      path = Path.new
      point = ->(px, py) { [px, @page.height - py] }
      path.move_to(*point.call(x + tl, y))
      path.line_to(*point.call(x + width - tr, y))
      path.curve_to(*point.call(x + width - tr + KAPPA * tr, y),
        *point.call(x + width, y + tr - KAPPA * tr), *point.call(x + width, y + tr)) if tr.positive?
      path.line_to(*point.call(x + width, y + height - br))
      path.curve_to(*point.call(x + width, y + height - br + KAPPA * br),
        *point.call(x + width - br + KAPPA * br, y + height), *point.call(x + width - br, y + height)) if br.positive?
      path.line_to(*point.call(x + bl, y + height))
      path.curve_to(*point.call(x + bl - KAPPA * bl, y + height),
        *point.call(x, y + height - bl + KAPPA * bl), *point.call(x, y + height - bl)) if bl.positive?
      path.line_to(*point.call(x, y + tl))
      path.curve_to(*point.call(x, y + tl - KAPPA * tl),
        *point.call(x + tl - KAPPA * tl, y), *point.call(x + tl, y)) if tl.positive?
      path.close
    end

    def inset_bounds(bounds, widths)
      top, right, bottom, left = widths
      ::Zaniah::Bounds.new(bounds.x + left, bounds.y + top,
        bounds.width - left - right, bounds.height - top - bottom)
    end

    def paint_fill(path, color, opacity, rule: :nonzero)
      return unless color.a.positive?
      with_alpha(color.a * opacity) { @page.path(path).fill(rgb(color), rule: rule.to_sym) }
    end

    def paint_stroke(path, color, width, opacity, cap: :butt, join: :miter, miter: 10, dash: nil)
      return unless color.a.positive?
      with_alpha(color.a * opacity) do
        @page.path(path).stroke(rgb(color), width: width, cap: cap || :butt,
          join: join || :miter, miter: miter || 10, dash: dash)
      end
    end

    def with_alpha(alpha)
      return if alpha <= 0
      alpha < 1 ? @page.opacity(alpha) { yield } : yield
    end

    def rgb(color) = [color.r, color.g, color.b]
  end
end

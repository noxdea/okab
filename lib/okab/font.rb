# frozen_string_literal: true

require "digest"

module Okab
  class Font
    attr_reader :face

    def self.load(path) = new(Alhena::Font.open(path))
    def self.embed(document, font, subset: true) = document.embed_font(font, subset: subset)

    def initialize(face)
      raise ArgumentError, "expected an Alhena::Font" unless face.is_a?(Alhena::Font)

      @face = face
    end

    def measure(text, size:)
      raise ArgumentError, "text must be valid UTF-8" unless text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
      raise ArgumentError, "size must be finite and positive" unless size.is_a?(Numeric) && size.finite? && size.positive?

      @face.glyph_ids(text).sum { |glyph| @face.advance_width(glyph) } * size.to_f / @face.units_per_em
    end
  end

  class EmbeddedFont
    attr_reader :document, :font, :subset

    def initialize(document, font, subset: true)
      @document, @font, @subset = document, font, !!subset
      @cid_by_character, @characters = {}, {0 => ["\u0000", 0]}
    end

    def face = @font.face
    def measure(text, size:) = @font.measure(text, size: size)

    def encode(string)
      codepoints = string.codepoints
      cids = []
      codepoints.each_with_index do |codepoint, index|
        next if variation_selector?(codepoint)

        selector = variation_selector?(codepoints[index + 1]) ? codepoints[index + 1] : nil
        glyph = face.glyph_id(codepoint, variation_selector: selector)
        glyph = face.glyph_id(codepoint) if glyph.zero? && selector
        character = [codepoint, *([selector] if selector)].pack("U*")
        key = [character, glyph]
        cid = @cid_by_character[key]
        unless cid
          cid = @characters.length
          raise ArgumentError, "a PDF font cannot encode more than 65,535 characters" if cid > 65_535

          @cid_by_character[key] = cid
          @characters[cid] = [character, glyph]
        end
        cids << cid
      end
      cids.pack("n*")
    end

    def glyph_ids
      @characters.values.map(&:last).uniq
    end

    def subset_font
      if face.cff?
        raise Alhena::UnsupportedFont, "CID CFF embedding requires subset: true" unless @subset

        data = Alhena::Subset.build_cid(face, @characters.values.map(&:last))
        return [data, face, {}, true]
      end

      selected = @subset ? glyph_ids : (0...face.glyph_count).to_a
      data = Alhena::Subset.build(face, selected)
      subset_face = Alhena::Font.new(data)
      old_ids = Alhena::Subset.closure(face, [0, *selected].uniq)
      [data, subset_face, old_ids.each_with_index.to_h, false]
    end

    def characters = @characters

    def base_name(data)
      prefix = Digest::SHA256.hexdigest(data).upcase[0, 6].tr("0-9", "A-J")
      family = face.family.to_s.gsub(/[^A-Za-z0-9]/, "")
      "#{prefix}+#{family.empty? ? 'EmbeddedFont' : family}"
    end

    private

    def variation_selector?(codepoint)
      codepoint && ((0xfe00..0xfe0f).cover?(codepoint) || (0xe0100..0xe01ef).cover?(codepoint))
    end

  end
end

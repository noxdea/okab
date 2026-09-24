# frozen_string_literal: true

require "zlib"

module Okab
  class Document
    def initialize(title: nil, author: nil, creator: "Okab")
      @metadata = {Title: title || "", Author: author || "", Creator: creator}
      @pages, @fonts, @images, @opacities, @outlines = [], {}, {}, {}, []
    end

    def page(width:, height:)
      page = Page.new(self, width: width, height: height)
      @pages << page
      yield page if block_given?
      page
    end

    def outline(title, page:, level: 0)
      raise ArgumentError, "outline page belongs to another document" unless @pages.include?(page)
      raise ArgumentError, "outline level must be a nonnegative integer" unless level.is_a?(Integer) && level >= 0
      raise ArgumentError, "outline level cannot skip a parent" if level > (@outlines.last&.last || -1) + 1

      @outlines << [String(title).dup.freeze, page, level]
      self
    end

    def owns_page?(page)
      @pages.include?(page)
    end

    def embed_font(font, subset: true)
      font = Font.new(font) if font.is_a?(Alhena::Font)
      raise ArgumentError, "font must be an Okab::Font or Alhena::Font" unless font.is_a?(Font)

      key = [font.face.object_id, !!subset]
      @fonts[key] ||= EmbeddedFont.new(self, font, subset: subset)
    end

    def register_image(image)
      raise ArgumentError, "expected an Okab::Image" unless image.is_a?(Image)

      key = image.object_id
      @images[key] ||= ["Im#{@images.length + 1}", image]
      @images.fetch(key).first
    end

    def opacity_name(value)
      raise ArgumentError, "opacity must be finite and between 0 and 1" unless value.is_a?(Numeric) && !value.is_a?(Complex) && value.finite? && value.between?(0, 1)

      @opacities[value.to_f] ||= "GS#{@opacities.length + 1}"
    end

    def render
      raise InvalidDocument, "document has no pages" if @pages.empty?

      writer = PDF::Writer.new
      pages_ref, catalog_ref, info_ref = writer.reserve, writer.reserve, writer.reserve
      page_refs = @pages.map { writer.reserve }
      font_resources = render_fonts(writer)
      image_resources = render_images(writer)
      opacity_resources = @opacities.to_h do |opacity, name|
        [name, writer.add("<< /Type /ExtGState /ca #{number(opacity)} /CA #{number(opacity)} >>")]
      end

      @pages.zip(page_refs).each do |page, page_ref|
        font_names = font_resources.to_h { |key, resource| [key.object_id, resource[:name]] }
        content = page.content(fonts: font_names)
        content_ref = writer.stream(content)
        annotations = page.annotations.map { |annotation| annotation_object(writer, annotation, page_refs) }
        fonts = font_resources.values.to_h { |font| [font[:name], font[:ref]] }
        resources = "<< /Font #{resource_dictionary(fonts)} " \
          "/XObject #{resource_dictionary(image_resources)} " \
          "/ExtGState #{resource_dictionary(opacity_resources)} >>"
        box = "[0 0 #{number(page.width)} #{number(page.height)}]"
        annotation_refs = annotations.empty? ? "" : "/Annots [#{annotations.map { |ref| "#{ref} 0 R" }.join(' ')}]"
        writer.set(page_ref, "<< /Type /Page /Parent #{pages_ref} 0 R /MediaBox #{box} /Resources #{resources} /Contents #{content_ref} 0 R #{annotation_refs} >>")
      end

      writer.set(pages_ref, "<< /Type /Pages /Count #{@pages.length} /Kids [#{page_refs.map { |ref| "#{ref} 0 R" }.join(' ')}] >>")
      outline_root = render_outlines(writer, page_refs)
      catalog = "<< /Type /Catalog /Pages #{pages_ref} 0 R"
      catalog << " /Outlines #{outline_root} 0 R /PageMode /UseOutlines" if outline_root
      catalog << " >>"
      writer.set(catalog_ref, catalog)
      writer.set(info_ref, "<< #{@metadata.map { |key, value| "/#{key} #{pdf_text(value)}" }.join(' ')} >>")
      writer.render(root: catalog_ref, info: info_ref)
    end

    def write(path)
      File.binwrite(path, render)
      path
    end

    private

    def render_fonts(writer)
      @fonts.values.each_with_index.filter_map do |embedded, index|
        data, subset_face, subset_map, cff = embedded.subset_font
        base_name = embedded.base_name(data)
        font_file = writer.stream(data, cff ? "/Subtype /CIDFontType0C" : "/Length1 #{data.bytesize}")
        bbox = subset_face.bbox.map { |value| scale(value, subset_face.units_per_em) }
        ascent = scale(subset_face.ascent, subset_face.units_per_em)
        descent = scale(subset_face.descent, subset_face.units_per_em)
        font_file_key = cff ? "FontFile3" : "FontFile2"
        descriptor = writer.add("<< /Type /FontDescriptor /FontName /#{base_name} /Flags 32 " \
          "/FontBBox [#{bbox.join(' ')}] /ItalicAngle 0 /Ascent #{ascent} /Descent #{descent} " \
          "/CapHeight #{ascent} /StemV 80 /#{font_file_key} #{font_file} 0 R >>")
        cid_to_gid = +"\0\0".b
        widths, mappings = [], []
        embedded.characters.each do |cid, (character, old_gid)|
          next if cid.zero?

          cid_to_gid << [subset_map.fetch(old_gid)].pack("n") unless cff
          widths << "#{cid} [#{scale(embedded.face.advance_width(old_gid), embedded.face.units_per_em)}]"
          mappings << "<#{format('%04X', cid)}> #{PDF::Encoding.unicode_hex(character)}"
        end
        cid_map = cff ? "" : " /CIDToGIDMap #{writer.stream(cid_to_gid)} 0 R"
        subtype = cff ? "CIDFontType0" : "CIDFontType2"
        cid_font = writer.add("<< /Type /Font /Subtype /#{subtype} /BaseFont /#{base_name} " \
          "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> " \
          "/FontDescriptor #{descriptor} 0 R /DW 1000 /W [#{widths.join(' ')}]#{cid_map} >>")
        cmap = to_unicode_cmap(mappings)
        cmap_ref = writer.stream(cmap)
        type0 = writer.add("<< /Type /Font /Subtype /Type0 /BaseFont /#{base_name} /Encoding /Identity-H " \
          "/DescendantFonts [#{cid_font} 0 R] /ToUnicode #{cmap_ref} 0 R >>")
        [embedded, {name: "F#{index + 1}", ref: type0}]
      end.to_h
    end

    def render_images(writer)
      @images.values.to_h do |name, image|
        smask = image.alpha && writer.stream(Zlib::Deflate.deflate(image.alpha),
          "/Type /XObject /Subtype /Image /Width #{image.width} /Height #{image.height} " \
          "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode")
        filter = image.filter == :dct ? "/Filter /DCTDecode" : "/Filter /FlateDecode"
        data = image.filter == :dct ? image.data : Zlib::Deflate.deflate(image.data)
        color_space = image.color_space == :gray ? "/DeviceGray" : "/DeviceRGB"
        decode = image.decode_parms ? "/DecodeParms << #{image.decode_parms} >>" : ""
        mask = smask ? "/SMask #{smask} 0 R" : ""
        ref = writer.stream(data, "/Type /XObject /Subtype /Image /Width #{image.width} /Height #{image.height} " \
          "/ColorSpace #{color_space} /BitsPerComponent 8 #{filter} #{decode} #{mask}")
        [name, ref]
      end
    end

    def render_outlines(writer, page_refs)
      return nil if @outlines.empty?

      root = writer.reserve
      top, parents = [], []
      @outlines.each do |title, page, requested_level|
        parents = parents.take(requested_level)
        siblings = requested_level.zero? ? top : parents.fetch(requested_level - 1)[:children]
        item = {title: title, page: page_refs.fetch(@pages.index(page)), children: []}
        siblings << item
        parents[requested_level] = item
      end
      refs = {}
      allocate = lambda do |siblings|
        siblings.each { |item| refs[item.object_id] = writer.reserve; allocate.call(item[:children]) unless item[:children].empty? }
      end
      allocate.call(top)
      write_items = lambda do |siblings, parent_ref|
        siblings.each_with_index do |item, index|
          ref = refs.fetch(item.object_id)
          sibling_refs = siblings.map { |sibling| refs.fetch(sibling.object_id) }
          values = "/Title #{pdf_text(item[:title])} /Parent #{parent_ref} 0 R /Dest [#{item[:page]} 0 R /Fit]"
          values << " /Prev #{sibling_refs[index - 1]} 0 R" if index.positive?
          values << " /Next #{sibling_refs[index + 1]} 0 R" if index + 1 < sibling_refs.length
          unless item[:children].empty?
            child_refs = item[:children].map { |child| refs.fetch(child.object_id) }
            values << " /First #{child_refs.first} 0 R /Last #{child_refs.last} 0 R /Count #{descendant_count(item)}"
          end
          writer.set(ref, "<< #{values} >>")
          write_items.call(item[:children], ref) unless item[:children].empty?
        end
      end
      write_items.call(top, root)
      top_refs = top.map { |item| refs.fetch(item.object_id) }
      count = top.sum { |item| 1 + descendant_count(item) }
      writer.set(root, "<< /Type /Outlines /First #{top_refs.first} 0 R /Last #{top_refs.last} 0 R /Count #{count} >>")
      root
    end

    def descendant_count(item)
      item[:children].sum { |child| 1 + descendant_count(child) }
    end

    def annotation_object(writer, annotation, page_refs)
      x, y, width, height, type, target = annotation
      rect = "[#{number(x)} #{number(y)} #{number(x + width)} #{number(y + height)}]"
      action = if type == :uri
        "/A << /S /URI /URI #{pdf_text(target)} >>"
      else
        "/Dest [#{page_refs.fetch(@pages.index(target))} 0 R /Fit]"
      end
      writer.add("<< /Type /Annot /Subtype /Link /Rect #{rect} /Border [0 0 0] #{action} >>")
    end

    def resource_dictionary(resources)
      entries = resources.map { |name, ref| "/#{PDF::Encoding.name(name)} #{ref} 0 R" }
      "<< #{entries.join(' ')} >>"
    end

    def to_unicode_cmap(mappings)
      chunks = mappings.each_slice(100).map do |entries|
        "#{entries.length} beginbfchar\n#{entries.join("\n")}\nendbfchar\n"
      end.join
      "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n" \
        "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n" \
        "/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n" \
        "#{chunks}endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend"
    end

    def pdf_text(value)
      text = String(value).encode(::Encoding::UTF_8)
      if text.ascii_only?
        "(#{text.gsub(/[\\()]/) { |character| "\\#{character}" }.gsub(/[\x00-\x1f\x7f]/) { |character| format('\\%03o', character.ord) }})"
      else
        PDF::Encoding.hex("\xFE\xFF".b + text.encode(::Encoding::UTF_16BE).b)
      end
    rescue EncodingError
      raise ArgumentError, "PDF text must be valid UTF-8"
    end

    def scale(value, units_per_em)
      (value.to_f * 1000 / units_per_em).round
    end

    def number(value)
      PDF::Encoding.number(value)
    end
  end
end

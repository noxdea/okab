# frozen_string_literal: true

require "zlib"

module Okab
  class Image
    # ponytail: cap decoded memory at 50 MP; add streaming raster output if larger images are needed.
    MAX_PIXELS = 50_000_000
    private_constant :MAX_PIXELS
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
    private_constant :PNG_SIGNATURE

    attr_reader :width, :height, :color_space, :data, :alpha, :filter, :decode_parms

    def self.decode(bytes, format: :auto)
      raise ArgumentError, "image data must be a String" unless bytes.is_a?(String)
      format = :png if format == :auto && bytes.start_with?(PNG_SIGNATURE)
      format = :jpeg if format == :auto && bytes.start_with?("\xff\xd8".b)
      raise ArgumentError, "unsupported image format" unless %i[png jpeg].include?(format)

      format == :png ? decode_png(bytes) : decode_jpeg(bytes)
    end

    def initialize(width:, height:, color_space:, data:, alpha: nil, filter: nil, decode_parms: nil)
      raise InvalidDocument, "invalid image dimensions" unless width.is_a?(Integer) && height.is_a?(Integer) &&
        width.positive? && height.positive? && width * height <= MAX_PIXELS
      raise InvalidDocument, "invalid image color space" unless %i[gray rgb].include?(color_space)
      raise InvalidDocument, "invalid image data" unless data.is_a?(String)
      if filter == :dct
        raise InvalidDocument, "invalid JPEG data" unless data.start_with?("\xff\xd8".b) && alpha.nil?
        raise InvalidDocument, "invalid JPEG decode parameters" unless [nil, "/ColorTransform 1"].include?(decode_parms)
      else
        channels = color_space == :gray ? 1 : 3
        raise InvalidDocument, "invalid pixel data length" unless filter.nil? && decode_parms.nil? && data.bytesize == width * height * channels
        raise InvalidDocument, "invalid alpha data length" if alpha && (!alpha.is_a?(String) || alpha.bytesize != width * height)
      end

      @width, @height, @color_space = width, height, color_space
      @data, @alpha, @filter, @decode_parms = data.b.freeze, alpha&.b&.freeze, filter, decode_parms
      freeze
    end

    def self.decode_png(bytes)
      at, header, palette, transparency, compressed = PNG_SIGNATURE.bytesize, nil, nil, nil, +"".b
      while at < bytes.bytesize
        raise InvalidDocument, "truncated PNG chunk" if at + 12 > bytes.bytesize
        length = bytes.byteslice(at, 4).unpack1("N")
        type = bytes.byteslice(at + 4, 4)
        raise InvalidDocument, "invalid PNG chunk length" if length > bytes.bytesize - at - 12
        payload = bytes.byteslice(at + 8, length)
        checksum = bytes.byteslice(at + 8 + length, 4).unpack1("N")
        raise InvalidDocument, "PNG checksum mismatch" unless Zlib.crc32(type + payload) == checksum
        case type
        when "IHDR" then header = payload
        when "PLTE" then palette = payload
        when "tRNS" then transparency = payload
        when "IDAT" then compressed << payload
        when "IEND" then break
        end
        at += length + 12
      end
      raise InvalidDocument, "missing PNG header" unless header&.bytesize == 13
      width, height, depth, type, compression, filtering, interlace = header.unpack("NNC5")
      raise InvalidDocument, "unsupported PNG format" unless depth == 8 && compression.zero? && filtering.zero? && interlace.zero?
      # ponytail: only 8-bit non-interlaced PNG is decoded; packed, 16-bit, and Adam7 modes add separate row walkers.
      raise InvalidDocument, "invalid PNG dimensions" unless width.positive? && height.positive? && width * height <= MAX_PIXELS
      channels = {0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4}[type]
      raise InvalidDocument, "unsupported PNG color type" unless channels
      raise InvalidDocument, "indexed PNG has no palette" if type == 3 && (!palette || palette.empty? || palette.bytesize % 3 != 0)
      decoded = inflate_bounded(compressed, (width * channels + 1) * height)
      row_bytes, bpp = width * channels, channels
      prior = "\0" * row_bytes
      rgb, alpha = +"".b, +"".b
      height.times do |row|
        offset = row * (row_bytes + 1)
        filter = decoded.getbyte(offset)
        current = decoded.byteslice(offset + 1, row_bytes).bytes
        prior_bytes = prior.bytes
        current.each_index do |index|
          left = index >= bpp ? current[index - bpp] : 0
          above = prior_bytes[index]
          upper_left = index >= bpp ? prior_bytes[index - bpp] : 0
          current[index] = (current[index] + case filter
          when 0 then 0
          when 1 then left
          when 2 then above
          when 3 then (left + above) / 2
          when 4 then paeth(left, above, upper_left)
          else raise InvalidDocument, "invalid PNG filter"
          end) & 255
        end
        prior = current.pack("C*")
        width.times do |column|
          pixel = column * channels
          case type
          when 0
            gray = current[pixel]
            rgb << gray.chr * 3
            alpha << (transparency&.unpack1("n") == gray ? 0 : 255)
          when 2
            values = current[pixel, 3]
            rgb << values.pack("C*")
            alpha << (transparency && transparency.unpack("n*") == values ? 0 : 255)
          when 3
            index = current[pixel]
            raise InvalidDocument, "PNG palette index out of range" if index * 3 + 2 >= palette.bytesize
            rgb << palette.byteslice(index * 3, 3)
            alpha << (transparency&.getbyte(index) || 255)
          when 4
            rgb << current[pixel].chr * 3
            alpha << current[pixel + 1]
          when 6
            rgb << current[pixel, 3].pack("C*")
            alpha << current[pixel + 3]
          end
        end
      end
      alpha = nil if alpha.each_byte.all? { |value| value == 255 }
      new(width: width, height: height, color_space: :rgb, data: rgb, alpha: alpha)
    rescue Zlib::Error => error
      raise InvalidDocument, "invalid PNG compression: #{error.message}"
    end

    def self.decode_jpeg(bytes)
      raise InvalidDocument, "invalid JPEG marker" unless bytes.start_with?("\xff\xd8".b)
      at, frame = 2, nil
      while at + 4 <= bytes.bytesize
        at += 1 while at < bytes.bytesize && bytes.getbyte(at) != 0xff
        at += 1 while at < bytes.bytesize && bytes.getbyte(at) == 0xff
        marker = bytes.getbyte(at)
        at += 1
        next if [0xd8, 0xd9, 0x01, *0xd0..0xd7].include?(marker)
        length = bytes.byteslice(at, 2)&.unpack1("n")
        raise InvalidDocument, "truncated JPEG segment" unless length && length >= 2 && at + length <= bytes.bytesize
        # ponytail: support Huffman DCT SOF modes only; lossless/arithmetic JPEG needs another PDF image filter.
        if [0xc0, 0xc1, 0xc2].include?(marker)
          precision, height, width, components = bytes.byteslice(at + 2, 6).unpack("CnnC")
          raise InvalidDocument, "unsupported JPEG component count" unless [1, 3].include?(components)
          raise InvalidDocument, "unsupported JPEG precision" unless precision == 8
          frame = [width, height, components]
        elsif marker == 0xda
          raise InvalidDocument, "JPEG frame header not found" unless frame
          eoi = bytes.rindex("\xff\xd9".b)
          raise InvalidDocument, "JPEG image data is incomplete" unless eoi && eoi >= at + length
          width, height, components = frame
          return new(width: width, height: height, color_space: components == 1 ? :gray : :rgb,
            data: bytes, filter: :dct, decode_parms: components == 3 ? "/ColorTransform 1" : nil)
        end
        at += length
      end
      raise InvalidDocument, frame ? "JPEG scan header not found" : "JPEG frame header not found"
    end

    def self.inflate_bounded(bytes, expected)
      inflater, output = Zlib::Inflate.new, +"".b
      offset = 0
      while offset < bytes.bytesize
        output << inflater.inflate(bytes.byteslice(offset, 4096))
        raise InvalidDocument, "PNG data exceeds declared dimensions" if output.bytesize > expected
        offset += 4096
      end
      output << inflater.finish
      raise InvalidDocument, "PNG data length does not match dimensions" unless output.bytesize == expected
      output
    ensure
      inflater&.close
    end

    def self.paeth(left, above, upper_left)
      estimate = left + above - upper_left
      left_distance = (estimate - left).abs
      above_distance = (estimate - above).abs
      corner_distance = (estimate - upper_left).abs
      if left_distance <= above_distance && left_distance <= corner_distance
        left
      elsif above_distance <= corner_distance
        above
      else
        upper_left
      end
    end
  end
end

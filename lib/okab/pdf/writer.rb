# frozen_string_literal: true

require "bigdecimal"

module Okab
  module PDF
    class Writer
      def initialize
        @objects = []
      end

      def reserve
        @objects << nil
        @objects.length
      end

      def add(value)
        @objects << value.b
        @objects.length
      end

      def set(reference, value)
        raise InvalidDocument, "invalid PDF object reference" unless reference.between?(1, @objects.length)
        raise InvalidDocument, "PDF object already assigned" if @objects[reference - 1]

        @objects[reference - 1] = value.b
      end

      def stream(data, dictionary = "")
        add("<< /Length #{data.bytesize} #{dictionary} >>\nstream\n".b + data.b + "\nendstream".b)
      end

      def render(root:, info:)
        raise InvalidDocument, "unassigned PDF object" if @objects.any?(&:nil?)

        output = +"%PDF-1.7\n%\xE2\xE3\xCF\xD3\n".b
        offsets = [0]
        @objects.each_with_index do |object, index|
          offsets << output.bytesize
          output << "#{index + 1} 0 obj\n".b << object << "\nendobj\n".b
        end
        xref = output.bytesize
        output << "xref\n0 #{@objects.length + 1}\n0000000000 65535 f \n".b
        offsets.drop(1).each { |offset| output << format("%010d 00000 n \n", offset).b }
        output << "trailer\n<< /Size #{@objects.length + 1} /Root #{root} 0 R /Info #{info} 0 R >>\n".b
        output << "startxref\n#{xref}\n%%EOF\n".b
      end
    end

    module Encoding
      module_function

      def hex(bytes) = "<#{bytes.b.unpack1('H*')}>"

      def number(value)
        number = value.to_f
        raise ArgumentError, "PDF numbers must be finite" unless number.finite?

        BigDecimal(number.to_s).to_s("F")
      end

      def unicode_hex(text)
        hex(text.encode(::Encoding::UTF_16BE).b)
      end

      def name(value)
        value.to_s.b.gsub(/[^A-Za-z0-9_.+-]/) { |byte| format("#%02X", byte.ord) }
      end
    end
  end
end

# frozen_string_literal: true

require_relative "okab/version"
require "alhena"

module Okab
  class Error < StandardError; end
  class InvalidDocument < Error; end
end

require_relative "okab/pdf/writer"
require_relative "okab/font"
require_relative "okab/image"
require_relative "okab/page"
require_relative "okab/document"

# frozen_string_literal: true

require_relative "lib/okab/version"

Gem::Specification.new do |spec|
  spec.name = "okab"
  spec.version = Okab::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]

  spec.summary = "Generate searchable, font-embedded PDF documents"
  spec.description = "A Ruby library for deterministic PDF generation with embedded TrueType fonts, Japanese text extraction, vector graphics, PNG/JPEG images, links, and outlines."
  spec.homepage = "https://github.com/noxdea/okab"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Package only tracked runtime files.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "alhena", ">= 0.3.0", "< 0.4"
  spec.add_dependency "bigdecimal", "~> 3.1"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end

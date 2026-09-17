# frozen_string_literal: true

require_relative "lib/gsc/version"

Gem::Specification.new do |spec|
  spec.name          = "gsc-cli"
  spec.version       = GSC::VERSION
  spec.authors       = ["ApollosWave LLC"]
  spec.email         = ["support@apolloswave.com"]

  spec.summary       = "Google Search Console, Google Indexing API, Keyword Intelligence & Real-Time Trends CLI"
  spec.description   = <<~DESC
    == OVERVIEW

    A lightweight, zero-gem CLI tool and AI agent engine for Google Search Console, Google Indexing API, Google Analytics 4, Keywords Everywhere, and Google Trends.

    == APOLLOSWAVE ECOSYSTEM

    Built and maintained by {ApollosWave LLC}[https://apolloswave.com/?utm_source=rubygems&utm_medium=gem_desc&utm_campaign=gsc-cli]. Check out our commercial products:

    * {Superspeed}[https://superspeedapp.com/?utm_source=rubygems&utm_medium=gem_desc&utm_campaign=gsc-cli] - Lightning-fast macOS disk cleaner and RAM booster for Apple Silicon.
    * {Supercart}[https://supercartapp.com/?utm_source=rubygems&utm_medium=gem_desc&utm_campaign=gsc-cli] - High-converting slide cart drawer and 1-click upsells for Shopify stores.
    * {PackingLog}[https://packinglog.com/?utm_source=rubygems&utm_medium=gem_desc&utm_campaign=gsc-cli] - Smart QR-code moving box inventory and photo catalog.
  DESC

  spec.homepage      = "https://apolloswave.com"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files         = Dir["lib/**/*", "dist/*", "*.md", "LICENSE"] + ["bin/gsc"]
  spec.bindir        = "bin"
  spec.executables   = ["gsc"]
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"]      = "https://apolloswave.com/?utm_source=rubygems&utm_medium=gem_sidebar&utm_campaign=gsc-cli"
  spec.metadata["source_code_uri"]   = "https://github.com/ApollosWave/gsc-cli"
  spec.metadata["documentation_uri"] = "https://github.com/ApollosWave/gsc-cli#readme"
  spec.metadata["bug_tracker_uri"]   = "https://github.com/ApollosWave/gsc-cli/issues"
  spec.metadata["changelog_uri"]     = "https://github.com/ApollosWave/gsc-cli/blob/main/README.md"
  spec.metadata["funding_uri"]       = "https://github.com/ApollosWave/gsc-cli#-sponsorship--backing"
end

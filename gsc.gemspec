# frozen_string_literal: true

require_relative "lib/gsc/version"

Gem::Specification.new do |spec|
  spec.name          = "gsc-cli"
  spec.version       = GSC::VERSION
  spec.authors       = ["ApollosWave LLC"]
  spec.email         = ["support@apolloswave.com"]

  spec.summary       = "Zero-gem Google Search Console, Google Indexing API & Core Web Vitals CLI in pure Ruby"
  spec.description   = <<~DESC
    A high-performance, zero-dependency CLI tool and developer engine for Google Search Console, Google Indexing API, and Core Web Vitals. Built entirely with the pure Ruby standard library (Net::HTTP, OpenSSL, JSON) with sub-millisecond cold boot and comprehensive test coverage.

    == PRODUCTION DOGFOODING & ECOSYSTEM

    Maintained by {ApollosWave LLC}[https://apolloswave.com]. Production software built by our team:

    * {Superspeed}[https://superspeedapp.com] - Real-user monitoring (RUM), Core Web Vitals & speed intelligence for high-volume Shopify storefronts.
    * {Supercart}[https://supercartapp.com] - Slide cart drawer, in-house shipping protection & real-time e-commerce upsell infrastructure.
    * {PackingLog}[https://packinglog.com] - Smart QR-code moving box inventory and photo catalog SaaS.
  DESC

  spec.homepage      = "https://github.com/ApollosWave/gsc-cli"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files         = Dir["lib/**/*", "dist/*", "*.md", "LICENSE"] + ["bin/gsc"]
  spec.bindir        = "bin"
  spec.executables   = ["gsc"]
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"]      = "https://apolloswave.com"
  spec.metadata["source_code_uri"]   = "https://github.com/ApollosWave/gsc-cli"
  spec.metadata["documentation_uri"] = "https://github.com/ApollosWave/gsc-cli#readme"
  spec.metadata["bug_tracker_uri"]   = "https://github.com/ApollosWave/gsc-cli/issues"
  spec.metadata["changelog_uri"]     = "https://github.com/ApollosWave/gsc-cli/blob/main/README.md"
  spec.metadata["funding_uri"]       = "https://github.com/ApollosWave/gsc-cli#-sponsorship--backing"
end

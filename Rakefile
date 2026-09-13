# frozen_string_literal: true

require "fileutils"
require_relative "lib/gsc/version"

task default: :test

desc "Run syntax checks and all unit test suites"
task :test do
  puts "Checking syntax of all Ruby files..."
  files = Dir["lib/**/*.rb", "bin/gsc", "dist/gsc"].select { |f| File.file?(f) }
  failed = []

  files.each do |file|
    print "  Checking #{file}... "
    ok = system("ruby", "-c", file, out: File::NULL, err: File::NULL)
    if ok
      puts "OK"
    else
      puts "FAILED"
      failed << file
    end
  end

  if failed.any?
    abort "Syntax checks failed for: #{failed.join(", ")}"
  else
    puts "All #{files.size} Ruby files passed syntax checks!"
  end

  puts "\nRunning unit test suites..."
  test_files = Dir["test/**/*_test.rb"]
  if test_files.any?
    ok = system("ruby", "-Ilib", "-Itest", "-e", "Dir['test/**/*_test.rb'].each { |f| require File.expand_path(f) }")
    abort "Unit tests failed!" unless ok
  end
end

desc "Build standalone single-file distribution into dist/gsc"
task :"build:standalone" do
  puts "Bundling lib/gsc modules into dist/gsc..."
  FileUtils.mkdir_p("dist")
  dist_bin = File.expand_path("dist/gsc", __dir__)

  files_order = [
    "version.rb",
    "color.rb",
    "config.rb",
    "auth.rb",
    "client.rb",
    "api.rb",
    "sitemap_loader.rb",
    "google_trends.rb",
    "keyword_planner.rb",
    "keywords_everywhere.rb",
    "prompts.rb",
    "page_analyzer.rb",
    "site_crawler.rb",
    "google_suggest.rb",
    "open_page_rank.rb",
    "page_speed.rb",
    "page_comparator.rb",
    "content_gap.rb",
    "internal_links.rb",
    "schema_validator.rb",
    "llms_generator.rb",
    "serp_preview.rb",
    "network_tracer.rb",
    "robots_checker.rb",
    "backlinks_manager.rb",
    "indexnow.rb",
    "command_registry.rb",
    "cli_advanced.rb",
    "cli.rb"
  ]

  out = []
  out << "#!/usr/bin/env ruby"
  out << "# frozen_string_literal: true"
  out << ""
  out << "# =============================================================================="
  out << "# Google Search Console & Indexing API CLI Tool (Pure Ruby - Zero Gem Dependencies)"
  out << "# Standalone Single-File Distribution (Built from lib/gsc v#{GSC::VERSION})"
  out << "# =============================================================================="
  out << ""
  out << "require 'net/http'"
  out << "require 'uri'"
  out << "require 'json'"
  out << "require 'openssl'"
  out << "require 'base64'"
  out << "require 'optparse'"
  out << "require 'time'"
  out << "require 'date'"
  out << "require 'fileutils'"
  out << "require 'zlib'"
  out << "require 'stringio'"
  out << ""

  files_order.each do |filename|
    path = File.join(__dir__, "lib", "gsc", filename)
    content = File.read(path, encoding: "UTF-8")
    clean = content.gsub(/^# frozen_string_literal: true\s*/, "")
    out << "# --- #{filename} ---"
    out << clean.strip
    out << ""
  end

  out << "# Top-level aliases for backwards compatibility"
  out << "GoogleTrends       = GSC::GoogleTrends unless defined?(GoogleTrends)"
  out << "KeywordPlanner     = GSC::KeywordPlanner unless defined?(KeywordPlanner)"
  out << "KeywordsEverywhere = GSC::KeywordsEverywhere unless defined?(KeywordsEverywhere)"
  out << "Prompts            = GSC::Prompts unless defined?(Prompts)"
  out << "PageAnalyzer       = GSC::PageAnalyzer unless defined?(PageAnalyzer)"
  out << "SiteCrawler        = GSC::SiteCrawler unless defined?(SiteCrawler)"
  out << ""
  out << "GSC::CLI.start(ARGV)"
  out << ""

  File.write(dist_bin, out.join("\n"), encoding: "UTF-8")
  File.chmod(0755, dist_bin)

  puts "Standalone binary created at #{dist_bin} (#{File.size(dist_bin)} bytes)"
end

desc "Install standalone executable to ~/.local/bin/gsc"
task :"install:standalone" => :"build:standalone" do
  target_dir = File.expand_path("~/.local/bin")
  FileUtils.mkdir_p(target_dir)
  target_bin = File.join(target_dir, "gsc")

  FileUtils.cp("dist/gsc", target_bin)
  File.chmod(0755, target_bin)
  puts "Installed standalone gsc to #{target_bin}"
end

desc "Build RubyGem package"
task :"gem:build" do
  sh "gem build gsc.gemspec"
end

desc "Build and install RubyGem package locally"
task :"gem:install" => :"gem:build" do
  sh "gem install gsc-cli-#{GSC::VERSION}.gem"
end

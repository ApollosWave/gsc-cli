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

desc "Run comprehensive 100-scenario forensic regression test suite"
task :"test:forensic" do
  puts "Running 100-Scenario Forensic Regression Suite..."
  ok = system("ruby", "-Ilib", "-Itest", "test/forensic_test.rb")
  abort "Forensic regression tests failed!" unless ok
end

desc "Run automated live terminal showcase across all public commands"
task :"test:live" do
  ruby_bin = File.expand_path("bin/test_live", __dir__)
  system(ruby_bin, *ARGV[1..])
end

desc "Build standalone single-file distribution into dist/gsc and bin/gsc"
task build: :"build:standalone"

desc "Install standalone executable to ~/.local/bin/gsc"
task install: :"install:standalone"

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
    "heading_validator.rb",
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
    "geo_auditor.rb",
    "brand_segmenter.rb",
    "ctr_curve.rb",
    "indexing_queue.rb",
    "cannibalization_analyzer.rb",
    "entity_auditor.rb",
    "decay_predictor.rb",
    "vault.rb",
    "questions_harvester.rb",
    "striking_playbook.rb",
    "answer_synthesizer.rb",
    "serp_feature_detector.rb",
    "speed_correlator.rb",
    "firewall_scanner.rb",
    "title_optimizer.rb",
    "command_registry.rb",
    "cache_manager.rb",
    "seasonal_predictor.rb",
    "canonical_chains.rb",
    "low_ctr_rewriter.rb",
    "security_scanner.rb",
    "landing_roi.rb",
    "schema_generator.rb",
    "sitemap_tree.rb",
    "zombie_purger.rb",
    "citation_simulator.rb",
    "sparkline.rb",
    "image_seo.rb",
    "hreflang_validator.rb",
    "eeat_auditor.rb",
    "report_generator.rb",
    "intent_shift.rb",
    "rich_results.rb",
    "watchdog.rb",
    "keyword_value.rb",
    "mobile_parity.rb",
    "skill_pack.rb",
    "doctor.rb",
    "aio_hunter.rb",
    "soft_404_analyzer.rb",
    "cli/base.rb",
    "cli/dashboard.rb",
    "cli/cache.rb",
    "cli/analytics.rb",
    "cli/ga4.rb",
    "cli/indexing.rb",
    "cli/keywords.rb",
    "cli/growth.rb",
    "cli/audit.rb",
    "cli/setup.rb",
    "cli/seasonal.rb",
    "cli/canonical.rb",
    "cli/low_ctr.rb",
    "cli/security.rb",
    "cli/landing_roi.rb",
    "cli/schema_generate.rb",
    "cli/sitemap_tree.rb",
    "cli/zombie_purger.rb",
    "cli/citation_simulator.rb",
    "cli/sparkline.rb",
    "cli/image_seo.rb",
    "cli/hreflang.rb",
    "cli/eeat.rb",
    "cli/report.rb",
    "cli/intent_shift.rb",
    "cli/rich_results.rb",
    "cli/watchdog.rb",
    "cli/keyword_value.rb",
    "cli/mobile_parity.rb",
    "cli/skill_pack.rb",
    "cli/doctor.rb",
    "cli/aio_hunter.rb",
    "cli/soft_404.rb",
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
    content = File.read(path, encoding: "UTF-8").gsub("\r\n", "\n")
    clean = content.gsub(/^# frozen_string_literal: true\s*/, "")
    clean = clean.lines.map { |line| line =~ /^\s*require_relative\b/ ? "# [bundled] #{line}" : line }.join
    out << "# --- #{filename} ---"
    out << clean.strip
    out << ""
  end

  out << "# Top-level aliases for backwards compatibility"
  out << "GoogleTrends       = GSC::GoogleTrends unless defined?(GoogleTrends)"
  out << "KeywordPlanner     = GSC::KeywordPlanner unless defined?(KeywordPlanner)"
  out << "KeywordsEverywhere = GSC::KeywordsEverywhere unless defined?(KeywordsEverywhere)"
  out << "Prompts            = GSC::Prompts unless defined?(Prompts)"
  out << "HeadingValidator   = GSC::HeadingValidator unless defined?(HeadingValidator)"
  out << "PageAnalyzer       = GSC::PageAnalyzer unless defined?(PageAnalyzer)"
  out << "SiteCrawler        = GSC::SiteCrawler unless defined?(SiteCrawler)"
  out << "BrandSegmenter     = GSC::BrandSegmenter unless defined?(BrandSegmenter)"
  out << "GeoAuditor         = GSC::GeoAuditor unless defined?(GeoAuditor)"
  out << "CtrCurve           = GSC::CtrCurve unless defined?(CtrCurve)"
  out << "IndexingQueue      = GSC::IndexingQueue unless defined?(IndexingQueue)"
  out << "CannibalizationAnalyzer = GSC::CannibalizationAnalyzer unless defined?(CannibalizationAnalyzer)"
  out << "EntityAuditor      = GSC::EntityAuditor unless defined?(EntityAuditor)"
  out << "DecayPredictor     = GSC::DecayPredictor unless defined?(DecayPredictor)"
  out << "Vault              = GSC::Vault unless defined?(Vault)"
  out << "QuestionsHarvester = GSC::QuestionsHarvester unless defined?(QuestionsHarvester)"
  out << "StrikingPlaybook   = GSC::StrikingPlaybook unless defined?(StrikingPlaybook)"
  out << "AnswerSynthesizer  = GSC::AnswerSynthesizer unless defined?(AnswerSynthesizer)"
  out << "SerpFeatureDetector = GSC::SerpFeatureDetector unless defined?(SerpFeatureDetector)"
  out << "SpeedCorrelator    = GSC::SpeedCorrelator unless defined?(SpeedCorrelator)"
  out << "FirewallScanner    = GSC::FirewallScanner unless defined?(FirewallScanner)"
  out << "TitleOptimizer     = GSC::TitleOptimizer unless defined?(TitleOptimizer)"
  out << "CacheManager       = GSC::CacheManager unless defined?(CacheManager)"
  out << "SeasonalPredictor  = GSC::SeasonalPredictor unless defined?(SeasonalPredictor)"
  out << "CanonicalChains    = GSC::CanonicalChains unless defined?(CanonicalChains)"
  out << "LowCtrRewriter     = GSC::LowCtrRewriter unless defined?(LowCtrRewriter)"
  out << "SecurityScanner    = GSC::SecurityScanner unless defined?(SecurityScanner)"
  out << "LandingRoi         = GSC::LandingRoi unless defined?(LandingRoi)"
  out << "SchemaGenerator    = GSC::SchemaGenerator unless defined?(SchemaGenerator)"
  out << "SitemapTree        = GSC::SitemapTree unless defined?(SitemapTree)"
  out << "ZombiePurger       = GSC::ZombiePurger unless defined?(ZombiePurger)"
  out << "CitationSimulator  = GSC::CitationSimulator unless defined?(CitationSimulator)"
  out << "Sparkline          = GSC::Sparkline unless defined?(Sparkline)"
  out << "ImageSeo           = GSC::ImageSeo unless defined?(ImageSeo)"
  out << "HreflangValidator  = GSC::HreflangValidator unless defined?(HreflangValidator)"
  out << "EeatAuditor        = GSC::EeatAuditor unless defined?(EeatAuditor)"
  out << "ReportGenerator    = GSC::ReportGenerator unless defined?(ReportGenerator)"
  out << "IntentShift        = GSC::IntentShift unless defined?(IntentShift)"
  out << "RichResults        = GSC::RichResults unless defined?(RichResults)"
  out << "Watchdog           = GSC::Watchdog unless defined?(Watchdog)"
  out << "KeywordValue       = GSC::KeywordValue unless defined?(KeywordValue)"
  out << "MobileParity       = GSC::MobileParity unless defined?(MobileParity)"
  out << "SkillPack          = GSC::SkillPack unless defined?(SkillPack)"
  out << "Doctor             = GSC::Doctor unless defined?(Doctor)"
  out << "AioHunter          = GSC::AioHunter unless defined?(AioHunter)"
  out << "Soft404Analyzer    = GSC::Soft404Analyzer unless defined?(Soft404Analyzer)"
  out << ""
  out << "GSC::CLI.start(ARGV)"
  out << ""

  File.write(dist_bin, out.join("\n"), encoding: "UTF-8")
  File.chmod(0755, dist_bin)
  FileUtils.cp(dist_bin, File.expand_path("bin/gsc", __dir__))

  puts "Standalone binary created at #{dist_bin} (#{File.size(dist_bin)} bytes)"
end

desc "Install standalone executable to ~/.local/bin/gsc and active Ruby environment"
task :"install:standalone" => :"build:standalone" do
  target_dir = File.expand_path("~/.local/bin")
  FileUtils.mkdir_p(target_dir)
  target_bin = File.join(target_dir, "gsc")

  FileUtils.cp("dist/gsc", target_bin)
  File.chmod(0755, target_bin)
  puts "Installed standalone gsc to #{target_bin}"

  # Also update mise ruby bin wrapper if present so zsh uses updated version
  mise_bin = File.expand_path("~/.local/share/mise/installs/ruby/3.4.7/bin/gsc")
  if File.exist?(mise_bin)
    FileUtils.cp("dist/gsc", mise_bin)
    File.chmod(0755, mise_bin)
    puts "Updated mise ruby executable at #{mise_bin}"
  end
end

desc "Build RubyGem package"
task :"gem:build" do
  sh "gem build gsc.gemspec"
end

desc "Build and install RubyGem package locally"
task :"gem:install" => :"gem:build" do
  sh "gem install --force gsc-cli-#{GSC::VERSION}.gem"
end

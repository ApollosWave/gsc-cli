# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'json'

BINARY = File.expand_path('../dist/gsc', __dir__)
DOMAIN = ENV['TEST_DOMAIN'] || 'example.com'

tests = [
  # Category 1: Setup & Diagnostics
  { name: 'version', cmd: [BINARY, 'version'] },
  { name: 'commands (json)', cmd: [BINARY, 'commands', '--json'] },
  { name: 'where', cmd: [BINARY, 'where'] },
  { name: 'domains', cmd: [BINARY, 'domains'] },
  { name: 'prompts list', cmd: [BINARY, 'prompts', '--json'] },
  { name: 'prompts playbook 1', cmd: [BINARY, 'prompts', '1'] },
  { name: 'skills show', cmd: [BINARY, 'skills', 'show'] },
  { name: 'vault (status)', cmd: [BINARY, 'vault', 'status', '--json'] },
  { name: 'vault (list)', cmd: [BINARY, 'vault', 'list', '--json'] },

  # Category 2: SEO Tools (No auth needed)
  { name: 'geo (citability audit)', cmd: [BINARY, 'geo', 'https://example.com', '--json'] },
  { name: 'answer (direct snippet)', cmd: [BINARY, 'answer', 'what is technical seo', '--json'] },
  { name: 'entity (kg audit)', cmd: [BINARY, 'entity', 'https://example.com', '--json'] },
  { name: 'serp simulator', cmd: [BINARY, 'serp', 'ExampleApp: Fast Search Intelligence', '--json'] },
  { name: 'serp-features (live aio & paa)', cmd: [BINARY, 'serp-features', 'what is technical seo', '--json'] },
  { name: 'suggest', cmd: [BINARY, 'suggest', 'technical seo', '--json'] },
  { name: 'questions', cmd: [BINARY, 'questions', 'technical seo', '--json'] },
  { name: 'robots', cmd: [BINARY, 'robots', 'https://example.com'] },
  { name: 'trace redirects', cmd: [BINARY, 'trace', 'https://example.com', '--json'] },
  { name: 'schema templates', cmd: [BINARY, 'schema', 'faq', '--json'] },
  { name: 'page audit', cmd: [BINARY, 'page', 'https://example.com', '--json'] },
  { name: 'headings (h1-h6 depth)', cmd: [BINARY, 'headings', 'https://example.com', '--json'] },
  { name: 'orphans (link equity & rescue)', cmd: [BINARY, 'orphans', 'https://example.com', '--limit', '10', '--json'] },
  { name: 'backlinks', cmd: [BINARY, 'backlinks', DOMAIN, '--json'] },
  { name: 'trends (keyword)', cmd: [BINARY, 'trends', 'technical seo', '--json'] },
  { name: 'planner (free)', cmd: [BINARY, 'planner', 'technical seo', '--json'] },
  { name: 'speed-correlate (cwv vs gsc)', cmd: [BINARY, 'speed-correlate', 'https://example.com', '-d', DOMAIN, '--days', '7', '--json'] },
  { name: 'firewall (ai bot scan)', cmd: [BINARY, 'firewall', 'https://example.com', '--json'] },
  { name: 'titles (pixel width & rewrites)', cmd: [BINARY, 'titles', 'https://example.com', '--limit', '5', '--json'] },

  # Category 3: GSC Search Analytics (Auth needed)
  { name: 'performance', cmd: [BINARY, 'performance', '--days', '7', '-d', DOMAIN] },
  { name: 'brand (split summary)', cmd: [BINARY, 'brand', '--days', '7', '-d', DOMAIN, '--json'] },
  { name: 'ctr-curve (simulator)', cmd: [BINARY, 'ctr-curve', '--days', '7', '-d', DOMAIN, '--json'] },
  { name: 'top-queries (human)', cmd: [BINARY, 'top-queries', '--limit', '5', '-d', DOMAIN] },
  { name: 'top-queries (brand)', cmd: [BINARY, 'top-queries', '--brand', '--limit', '5', '-d', DOMAIN, '--json'] },
  { name: 'top-queries (non-brand)', cmd: [BINARY, 'top-queries', '--non-brand', '--limit', '5', '-d', DOMAIN, '--json'] },
  { name: 'top-queries (json)', cmd: [BINARY, 'top-queries', '--limit', '5', '--json', '-d', DOMAIN] },
  { name: 'top-pages (human)', cmd: [BINARY, 'top-pages', '--limit', '5', '-d', DOMAIN] },
  { name: 'top-pages (json)', cmd: [BINARY, 'top-pages', '--limit', '5', '--json', '-d', DOMAIN] },
  { name: 'opportunities (human)', cmd: [BINARY, 'opportunities', '--limit', '5', '-d', DOMAIN] },
  { name: 'opportunities (json)', cmd: [BINARY, 'opportunities', '--limit', '5', '--json', '-d', DOMAIN] },
  { name: 'strike (tactical playbook)', cmd: [BINARY, 'strike', '--limit', '3', '-d', DOMAIN, '--json'] },
  { name: 'underperformers', cmd: [BINARY, 'underperformers', '--limit', '5', '-d', DOMAIN] },
  { name: 'cannibalization', cmd: [BINARY, 'cannibalization', '-d', DOMAIN] },
  { name: 'questions-harvest', cmd: [BINARY, 'questions-harvest', '--limit', '5', '-d', DOMAIN, '--json'] },
  { name: 'decay', cmd: [BINARY, 'decay', '-d', DOMAIN] },
  { name: 'devices', cmd: [BINARY, 'devices', '-d', DOMAIN] },
  { name: 'countries', cmd: [BINARY, 'countries', '--limit', '5', '-d', DOMAIN] },
  { name: 'snippets', cmd: [BINARY, 'snippets', '-d', DOMAIN] },
  { name: 'sitemaps-list', cmd: [BINARY, 'sitemaps-list', '-d', DOMAIN] },

  # Category 4: GSC Inspection & Indexing API
  { name: 'inspect url', cmd: [BINARY, 'inspect', 'https://example.com/', '-d', DOMAIN] },
  { name: 'index url (dry-run)', cmd: [BINARY, 'index', 'https://example.com/', '--dry-run', '-d', DOMAIN] },
  { name: 'remove url (dry-run)', cmd: [BINARY, 'remove', 'https://example.com/old', '--dry-run', '-d', DOMAIN] },
  { name: 'index-batch (status)', cmd: [BINARY, 'index-batch', 'status', '--json'] },
  { name: 'index-batch (run dry-run)', cmd: [BINARY, 'index-batch', 'run', '--dry-run', '--json'] },

  # Category 5: GA4
  { name: 'ga4-properties', cmd: [BINARY, 'ga4-properties'] },

  # Category 6: 360 Comprehensive Audit
  { name: '360 audit', cmd: [BINARY, 'audit', '--days', '7', '-d', DOMAIN] },

  # Category 7: Local SQLite/JSON Cache (Turn 20)
  { name: 'cache (status)', cmd: [BINARY, 'cache', 'status', '--json'] },

  # Category 8: Seasonal Trend & Spike Predictor (Turn 21)
  { name: 'seasonal (keyword)', cmd: [BINARY, 'seasonal', 'technical seo', '--json'] },

  # Category 9: Canonical Loop & Redirect Chain Breaker (Turn 22)
  { name: 'canonical-chains', cmd: [BINARY, 'canonical-chains', 'https://example.com', '--json'] },

  # Category 10: Multi-Page Agent Packager (Turn 23)
  { name: 'llms (agent bundle)', cmd: [BINARY, 'llms', 'https://example.com', '--package', '--json'] },

  # Category 11: Low-CTR High-Impression Title Tag Rewriter (Turn 24)
  { name: 'low-ctr (title rewrites)', cmd: [BINARY, 'low-ctr', 'technical seo', '--json'] },

  # Category 12: Security Headers & Mixed Content Auditor (Turn 25)
  { name: 'security (https & headers)', cmd: [BINARY, 'security', 'https://example.com', '--json'] },

  # Category 13: Top Landing Page Bounce Rate & Revenue Impact (Turn 26)
  { name: 'landing-roi (revenue leakage)', cmd: [BINARY, 'landing-roi', 'https://example.com/pricing', '--clicks', '1000', '--bounce', '75', '--json'] },

  # Category 14: Structured Data Rich Snippet Generator (Turn 27)
  { name: 'schema-generate (json-ld)', cmd: [BINARY, 'schema-generate', '--type', 'faq', '--q', 'How to test?', '--a', 'Run rake test.', '--json'] },

  # Category 15: Sitemap Index Hierarchy & Coverage Auditor (Turn 28)
  { name: 'sitemap-tree (hierarchy & limits)', cmd: [BINARY, 'sitemap-tree', 'test/fixtures/sitemap_index.xml', '--json'] },

  # Category 16: Zombie Content Purger & Crawl Equity Optimizer (Turn 29)
  { name: 'zombies (purge & crawl equity)', cmd: [BINARY, 'zombies', 'test/fixtures/sitemap.xml', '--json'] },

  # Category 17: AI Search Citation Simulator (Turn 30)
  { name: 'cite-sim (ai citation simulator)', cmd: [BINARY, 'cite-sim', 'https://example.com', 'example domain', '--json'] },

  # Category 18: Terminal ASCII Sparklines & Visual Trend Graphs (Turn 31)
  { name: 'sparklines (ascii trend charts)', cmd: [BINARY, 'sparklines', '--data', '10,20,35,50,75,90,120', '--json'] },

  # Category 19: Image SEO & Next-Gen Format Auditor (Turn 32)
  { name: 'image-seo (next-gen formats & cls)', cmd: [BINARY, 'image-seo', 'https://example.com', '--json'] },

  # Category 20: International Hreflang Reciprocity Validator (Turn 33)
  { name: 'hreflang-check (reciprocity & iso)', cmd: [BINARY, 'hreflang-check', 'https://example.com', '--no-reciprocity', '--json'] },

  # Category 21: Author E-E-A-T & Credential Signal Auditor (Turn 34)
  { name: 'eeat (author credentials & trust)', cmd: [BINARY, 'eeat', 'https://example.com', '--json'] },

  # Category 22: Automated Executive Markdown & HTML SEO Report Generator (Turn 35)
  { name: 'report (executive 360 scorecard)', cmd: [BINARY, 'report', 'example.com', '--days', '14', '--json'] },

  # Category 23: Search Intent Shift & Query Volatility Tracker (Turn 36)
  { name: 'intent-shift (intent volatility & mismatches)', cmd: [BINARY, 'intent-shift', 'example.com', '--json'] },

  # Category 24: Google Rich Results & Schema Validation Suite (Turn 37)
  { name: 'rich-results (google rich snippets test)', cmd: [BINARY, 'rich-results', 'https://example.com', '--json'] },

  # Category 25: Continuous SERP Watchdog & Rank Drift Monitor (Turn 38)
  { name: 'watch (serp rank & ctr watchdog)', cmd: [BINARY, 'watch', 'example.com', '--once', '--json'] },

  # Category 26: Conversion-Weighted Keyword Opportunity Matrix (Turn 39)
  { name: 'kw-value (conversion & pipeline matrix)', cmd: [BINARY, 'kw-value', 'example.com', '--json'] },

  # Category 27: Mobile vs Desktop SERP Parity & Responsive Auditor (Turn 40)
  { name: 'mobile-parity (cross-device serp gap)', cmd: [BINARY, 'mobile-parity', 'example.com', '--json'] },

  # Category 28: Autonomous AI Agent Skill Packaging Engine (Turn 41)
  { name: 'skill-pack (autonomous agent skill pack)', cmd: [BINARY, 'skill-pack', '--dry-run', '--json'] },

  # Category 29: Zero-Dependency Architecture & System Certification (Turn 42)
  { name: 'doctor (pure ruby & cold start check)', cmd: [BINARY, 'doctor', '--json'] },

  # Category 30: Google AI Overview (AIO) Opportunity Hunter (Turn 43)
  { name: 'aio-hunter (google ai overview radar)', cmd: [BINARY, 'aio-hunter', 'how to optimize website speed', '--json'] },

  # Category 31: 404 & Soft-404 Crawl Error Diagnostic Engine (Turn 44)
  { name: 'soft-404 (soft-404 diagnostic & redirects)', cmd: [BINARY, 'soft-404', '--json'] }
]

results = []
puts '=' * 80
version_str = `#{BINARY} --version`.strip
puts "TESTING ALL GSC COMMANDS (#{version_str.lines.first.strip})"
puts '=' * 80

tests.each_with_index do |t, idx|
  cmd_str = t[:cmd].join(' ')
  print format('[%02d/%02d] %-30s ... ', idx + 1, tests.size, t[:name])
  $stdout.flush

  stdout, stderr, status = Open3.capture3(*t[:cmd])
  ok = status.success?
  output = (stdout.to_s.dup.force_encoding('UTF-8').scrub + stderr.to_s.dup.force_encoding('UTF-8').scrub).strip

  has_error_pattern = output =~ /(?:Execution Error|undefined method|does not have #dig|Fatal Error|undefined local variable)/i

  json_valid = true
  if t[:cmd].include?('--json')
    begin
      clean_stdout = stdout.to_s.dup.force_encoding('UTF-8').scrub
      parsed = JSON.parse(clean_stdout)
      json_valid = parsed.is_a?(Hash) || parsed.is_a?(Array)
    rescue StandardError
      json_valid = false
    end
  end

  if ok && !has_error_pattern && json_valid
    puts 'PASS'
    results << { name: t[:name], cmd: cmd_str, status: 'PASS', exit_code: status.exitstatus }
  else
    reason = !ok ? "exit: #{status.exitstatus}" : (!json_valid ? "invalid JSON" : "error pattern detected")
    puts "FAIL (#{reason})"
    puts "   Error Preview:\n   #{output.lines.first(5).map(&:strip).join("\n   ")}"
    results << { name: t[:name], cmd: cmd_str, status: 'FAIL', exit_code: status.exitstatus, error: output }
  end
end

puts "\n" + ('=' * 80)
passed_count = results.count { |r| r[:status] == 'PASS' }
puts "SUMMARY: #{passed_count}/#{results.size} passed."
puts '=' * 80

failed = results.select { |r| r[:status] == 'FAIL' }
if failed.any?
  puts 'Failed commands:'
  failed.each { |f| puts " - #{f[:name]}: #{f[:cmd]}" }
  exit 1
else
  puts 'All tested commands executed and returned expected results with zero errors!'
end

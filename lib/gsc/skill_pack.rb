# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'fileutils'

module GSC
  class SkillPack
    DEFAULT_SKILL_NAME = 'gsc'

    attr_reader :options, :target_dir

    def initialize(options = {}, target_dir = nil)
      @options = options
      @target_dir = target_dir || options[:dir]
    end

    def self.package(options = {}, target_dir = nil)
      new(options, target_dir).package
    end

    def package
      content_md = generate_skill_markdown
      recipes = generate_recipes_json

      destinations = resolve_destinations

      installed_paths = []

      unless @options[:dry_run]
        destinations.each do |dest|
          FileUtils.mkdir_p(dest[:dir])
          skill_path = File.join(dest[:dir], 'SKILL.md')
          recipe_path = File.join(dest[:dir], 'recipes.json')

          File.write(skill_path, content_md, encoding: 'UTF-8')
          File.write(recipe_path, JSON.pretty_generate(recipes), encoding: 'UTF-8')

          installed_paths << {
            platform: dest[:platform],
            skill_path: skill_path,
            recipe_path: recipe_path
          }
        end
      end

      # Agent verification check
      verification = verify_agent_environment

      {
        skill_name: DEFAULT_SKILL_NAME,
        version: GSC::VERSION,
        dry_run: !!@options[:dry_run],
        destinations_count: destinations.size,
        installed_locations: installed_paths,
        verification: verification,
        recipes_count: recipes[:recipes].size,
        skill_preview: content_md[0..400] + "..."
      }
    end

    def generate_skill_markdown
      <<~MARKDOWN
        ---
        name: gsc
        description: Automates Google Search Console, Google Indexing API, live URL index inspection, sitemap batch submission, search ranking analytics, E-E-A-T audits, image optimization, schema testing, and conversion-weighted revenue opportunity matrices.
        ---

        # Google Search Console (GSC) CLI Agent Skill

        This skill provides full-featured, zero-dependency autonomous search engine intelligence directly inside AI developer coding environments (Google Antigravity, Claude Code, Cursor, Windsurf).

        ## Core Capabilities & Quick Reference

        ### 1. Organic Search Performance & Analytics
        - `gsc performance [domain] --json`: Overview clicks, impressions, CTR, average position.
        - `gsc top-queries [domain] --limit 50 --json`: Top ranking search queries.
        - `gsc top-pages [domain] --limit 50 --json`: Top ranking landing pages.
        - `gsc opportunities [domain] --json`: High-opportunity queries in striking distance (positions 4–20).
        - `gsc strike [domain] --json`: Tactical striking-distance keyword playbook.
        - `gsc brand [domain] --json`: Brand vs non-brand organic search segmentation.

        ### 2. Live URL Indexing & Googlebot Inspection
        - `gsc inspect <url> --json`: Real-time Googlebot crawl verdict and indexing status.
        - `gsc index <url> --json`: Submit URL to Google Indexing API for rapid re-crawl.
        - `gsc index-batch [sitemap] --json`: Bulk submit URLs from sitemap to Indexing API.

        ### 3. SEO Diagnostics & Technical Audits
        - `gsc audit [domain] --json`: Comprehensive 360-degree organic health audit.
        - `gsc report [domain] --html --json`: Generate single-file executive audit dashboard.
        - `gsc image-seo <url|file> --json`: Audit WebP/AVIF formats, missing alt text, and CLS image dimensions.
        - `gsc hreflang-check <url|file> --json`: International hreflang reciprocity and ISO syntax verification.
        - `gsc eeat <url|file> --json`: Author E-E-A-T, credentials, reviewer attribution, and Knowledge Graph signals.
        - `gsc rich-results <url|file> --json`: Test JSON-LD against Google Rich Results API rules.
        - `gsc mobile-parity [domain] --json`: Cross-device Desktop vs Mobile position gap and responsive penalty audit.

        ### 4. Growth, Revenue & Strategy
        - `gsc kw-value [domain] --json`: Conversion-weighted keyword revenue matrix ($ upside to Top 3).
        - `gsc intent-shift [domain] --json`: Search intent drift & landing page mismatch detection.
        - `gsc zombies [sitemap] --json`: Identify dead crawl-waste pages and generate 410/301 rules.
        - `gsc watch [domain] --once --json`: Background rank drop and CTR crash monitoring watchdog.
        - `gsc cite-sim <url> <query> --json`: AI Search Overviews citation probability simulator.

        ## Autonomous Execution Recipes for AI Agents

        ### Recipe 1: Diagnose Sudden Organic Traffic Drop
        1. Run `gsc watch [domain] --once --json` to detect queries with severe rank drops (>= 2 positions).
        2. Run `gsc mobile-parity [domain] --json` to check if drops are concentrated on mobile devices.
        3. For dropped URLs, run `gsc inspect <url> --json` to check for Googlebot indexing failures.

        ### Recipe 2: High-ROI Striking Distance Acceleration
        1. Run `gsc kw-value [domain] --json` to locate queries in positions 4–15 with highest monthly $ upside.
        2. Run `gsc intent-shift [domain] --json` to verify searcher intent matches the landing page type.
        3. Run `gsc rich-results <url> --json` to check if adding FAQ or Product schema can capture SERP real estate.
      MARKDOWN
    end

    def generate_recipes_json
      {
        skill: DEFAULT_SKILL_NAME,
        version: GSC::VERSION,
        recipes: [
          {
            name: "diagnose_traffic_drop",
            trigger: "User reports traffic drop or lost search rankings",
            steps: [
              { command: "gsc watch {{domain}} --once --json", extract: "alerts" },
              { command: "gsc mobile-parity {{domain}} --json", extract: "disparities" }
            ]
          },
          {
            name: "optimize_striking_distance",
            trigger: "User asks how to increase revenue or capture high-ROI search keywords",
            steps: [
              { command: "gsc kw-value {{domain}} --json", extract: "keywords" },
              { command: "gsc intent-shift {{domain}} --json", extract: "shifts" }
            ]
          },
          {
            name: "technical_page_audit",
            trigger: "User asks to audit an individual page or template",
            steps: [
              { command: "gsc rich-results {{url}} --json", extract: "schemas" },
              { command: "gsc image-seo {{url}} --json", extract: "images" },
              { command: "gsc eeat {{url}} --json", extract: "signals" }
            ]
          }
        ]
      }
    end

    private

    def resolve_destinations
      destinations = []

      # If explicit target directory provided
      if @target_dir && !@target_dir.empty?
        destinations << { platform: 'Custom Directory', dir: File.expand_path(@target_dir) }
        return destinations
      end

      target = (@options[:target] || 'all').to_s.downcase

      if target == 'all' || target == 'antigravity' || target == 'gemini'
        gemini_dir = File.expand_path('~/.gemini/config/skills/gsc')
        destinations << { platform: 'Google Antigravity / Gemini', dir: gemini_dir }
      end

      if target == 'all' || target == 'claude'
        claude_dir = File.expand_path('~/.claude/skills/gsc')
        destinations << { platform: 'Claude Code', dir: claude_dir }
      end

      if target == 'all' || target == 'workspace' || target == 'local'
        local_dir = File.expand_path('.agents/skills/gsc', Dir.pwd)
        destinations << { platform: 'Universal Workspace (.agents)', dir: local_dir }
      end

      destinations
    end

    def verify_agent_environment
      bin = ENV['GSC_BIN_PATH'] || File.expand_path('~/.local/bin/gsc')
      bin_exists = File.exist?(bin) && File.executable?(bin)

      {
        binary_path: bin,
        binary_available: bin_exists,
        ruby_version: RUBY_VERSION,
        status: bin_exists ? 'READY_FOR_AI_AGENTS' : 'BINARY_NEEDS_INSTALL'
      }
    end
  end
end

# frozen_string_literal: true

require 'optparse'
require 'json'
require_relative 'cli/base'
require_relative 'cli/dashboard'
require_relative 'cli/analytics'
require_relative 'cli/indexing'
require_relative 'cli/audit'
require_relative 'cli/growth'
require_relative 'cli/keywords'
require_relative 'cli/cache'
require_relative 'cli/setup'
require_relative 'cli/ga4'
require_relative 'cli/seasonal'
require_relative 'cli/canonical'
require_relative 'cli/low_ctr'
require_relative 'cli/security'
require_relative 'cli/landing_roi'
require_relative 'cli/schema_generate'
require_relative 'cli/sitemap_tree'

module GSC
  class CLI
    VERSION = GSC::VERSION
    BANNER = Base::BANNER
    COMMAND_REGISTRY = GSC::COMMAND_REGISTRY
    SKILL_MD_CONTENT = GSC::SKILL_MD_CONTENT

    def self.start(argv = ARGV)
      run(argv)
    end

    def self.run(argv = ARGV)
      $stdout.sync = true

      options = {
        domain: ENV['GSC_DOMAIN'],
        key: ENV['GSC_KEY_PATH'],
        days: 30,
        limit: 50,
        sort: nil,
        order: nil,
        min_imp: 10,
        min_pos: 7.0,
        max_pos: 20.0,
        compare: 28,
        csv: nil,
        delay: 120,
        dry_run: false,
        json: false,
        property: nil,
        organic: false,
        all_hosts: false,
        site_only: false,
        watch: nil,
        geo: 'US',
        time: '5y',
        country: 'us'
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gsc <command> [target] [options]"
        opts.separator ""
        opts.separator "Options:"

        opts.on('-d', '--domain DOMAIN', 'Target domain (overrides default active domain)') do |d|
          options[:domain] = d
        end

        opts.on('-k', '--key PATH', 'Path to Google Service Account JSON key') do |k|
          options[:key] = k
        end

        opts.on('-j', '--json', 'Output machine-readable JSON (ideal for AI agents)') do
          options[:json] = true
        end

        opts.on('--compact', 'Output minified single-line JSON without whitespace (saves 30-45% LLM tokens)') do
          options[:json] = true
          options[:compact] = true
        end

        opts.on('--ndjson', 'Output newline-delimited JSON lines (ideal for streaming & token efficiency)') do
          options[:json] = true
          options[:ndjson] = true
        end

        opts.on('--days DAYS', Integer, 'Time window for analytics in days (default: 30)') do |days|
          options[:days] = [days.to_i, 1].max
        end

        opts.on('--limit LIMIT', Integer, 'Maximum rows to display (default: 50)') do |limit|
          options[:limit] = [limit.to_i, 1].max
        end

        opts.on('--all', 'Retrieve all available rows via startRow pagination') do
          options[:all] = true
        end

        opts.on('-s', '--sort FIELD', 'Sort analytics: clicks, impressions (imp), position (pos), ctr') do |s|
          options[:sort] = s
        end

        opts.on('--order ORDER', 'Sort direction: asc or desc') do |o|
          options[:order] = o
        end

        opts.on('--asc', 'Sort ascending (default for position/rank)') do
          options[:order] = 'asc'
        end

        opts.on('--desc', 'Sort descending (default for clicks, impressions, ctr)') do
          options[:order] = 'desc'
        end

        opts.on('--brand', 'Filter queries to brand/navigational terms only') do
          options[:brand] = true
        end

        opts.on('--non-brand', 'Filter queries to non-brand/discovery terms only') do
          options[:non_brand] = true
        end

        opts.on('--brand-name NAME', 'Specify custom brand name or alias for segmentation') do |name|
          options[:brand_name] = name
        end

        opts.on('--target-pos POS', Integer, 'Target SERP ranking position for CTR simulation (default: 3)') do |pos|
          options[:target_pos] = pos
        end

        opts.on('--batch-size SIZE', Integer, 'Batch size for index queue processing (default: 50)') do |size|
          options[:batch_size] = size
        end

        opts.on('-f', '--force', '--yes', '-y', 'Bypass confirmation prompts (required for non-interactive queue clears)') do
          options[:force] = true
        end

        opts.on('--concurrency COUNT', Integer, 'Concurrent threads for multi-page site crawler (default: 5, max: 20)') do |c|
          options[:concurrency] = c
        end

        opts.on('--min-imp COUNT', Integer, 'Minimum impressions threshold (default: 10)') do |count|
          options[:min_imp] = count
        end

        opts.on('--synthesize', 'Synthesize high-ranking 40-60 word answers into FAQ schema') do
          options[:synthesize] = true
        end

        opts.on('--cpc VALUE', Float, 'Estimated CPC value in USD for click revenue loss calculations (default: 1.50)') do |val|
          options[:cpc] = val
        end

        opts.on('--min-pos POS', Float, 'Minimum position for opportunity filtering (default: 7.0)') do |pos|
          options[:min_pos] = pos
        end

        opts.on('--max-pos POS', Float, 'Maximum position for opportunity filtering (default: 20.0)') do |pos|
          options[:max_pos] = pos
        end

        opts.on('--compare DAYS', Integer, 'Comparison window in days for decay/trends (default: 28)') do |days|
          options[:compare] = days
        end

        opts.on('--property ID', 'Explicit GA4 Property ID (overrides domain config)') do |prop|
          options[:property] = prop
        end

        opts.on('--organic', 'Filter GA4 analytics to organic search traffic only') do
          options[:organic] = true
        end

        opts.on('--all-hosts', 'Do not filter GA4 data by hostname (include cross-domain hosts)') do
          options[:all_hosts] = true
        end

        opts.on('--site-only', 'Filter GA4 strictly to apex website pages (exclude subdomains)') do
          options[:site_only] = true
        end

        opts.on('-w', '--watch [INTERVAL]', Integer, 'Auto-refresh report in real-time (default: 5s)') do |sec|
          options[:watch] = sec || 5
        end

        opts.on('-c', '--copy', 'Copy prompt or output directly to system clipboard') do
          options[:copy] = true
        end

        opts.on('--seed SEED', 'Seed keyword for prompt or expansion') do |s|
          options[:seed] = s
        end

        opts.on('--keyword KEYWORD', 'Target keyword(s) for heading/content optimization analysis') do |kw|
          options[:keyword] = kw
        end

        opts.on('--url URL', 'Target URL for prompt or index verification') do |u|
          options[:url] = u
        end

        opts.on('--generate', 'Generate recommended schema or configuration code snippet') do
          options[:generate] = true
        end

        opts.on('--csv PATH', 'Export results to a CSV file') do |csv|
          options[:csv] = csv
        end

        opts.on('--geo GEO', 'Geographic region for Google Trends (e.g. US, GB, DE, or "worldwide")') do |geo|
          options[:geo] = geo.to_s.upcase == 'WORLDWIDE' ? '' : geo.to_s.upcase
        end

        opts.on('--time TIME', 'Timeframe for Google Trends (e.g. 5y, 12m, 3m, 1m, 7d, all)') do |t|
          options[:time] = t
        end

        opts.on('--country CODE', 'Target country for Keyword Planner (default: us)') do |c|
          options[:country] = c
        end

        opts.on('--save', 'Save keyword research snapshot to ~/.config/gsc/domains/<domain>/keywords/') do
          options[:save] = true
        end

        opts.on('--alphabet', 'Run alphabet soup harvest (a-z) for search suggestions') do
          options[:alphabet] = true
        end

        opts.on('--numbers', 'Include numbers (0-9) in alphabet soup search suggestions') do
          options[:numbers] = true
        end

        opts.on('--strategy STRAT', 'PageSpeed device strategy: mobile or desktop (default: mobile)') do |s|
          options[:strategy] = s
        end

        opts.on('--bot NAME', 'User agent bot name for robots.txt testing (default: googlebot)') do |b|
          options[:bot] = b
        end

        opts.on('--pages', 'Analyze decay/trends by landing page URLs (default)') do
          options[:dimension] = 'page'
        end

        opts.on('--queries', 'Analyze decay/trends by search query keywords') do
          options[:dimension] = 'query'
        end

        opts.on('--alias ALIAS', 'Short alias for Agency Vault property (e.g. sc, speed, client1)') do |a|
          options[:alias] = a
        end

        opts.on('--delay MS', Integer, 'Delay between sequential requests in ms (default: 120)') do |delay|
          options[:delay] = delay
        end

        opts.on('--check-links', 'Test HTTP response codes for all links (detects 404s/broken links)') do
          options[:check_links] = true
        end

        opts.on('--report PATH', 'Export comprehensive Markdown audit report (e.g. docs/seo/site_audit_issues.md)') do |path|
          options[:report] = path
        end

        opts.on('--title TITLE', 'Custom page title for SERP simulator') do |t|
          options[:title] = t
        end

        opts.on('--desc DESC', 'Custom meta description for SERP simulator') do |d|
          options[:desc] = d
        end

        opts.on('--key KEY', 'API key for IndexNow or service accounts') do |k|
          options[:key] = k
        end

        opts.on('--dry-run', 'Simulate API calls without mutating data') do
          options[:dry_run] = true
        end

        opts.on('-v', '--version', 'Show version') do
          Setup.print_version_info(options)
          exit 0
        end

        opts.on('--overflow-only', 'Filter titles to overflowing tags only') do
          options[:overflow_only] = true
        end

        opts.on('--audit', 'Audit AI readability for llms.txt') do
          options[:audit] = true
        end

        opts.on('--full', 'Generate full consolidated multi-page /llms-full.txt knowledge base') do
          options[:full] = true
        end

        opts.on('--package', '--bundle', 'Package complete AI agent bundle (both /llms.txt and /llms-full.txt)') do
          options[:package] = true
        end

        opts.on('--write [DIR]', '--save [DIR]', 'Write generated llms files to disk (default: current directory)') do |dir|
          options[:write] = dir || '.'
          options[:save] = true
        end

        opts.on('--local', 'Install skill locally to current workspace') do
          options[:local] = true
        end

        opts.on('--aov VALUE', Float, 'Average Order Value / customer value for ROI models (default: 75.0)') do |v|
          options[:aov] = v
        end

        opts.on('--conv-rate VALUE', Float, 'Conversion rate for ROI models (default: 0.025 = 2.5%)') do |v|
          options[:conv_rate] = v
        end

        opts.on('--margin VALUE', Float, 'Gross profit margin for revenue modeling (default: 0.60 = 60%)') do |v|
          options[:margin] = v
        end

        opts.on('--benchmark VALUE', Float, 'Healthy benchmark bounce rate (default: 45.0%)') do |v|
          options[:benchmark] = v
        end

        opts.on('--bounce VALUE', Float, 'Explicit bounce rate for standalone URL audit') do |v|
          options[:bounce] = v
        end

        opts.on('--clicks VALUE', Integer, 'Explicit click volume for standalone URL audit') do |v|
          options[:clicks] = v
        end

        opts.on('-o', '--open', 'Open official Google testing tool (Rich Results Test, GSC Web UI) in default browser') do
          options[:open] = true
        end

        opts.on('--type TYPE', 'Schema type (e.g. product, faq, howto, article, software, organization)') do |t|
          options[:type] = t
        end

        opts.on('--name NAME', 'Name of entity for Schema markup') do |n|
          options[:name] = n
        end

        opts.on('--headline HEADLINE', 'Headline for Article Schema') do |h|
          options[:headline] = h
        end

        opts.on('--author AUTHOR', 'Author name for Article Schema') do |a|
          options[:author] = a
        end

        opts.on('--price VALUE', Float, 'Price for Product/Software schema (e.g. 49.99)') do |p|
          options[:price] = p
        end

        opts.on('--currency CODE', 'Currency code for Offer (default: USD)') do |c|
          options[:currency] = c
        end

        opts.on('--rating VALUE', Float, 'Rating value (1.0 to 5.0)') do |r|
          options[:rating] = r
        end

        opts.on('--reviews COUNT', Integer, 'Total review count') do |cnt|
          options[:reviews] = cnt
        end

        opts.on('--q QUESTION', 'Question text for FAQ schema') do |q|
          options[:q] = q
        end

        opts.on('--a ANSWER', 'Answer text for FAQ schema') do |a|
          options[:a] = a
        end

        opts.on('--format FORMAT', 'Snippet format: html, nextjs, shopify, nginx, htaccess, redirects, meta (default: html)') do |fmt|
          options[:format] = fmt
        end

        opts.on('--inventory FILE', 'Path to URL inventory file or sitemap for audit') do |inv|
          options[:inventory] = inv
        end

        opts.on('--threshold VALUE', Integer, 'Max impressions to consider a page a zombie (default: 0)') do |th|
          options[:threshold] = th
        end

        opts.on('--action ACTION', 'Filter zombie triage action (purge, redirect, consolidate, noindex)') do |act|
          options[:action] = act
        end

        opts.on('--model MODEL', 'Target AI search model profile: perplexity, chatgpt, claude, aio (default: perplexity)') do |m|
          options[:model] = m
        end

        opts.on('--metric METRIC', 'Target metric for sparklines/chart: clicks, impressions, position, ctr, all (default: all)') do |met|
          options[:metric] = met
        end

        opts.on('--height HEIGHT', Integer, 'Height in terminal lines for ASCII chart (default: 5)') do |h|
          options[:height] = h
        end

        opts.on('--data DATA', 'Custom comma-separated numerical points to plot as sparkline') do |d|
          options[:data] = d
        end

        opts.on('--sparkline', 'Display inline Unicode sparklines for metrics and reports') do
          options[:sparkline] = true
        end

        opts.on('--check-size', 'Perform HTTP HEAD request to verify remote image file sizes & payload weight') do
          options[:check_size] = true
        end

        opts.on('--no-reciprocity', 'Skip remote HTTP reciprocity graph verification') do
          options[:check_reciprocity] = false
        end

        opts.on('--html [FILE]', 'Export executive report as standalone HTML dashboard') do |f|
          options[:html] = f || true
        end

        opts.on('--md [FILE]', 'Export executive report as formatted Markdown document') do |f|
          options[:md] = f || true
        end

        opts.on('--title TITLE', 'Custom title for executive report') do |t|
          options[:title] = t
        end

        opts.on('--patch', 'Synthesize and print 1-click Google-compliant JSON-LD fix') do
          options[:patch] = true
        end

        opts.on('--once', 'Run single watchdog inspection pass and exit') do
          options[:once] = true
        end

        opts.on('--daemon', 'Run watchdog as continuous background daemon') do
          options[:daemon] = true
        end

        opts.on('--interval SECONDS', Integer, 'Watchdog polling interval in seconds (default: 3600)') do |sec|
          options[:interval] = sec
        end

        opts.on('--webhook URL', 'Webhook endpoint URL for automated alert notifications') do |url|
          options[:webhook] = url
        end

        opts.on('--slack URL', 'Slack incoming webhook URL for automated alert notifications') do |url|
          options[:slack] = url
        end

        opts.on('--cron', 'Generate standard crontab entry for automated monitoring') do
          options[:cron] = true
        end

        opts.on('--launchd', 'Generate macOS launchd service plist for automated monitoring') do
          options[:launchd] = true
        end

        opts.on('--systemd', 'Generate Linux systemd service unit for automated monitoring') do
          options[:systemd] = true
        end

        opts.on('--target PLATFORM', 'Target AI agent platform: antigravity, claude, workspace, all (default: all)') do |t|
          options[:target] = t
        end

        opts.on('--dir PATH', 'Destination directory path for generated files') do |d|
          options[:dir] = d
        end

        opts.on('--strict', 'Fail with non-zero exit code if architecture certification is not 100%') do
          options[:strict] = true
        end

        opts.on('--fix [FORMAT]', 'Automatically repair configuration permissions, or specify server format for 404 redirects (nginx, htaccess, nextjs)') do |fmt|
          options[:fix] = fmt || true
        end


        opts.on('--in-dashboard', 'Internal interactive dashboard flag') do
          options[:in_dashboard] = true
        end

        opts.on('-h', '--help', 'Show help') do
          Setup.handle_help(opts, options)
          exit 0
        end
      end

      args = parser.parse(argv)

      if options[:ndjson]
        JSON.singleton_class.class_eval do
          alias_method :orig_pretty_generate, :pretty_generate unless method_defined?(:orig_pretty_generate)
          define_method(:pretty_generate) do |obj, *args|
            if obj.is_a?(Array)
              obj.map { |item| JSON.generate(item) }.join("\n")
            elsif obj.is_a?(Hash)
              rows = obj[:rows] || obj['rows'] || obj[:queries] || obj['queries'] ||
                     obj[:pages] || obj['pages'] || obj[:all_results] || obj['all_results'] ||
                     obj[:playbooks] || obj['playbooks'] || obj[:categories] || obj['categories'] ||
                     obj[:snapshots] || obj['snapshots'] || obj[:opportunities] || obj['opportunities']
              if rows.is_a?(Array)
                rows.map { |r| JSON.generate(r) }.join("\n")
              else
                JSON.generate(obj)
              end
            else
              JSON.generate(obj)
            end
          end
        end
      elsif options[:compact]
        JSON.singleton_class.class_eval do
          alias_method :orig_pretty_generate, :pretty_generate unless method_defined?(:orig_pretty_generate)
          define_method(:pretty_generate) do |obj, *args|
            JSON.generate(obj)
          end
        end
      end

      if args.empty?
        if !options[:json] && ENV['GSC_NON_INTERACTIVE'] != '1'
          Dashboard.run(options)
          exit 0
        else
          Setup.handle_help(parser, options)
          exit 0
        end
      end

      command = args[0]
      target  = args[1]
      extra   = args[2]

      # 1. Dashboard & Interactive Shell
      case command
      when 'interactive', 'shell', 'repl', 'menu', 'dashboard'
        Dashboard.run(options)
        exit 0 unless options[:in_dashboard]
        return

      # 2. Turn 20 Offline Cache
      when 'cache'
        Cache.run(target, extra, args[3..-1] || [], options)
        exit 0 unless options[:in_dashboard]
        return

      # 3. Setup & Domain Configuration (Zero auth required)
      when 'vault', 'use', 'switch', 'sw', 'domains', 'list', /^(?!404$)\d+$/,
           'connect', 'setup', 'init', 'install', 'connect-ga4', 'setup-ga4', 'link-ga4',
           'connect-ke', 'setup-ke', 'link-ke', 'connect-keywordseverywhere',
           'open', 'where', 'which', 'version', '-v', '--version', 'update',
           'prompts', 'prompt', 'playbooks', 'playbook', 'skills', 'skill', 'init-skill',
           'config', 'commands', 'palette'
        Setup.run(command, target, extra, args, options, parser)
        exit 0 unless options[:in_dashboard]
        return


      when 'help'
        Setup.handle_help(parser, options)
        exit 0 unless options[:in_dashboard]
        return

      # 4. Keyword Research & Expansion (No GSC auth required)
      when 'planner', 'kp', 'keywords', 'planner-import', 'pi', 'import', 'imp',
           'saved', 'research', 'saved-keywords', 'sv', 'check', 'chk',
           'ke', 'keywordseverywhere', 'keywords-everywhere', 'k', 'ke-credits', 'credits',
           'suggest', 'autocomplete', 'sug', 'questions', 'paa', 'faqs'
        Keywords.run(command, target, extra, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'trends', 'tr', 'google-trends', 'gtrends', 't'
        if target && !target.strip.empty?
          Keywords.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If target is nil, falls through to GSC search console decay/trends below

      when 'seasonal', 'season', 'spike', 'seasonal-trends', 'seasonality'
        if target && !target.strip.empty? && target !~ /^https?:\/\// && target !~ /\.(com|org|net|io|app|co|dev|store)$/
          Seasonal.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain portfolio radar below

      when 'canonical-chains', 'canonical', 'chains', 'redirect-chains', 'redirects-audit'
        if target && target =~ %r{^https?://}
          Canonical.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain batch below

      when 'low-ctr', 'ctr-rewrite', 'lost-clicks', 'rewrite-titles', 'ctr-fix', 'lowctr'
        if target && !target.strip.empty? && (target =~ %r{^https?://} || target !~ /\.(com|org|net|io|app|co|dev|store)$/)
          LowCtr.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain audit below

      when 'security', 'security-headers', 'sec', 'mixed-content', 'hsts', 'ssl-check'
        Security.run(command, target, extra, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'landing-roi', 'landing-revenue', 'roi', 'lroi'
        if target && target =~ %r{^https?://}
          LandingRoi.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain audit below

      when 'schema-generate', 'schema-gen', 'rich-gen', 'sg'
        SchemaGenerate.run(command, target, extra, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'sitemap-tree', 'sitemap-hierarchy', 'smt', 'sm-tree'
        if target && (target =~ %r{^https?://} || File.exist?(target))
          SitemapTree.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain audit below

      when 'image-seo', 'image', 'images-audit', 'img', 'img-seo'
        if target && (target =~ %r{^https?://} || File.exist?(target))
          ImageSeo.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain audit below

      when 'hreflang-check', 'hreflang', 'hreflang-audit', 'hlang'
        if target && (target =~ %r{^https?://} || File.exist?(target))
          Hreflang.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain audit below

      when 'eeat', 'eeat-audit', 'author-audit', 'credentials'
        if target && (target =~ %r{^https?://} || File.exist?(target))
          Eeat.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target or target is a domain, falls through to authenticated domain audit below

      when 'report', 'rep', 'executive-report', 'audit-report'
        if target && target =~ /\.(com|org|net|io|app|co|dev|store)$/
          Report.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target, falls through to authenticated domain audit below

      when 'intent-shift', 'intent', 'search-intent', 'intent-drift'
        if target && target =~ /\.(com|org|net|io|app|co|dev|store)$/
          IntentShift.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target, falls through to authenticated domain audit below

      when 'rich-results', 'rich', 'richresults', 'rich-test', 'test-rich-results', 'test-rich', 'schema-test', 'test-schema'
        options[:open] = true if %w[rich-test test-rich-results test-rich schema-test test-schema].include?(command)
        if target && (target =~ %r{^https?://} || File.exist?(target) || target =~ /\.(com|org|net|io|app|co|dev|store)$/)
          RichResults.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target, falls through to authenticated domain audit below

      when 'watch', 'watchdog', 'mon', 'monitor'
        if target && target =~ /\.(com|org|net|io|app|co|dev|store)$/
          Watchdog.run(command, target, extra, options)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target, falls through to authenticated domain audit below

      when 'kw-value', 'kwval', 'value', 'kw-revenue', 'kw-roi'
        if target && target =~ /\.(com|org|net|io|app|co|dev|store)$/
          sa_record = Auth.find_service_account(options[:key], target)
          api = nil
          if sa_record
            token = options[:dry_run] ? 'DRY_RUN_PREVIEW_TOKEN' : Auth.fetch_access_token(sa_record[:data])
            api = API.new(Client.new(token: token)) rescue nil
          end
          KeywordValue.run(command, target, extra, options, api, "sc-domain:#{target}", target)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target, falls through to authenticated domain audit below

      when 'mobile-parity', 'mobile', 'parity', 'mobile-gap'
        if target && target =~ /\.(com|org|net|io|app|co|dev|store)$/
          sa_record = Auth.find_service_account(options[:key], target)
          api = nil
          if sa_record
            token = options[:dry_run] ? 'DRY_RUN_PREVIEW_TOKEN' : Auth.fetch_access_token(sa_record[:data])
            api = API.new(Client.new(token: token)) rescue nil
          end
          MobileParity.run(command, target, extra, options, api, "sc-domain:#{target}", target)
          exit 0 unless options[:in_dashboard]
          return
        end
        # If no target, falls through to authenticated domain audit below

      when 'skill-pack', 'agent-pack', 'skillpack', 'pack-skill'
        SkillPack.run(command, target, extra, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'doctor', 'doc', 'health', 'checkup'
        Doctor.run(command, target, extra, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'aio-hunter', 'aio', 'aio-hunt', 'overview'
        query_or_domain = target || (extra && extra.first)
        domain = options[:domain] || (query_or_domain if query_or_domain.to_s =~ /\.[a-z]{2,}$/i)
        domain ||= Config.default_domain if query_or_domain.nil? || query_or_domain.to_s.strip.empty?
        sa_record = domain ? Auth.find_service_account(options[:key], domain) : nil
        api = nil
        site_url = nil
        if sa_record && domain
          token = options[:dry_run] ? 'DRY_RUN_PREVIEW_TOKEN' : Auth.fetch_access_token(sa_record[:data])
          api = API.new(Client.new(token: token)) rescue nil
          site_url = "sc-domain:#{domain}"
        end
        AioHunter.run(command, target, extra, options, api, site_url, domain)
        exit 0 unless options[:in_dashboard]
        return

      when 'soft-404', '404', 'soft404', 'broken-urls'
        Soft404.run(command, target, extra, options)
        exit 0 unless options[:in_dashboard]
        return

      # 5. Growth & SERP Previews (No GSC auth required)
      when 'answer', 'direct-answer', 'aeo-snippet', 'info-gain', 'ans'
        Growth.handle_answer(target, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'serp-features', 'sf', 'serp-live', 'features'
        Growth.handle_serp_features(target, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'preview', 'serp', 'serp-preview', 'social-preview'
        Growth.handle_preview(target, options)
        exit 0 unless options[:in_dashboard]
        return

      # 6. SEO Audits & Tools (No GSC auth required)
      when 'authority', 'opr', 'da', 'domain-authority',
           'speed', 'vitals', 'pagespeed', 'psi',
           'speed-correlate', 'cwv-correlate', 'sc-perf',
           'compare', 'diff-seo', 'vs',
           'content-gap', 'gap',
           'internal-links', 'orphans', 'links-audit',
           'schema', 'rich-snippets', 'ld-json',
           'llms', 'ai-ready',
           'trace', 'redirects', 'hops',
           'robots', 'robots-txt',
           'backlinks', 'links',
           'geo', 'aeo', 'citability',
           'entity', 'kg', 'knowledge-graph',
           'firewall', 'ai-bots', 'waf-scan', 'bot-firewall',
           'titles', 'title-opt', 'pixel-titles', 'title-tags',
           'headings', 'h1', 'heading-structure'
        Audit.run(command, target, extra, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'index-batch', 'queue', 'batch-index'
        action = target.to_s.strip.downcase
        if action != 'run' && action != 'process' && action != 'execute'
          Indexing.run(command, target, extra, options, nil, nil, nil, nil)
          exit 0 unless options[:in_dashboard]
          return
        end
      end

      # 7. Authenticated Commands (GSC / Indexing / Analytics / GA4)
      puts Base::BANNER unless options[:json] || options[:in_dashboard] || options[:format]

      hostname, site_url, https_origin = Base.resolve_domain(options[:domain], target, options)

      sa_record = Auth.find_service_account(options[:key], hostname)
      unless sa_record
        if options[:json]
          puts JSON.pretty_generate({ error: 'Service account JSON key not found. Run gsc connect or gsc vault to configure.' })
        else
          puts Color.c("\n❌ Error: Google Service Account Key JSON not found!\n", Color::RED, Color::BOLD)
          puts "💡 #{Color::BOLD}Quick Setup:#{Color::RESET} Run #{Color.c('gsc connect', Color::CYAN, Color::BOLD)} to drag & drop your key or auto-detect from Downloads!"
          puts "   Or run #{Color.c("gsc vault add /path/to/key.json --domain #{hostname}", Color::CYAN)} for Agency Vault multi-domain management."
          puts
          Setup.print_setup_instructions
        end
        exit 1
      end

      service_account = sa_record[:data]
      if sa_record[:type] == 'vault'
        puts Color.c("🔑 Authenticated via Agency Vault: #{service_account['client_email']} [AES-256-GCM]", Color::GRAY) unless options[:json] || options[:format]
      else
        puts Color.c("🔑 Authenticated as: #{service_account['client_email']} (#{File.basename(sa_record[:source].to_s)})", Color::GRAY) unless options[:json] || options[:format]
      end

      puts Color.c("🎯 Target Domain:    #{hostname} (GSC Property: #{site_url})\n", Color::GRAY) unless options[:json] || options[:format]

      token = if options[:dry_run]
                'DRY_RUN_PREVIEW_TOKEN'
              else
                Auth.fetch_access_token(service_account)
              end

      client = Client.new(token: token)
      api    = API.new(client)

      dispatch_authenticated_command(command, target, extra, options, api, site_url, hostname, https_origin)
    rescue StandardError => e
      if options && options[:json]
        puts JSON.pretty_generate({ error: e.message })
      else
        puts Color.c("\n❌ Execution Error: #{e.message}", Color::RED, Color::BOLD)
      end
      exit 1
    end

    def self.dispatch_authenticated_command(command, target, extra, options, api, site_url, hostname, https_origin)
      case command
      when 'index', 'idx', 'remove', 'rm', 'status', 'auto', 'index-sitemap',
           'index-batch', 'queue', 'batch-index', 'inspect', 'i', 'inspect-sitemap',
           'sitemaps-list', 'sitemaps', 's', 'sitemaps-submit', 'sites-list',
           'indexnow', 'in', 'indexnow-sitemap', 'ins'
        Indexing.run(command, target, extra, options, api, site_url, hostname, https_origin)

      when 'performance', 'perf', 'p', 'top-queries', 'queries', 'query', 'tq',
           'brand', 'brand-split', 'brand-segmentation', 'top-pages', 'pages', 'tp',
           'ctr-curve', 'ctr-simulator', 'traffic-gain', 'decay', 'trends-decay', 'd',
           'devices', 'countries', 'snippets', 'appearance', 'search-appearance', 'cities'
        Analytics.run(command, target, extra, options, api, site_url, hostname, https_origin)

      when 'ga4', 'bounce', 'correlation', 'engagement', 'ga4-properties', 'ga4-list',
           'realtime', 'live', 'r', 'ads', 'campaigns', 'channels', 'traffic'
        GA4.run(command, target, extra, options, api, hostname, site_url)

      when 'opportunities', 'striking-distance', 'quick-wins', 'o', 'opp',
           'strike', 'striker', 'striking-playbook', 'underperformers', 'ctr-underperformers', 'ctr-gaps', 'u',
           'cannibalization', 'conflicts', 'c', 'questions-harvest', 'harvest-questions', 'qh', 'faq-harvest'
        Growth.run(command, target, extra, options, api, site_url, hostname, https_origin)

      when 'zombies', 'bloat', 'z', 'zombie-purge', 'zombie-clean', 'crawl-waste', 'purge'
        ZombiePurger.run(command, target, extra, options, api, site_url, hostname, https_origin)

      when 'audit', 'a', 'page', 'page-audit', 'site-audit', 'site-crawl', 'crawl'
        Audit.run(command, target, extra, options, api, site_url, hostname, https_origin)

      when 'seasonal', 'season', 'spike', 'seasonal-trends', 'seasonality'
        Seasonal.run(command, target, extra, options, api, site_url, hostname)

      when 'canonical-chains', 'canonical', 'chains', 'redirect-chains', 'redirects-audit'
        Canonical.run(command, target, extra, options, api, site_url, hostname)

      when 'low-ctr', 'ctr-rewrite', 'lost-clicks', 'rewrite-titles', 'ctr-fix', 'lowctr'
        LowCtr.run(command, target, extra, options, api, site_url, hostname)

      when 'security', 'security-headers', 'sec', 'mixed-content', 'hsts', 'ssl-check'
        Security.run(command, target, extra, options, api, site_url, hostname)

      when 'landing-roi', 'landing-revenue', 'roi', 'lroi'
        LandingRoi.run(command, target, extra, options, api, site_url, hostname)

      when 'sitemap-tree', 'sitemap-hierarchy', 'smt', 'sm-tree'
        SitemapTree.run(command, target, extra, options, api, site_url, hostname)

      when 'cite-sim', 'cite', 'csim', 'ai-cite', 'simulate-citation'
        CitationSimulator.run(command, target, extra, options, api, site_url, hostname)

      when 'sparklines', 'sparkline', 'spark', 'trends-graph', 'tg'
        Sparkline.run(command, target, extra, options, api, site_url, hostname)

      when 'image-seo', 'image', 'images-audit', 'img', 'img-seo'
        ImageSeo.run(command, target, extra, options, api, site_url, hostname)

      when 'hreflang-check', 'hreflang', 'hreflang-audit', 'hlang'
        Hreflang.run(command, target, extra, options, api, site_url, hostname)

      when 'eeat', 'eeat-audit', 'author-audit', 'credentials'
        Eeat.run(command, target, extra, options, api, site_url, hostname)

      when 'report', 'rep', 'executive-report', 'audit-report'
        Report.run(command, target, extra, options, api, site_url, hostname)

      when 'intent-shift', 'intent', 'search-intent', 'intent-drift'
        IntentShift.run(command, target, extra, options, api, site_url, hostname)

      when 'rich-results', 'rich', 'richresults', 'rich-test', 'test-rich-results', 'test-rich', 'schema-test', 'test-schema'
        options[:open] = true if %w[rich-test test-rich-results test-rich schema-test test-schema].include?(command)
        RichResults.run(command, target, extra, options, api, site_url, hostname)

      when 'watch', 'watchdog', 'mon', 'monitor'
        Watchdog.run(command, target, extra, options, api, site_url, hostname)

      when 'kw-value', 'kwval', 'value', 'kw-revenue', 'kw-roi'
        KeywordValue.run(command, target, extra, options, api, site_url, hostname)

      when 'mobile-parity', 'mobile', 'parity', 'mobile-gap'
        MobileParity.run(command, target, extra, options, api, site_url, hostname)

      when 'skill-pack', 'agent-pack', 'skillpack', 'pack-skill'
        SkillPack.run(command, target, extra, options, api, site_url, hostname)

      when 'doctor', 'doc', 'health', 'checkup'
        Doctor.run(command, target, extra, options, api, site_url, hostname)

      when 'aio-hunter', 'aio', 'aio-hunt', 'overview'
        AioHunter.run(command, target, extra, options, api, site_url, hostname)

      when 'soft-404', '404', 'soft404', 'broken-urls'
        Soft404.run(command, target, extra, options, api, site_url, hostname)

      else
        if options[:json]
          puts JSON.pretty_generate({ error: "Unknown command: #{command}" })
        else
          puts Color.c("❌ Unknown command: '#{command}'. Run 'gsc --help' for options.", Color::RED)
        end
        exit 1 unless options[:in_dashboard]
      end
    end

    # =========================================================================
    # Backward Compatibility Class Method Delegates
    # Ensures existing scripts/tests calling GSC::CLI.<method> work 100%
    # =========================================================================
    class << self
      # Base formatters and utilities
      def dispatch_command(*args, &blk); dispatch_authenticated_command(*args, &blk); end
      def format_number(*args, &blk); Base.format_number(*args, &blk); end
      def format_country(*args, &blk); Base.format_country(*args, &blk); end
      def format_device(*args, &blk); Base.format_device(*args, &blk); end
      def format_appearance(*args, &blk); Base.format_appearance(*args, &blk); end
      def format_duration(*args, &blk); Base.format_duration(*args, &blk); end
      def write_csv(*args, &blk); Base.write_csv(*args, &blk); end
      def normalize_path(*args, &blk); Base.normalize_path(*args, &blk); end
      def resolve_domain(*args, &blk); Base.resolve_domain(*args, &blk); end
      def fetch_available_domains(*args, &blk); Base.fetch_available_domains(*args, &blk); end
      def require_target!(*args, &blk); Base.require_target!(*args, &blk); end
      def dry_run?(*args, &blk); Base.dry_run?(*args, &blk); end
      def simulate_dry_run?(*args, &blk); Base.simulate_dry_run?(*args, &blk); end

      # Interactive Dashboard
      def handle_interactive_shell(options = {}); Dashboard.run(options); end
      def print_main_menu_shortcuts(*args, &blk); Dashboard.print_main_menu_shortcuts(*args, &blk); end
      def print_keywords_menu(*args, &blk); Dashboard.print_keywords_menu(*args, &blk); end
      def print_analytics_menu(*args, &blk); Dashboard.print_analytics_menu(*args, &blk); end
      def print_ga4_menu(*args, &blk); Dashboard.print_ga4_menu(*args, &blk); end
      def print_indexing_menu(*args, &blk); Dashboard.print_indexing_menu(*args, &blk); end
      def print_setup_menu(*args, &blk); Dashboard.print_setup_menu(*args, &blk); end

      # Analytics & Tables
      def resolve_sort_params(*args, &blk); Analytics.resolve_sort_params(*args, &blk); end
      def sort_analytics_rows(*args, &blk); Analytics.sort_analytics_rows(*args, &blk); end
      def expected_ctr_for(*args, &blk); Analytics.expected_ctr_for(*args, &blk); end
      def print_devices_table(*args, &blk); Analytics.print_devices_table(*args, &blk); end
      def print_countries_table(*args, &blk); Analytics.print_countries_table(*args, &blk); end
      def print_snippets_table(*args, &blk); Analytics.print_snippets_table(*args, &blk); end
      def print_cities_table(*args, &blk); Analytics.print_cities_table(*args, &blk); end
      def print_mini_queries_table(*args, &blk); Analytics.print_mini_queries_table(*args, &blk); end
      def print_mini_pages_table(*args, &blk); Analytics.print_mini_pages_table(*args, &blk); end

      # Setup, Configuration & Wizard
      def handle_connect_wizard(*args, &blk); Setup.handle_connect_wizard(*args, &blk); end
      def handle_connect_ga4_wizard(*args, &blk); Setup.handle_connect_ga4_wizard(*args, &blk); end
      def handle_open_command(*args, &blk); Setup.handle_open_command(*args, &blk); end
      def print_version_info(*args, &blk); Setup.print_version_info(*args, &blk); end
      def handle_update_command(*args, &blk); Setup.handle_update_command(*args, &blk); end
      def copy_to_clipboard(*args, &blk); Setup.copy_to_clipboard(*args, &blk); end
      def handle_prompts_command(*args, &blk); Setup.handle_prompts_command(*args, &blk); end
      def show_playbook_detail(*args, &blk); Setup.show_playbook_detail(*args, &blk); end
      def handle_skills_command(*args, &blk); Setup.handle_skills_command(*args, &blk); end
      def print_where_info(*args, &blk); Setup.print_where_info(*args, &blk); end
      def handle_use_command(*args, &blk); Setup.handle_use(*args, &blk); end
      def handle_config_command(*args, &blk); Setup.handle_config_command(*args, &blk); end
      def print_setup_instructions(*args, &blk); Setup.print_setup_instructions(*args, &blk); end
      def print_commands_help(*args, &blk); Setup.print_commands_help(*args, &blk); end

      # Keywords & Trends
      def handle_google_trends_command(*args, &blk); Keywords.handle_trends(*args, &blk); end
      def render_keyword_table(*args, &blk); Keywords.render_keyword_table(*args, &blk); end
      def handle_saved_keywords_command(*args, &blk); Keywords.handle_saved(*args, &blk); end
      def handle_planner_import_command(*args, &blk); Keywords.handle_planner_import(*args, &blk); end
      def handle_connect_ke_wizard(*args, &blk); Keywords.handle_connect_ke(*args, &blk); end
      def handle_ke_credits_command(*args, &blk); Keywords.handle_ke_credits(*args, &blk); end
      def handle_ke_command(*args, &blk); Keywords.handle_ke(*args, &blk); end
      def handle_planner_expand_command(*args, &blk); Keywords.handle_planner_expand(*args, &blk); end

      # Audits & Crawling
      def handle_page_audit_command(*args, &blk); Audit.handle_page(*args, &blk); end
      def handle_headings_command(*args, &blk); Audit.handle_headings(*args, &blk); end
      def handle_site_crawl_command(*args, &blk); Audit.handle_site_crawl(*args, &blk); end
      def run_comprehensive_audit(*args, &blk); Audit.run_comprehensive_audit(*args, &blk); end
      def print_comprehensive_audit(*args, &blk); Audit.print_comprehensive_audit(*args, &blk); end

      # Growth & Tactical Playbooks
      def handle_strike_command(*args, &blk); Growth.handle_strike(*args, &blk); end
      def handle_seasonal_command(*args, &blk); Seasonal.run(*args, &blk); end
      def handle_canonical_command(*args, &blk); Canonical.run('canonical', *args, &blk); end

      # Indexing Batch Queue
      def print_batch_summary(*args, &blk); Indexing.print_batch_summary(*args, &blk); end

      # GA4 Error Handling
      def handle_ga4_api_error(*args, &blk); GA4.handle_ga4_api_error(*args, &blk); end
    end
  end
end

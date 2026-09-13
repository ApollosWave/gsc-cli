# frozen_string_literal: true

module GSC
  # CLI Command Runner
  class CLI
    VERSION = GSC::VERSION
    DEFAULT_UPDATE_URL = ENV['GSC_UPDATE_URL'] || 'https://raw.githubusercontent.com/ApollosWave/gsc-cli/main/dist/gsc'

    BANNER = <<~BANNER
      #{Color::BOLD}#{Color::CYAN}╔══════════════════════════════════════════════════════════════╗
      ║     🚀 GOOGLE SEARCH CONSOLE & INDEXING API (RUBY CLI)       ║
      ╚══════════════════════════════════════════════════════════════╝#{Color::RESET}
    BANNER

    Prompts          = GSC::Prompts
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

        opts.on('--days DAYS', Integer, 'Time window for analytics in days (default: 30)') do |days|
          options[:days] = days
        end

        opts.on('--limit LIMIT', Integer, 'Maximum rows to display (default: 50)') do |limit|
  options[:limit] = limit
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

        opts.on('--min-imp COUNT', Integer, 'Minimum impressions threshold (default: 10)') do |count|
          options[:min_imp] = count
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

opts.on('--url URL', 'Target URL for prompt or index verification') do |u|
  options[:url] = u
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
          print_version_info(options)
          exit 0
        end

        opts.on('--in-dashboard', 'Internal interactive dashboard flag') do
          options[:in_dashboard] = true
        end

        opts.on('-h', '--help', 'Show help') do
          puts BANNER
          puts opts
          print_commands_help
          exit 0
        end
      end

      args = parser.parse(argv)

      if args.empty?
        if !options[:json] && ENV['GSC_NON_INTERACTIVE'] != '1'
          handle_interactive_shell(options)
          exit 0
        else
          puts BANNER
          puts parser
          print_commands_help
          exit 0
        end
      end

      command = args[0]
      target  = args[1]
      extra   = args[2]

      # Built-in config commands that don't need Google API authentication
      case command
      when 'interactive', 'shell', 'repl', 'menu', 'dashboard'
        handle_interactive_shell(options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]

      when /^\d+$/
        handle_use_command(command, options)
        exit 0 unless options[:in_dashboard]
        return

      when 'domains', 'list'
        handle_use_command(nil, options)
        exit 0 unless options[:in_dashboard]
        return

when 'suggest', 'autocomplete', 'sug'
  handle_suggest_command(target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'questions', 'paa', 'faqs'
  handle_questions_command(target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'authority', 'opr', 'da', 'domain-authority'
  handle_authority_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'speed', 'vitals', 'pagespeed', 'psi'
  handle_speed_command(target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'compare', 'diff-seo', 'vs'
  handle_compare_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'content-gap', 'gap'
  handle_content_gap_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'internal-links', 'orphans', 'links-audit'
  handle_internal_links_command(target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'schema', 'rich-snippets', 'ld-json'
  handle_schema_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'llms', 'ai-ready'
  handle_llms_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'preview', 'serp', 'serp-preview', 'social-preview'
  handle_preview_command(target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'indexnow', 'in'
  handle_indexnow_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'indexnow-sitemap', 'ins'
  handle_indexnow_sitemap_command(target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'trace', 'redirects', 'hops'
  handle_trace_command(target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'robots', 'robots-txt'
  handle_robots_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'backlinks', 'links'
  handle_backlinks_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]


      when 'trends', 'tr', 'google-trends', 'gtrends', 't'
  if target.nil? || target.strip.empty?
    # No target query given: pass through to GSC period decay/trends below
  else
    handle_google_trends_command(target, options)
    exit 0 unless options[:in_dashboard]
    return
  end
when 'planner', 'kp', 'keywords'
  if target == 'import'
    handle_planner_import_command(extra, options)
    exit 0 unless options[:in_dashboard]
    return
  elsif target && (File.exist?(target) || target.end_with?('.csv', '.tsv', '.md'))
    handle_planner_import_command(target, options)
    exit 0 unless options[:in_dashboard]
    return
  else
    handle_planner_expand_command(target, options)
    exit 0 unless options[:in_dashboard]
    return
  end
when 'planner-import', 'pi', 'import', 'imp'
  handle_planner_import_command(target, options)
  exit 0 unless options[:in_dashboard]
  return
when 'saved', 'research', 'saved-keywords', 'sv'
  handle_saved_keywords_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]
when 'check', 'chk'
  handle_saved_keywords_command('check', target, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'ke', 'keywordseverywhere', 'keywords-everywhere', 'k'
  if target == 'credits' || target == 'account'
    handle_ke_credits_command(options)
  elsif target == 'connect' || target == 'setup'
    handle_connect_ke_wizard(extra)
  else
    handle_ke_command(target, options)
  end
  exit 0 unless options[:in_dashboard]
  return
when 'ke-credits'
  handle_ke_credits_command(options)
  exit 0 unless options[:in_dashboard]
  return
when 'connect-ke', 'setup-ke', 'link-ke', 'connect-keywordseverywhere'
  handle_connect_ke_wizard(target)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
when 'version', '-v', '--version'
        print_version_info(options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'update', 'upgrade'
        handle_update_command(options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'where', 'which'
        print_where_info(options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'use'
        handle_use_command(target, options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'config'
        handle_config_command(target, extra, args[3], options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'connect', 'setup', 'init', 'install'
        if target.to_s.downcase == 'ke' || target.to_s.downcase == 'keywordseverywhere'
          handle_connect_ke_wizard(extra)
        elsif target.to_s.downcase == 'indexnow' || target.to_s.downcase == 'in'
          handle_indexnow_command('connect', extra, options)
        else
          handle_connect_wizard
        end
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'connect-ga4', 'setup-ga4', 'link-ga4'
        handle_connect_ga4_wizard(options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'open'
        handle_open_command
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
when 'prompts', 'prompt', 'playbooks', 'playbook'
  handle_prompts_command(target, extra, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]
when 'skills', 'skill', 'init-skill'
        subcmd = (command == 'init-skill') ? 'install' : target
        handle_skills_command(subcmd, options)
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'commands', 'palette', 'schema'
        if options[:json]
          puts JSON.pretty_generate({
            cli: 'gsc',
            activeDomain: Config.default_domain,
            commandCount: COMMAND_REGISTRY.sum { |c| c[:commands].size },
            categories: COMMAND_REGISTRY
          })
        else
          print_commands_help
        end
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      when 'help'
        puts BANNER
        puts parser
        print_commands_help
        exit 0 unless options[:in_dashboard]
        return if options[:in_dashboard]
      end

      puts BANNER unless options[:json] || options[:in_dashboard]

      # 1. Locate and authenticate Service Account
      key_path = Auth.find_key(options[:key])
      unless key_path
        if options[:json]
          puts JSON.pretty_generate({ error: 'Service account JSON key not found. Run gsc connect to configure.' })
        else
          puts Color.c("\n❌ Error: Google Service Account Key JSON not found!\n", Color::RED, Color::BOLD)
          puts "💡 #{Color::BOLD}Quick Setup:#{Color::RESET} Run #{Color.c('gsc connect', Color::CYAN, Color::BOLD)} to drag & drop your key or auto-detect from Downloads!"
          puts "   Or run #{Color.c('gsc open', Color::CYAN)} to open the config folder in Finder."
          puts
          print_setup_instructions
        end
        exit 1
      end

      service_account = JSON.parse(File.read(key_path))
      puts Color.c("🔑 Authenticated as: #{service_account['client_email']} (#{File.basename(key_path)})", Color::GRAY) unless options[:json]

      # 2. Resolve domain
      hostname, site_url, https_origin = resolve_domain(options[:domain], target, options)
      puts Color.c("🎯 Target Domain:    #{hostname} (GSC Property: #{site_url})\n", Color::GRAY) unless options[:json]

      # 3. Get OAuth Token
      token = if options[:dry_run]
                'DRY_RUN_MOCK_TOKEN'
              else
                Auth.fetch_access_token(service_account)
              end

      client = Client.new(token: token)
      api    = API.new(client)

      # 4. Execute Command
      dispatch_command(command, target, api, options, hostname, site_url, https_origin)
    rescue StandardError => e
      if options && options[:json]
        puts JSON.pretty_generate({ error: e.message })
      else
        puts Color.c("\n❌ Execution Error: #{e.message}", Color::RED, Color::BOLD)
      end
      exit 1
    end

    def self.dispatch_command(command, target, api, options, hostname, site_url, https_origin)
      case command
      when 'index'
        require_target!(target, "index https://#{hostname}/page", options)
        puts "🚀 Sending #{Color::BOLD}URL_UPDATED#{Color::RESET} indexing request for:\n   #{Color.c(target, Color::CYAN)}" unless options[:json]
        return if simulate_dry_run?(options)

        res = api.publish_url(target, 'URL_UPDATED')
        if options[:json]
          puts JSON.pretty_generate(res[:data] || { ok: res[:ok], status: res[:status] })
        elsif res[:ok]
          puts Color.c("\n✅ Success! Google Indexing API accepted the URL (HTTP 200).", Color::GREEN)
          notify_time = res.dig(:data, 'urlNotificationMetadata', 'latestUpdate', 'notifyTime') || Time.now.iso8601
          puts "   Notify Time: #{notify_time}"
          puts Color.c("\nGooglebot will prioritize crawling this URL shortly.", Color::DIM)
        else
          puts Color.c("\n❌ Indexing API Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end

      when 'remove'
        require_target!(target, "remove https://#{hostname}/page", options)
        puts "🗑️ Sending #{Color::BOLD}URL_DELETED#{Color::RESET} request for:\n   #{Color.c(target, Color::RED)}" unless options[:json]
        return if simulate_dry_run?(options)

        res = api.publish_url(target, 'URL_DELETED')
        if options[:json]
          puts JSON.pretty_generate(res[:data] || { ok: res[:ok], status: res[:status] })
        elsif res[:ok]
          puts Color.c("\n✅ Success! Google Indexing API recorded URL deletion.", Color::GREEN)
        else
          puts Color.c("\n❌ Indexing API Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end

      when 'status'
        require_target!(target, "status https://#{hostname}/page", options)
        puts "🔍 Querying Indexing API metadata for:\n   #{Color.c(target, Color::CYAN)}\n" unless options[:json]
        res = api.get_url_status(target)
        if options[:json]
          puts JSON.pretty_generate(res[:data])
        elsif res[:ok]
          puts Color.c("✅ Latest Notification Record:", Color::GREEN)
          puts JSON.pretty_generate(res[:data])
        else
          puts Color.c("❌ Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end

      when 'auto', 'index-sitemap'
        puts "📥 Loading XML sitemap for #{Color.c(hostname, Color::CYAN)}..." unless options[:json]
        urls = SitemapLoader.resolve_urls(target, https_origin, quiet: options[:json])
        puts "📋 Found #{Color.c(urls.size.to_s, Color::BOLD)} URLs. Submitting batch to Google Indexing API...\n" unless options[:json]

        success_count = 0
        fail_count    = 0
        results = []

        urls.each_with_index do |u, idx|
          progress = "[#{idx + 1}/#{urls.size}]".rjust(urls.size.to_s.length + 3)
          print "  #{Color.c(progress, Color::GRAY)} #{u} " unless options[:json]

          if options[:dry_run]
            puts Color.c('[DRY RUN]', Color::YELLOW) unless options[:json]
            success_count += 1
            results << { url: u, status: 'simulated' }
            next
          end

          res = api.publish_url(u, 'URL_UPDATED')
          if res[:ok]
            success_count += 1
            puts Color.c('✔ OK', Color::GREEN) unless options[:json]
            results << { url: u, status: 'ok', notifyTime: res.dig(:data, 'urlNotificationMetadata', 'latestUpdate', 'notifyTime') }
          else
            fail_count += 1
            msg = res.dig(:data, 'error', 'message') || "HTTP #{res[:status]}"
            puts Color.c("✖ Failed (#{msg})", Color::RED) unless options[:json]
            results << { url: u, status: 'failed', error: msg }
          end

          sleep(options[:delay] / 1000.0) if options[:delay] > 0
        end

        if options[:json]
          puts JSON.pretty_generate({ total: urls.size, success: success_count, failed: fail_count, results: results })
        else
          print_batch_summary(success_count, fail_count, urls.size)
        end

when 'page', 'onpage', 'page-audit'
  handle_page_audit_command(target, site_url, api, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'site-audit', 'audit-site', 'crawl'
  handle_site_crawl_command(target, site_url, api, options)
  exit 0 unless options[:in_dashboard]
  return if options[:in_dashboard]

when 'inspect', 'i'
        require_target!(target, "inspect https://#{hostname}/page", options)
        puts "🔍 Inspecting URL via Search Console API:\n   #{Color.c(target, Color::CYAN)} (Property: #{site_url})\n" unless options[:json]
        res = api.inspect_url(target, site_url)
        if options[:json]
          r = res.dig(:data, 'inspectionResult', 'indexStatusResult') || {}
          puts JSON.pretty_generate(r.merge('url' => target, 'ok' => res[:ok], 'status' => res[:status]))
        elsif res[:ok]
          r = res.dig(:data, 'inspectionResult', 'indexStatusResult')
          if r
            verdict_color = (r['verdict'] == 'PASS') ? Color::GREEN : Color::YELLOW
            puts Color.c('📋 INDEXATION DIAGNOSTICS:', Color::BOLD)
            puts "   Verdict:          #{Color.c(r['verdict'], verdict_color, Color::BOLD)}"
            puts "   Coverage Status:  #{r['coverageState'] || 'Unknown'}"
            puts "   Indexing Allowed: #{r['indexingState'] == 'INDEXING_ALLOWED' ? Color.c('ALLOWED', Color::GREEN) : Color.c(r['indexingState'] || 'NO', Color::RED)}"
            puts "   Robots.txt:       #{r['robotsTxtState'] == 'ALLOWED' ? Color.c('ALLOWED', Color::GREEN) : Color.c(r['robotsTxtState'] || 'BLOCKED', Color::RED)}"
            puts "   Last Crawled:     #{Color.c(r['lastCrawlTime'] || 'Never / Not yet recorded', Color::CYAN)}"
            puts "   User Canonical:   #{r['userCanonical'] || 'None specified'}"
            puts "   Google Canonical: #{r['googleCanonical'] || 'None assigned'}"
          else
            puts JSON.pretty_generate(res[:data])
          end
        else
          puts Color.c("❌ Inspection Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end

      when 'inspect-sitemap'
        puts "📥 Loading sitemap for bulk inspection on #{Color.c(hostname, Color::CYAN)}..." unless options[:json]
        urls = SitemapLoader.resolve_urls(target, https_origin, quiet: options[:json])
        puts "🔍 Bulk inspecting #{Color.c(urls.size.to_s, Color::BOLD)} URLs via Search Console API (#{site_url})...\n" unless options[:json]

        results = []
        pass_count = 0
        queue_count = 0
        error_count = 0

        unless options[:json]
          puts Color.c("  #   | Status   | Last Crawl  | Coverage Status                     | URL", Color::DIM)
          puts "  ------------------------------------------------------------------------------------------------"
        end

        urls.each_with_index do |u, idx|
          idx_str = (idx + 1).to_s.rjust(4)
          res = api.inspect_url(u, site_url)

          if res[:ok]
            r = res.dig(:data, 'inspectionResult', 'indexStatusResult')
            verdict  = r ? r['verdict'] : 'UNKNOWN'
            coverage = ((r && r['coverageState']) || 'Unknown').ljust(35)
            last_cr  = (r && r['lastCrawlTime']) ? r['lastCrawlTime'].split('T').first : 'Never     '

            if verdict == 'PASS'
              pass_count += 1
              puts "  #{idx_str} | #{Color.c('✅ PASS', Color::GREEN)}   | #{last_cr} | #{coverage} | #{u}" unless options[:json]
            else
              queue_count += 1
              puts "  #{idx_str} | #{Color.c('⏳ QUEUE', Color::YELLOW)}  | #{last_cr} | #{coverage} | #{u}" unless options[:json]
            end

            results << {
              url: u,
              verdict: verdict,
              coverage: r&.dig('coverageState') || 'Unknown',
              last_crawl: r&.dig('lastCrawlTime') || 'Never',
              robots_txt: r&.dig('robotsTxtState') || 'Unknown'
            }
          else
            error_count += 1
            puts "  #{idx_str} | #{Color.c('❌ ERROR', Color::RED)}  | ---------- | HTTP #{res[:status].to_s.ljust(30)} | #{u}" unless options[:json]
            results << { url: u, verdict: 'ERROR', error: "HTTP #{res[:status]}" }
          end

          sleep(options[:delay] / 1000.0) if options[:delay] > 0
        end

        if options[:json]
          puts JSON.pretty_generate({ total: urls.size, indexedPass: pass_count, pendingQueue: queue_count, errors: error_count, urls: results })
        else
          puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "#{Color::BOLD}📊 BULK INDEXATION SUMMARY (#{urls.size} URLs)#{Color::RESET}"
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "  ✅ Indexed on Google (PASS): #{Color.c(pass_count.to_s, Color::GREEN, Color::BOLD)} (#{'%.1f' % ((pass_count.to_f / urls.size) * 100)}%)"
          puts "  ⏳ Pending / Queue:          #{Color.c(queue_count.to_s, Color::YELLOW, Color::BOLD)} (#{'%.1f' % ((queue_count.to_f / urls.size) * 100)}%)"
          puts "  ❌ Errors:                   #{Color.c(error_count.to_s, Color::RED, Color::BOLD)}" if error_count > 0
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"

          if options[:csv]
            write_csv(options[:csv], ['URL', 'Verdict', 'Coverage', 'LastCrawl', 'RobotsTxt'], results.map(&:values))
            puts Color.c("📁 Exported audit table to #{options[:csv]}\n", Color::CYAN)
          end
        end

      when 'top-queries', 'queries', 'query', 'tq'
        sort_field, sort_order = resolve_sort_params(options[:sort], options[:order])
        sort_desc = sort_field ? "sorted by #{sort_field} #{sort_order}" : "sorted by clicks & impressions"
        puts "📊 Fetching top search queries for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days, #{sort_desc})...\n" unless options[:json]

        res = if options[:all]
        puts "🔄 Paginating across all query rows via startRow..." unless options[:json]
        api.query_all_analytics(site_url, days: options[:days], dimensions: ['query'])
      else
        fetch_limit = [options[:limit] * 10, 1000].max
        api.query_analytics(site_url, days: options[:days], dimensions: ['query'], row_limit: fetch_limit)
      end
        if res[:ok]
          raw_rows = (res.dig(:data, 'rows') || []).map do |r|
            {
              query: r['keys'].first,
              clicks: r['clicks'],
              impressions: r['impressions'],
              ctr: (r['ctr'] * 100).round(2),
              position: r['position'].round(1)
            }
          end

          sorted_rows = sort_analytics_rows(raw_rows, options[:sort], options[:order])
rows = options[:all] ? sorted_rows : sorted_rows.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(rows)
          elsif rows.empty?
            puts Color.c("ℹ️ No search query data recorded in the last #{options[:days]} days.", Color::YELLOW)
          else
            puts "#{Color::BOLD}Clicks | Impressions | CTR    | Position | Query#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            rows.each do |row|
              clicks  = row[:clicks].to_s.ljust(6)
              imp     = row[:impressions].to_s.ljust(11)
              ctr     = "#{row[:ctr]}%".ljust(6)
              pos     = row[:position].to_s.ljust(8)
              puts "#{clicks} | #{imp} | #{ctr} | #{pos} | #{Color.c(row[:query], Color::CYAN)}"
            end
            puts "\n#{Color.c("Total Queries Displayed: #{rows.size}", Color::GRAY)}\n"

            if options[:csv]
              csv_data = rows.map { |r| [r[:query], r[:clicks], r[:impressions], r[:ctr], r[:position]] }
              write_csv(options[:csv], %w[Query Clicks Impressions CTR Position], csv_data)
              puts Color.c("📁 Exported queries to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'top-pages', 'pages', 'tp'
        sort_field, sort_order = resolve_sort_params(options[:sort], options[:order])
        sort_desc = sort_field ? "sorted by #{sort_field} #{sort_order}" : "sorted by clicks & impressions"
        puts "📊 Fetching top performing pages for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days, #{sort_desc})...\n" unless options[:json]

        res = if options[:all]
        puts "🔄 Paginating across all page rows via startRow..." unless options[:json]
        api.query_all_analytics(site_url, days: options[:days], dimensions: ['page'])
      else
        fetch_limit = [options[:limit] * 10, 1000].max
        api.query_analytics(site_url, days: options[:days], dimensions: ['page'], row_limit: fetch_limit)
      end
        if res[:ok]
          raw_rows = (res.dig(:data, 'rows') || []).map do |r|
            {
              page: r['keys'].first,
              clicks: r['clicks'],
              impressions: r['impressions'],
              ctr: (r['ctr'] * 100).round(2),
              position: r['position'].round(1)
            }
          end

          sorted_rows = sort_analytics_rows(raw_rows, options[:sort], options[:order])
rows = options[:all] ? sorted_rows : sorted_rows.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(rows)
          elsif rows.empty?
            puts Color.c("ℹ️ No page performance data recorded in the last #{options[:days]} days.", Color::YELLOW)
          else
            puts "#{Color::BOLD}Clicks | Impressions | CTR    | Position | Page URL#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            rows.each do |row|
              clicks  = row[:clicks].to_s.ljust(6)
              imp     = row[:impressions].to_s.ljust(11)
              ctr     = "#{row[:ctr]}%".ljust(6)
              pos     = row[:position].to_s.ljust(8)
              puts "#{clicks} | #{imp} | #{ctr} | #{pos} | #{Color.c(row[:page], Color::CYAN)}"
            end
            puts "\n#{Color.c("Total Pages Displayed: #{rows.size}", Color::GRAY)}\n"

            if options[:csv]
              csv_data = rows.map { |r| [r[:page], r[:clicks], r[:impressions], r[:ctr], r[:position]] }
              write_csv(options[:csv], %w[Page Clicks Impressions CTR Position], csv_data)
              puts Color.c("📁 Exported pages to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'performance', 'perf', 'p'
        puts "📈 Calculating Search Console & Behavioral Performance for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days)...\n" unless options[:json]

        # 1. Overall Totals
        res = api.query_analytics(site_url, days: options[:days], dimensions: [])
        unless res[:ok]
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Performance API Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
          return
        end

        row = res.dig(:data, 'rows', 0) || { 'clicks' => 0, 'impressions' => 0, 'ctr' => 0, 'position' => 0 }
        total_clicks = row['clicks'] || 0
        total_imp    = row['impressions'] || 0
        avg_ctr      = ((row['ctr'] || 0) * 100).round(2)
        avg_pos      = (row['position'] || 0).round(1)

        # 2. Device Breakdown
        dev_res = api.query_analytics(site_url, days: options[:days], dimensions: ['device'])
        devices_data = (dev_res[:ok] ? (dev_res.dig(:data, 'rows') || []) : []).map do |r|
          c = r['clicks'] || 0
          i = r['impressions'] || 0
          ctr = ((r['ctr'] || 0) * 100).round(2)
          pos = (r['position'] || 0).round(1)
          share = total_clicks > 0 ? "#{(c.to_f / total_clicks * 100).round(1)}%" : "-"
          { device: r['keys'].first, clicks: c, impressions: i, ctr: ctr, position: pos, share: share }
        end.sort_by { |r| -r[:clicks] }

        # 3. Top Countries
        cntry_limit = (options[:limit] == 50 ? 10 : options[:limit])
        cntry_res = api.query_analytics(site_url, days: options[:days], dimensions: ['country'], row_limit: [cntry_limit * 3, 50].max)
        countries_data = (cntry_res[:ok] ? (cntry_res.dig(:data, 'rows') || []) : []).map do |r|
          {
            country: r['keys'].first,
            clicks: r['clicks'] || 0,
            impressions: r['impressions'] || 0,
            ctr: ((r['ctr'] || 0) * 100).round(2),
            position: (r['position'] || 0).round(1)
          }
        end.sort_by { |r| [-r[:clicks], -r[:impressions]] }.first(cntry_limit)

        # 4. Search Appearance / Rich Snippets
        snip_res = api.query_analytics(site_url, days: options[:days], dimensions: ['searchAppearance'], row_limit: 10)
        snippets_data = (snip_res[:ok] ? (snip_res.dig(:data, 'rows') || []) : []).map do |r|
          {
            type: r['keys'].first,
            clicks: r['clicks'] || 0,
            impressions: r['impressions'] || 0,
            ctr: ((r['ctr'] || 0) * 100).round(2),
            position: (r['position'] || 0).round(1)
          }
        end.sort_by { |r| -r[:clicks] }

        # 5. Top Search Queries (Top 5 for dashboard summary)
        q_res = api.query_analytics(site_url, days: options[:days], dimensions: ['query'], row_limit: 5)
        queries_data = (q_res[:ok] ? (q_res.dig(:data, 'rows') || []) : []).map do |r|
          {
            query: r['keys'].first,
            clicks: r['clicks'] || 0,
            impressions: r['impressions'] || 0,
            ctr: ((r['ctr'] || 0) * 100).round(2),
            position: (r['position'] || 0).round(1)
          }
        end.sort_by { |r| -r[:clicks] }

        # 6. Top Landing Pages (Top 5 for dashboard summary)
        p_res = api.query_analytics(site_url, days: options[:days], dimensions: ['page'], row_limit: 5)
        pages_data = (p_res[:ok] ? (p_res.dig(:data, 'rows') || []) : []).map do |r|
          path = r['keys'].first.sub(%r{^https?://[^/]+}, '')
          path = '/' if path.empty?
          {
            path: path,
            clicks: r['clicks'] || 0,
            impressions: r['impressions'] || 0,
            ctr: ((r['ctr'] || 0) * 100).round(2),
            position: (r['position'] || 0).round(1)
          }
        end.sort_by { |r| -r[:clicks] }

        # 7. GA4 Top Cities (if linked)
        ga4_property_id = options[:property] || Config.ga4_property_id(hostname)
        cities_data = []
        if ga4_property_id
          ga4_res = api.query_ga4_cities(ga4_property_id, days: options[:days], limit: 8, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
          if ga4_res[:ok]
            cities_data = (ga4_res.dig(:data, 'rows') || []).map do |cr|
              city    = cr.dig('dimensionValues', 0, 'value') || '(unknown)'
              country = cr.dig('dimensionValues', 1, 'value') || '(unknown)'
              sess    = (cr.dig('metricValues', 0, 'value') || 0).to_i
              bounce  = ((cr.dig('metricValues', 1, 'value') || 0).to_f * 100).round(1)
              dur     = (cr.dig('metricValues', 2, 'value') || 0).to_f.round
              { city: city, country: country, sessions: sess, bounce_rate: "#{bounce}%", duration: format_duration(dur) }
            end
          end
        end

        if options[:json]
          payload = {
            domain: hostname,
            property: site_url,
            ga4PropertyId: ga4_property_id,
            startDate: res[:start_date],
            endDate: res[:end_date],
            totals: {
              clicks: total_clicks,
              impressions: total_imp,
              ctr: avg_ctr,
              position: avg_pos
            },
            devices: devices_data,
            countries: countries_data,
            snippets: snippets_data,
            topQueries: queries_data,
            topPages: pages_data,
            cities: cities_data
          }
          puts JSON.pretty_generate(payload)
        else
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "#{Color::BOLD}📊 SEARCH PERFORMANCE TOTALS (#{res[:start_date]} to #{res[:end_date]})#{Color::RESET}"
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "  🔵 Total Clicks:       #{Color.c(format_number(total_clicks), Color::GREEN, Color::BOLD)}"
          puts "  🟣 Total Impressions:  #{Color.c(format_number(total_imp), Color::MAGENTA, Color::BOLD)}"
          puts "  🟢 Average CTR:        #{Color.c("#{avg_ctr}%", Color::CYAN, Color::BOLD)}"
          puts "  🟠 Average Position:   #{Color.c(avg_pos.to_s, Color::YELLOW, Color::BOLD)}"
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"

          print_devices_table(devices_data) unless devices_data.empty?
          print_countries_table(countries_data) unless countries_data.empty?
          print_snippets_table(snippets_data)
          print_mini_queries_table(queries_data) unless queries_data.empty?
          print_mini_pages_table(pages_data) unless pages_data.empty?

          if ga4_property_id && !cities_data.empty?
            print_cities_table(cities_data, ga4_property_id)
          elsif !ga4_property_id
            puts "\n#{Color.c("💡 Link GA4 with `gsc connect-ga4` or `gsc config set-ga4 <id>` to see city-level behavioral data & retention.", Color::GRAY)}"
          end
          puts
        end

      when 'devices'
        puts "📱 Fetching device breakdown for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days)...\n" unless options[:json]
        res = api.query_analytics(site_url, days: options[:days], dimensions: ['device'])
        if res[:ok]
          tot_res = api.query_analytics(site_url, days: options[:days], dimensions: [])
          tot_clicks = tot_res.dig(:data, 'rows', 0, 'clicks') || 0
          rows = (res.dig(:data, 'rows') || []).map do |r|
            c = r['clicks'] || 0
            i = r['impressions'] || 0
            ctr = ((r['ctr'] || 0) * 100).round(2)
            pos = (r['position'] || 0).round(1)
            share = tot_clicks > 0 ? "#{(c.to_f / tot_clicks * 100).round(1)}%" : "-"
            { device: r['keys'].first, clicks: c, impressions: i, ctr: ctr, position: pos, share: share }
          end.sort_by { |r| -r[:clicks] }

          if options[:json]
            puts JSON.pretty_generate(rows)
          elsif rows.empty?
            puts Color.c("ℹ️ No device data recorded in the last #{options[:days]} days.", Color::YELLOW)
          else
            print_devices_table(rows)
            puts
            if options[:csv]
              write_csv(options[:csv], %w[Device Clicks Impressions CTR Position Share], rows.map { |r| [r[:device], r[:clicks], r[:impressions], r[:ctr], r[:position], r[:share]] })
              puts Color.c("📁 Exported device breakdown to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Device API Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'countries'
        limit = options[:limit] || 20
        puts "🌍 Fetching top #{limit} countries for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days)...\n" unless options[:json]
        res = api.query_analytics(site_url, days: options[:days], dimensions: ['country'], row_limit: limit)
        if res[:ok]
          rows = (res.dig(:data, 'rows') || []).map do |r|
            {
              country: r['keys'].first,
              clicks: r['clicks'] || 0,
              impressions: r['impressions'] || 0,
              ctr: ((r['ctr'] || 0) * 100).round(2),
              position: (r['position'] || 0).round(1)
            }
          end.sort_by { |r| -r[:clicks] }

          if options[:json]
            puts JSON.pretty_generate(rows)
          elsif rows.empty?
            puts Color.c("ℹ️ No country data recorded in the last #{options[:days]} days.", Color::YELLOW)
          else
            print_countries_table(rows)
            puts
            if options[:csv]
              write_csv(options[:csv], %w[Country Clicks Impressions CTR Position], rows.map { |r| [r[:country], r[:clicks], r[:impressions], r[:ctr], r[:position]] })
              puts Color.c("📁 Exported country breakdown to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Country API Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'snippets', 'appearance', 'search-appearance'
        puts "✨ Fetching search appearance & rich snippets for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days)...\n" unless options[:json]
        res = api.query_analytics(site_url, days: options[:days], dimensions: ['searchAppearance'], row_limit: 20)
        if res[:ok]
          rows = (res.dig(:data, 'rows') || []).map do |r|
            {
              type: r['keys'].first,
              clicks: r['clicks'] || 0,
              impressions: r['impressions'] || 0,
              ctr: ((r['ctr'] || 0) * 100).round(2),
              position: (r['position'] || 0).round(1)
            }
          end.sort_by { |r| -r[:clicks] }

          if options[:json]
            puts JSON.pretty_generate(rows)
          else
            print_snippets_table(rows)
            puts
            if options[:csv]
              write_csv(options[:csv], %w[AppearanceType Clicks Impressions CTR Position], rows.map { |r| [r[:type], r[:clicks], r[:impressions], r[:ctr], r[:position]] })
              puts Color.c("📁 Exported rich snippets to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Appearance API Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'cities'
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({ error: "No GA4 Property ID linked for #{hostname}. Link with `gsc config set-ga4 <id>` or `gsc connect-ga4`." })
          else
            puts Color.c("\n❌ No GA4 Property ID linked for #{hostname}!", Color::RED, Color::BOLD)
            puts "Link your GA4 property ID using:\n  #{Color.c("gsc connect-ga4", Color::GREEN, Color::BOLD)} (interactive wizard)"
            puts "  #{Color.c("gsc config set-ga4 <property_id>", Color::CYAN)} (direct link)\n"
          end
          return
        end

        limit = options[:limit] || 20
        puts "🏙️ Fetching top #{limit} cities for #{Color.c(hostname, Color::CYAN)} [Property #{property_id}] (Past #{options[:days]} days)...\n" unless options[:json]
        res = api.query_ga4_cities(property_id, days: options[:days], limit: limit, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        if res[:ok]
          rows = (res.dig(:data, 'rows') || []).map do |cr|
            city    = cr.dig('dimensionValues', 0, 'value') || '(unknown)'
            country = cr.dig('dimensionValues', 1, 'value') || '(unknown)'
            sess    = (cr.dig('metricValues', 0, 'value') || 0).to_i
            bounce  = ((cr.dig('metricValues', 1, 'value') || 0).to_f * 100).round(1)
            dur     = (cr.dig('metricValues', 2, 'value') || 0).to_f.round
            { city: city, country: country, sessions: sess, bounce_rate: "#{bounce}%", duration: format_duration(dur) }
          end

          if options[:json]
            puts JSON.pretty_generate(rows)
          elsif rows.empty?
            puts Color.c("ℹ️ No city data recorded in the last #{options[:days]} days.", Color::YELLOW)
          else
            print_cities_table(rows, property_id)
            puts
            if options[:csv]
              write_csv(options[:csv], %w[City Country Sessions BounceRate AvgDuration], rows.map { |r| [r[:city], r[:country], r[:sessions], r[:bounce_rate], r[:duration]] })
              puts Color.c("📁 Exported city breakdown to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          handle_ga4_api_error(res, property_id, hostname, options)
        end

      when 'sitemaps-list', 'sitemaps', 's'
        puts "📑 Fetching submitted sitemaps for #{Color.c(site_url, Color::CYAN)}...\n" unless options[:json]
        res = api.list_sitemaps(site_url)
        if options[:json]
          puts JSON.pretty_generate(res[:data] || {})
        elsif res[:ok]
          sitemaps = res.dig(:data, 'sitemap') || []
          if sitemaps.empty?
            puts Color.c("ℹ️ No sitemaps currently submitted in Search Console for this property.", Color::YELLOW)
          else
            puts "#{Color::BOLD}Type         | Last Downloaded | Errors | Warnings | Path#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            sitemaps.each do |sm|
              type    = (sm['type'] || 'sitemap').ljust(12)
              last_dl = sm['lastDownloaded'] ? sm['lastDownloaded'].split('T').first : 'Never     '
              errors  = (sm['errors'] || 0).to_s.ljust(6)
              warns   = (sm['warnings'] || 0).to_s.ljust(8)
              puts "#{type} | #{last_dl}      | #{errors} | #{warns} | #{Color.c(sm['path'], Color::CYAN)}"
            end
          end
          puts
        else
          puts Color.c("❌ Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end

      when 'sitemaps-submit'
        sitemap_url = target || "#{https_origin}/sitemap.xml"
        puts "📤 Submitting sitemap to Google Search Console:\n   #{Color.c(sitemap_url, Color::CYAN)} (Property: #{site_url})\n" unless options[:json]
        res = api.submit_sitemap(site_url, sitemap_url)
        if options[:json]
          puts JSON.pretty_generate({ ok: res[:ok], status: res[:status], sitemap: sitemap_url })
        elsif res[:ok] || res[:status] == 204
          puts Color.c("✅ Success! Sitemap registered with Google Search Console.", Color::GREEN)
        else
          puts Color.c("❌ Failed to submit sitemap (#{res[:status]}): #{res[:data]}", Color::RED)
        end

      when 'sites-list', 'domains'
        puts "🌐 Fetching all Search Console properties accessible by key...\n" unless options[:json]
        res = api.list_sites
        if res[:ok]
          entries = (res.dig(:data, 'siteEntry') || []).sort_by { |s| s['siteUrl'].sub(%r{^https?://}, '').sub(/^sc-domain:/, '') }
          active_dom = Config.default_domain
          mapped = entries.map do |s|
            clean_s_dom = s['siteUrl'].sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')
            is_active = active_dom && (active_dom == clean_s_dom || s['siteUrl'].include?(active_dom))
            ga4_id = Config.ga4_property_id(clean_s_dom)
            s.merge('active' => !!is_active, 'ga4PropertyId' => ga4_id, 'cleanDomain' => clean_s_dom)
          end

          if options[:json]
            puts JSON.pretty_generate(mapped)
          elsif entries.empty?
            puts Color.c("⚠️ No Search Console properties found.", Color::YELLOW)
          else
            puts "#{Color::BOLD} #  | Permission Level | Site Property Identifier             | GA4 Link Status#{Color::RESET}"
            puts "--------------------------------------------------------------------------------------------------"
            mapped.each_with_index do |s, idx|
              num_str = Color.c("[#{idx + 1}]".ljust(4), Color::CYAN, Color::BOLD)
              level = (s['permissionLevel'] || 'Unknown').ljust(17)
              site_str = Color.c(s['siteUrl'].ljust(36), Color::CYAN)
              ga4_str = if s['ga4PropertyId']
                Color.c("[GA4: #{s['ga4PropertyId']}]", Color::MAGENTA, Color::BOLD)
              else
                Color.c("[GA4: Not linked]", Color::GRAY)
              end
              suffix = s['active'] ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""
              puts "#{num_str}| #{level} | #{site_str} | #{ga4_str}#{suffix}"
            end
            puts

            if $stdin.tty? && mapped.any?
              print "Select domain number (1-#{mapped.size}) to switch active, or press Enter to keep current: "
              choice = $stdin.gets&.strip
              if choice && choice =~ /^\d+$/
                choice_num = choice.to_i
                if choice_num >= 1 && choice_num <= mapped.size
                  chosen = mapped[choice_num - 1]
                  clean = Config.set_default_domain(chosen['cleanDomain'])
                  puts "\n" + Color.c("✅ Active default domain set to: #{clean}", Color::GREEN, Color::BOLD)
                  puts Color.c("   Saved to #{Config::CONFIG_FILE}", Color::GRAY)
                  puts "\nNow all commands will automatically target #{Color.c(clean, Color::CYAN)} without needing -d!\n\n"
                else
                  puts Color.c("Invalid selection.", Color::YELLOW)
                end
              end
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'audit', 'a'
        run_comprehensive_audit(api, site_url, hostname, https_origin, options)

      when 'opportunities', 'striking-distance', 'quick-wins', 'o', 'opp'
        min_pos = options[:min_pos] || 7.0
        max_pos = options[:max_pos] || 20.0
        min_imp = options[:min_imp] || 10
        puts "🎯 Finding striking-distance keyword opportunities for #{Color.c(site_url, Color::CYAN)} (Positions #{min_pos}–#{max_pos}, Min #{min_imp} Imp)...\n" unless options[:json]

        res = api.query_analytics(site_url, days: options[:days], dimensions: %w[query page], row_limit: 2500)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          opportunities = []

          raw_rows.each do |r|
            q = r['keys'][0]
            p = r['keys'][1]
            pos = r['position'].round(1)
            imp = r['impressions']
            clicks = r['clicks']
            ctr = (r['ctr'] * 100).round(2)

            next unless pos >= min_pos && pos <= max_pos
            next unless imp >= min_imp

            target_ctr = 12.0
            potential_clicks = [((imp * (target_ctr / 100.0)) - clicks).round, 1].max
            score = (potential_clicks * (1.0 / [pos - 2.0, 1.0].max) * 10.0).round(1)

            opportunities << {
              query: q,
              page: p,
              position: pos,
              impressions: imp,
              clicks: clicks,
              ctr: ctr,
              potentialGain: potential_clicks,
              opportunityScore: score
            }
          end

          opportunities.sort_by! { |o| -o[:opportunityScore] }
          opportunities = opportunities.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(opportunities)
          elsif opportunities.empty?
            puts Color.c("ℹ️ No striking-distance opportunities found with current filters (Min #{min_imp} imp, Pos #{min_pos}–#{max_pos}).", Color::YELLOW)
            puts "💡 Tip: Try lowering --min-imp (e.g. gsc opportunities --min-imp 3) or increasing --days 90."
          else
            puts "#{Color::BOLD}Pos   | Imp    | Clicks | Est. +Clicks | Target Page & Query#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            opportunities.each do |opp|
              pos_str    = opp[:position].to_s.ljust(5)
              imp_str    = opp[:impressions].to_s.ljust(6)
              clicks_str = opp[:clicks].to_s.ljust(6)
              gain_str   = "+#{opp[:potentialGain]}/mo".ljust(12)
              page_short = opp[:page].sub(%r{^https?://[^/]+}, '')
              page_short = '/' if page_short.empty?

              puts "#{Color.c(pos_str, Color::YELLOW)} | #{imp_str} | #{clicks_str} | #{Color.c(gain_str, Color::GREEN, Color::BOLD)} | #{Color.c(page_short, Color::CYAN)}"
              puts "      |        |        |              | ↳ #{Color::BOLD}\"#{opp[:query]}\"#{Color::RESET}"
            end
            puts "\n#{Color.c("Total Opportunities: #{opportunities.size}", Color::GRAY)}"
            puts "💡 #{Color::BOLD}Optimization Playbook:#{Color::RESET} Add an H2 subheading and 1-2 paragraphs directly targeting these queries on their respective pages to push them onto Page 1.\n\n"

            if options[:csv]
              csv_data = opportunities.map { |o| [o[:query], o[:page], o[:position], o[:impressions], o[:clicks], o[:ctr], o[:potentialGain], o[:opportunityScore]] }
              write_csv(options[:csv], %w[Query Page Position Impressions Clicks CTR PotentialGain Score], csv_data)
              puts Color.c("📁 Exported opportunities to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'underperformers', 'ctr-underperformers', 'ctr-gaps', 'u'
        min_imp = options[:min_imp] || 15
        puts "⚡ Scanning for CTR Underperformers in Top 10 for #{Color.c(site_url, Color::CYAN)} (Min #{min_imp} Imp)...\n" unless options[:json]

        res = api.query_analytics(site_url, days: options[:days], dimensions: %w[query page], row_limit: 2500)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          underperformers = []

          raw_rows.each do |r|
            q = r['keys'][0]
            p = r['keys'][1]
            pos = r['position'].round(1)
            imp = r['impressions']
            clicks = r['clicks']
            ctr = (r['ctr'] * 100).round(2)

            next unless pos <= 10.0
            next unless imp >= min_imp

            expected = expected_ctr_for(pos)
            gap = expected - ctr
            next unless gap >= 2.0 && ctr < (expected * 0.70)

            lost_clicks = [((imp * (gap / 100.0))).round, 1].max

            underperformers << {
              query: q,
              page: p,
              position: pos,
              impressions: imp,
              clicks: clicks,
              actualCtr: ctr,
              expectedCtr: expected,
              lostClicks: lost_clicks
            }
          end

          underperformers.sort_by! { |u| -u[:lostClicks] }
          underperformers = underperformers.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(underperformers)
          elsif underperformers.empty?
            puts Color.c("✅ No significant CTR underperformers detected in Top 10! Your titles are converting well.", Color::GREEN)
          else
            puts "#{Color::BOLD}Pos   | Imp    | CTR    | Expected | Lost Clicks | Query & Page#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            underperformers.each do |item|
              pos_str    = item[:position].to_s.ljust(5)
              imp_str    = item[:impressions].to_s.ljust(6)
              ctr_str    = "#{item[:actualCtr]}%".ljust(6)
              exp_str    = "~#{item[:expectedCtr]}%".ljust(8)
              lost_str   = "~#{item[:lostClicks]} clicks".ljust(11)
              page_short = item[:page].sub(%r{^https?://[^/]+}, '')
              page_short = '/' if page_short.empty?

              puts "#{Color.c(pos_str, Color::GREEN)} | #{imp_str} | #{Color.c(ctr_str, Color::RED)} | #{exp_str} | #{Color.c(lost_str, Color::YELLOW, Color::BOLD)} | #{Color.c(page_short, Color::CYAN)}"
              puts "      |        |        |          |             | ↳ #{Color::BOLD}\"#{item[:query]}\"#{Color::RESET}"
            end
            puts "\n#{Color.c("Total Underperformers: #{underperformers.size}", Color::GRAY)}"
            puts "💡 #{Color::BOLD}Quick Win Playbook:#{Color::RESET} You already have top rankings! Rewrite the <title> tag and meta description with numbers, brackets [2026], or clear benefit hooks to recover lost clicks immediately.\n\n"

            if options[:csv]
              csv_data = underperformers.map { |u| [u[:query], u[:page], u[:position], u[:impressions], u[:clicks], u[:actualCtr], u[:expectedCtr], u[:lostClicks]] }
              write_csv(options[:csv], %w[Query Page Position Impressions Clicks ActualCTR ExpectedCTR LostClicks], csv_data)
              puts Color.c("📁 Exported CTR underperformers to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'cannibalization', 'conflicts', 'c'
        puts "⚔️ Analyzing keyword cannibalization conflicts for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days)...\n" unless options[:json]

        res = api.query_analytics(site_url, days: options[:days], dimensions: %w[query page], row_limit: 5000)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          grouped = Hash.new { |h, k| h[k] = [] }
          raw_rows.each do |r|
            grouped[r['keys'][0]] << {
              page: r['keys'][1],
              clicks: r['clicks'],
              impressions: r['impressions'],
              position: r['position'].round(1)
            }
          end

          conflicts = []
          grouped.each do |query, pages|
            next if pages.size < 2

            total_imp = pages.sum { |p| p[:impressions] }
            next if total_imp < (options[:min_imp] || 10)

            sorted_pages = pages.sort_by { |p| -p[:impressions] }
            secondary = sorted_pages[1]

            sec_ratio = secondary[:impressions].to_f / total_imp
            next unless sec_ratio >= 0.15

            conflicts << {
              query: query,
              totalImpressions: total_imp,
              totalClicks: pages.sum { |p| p[:clicks] },
              competingPagesCount: pages.size,
              pages: sorted_pages.map do |p|
                p.merge(impressionShare: "#{( (p[:impressions].to_f / total_imp) * 100 ).round(1)}%")
              end
            }
          end

          conflicts.sort_by! { |c| -c[:totalImpressions] }
          conflicts = conflicts.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(conflicts)
          elsif conflicts.empty?
            puts Color.c("✅ Zero keyword cannibalization detected! Each query has a distinct ranking page.", Color::GREEN)
          else
            puts "#{Color::BOLD}⚠️  #{conflicts.size} Keyword Cannibalization Conflicts Found:#{Color::RESET}\n\n"
            conflicts.each_with_index do |conf, i|
              puts "#{Color::BOLD}#{i + 1}. \"#{conf[:query]}\"#{Color::RESET} (Total Imp: #{Color.c(conf[:totalImpressions].to_s, Color::CYAN)}, Clicks: #{conf[:totalClicks]})"
              conf[:pages].each do |p|
                share_str = p[:impressionShare].ljust(6)
                imp_str   = "#{p[:impressions]} imp".ljust(9)
                pos_str   = "Pos #{p[:position]}".ljust(9)
                page_short = p[:page].sub(%r{^https?://[^/]+}, '')
                page_short = '/' if page_short.empty?
                puts "   • #{Color.c(share_str, Color::YELLOW)} | #{imp_str} | #{pos_str} | #{page_short}"
              end
              primary_url = conf[:pages][0][:page].sub(%r{^https?://[^/]+}, '')
              puts "   👉 #{Color.c("Remedy:", Color::BOLD)} Set canonical pointing to #{Color.c(primary_url, Color::CYAN)} or 301 redirect secondary pages.\n\n"
            end

            if options[:csv]
              csv_rows = []
              conflicts.each do |c|
                c[:pages].each do |p|
                  csv_rows << [c[:query], c[:totalImpressions], p[:page], p[:impressionShare], p[:impressions], p[:clicks], p[:position]]
                end
              end
              write_csv(options[:csv], %w[Query TotalImpressions Page ImpressionShare PageImpressions PageClicks Position], csv_rows)
              puts Color.c("📁 Exported cannibalization report to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'decay', 'trends', 'd'
        window_days = options[:compare] || 28
        puts "📉 Analyzing ranking & traffic decay for #{Color.c(site_url, Color::CYAN)} (Comparing Past #{window_days}d vs Prior #{window_days}d)...\n" unless options[:json]

        end_current = Date.today - 2
        start_current = end_current - window_days
        end_prior = start_current
        start_prior = end_prior - window_days

        curr_res = api.query_analytics(site_url, start_date: start_current.iso8601, end_date: end_current.iso8601, dimensions: ['query'], row_limit: 2500)
        prior_res = api.query_analytics(site_url, start_date: start_prior.iso8601, end_date: end_prior.iso8601, dimensions: ['query'], row_limit: 2500)

        if curr_res[:ok] && prior_res[:ok]
          curr_map = {}
          (curr_res.dig(:data, 'rows') || []).each do |r|
            curr_map[r['keys'][0]] = {
              clicks: r['clicks'],
              impressions: r['impressions'],
              position: r['position'].round(1)
            }
          end

          prior_map = {}
          (prior_res.dig(:data, 'rows') || []).each do |r|
            prior_map[r['keys'][0]] = {
              clicks: r['clicks'],
              impressions: r['impressions'],
              position: r['position'].round(1)
            }
          end

          all_queries = (curr_map.keys + prior_map.keys).uniq
          comparison = []

          all_queries.each do |q|
            c_data = curr_map[q] || { clicks: 0, impressions: 0, position: 999.0 }
            p_data = prior_map[q] || { clicks: 0, impressions: 0, position: 999.0 }

            c_clicks = c_data[:clicks]
            p_clicks = p_data[:clicks]
            c_imp    = c_data[:impressions]
            p_imp    = p_data[:impressions]
            c_pos    = c_data[:position]
            p_pos    = p_data[:position]

            next if c_imp < 3 && p_imp < 3

            clicks_diff = c_clicks - p_clicks
            imp_diff    = c_imp - p_imp
            pos_diff    = (p_pos == 999.0 || c_pos == 999.0) ? 0.0 : (p_pos - c_pos).round(1)

            status = if p_imp.zero? && c_imp.positive?
              :new
            elsif c_imp.zero? && p_imp.positive?
              :lost
            elsif pos_diff <= -2.5 || (c_imp < p_imp * 0.65 && p_imp >= 10)
              :decaying
            elsif pos_diff >= 2.5 || (c_imp > p_imp * 1.35 && c_imp >= 10)
              :surging
            else
              :stable
            end

            comparison << {
              query: q,
              status: status,
              currentClicks: c_clicks,
              priorClicks: p_clicks,
              clicksDiff: clicks_diff,
              currentImp: c_imp,
              priorImp: p_imp,
              impDiff: imp_diff,
              currentPos: (c_pos == 999.0 ? nil : c_pos),
              priorPos: (p_pos == 999.0 ? nil : p_pos),
              posDiff: pos_diff
            }
          end

          decaying = comparison.select { |c| c[:status] == :decaying }.sort_by { |c| c[:posDiff] }
          surging  = comparison.select { |c| c[:status] == :surging }.sort_by { |c| -c[:posDiff] }
          new_q    = comparison.select { |c| c[:status] == :new }.sort_by { |c| -c[:currentImp] }
          lost_q   = comparison.select { |c| c[:status] == :lost }.sort_by { |c| -c[:priorImp] }

          summary = {
            windowDays: window_days,
            currentPeriod: "#{start_current} to #{end_current}",
            priorPeriod: "#{start_prior} to #{end_prior}",
            decayingCount: decaying.size,
            surgingCount: surging.size,
            newCount: new_q.size,
            lostCount: lost_q.size,
            decaying: decaying.first(options[:limit]),
            surging: surging.first(options[:limit]),
            newDiscoveries: new_q.first(options[:limit]),
            lostKeywords: lost_q.first(options[:limit])
          }

          if options[:json]
            puts JSON.pretty_generate(summary)
          else
            puts "#{Color::BOLD}📊 SEARCH CONSOLE TRENDS SUMMARY (#{window_days}-Day Comparison)#{Color::RESET}"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
            puts "  🔻 Decaying Keywords:   #{Color.c(decaying.size.to_s, Color::RED, Color::BOLD)}"
            puts "  🚀 Surging Keywords:     #{Color.c(surging.size.to_s, Color::GREEN, Color::BOLD)}"
            puts "  ✨ New Breakout Queries: #{Color.c(new_q.size.to_s, Color::CYAN, Color::BOLD)}"
            puts "  💀 Lost Keywords:        #{Color.c(lost_q.size.to_s, Color::GRAY, Color::BOLD)}"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"

            if decaying.any?
              puts "#{Color::BOLD}🔻 TOP DECAYING KEYWORDS (Rank or Traffic Loss):#{Color::RESET}"
              puts "Prior Pos | Curr Pos | Drop   | Prior Imp | Curr Imp | Query"
              puts "--------------------------------------------------------------------------------"
              decaying.first(options[:limit]).each do |d|
                p_pos = d[:priorPos] ? d[:priorPos].to_s.ljust(9) : '-'.ljust(9)
                c_pos = d[:currentPos] ? d[:currentPos].to_s.ljust(8) : 'Off P2'.ljust(8)
                drop  = Color.c("#{d[:posDiff]}".ljust(6), Color::RED)
                p_imp = d[:priorImp].to_s.ljust(9)
                c_imp = d[:currentImp].to_s.ljust(8)
                puts "#{p_pos} | #{c_pos} | #{drop} | #{p_imp} | #{c_imp} | #{Color::BOLD}\"#{d[:query]}\"#{Color::RESET}"
              end
              puts
            end

            if surging.any?
              puts "#{Color::BOLD}🚀 TOP SURGING KEYWORDS (Rank or Traffic Gain):#{Color::RESET}"
              puts "Prior Pos | Curr Pos | Gain   | Prior Imp | Curr Imp | Query"
              puts "--------------------------------------------------------------------------------"
              surging.first(options[:limit]).each do |s|
                p_pos = s[:priorPos] ? s[:priorPos].to_s.ljust(9) : '-'.ljust(9)
                c_pos = s[:currentPos] ? s[:currentPos].to_s.ljust(8) : '-'.ljust(8)
                gain  = Color.c("+#{s[:posDiff]}".ljust(6), Color::GREEN)
                p_imp = s[:priorImp].to_s.ljust(9)
                c_imp = s[:currentImp].to_s.ljust(8)
                puts "#{p_pos} | #{c_pos} | #{gain} | #{p_imp} | #{c_imp} | #{Color::BOLD}\"#{s[:query]}\"#{Color::RESET}"
              end
              puts
            end

            if options[:csv]
              csv_rows = comparison.map do |c|
                [c[:query], c[:status], c[:priorPos], c[:currentPos], c[:posDiff], c[:priorImp], c[:currentImp], c[:impDiff], c[:priorClicks], c[:currentClicks], c[:clicksDiff]]
              end
              write_csv(options[:csv], %w[Query Status PriorPos CurrentPos PosDiff PriorImp CurrentImp ImpDiff PriorClicks CurrentClicks ClicksDiff], csv_rows)
              puts Color.c("📁 Exported decay & trend analysis to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          err = curr_res[:data] || prior_res[:data]
          if options[:json]
            puts JSON.pretty_generate({ error: err })
          else
            puts Color.c("❌ Search Analytics Error: #{err}", Color::RED)
          end
        end

      when 'zombies', 'bloat', 'z'
        sitemap_target = target
        puts "🧟 Scanning for Zombie Pages (Index Bloat) against 90-day search traffic...\n" unless options[:json]

        urls = SitemapLoader.resolve_urls(sitemap_target, https_origin)
        if urls.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'No URLs found to audit in sitemap.' })
          else
            puts Color.c("❌ Error: No URLs found in sitemap #{sitemap_target || 'public/sitemap.xml'}", Color::RED)
          end
          exit 1
        end

        puts "🔍 Loaded #{Color.c(urls.size.to_s, Color::CYAN)} URLs from sitemap. Querying 90-day GSC impressions..." unless options[:json]
        res = api.query_analytics(site_url, days: 90, dimensions: ['page'], row_limit: 5000)

        if res[:ok]
          active_pages = {}
          (res.dig(:data, 'rows') || []).each do |r|
            clean_page = r['keys'][0].downcase.sub(%r{/$}, '')
            active_pages[clean_page] = {
              clicks: r['clicks'],
              impressions: r['impressions'],
              position: r['position'].round(1)
            }
          end

          zombies = []
          active  = []

          urls.each do |url|
            clean_u = url.downcase.sub(%r{/$}, '')
            if active_pages.key?(clean_u)
              active << active_pages[clean_u].merge(url: url)
            else
              zombies << url
            end
          end

          zombie_ratio = ((zombies.size.to_f / urls.size) * 100).round(1)
          payload = {
            totalSitemapUrls: urls.size,
            activeCount: active.size,
            zombieCount: zombies.size,
            zombiePercentage: "#{zombie_ratio}%",
            zombieUrls: zombies.first(options[:limit])
          }

          if options[:json]
            puts JSON.pretty_generate(payload)
          else
            puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
            puts "#{Color::BOLD}🧟 ZOMBIE PAGE / INDEX BLOAT AUDIT (#{urls.size} Sitemap URLs)#{Color::RESET}"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
            puts "  ✅ Active URLs (Receiving Impressions): #{Color.c(active.size.to_s, Color::GREEN, Color::BOLD)} (#{'%.1f' % (100 - zombie_ratio)}%)"
            puts "  🧟 Zombie URLs (0 Impressions in 90d):   #{Color.c(zombies.size.to_s, Color::RED, Color::BOLD)} (#{zombie_ratio}%)"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"

            if zombies.any?
              puts "#{Color::BOLD}Sample Zombie URLs (Wasted Crawl Budget):#{Color::RESET}"
              zombies.first(options[:limit]).each do |zu|
                short_u = zu.sub(%r{^https?://[^/]+}, '')
                puts "  • #{Color.c(short_u, Color::RED)}"
              end
              puts "\n💡 #{Color::BOLD}Action Plan:#{Color::RESET} If these pages are thin or duplicates, add 'noindex' or 301 redirect them to preserve crawl budget for core revenue pages.\n\n"
            end

            if options[:csv]
              csv_rows = urls.map { |u| [u, active_pages.key?(u.downcase.sub(%r{/$}, '')) ? 'ACTIVE' : 'ZOMBIE'] }
              write_csv(options[:csv], %w[URL Status], csv_rows)
              puts Color.c("📁 Exported zombie report to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end

      when 'ga4', 'bounce'
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "No GA4 property linked for domain '#{hostname}'. Run 'gsc config set-ga4 <property_id> -d #{hostname}' or pass '--property <id>'."
            })
          else
            puts "\n#{Color.c("⚠️  No GA4 Property ID linked for domain: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "\nGoogle Analytics 4 is not yet linked for #{Color.c(hostname, Color::CYAN)}."
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify a property ID directly:"
            puts "   #{Color.c("gsc ga4 --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        traffic_label = options[:organic] ? "Organic Search Only" : "All Traffic"
        puts "📈 Fetching GA4 landing page behavioral metrics for #{Color.c(hostname, Color::CYAN)} [Property #{property_id}] (#{traffic_label}, Past #{options[:days]} days)..." unless options[:json]

        res = api.query_ga4_report(property_id, days: options[:days], limit: options[:limit] * 3, organic_only: options[:organic], hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          if raw_rows.empty?
            if options[:json]
              puts JSON.pretty_generate([])
            else
              puts Color.c("⚠️ No landing page behavioral data found in GA4 for this date range.", Color::YELLOW)
            end
            return
          end

          pages_map = {}
          raw_rows.each do |row|
            path_val = row.dig('dimensionValues', 0, 'value') || '/'
            norm = normalize_path(path_val)

            sessions = row.dig('metricValues', 0, 'value').to_i
            users    = row.dig('metricValues', 1, 'value').to_i
            eng_rate = row.dig('metricValues', 2, 'value').to_f
            bounce   = row.dig('metricValues', 3, 'value').to_f
            duration = row.dig('metricValues', 4, 'value').to_f
            views    = row.dig('metricValues', 5, 'value').to_i

            pages_map[norm] ||= { path: norm, sessions: 0, users: 0, views: 0, total_duration_secs: 0.0, weighted_eng: 0.0, weighted_bounce: 0.0 }
            entry = pages_map[norm]
            entry[:sessions] += sessions
            entry[:users] += users
            entry[:views] += views
            entry[:total_duration_secs] += (duration * sessions)
            entry[:weighted_eng] += (eng_rate * sessions)
            entry[:weighted_bounce] += (bounce * sessions)
          end

          data = pages_map.values.map do |e|
            s = e[:sessions]
            avg_eng = s.positive? ? (e[:weighted_eng] / s) * 100.0 : 0.0
            avg_bounce = s.positive? ? (e[:weighted_bounce] / s) * 100.0 : 0.0
            avg_dur = s.positive? ? (e[:total_duration_secs] / s) : 0.0

            {
              path: e[:path],
              sessions: s,
              users: e[:users],
              views: e[:views],
              engagement_rate: avg_eng.round(1),
              bounce_rate: avg_bounce.round(1),
              duration_seconds: avg_dur.round(1),
              duration_formatted: format_duration(avg_dur)
            }
          end

          sort_key = case options[:sort]&.to_s&.downcase
          when 'bounce' then :bounce_rate
          when 'eng', 'engagement' then :engagement_rate
          when 'dur', 'duration', 'time' then :duration_seconds
          when 'views', 'pageviews' then :views
          when 'users' then :users
          else :sessions
          end

          is_asc = (options[:order] == 'asc')
          data.sort_by! { |d| d[sort_key] || 0 }
          data.reverse! unless is_asc

          display_rows = data.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(display_rows)
          else
            puts "\n#{Color::BOLD}Sessions | Bounce | Eng Rate | Avg Time | Views | Landing Page Path#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            display_rows.each do |r|
              s_col = r[:sessions].to_s.ljust(8)

              b_pct = "#{r[:bounce_rate]}%"
              b_col = if r[:bounce_rate] >= 70.0
                Color.c(b_pct.ljust(6), Color::RED, Color::BOLD)
              elsif r[:bounce_rate] <= 40.0
                Color.c(b_pct.ljust(6), Color::GREEN)
              else
                b_pct.ljust(6)
              end

              e_col = "#{r[:engagement_rate]}%".ljust(8)
              d_col = r[:duration_formatted].ljust(8)
              v_col = r[:views].to_s.ljust(5)
              p_col = Color.c(r[:path], Color::CYAN)

              puts "#{s_col} | #{b_col} | #{e_col} | #{d_col} | #{v_col} | #{p_col}"
            end

            puts "\nTotal Landing Pages: #{data.size} (Showing #{display_rows.size})\n"
          end

          if options[:csv]
            csv_rows = display_rows.map do |r|
              [r[:path], r[:sessions], r[:users], "#{r[:bounce_rate]}%", "#{r[:engagement_rate]}%", r[:duration_seconds], r[:views]]
            end
            write_csv(options[:csv], %w[Path Sessions ActiveUsers BounceRate EngagementRate DurationSeconds PageViews], csv_rows)
            puts Color.c("📁 Exported GA4 report to #{options[:csv]}", Color::CYAN) unless options[:json]
          end
        else
          handle_ga4_api_error(res, property_id, hostname, options)
        end

      when 'correlation', 'engagement'
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Correlation requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Correlation requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "\nSearch Console measures #{Color::BOLD}Pre-Click SERP rankings#{Color::RESET}, while GA4 measures #{Color::BOLD}Post-Click on-site behavior#{Color::RESET}."
            puts "To correlate them, link your GA4 Property ID to this domain:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc correlation --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        traffic_mode = options[:organic] ? "Organic Search Only" : "All Traffic"
        puts "🔗 Correlating Search Console Rankings with GA4 On-Site Behavior for #{Color.c(hostname, Color::CYAN)}..." unless options[:json]
        puts "   GSC: #{Color.c(site_url, Color::CYAN)} | GA4 Property: #{Color.c(property_id, Color::MAGENTA)} (#{traffic_mode}, #{options[:days]}d)\n" unless options[:json]

        # 1. Fetch GSC Page Rankings
        gsc_res = api.query_analytics(site_url, days: options[:days], dimensions: ['page'], row_limit: 250)
        unless gsc_res[:ok]
          if options[:json]
            puts JSON.pretty_generate({ error: "GSC Error: #{gsc_res[:data]}" })
          else
            puts Color.c("❌ Search Console Error (#{gsc_res[:status]}): #{gsc_res[:data]}", Color::RED)
          end
          return
        end

        # 2. Fetch GA4 Behavioral Report
        ga4_res = api.query_ga4_report(property_id, days: options[:days], limit: 250, organic_only: options[:organic], hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        unless ga4_res[:ok]
          handle_ga4_api_error(ga4_res, property_id, hostname, options)
          return
        end

        gsc_rows = gsc_res.dig(:data, 'rows') || []
        ga4_rows = ga4_res.dig(:data, 'rows') || []

        # Index GA4 pages by normalized path
        ga4_index = {}
        ga4_rows.each do |r|
          path_val = r.dig('dimensionValues', 0, 'value') || '/'
          norm = normalize_path(path_val)

          sessions = r.dig('metricValues', 0, 'value').to_i
          eng_rate = r.dig('metricValues', 2, 'value').to_f
          bounce   = r.dig('metricValues', 3, 'value').to_f
          dur      = r.dig('metricValues', 4, 'value').to_f
          views    = r.dig('metricValues', 5, 'value').to_i

          ga4_index[norm] ||= { sessions: 0, views: 0, total_dur: 0.0, weighted_eng: 0.0, weighted_bounce: 0.0 }
          e = ga4_index[norm]
          e[:sessions] += sessions
          e[:views] += views
          e[:total_dur] += (dur * sessions)
          e[:weighted_eng] += (eng_rate * sessions)
          e[:weighted_bounce] += (bounce * sessions)
        end

        merged = []
        gsc_seen = {}

        gsc_rows.each do |row|
          full_url = row['keys'][0]
          norm = normalize_path(full_url)
          gsc_seen[norm] = true

          clicks = row['clicks'].to_i
          imp    = row['impressions'].to_i
          pos    = row['position'].to_f.round(1)
          ctr    = (row['ctr'].to_f * 100.0).round(1)

          ga4_data = ga4_index[norm]
          if ga4_data
            s = ga4_data[:sessions]
            b_rate = s.positive? ? (ga4_data[:weighted_bounce] / s) * 100.0 : 0.0
            e_rate = s.positive? ? (ga4_data[:weighted_eng] / s) * 100.0 : 0.0
            dur    = s.positive? ? (ga4_data[:total_dur] / s) : 0.0
          else
            s = 0
            b_rate = 0.0
            e_rate = 0.0
            dur = 0.0
          end

          diagnosis = if clicks >= 10 && dur >= 90.0
            '🛠️ ENGAGED TOOL'
          elsif clicks >= 10 && b_rate >= 70.0 && dur < 45.0
            '🚨 HIGH BOUNCE'
          elsif pos >= 7.0 && (dur >= 60.0 || (s >= 10 && b_rate <= 35.0))
            '⭐ HIDDEN GEM'
          elsif clicks >= 15 && s < 5
            '⚠️ TRACKING GAP'
          elsif pos <= 5.0 && ctr >= 5.0 && b_rate <= 50.0 && s >= 10
            '💎 WINNER'
          elsif s.zero? && clicks.zero?
            '💤 DORMANT'
          else
            'HEALTHY'
          end

          merged << {
            path: norm,
            url: full_url,
            clicks: clicks,
            impressions: imp,
            position: pos,
            ctr: ctr,
            sessions: s,
            bounce_rate: b_rate.round(1),
            engagement_rate: e_rate.round(1),
            duration_seconds: dur.round(1),
            duration_formatted: format_duration(dur),
            diagnosis: diagnosis
          }
        end

        ga4_index.each do |norm, e|
          next if gsc_seen[norm]
          s = e[:sessions]
          b_rate = s.positive? ? (e[:weighted_bounce] / s) * 100.0 : 0.0
          e_rate = s.positive? ? (e[:weighted_eng] / s) * 100.0 : 0.0
          dur    = s.positive? ? (e[:total_dur] / s) : 0.0

          merged << {
            path: norm,
            url: "https://#{hostname}#{norm}",
            clicks: 0,
            impressions: 0,
            position: 99.0,
            ctr: 0.0,
            sessions: s,
            bounce_rate: b_rate.round(1),
            engagement_rate: e_rate.round(1),
            duration_seconds: dur.round(1),
            duration_formatted: format_duration(dur),
            diagnosis: 'DIRECT/REFERRAL'
          }
        end

        merged.sort_by! { |m| [m[:diagnosis] == '🚨 HIGH BOUNCE' ? 0 : 1, -m[:clicks], -m[:sessions]] }
        display_rows = merged.first(options[:limit])

        if options[:json]
          puts JSON.pretty_generate(display_rows)
        else
          puts "#{Color::BOLD}GSC Clicks | GSC Pos | GA4 Sess | Bounce | Avg Time | Insight               | Page Path#{Color::RESET}"
          puts "---------------------------------------------------------------------------------------------------------"
          display_rows.each do |r|
            c_col = r[:clicks].to_s.ljust(10)
            p_col = r[:position].to_s.ljust(7)
            s_col = r[:sessions].to_s.ljust(8)

            b_pct = "#{r[:bounce_rate]}%"
            b_col = if r[:bounce_rate] >= 70.0 && r[:sessions] > 0
              Color.c(b_pct.ljust(6), Color::RED, Color::BOLD)
            elsif r[:bounce_rate] <= 40.0 && r[:sessions] > 0
              Color.c(b_pct.ljust(6), Color::GREEN)
            else
              b_pct.ljust(6)
            end

            t_col = r[:duration_formatted].ljust(8)

            diag_str = case r[:diagnosis]
            when '🚨 HIGH BOUNCE' then Color.c('🚨 HIGH BOUNCE'.ljust(21), Color::RED, Color::BOLD)
            when '🛠️ ENGAGED TOOL' then Color.c('🛠️ ENGAGED TOOL'.ljust(21), Color::CYAN, Color::BOLD)
            when '⭐ HIDDEN GEM' then Color.c('⭐ HIDDEN GEM'.ljust(21), Color::YELLOW, Color::BOLD)
            when '⚠️ TRACKING GAP' then Color.c('⚠️ TRACKING GAP'.ljust(21), Color::YELLOW)
            when '💎 WINNER' then Color.c('💎 WINNER'.ljust(21), Color::GREEN, Color::BOLD)
            else Color.c(r[:diagnosis].ljust(21), Color::GRAY)
            end

            path_col = Color.c(r[:path], Color::CYAN)

            puts "#{c_col} | #{p_col} | #{s_col} | #{b_col} | #{t_col} | #{diag_str} | #{path_col}"
          end

          high_bounce = merged.select { |m| m[:diagnosis] == '🚨 HIGH BOUNCE' }
          gems        = merged.select { |m| m[:diagnosis] == '⭐ HIDDEN GEM' }
          tools       = merged.select { |m| m[:diagnosis] == '🛠️ ENGAGED TOOL' }

          if tools.any?
            puts "\n💡 #{Color::BOLD}Engaged Tool / Utility Action Plan:#{Color::RESET} #{tools.size} interactive pages show exceptional time on page (>90s). Since users get their answer and leave, add embedded CTAs, related tools, or app trials to convert these active users."
          end
          if high_bounce.any?
            puts "💡 #{Color::BOLD}High Bounce Action Plan:#{Color::RESET} #{high_bounce.size} pages receive search clicks but abandon quickly (<45s with >70% bounce). Check for search intent mismatch (e.g. consumer searches landing on B2B features) or optimize above-the-fold content."
          end
          if gems.any?
            puts "💡 #{Color::BOLD}Hidden Gem Action Plan:#{Color::RESET} #{gems.size} pages show exceptional visitor stickiness despite lower rankings. Build internal links from your homepage to push them into the Top 3 on Google."
          end
          puts
        end

        if options[:csv]
          csv_rows = display_rows.map do |r|
            [r[:path], r[:url], r[:clicks], r[:impressions], r[:position], "#{r[:ctr]}%", r[:sessions], "#{r[:bounce_rate]}%", "#{r[:engagement_rate]}%", r[:duration_seconds], r[:diagnosis]]
          end
          write_csv(options[:csv], %w[Path URL GSCClicks GSCImpressions GSCPosition GSCCTR GA4Sessions GA4BounceRate GA4EngagementRate GA4Duration Diagnosis], csv_rows)
          puts Color.c("📁 Exported correlation report to #{options[:csv]}", Color::CYAN) unless options[:json]
        end

      when 'ga4-properties', 'ga4-list'
        puts "🔍 Discovering Google Analytics 4 properties accessible by service account...\n" unless options[:json]
        res = api.list_ga4_summaries
        if res[:ok]
          summaries = res.dig(:data, 'accountSummaries') || []
          properties = []
          summaries.each do |acc|
            acc_name = acc['displayName'] || acc['account']
            (acc['propertySummaries'] || []).each do |prop|
              prop_id = prop['property'].sub(%r{^properties/}, '')
              prop_name = prop['displayName']
              properties << {
                propertyId: prop_id,
                displayName: prop_name,
                accountName: acc_name,
                fullResource: prop['property']
              }
            end
          end

          linked_prop = Config.ga4_property_id(hostname)

          if options[:json]
            puts JSON.pretty_generate(properties)
          elsif properties.empty?
            puts Color.c("⚠️ No GA4 properties found accessible by this service account.", Color::YELLOW)
            puts "\n#{Color::BOLD}To grant access:#{Color::RESET}"
            puts "1. Go to: https://analytics.google.com/"
            puts "2. In Admin > Property Access Management, add your service account email with Viewer role."
          else
            puts "#{Color::BOLD}Property ID  | GA4 Property Name           | Account Name#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            properties.each do |p|
              id_str = Color.c(p[:propertyId].ljust(12), Color::MAGENTA, Color::BOLD)
              name_str = p[:displayName].ljust(27)
              acc_str  = Color.c(p[:accountName], Color::GRAY)

              is_linked = (p[:propertyId] == linked_prop)
              matches_dom = p[:displayName].downcase.include?(hostname.downcase.sub(/\..*$/, ''))

              tag = if is_linked
                " #{Color.c('👈 [LINKED to ' + hostname + ']', Color::GREEN, Color::BOLD)}"
              elsif matches_dom
                " #{Color.c('👈 [Recommended for ' + hostname + ']', Color::CYAN)}"
              else
                ""
              end

              puts "#{id_str} | #{name_str} | #{acc_str}#{tag}"
            end

            puts "\nTo link a property to #{Color.c(hostname, Color::CYAN)}:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}\n\n"
          end
        else
          handle_ga4_api_error(res, nil, hostname, options)
        end

      when 'realtime', 'live', 'r'
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Realtime monitoring requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Realtime monitoring requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc realtime --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        interval = options[:watch] ? [options[:watch], 3].max : nil
        title_map = api.query_ga4_title_map(property_id, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])

        begin
          loop do
            print "\e[H\e[2J" if interval && !options[:json]

            res = api.query_ga4_realtime(property_id, limit: options[:limit] || 25)
            if res[:ok]
              data = res[:data] || {}
              reported_total = data.dig('totals', 0, 'metricValues', 0, 'value')&.to_i
              raw_rows = data['rows'] || []

              page_counts = Hash.new(0)
              country_counts = Hash.new(0)
              breakdown = []

              raw_rows.each do |r|
                page = r.dig('dimensionValues', 0, 'value')
                page = '/' if page.nil? || page.strip.empty?
                country = r.dig('dimensionValues', 1, 'value')
                country = 'Unknown' if country.nil? || country.strip.empty?
                active = r.dig('metricValues', 0, 'value').to_i

                # Resolve URL path from page title
                path = if page.start_with?('/')
                         page
                       elsif title_map[page]
                         title_map[page]
                       elsif page =~ %r{/(?:[a-zA-Z0-9_\-\./]+)}
                         page[%r{/(?:[a-zA-Z0-9_\-\./]+)}]
                       else
                         match = title_map.find { |t, _| t.downcase.include?(page.downcase) || page.downcase.include?(t.downcase) }
                         match ? match[1] : '-'
                       end

                display_key = path.start_with?('/') ? path : page
                page_counts[display_key] += active
                country_counts[country] += active
                breakdown << { path: path, page: page, country: country, active_users: active }
              end

              row_max = raw_rows.map { |r| r.dig('metricValues', 0, 'value').to_i }.max || 0
              page_max = page_counts.values.max || 0
              total_active = reported_total || [row_max, page_max].max || 0
              if total_active.zero? && raw_rows.any?
                total_active = [row_max, page_max, 1].max
              end

              payload = {
                domain: hostname,
                property_id: property_id,
                total_active_users: total_active,
                timestamp: Time.now.iso8601,
                top_pages: page_counts.sort_by { |_k, v| -v }.first(options[:limit] || 15).map { |k, v| { page: k, active_users: v } },
                top_countries: country_counts.sort_by { |_k, v| -v }.first(10).map { |k, v| { country: k, active_users: v } },
                active_streams: breakdown
              }

              if options[:json]
                puts JSON.pretty_generate(payload)
              else
                header_text = "⚡ GA4 REALTIME VISITOR MONITOR: #{hostname} [Property #{property_id}]"
                time_str = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                puts "#{Color::BOLD}#{Color.c(header_text, Color::CYAN)} (#{time_str})#{Color::RESET}"
                puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}"

                count_color = total_active > 0 ? Color::GREEN : Color::YELLOW
                puts "  👥 Active Users (Last 30 Mins): #{Color.c(total_active.to_s, count_color, Color::BOLD)}"
                puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}\n"

                if total_active.zero? && raw_rows.empty?
                  puts Color.c("  (No active visitors on site in the last 30 minutes)\n", Color::GRAY)
                else
                  puts "#{Color::BOLD}Active Users | Country         | URL Path                       | Page / Screen Title#{Color::RESET}"
                  puts "------------------------------------------------------------------------------------------------------------------------"
                  breakdown.first(options[:limit] || 25).each do |b|
                    u_col = Color.c(b[:active_users].to_s.ljust(12), Color::GREEN, Color::BOLD)
                    c_col = b[:country].to_s[0..14].ljust(15)
                    path_str = b[:path].to_s[0..29].ljust(30)
                    path_col = Color.c(path_str, Color::MAGENTA, Color::BOLD)
                    p_col = Color.c(b[:page], Color::CYAN)
                    puts "#{u_col} | #{c_col} | #{path_col} | #{p_col}"
                  end
                  puts

                  if country_counts.any?
                    top_c = country_counts.sort_by { |_k, v| -v }.first(5).map { |c, count| "#{c}: #{count}" }.join(" | ")
                    puts "🌍 Top Countries: #{top_c}\n\n"
                  end
                end

                if interval
                  puts Color.c("⏳ Refreshing every #{interval}s (Press Ctrl+C to exit)...", Color::GRAY)
                end
              end
            else
              handle_ga4_api_error(res, property_id, hostname, options)
              break
            end

            break unless interval
            sleep interval
          end
        rescue Interrupt
          puts "\n👋 Exited live monitor." unless options[:json]
        end

      when 'ads', 'campaigns'
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Google Ads reporting requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Google Ads reporting requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc ads --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        puts "📢 Fetching Google Ads campaign performance for #{Color.c(hostname, Color::CYAN)} [Property #{property_id}] (Past #{options[:days]} days)..." unless options[:json]

        res = api.query_ga4_ads(property_id, days: options[:days], limit: options[:limit] || 50)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          if raw_rows.empty?
            if options[:json]
              puts JSON.pretty_generate({
                domain: hostname,
                property_id: property_id,
                campaigns: [],
                message: "No Google Ads campaign data recorded in GA4 for this date range."
              })
            else
              puts Color.c("\nℹ️  No Google Ads data found in GA4 for the past #{options[:days]} days.", Color::YELLOW)
              puts "• Check that Google Ads is linked in GA4 (Admin > Product Links > Google Ads Links)."
              puts "• Ensure Auto-tagging is enabled in Google Ads settings."
              puts "• Note: Google Ads cost/click metrics typically take 12–24 hours to populate in GA4.\n\n"
            end
            return
          end

          campaigns = []
          raw_rows.each do |row|
            camp_name = row.dig('dimensionValues', 0, 'value') || '(not set)'
            ad_group  = row.dig('dimensionValues', 1, 'value') || '(not set)'

            clicks    = row.dig('metricValues', 0, 'value').to_i
            cost      = row.dig('metricValues', 1, 'value').to_f
            cpc       = row.dig('metricValues', 2, 'value').to_f
            sessions  = row.dig('metricValues', 3, 'value').to_i
            conv      = row.dig('metricValues', 4, 'value').to_i
            bounce    = row.dig('metricValues', 5, 'value').to_f

            cpa = conv.positive? ? (cost / conv) : 0.0

            campaigns << {
              campaign: camp_name,
              ad_group: ad_group,
              clicks: clicks,
              cost: cost.round(2),
              cpc: cpc.round(2),
              sessions: sessions,
              conversions: conv,
              cpa: cpa.round(2),
              bounce_rate: (bounce * 100.0).round(1)
            }
          end

          campaigns.reject! { |c| c[:campaign] == '(not set)' && c[:clicks].zero? && c[:cost].zero? }

          if campaigns.empty?
            if options[:json]
              puts JSON.pretty_generate([])
            else
              puts Color.c("\nℹ️  No Google Ads clicks or spend recorded in GA4 for the past #{options[:days]} days.", Color::YELLOW, Color::BOLD)
              puts "\n#{Color::BOLD}Diagnostic Checklist:#{Color::RESET}"
              puts "  1. #{Color::BOLD}Campaign Hasn't Served Yet:#{Color::RESET} If your campaign was published recently, check Google Ads for 'Your campaign hasn't served in the past week' (often due to pending ad review, account security tasks, or low bids)."
              puts "  2. #{Color::BOLD}0 Impressions / Clicks:#{Color::RESET} GA4 only logs campaigns once Google Ads serves impressions and records traffic."
              puts "  3. #{Color::BOLD}GA4 Product Link:#{Color::RESET} Verify Google Ads is linked in GA4 (Admin > Product Links > Google Ads Links) with auto-tagging enabled."
              puts "  4. #{Color::BOLD}Sync Latency:#{Color::RESET} Ad spend & click metrics take 12–24 hours to populate in GA4 after ads begin serving.\n\n"
            end
            return
          end

          campaigns.sort_by! { |c| -c[:clicks] }

          if options[:json]
            puts JSON.pretty_generate(campaigns)
          else
            puts "\n#{Color::BOLD}Clicks | Cost ($) | Avg CPC | Sessions | Conv | CPA ($) | Bounce | Campaign Name [Ad Group]#{Color::RESET}"
            puts "-------------------------------------------------------------------------------------------------------"
            total_clicks = 0
            total_cost = 0.0
            total_sessions = 0
            total_conv = 0

            campaigns.first(options[:limit] || 25).each do |c|
              total_clicks += c[:clicks]
              total_cost += c[:cost]
              total_sessions += c[:sessions]
              total_conv += c[:conversions]

              clk_col = c[:clicks].to_s.ljust(6)
              cost_col = "$#{format('%.2f', c[:cost])}".ljust(8)
              cpc_col = "$#{format('%.2f', c[:cpc])}".ljust(7)
              sess_col = c[:sessions].to_s.ljust(8)
              conv_col = Color.c(c[:conversions].to_s.ljust(4), c[:conversions].positive? ? Color::GREEN : Color::GRAY)
              cpa_col = c[:conversions].positive? ? "$#{format('%.2f', c[:cpa])}".ljust(7) : "-".ljust(7)
              bnc_col = "#{c[:bounce_rate]}%".ljust(6)
              name_col = "#{Color.c(c[:campaign], Color::CYAN)} [#{Color.c(c[:ad_group], Color::GRAY)}]"

              puts "#{clk_col} | #{cost_col} | #{cpc_col} | #{sess_col} | #{conv_col} | #{cpa_col} | #{bnc_col} | #{name_col}"
            end

            puts "#{Color::BOLD}═══════════════════════════════════════════════════════════════════════════════════════#{Color::RESET}"
            total_cpa = total_conv.positive? ? "$#{format('%.2f', total_cost / total_conv)}" : "-"
            puts "Totals: #{total_clicks} clicks | $#{format('%.2f', total_cost)} cost | #{total_sessions} sessions | #{total_conv} conv | CPA: #{total_cpa}\n\n"
          end

          if options[:csv]
            csv_rows = campaigns.map do |c|
              [c[:campaign], c[:ad_group], c[:clicks], c[:cost], c[:cpc], c[:sessions], c[:conversions], c[:cpa], "#{c[:bounce_rate]}%"]
            end
            write_csv(options[:csv], %w[Campaign AdGroup Clicks Cost AvgCPC Sessions Conversions CPA BounceRate], csv_rows)
            puts Color.c("📁 Exported Google Ads report to #{options[:csv]}", Color::CYAN) unless options[:json]
          end
        else
          handle_ga4_api_error(res, property_id, hostname, options)
        end

      when 'channels', 'traffic'
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Traffic channel reporting requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Traffic channel reporting requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc channels --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        puts "🚦 Fetching Omnichannel acquisition breakdown for #{Color.c(hostname, Color::CYAN)} [Property #{property_id}] (Past #{options[:days]} days)..." unless options[:json]

        res = api.query_ga4_channels(property_id, days: options[:days], limit: options[:limit] || 25, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          if raw_rows.empty?
            if options[:json]
              puts JSON.pretty_generate([])
            else
              puts Color.c("⚠️ No acquisition channel data found in GA4 for this date range.", Color::YELLOW)
            end
            return
          end

          channels = []
          raw_rows.each do |row|
            channel  = row.dig('dimensionValues', 0, 'value') || '(not set)'
            source   = row.dig('dimensionValues', 1, 'value') || '(not set)'

            sessions = row.dig('metricValues', 0, 'value').to_i
            users    = row.dig('metricValues', 1, 'value').to_i
            eng_rate = row.dig('metricValues', 2, 'value').to_f
            bounce   = row.dig('metricValues', 3, 'value').to_f
            duration = row.dig('metricValues', 4, 'value').to_f
            conv     = row.dig('metricValues', 5, 'value').to_i

            channels << {
              channel: channel,
              source_medium: source,
              sessions: sessions,
              users: users,
              engagement_rate: (eng_rate * 100.0).round(1),
              bounce_rate: (bounce * 100.0).round(1),
              duration_seconds: duration.round(1),
              duration_formatted: format_duration(duration),
              conversions: conv
            }
          end

          channels.sort_by! { |c| -c[:sessions] }

          if options[:json]
            puts JSON.pretty_generate(channels)
          else
            puts "\n#{Color::BOLD}Sessions | Users | Eng Rate | Bounce | Avg Time | Conv | Channel Group [Source / Medium]#{Color::RESET}"
            puts "-----------------------------------------------------------------------------------------------"
            channels.first(options[:limit] || 20).each do |c|
              s_col = c[:sessions].to_s.ljust(8)
              u_col = c[:users].to_s.ljust(5)
              e_col = "#{c[:engagement_rate]}%".ljust(8)

              b_pct = "#{c[:bounce_rate]}%"
              b_col = if c[:bounce_rate] >= 70.0
                Color.c(b_pct.ljust(6), Color::RED)
              elsif c[:bounce_rate] <= 40.0
                Color.c(b_pct.ljust(6), Color::GREEN)
              else
                b_pct.ljust(6)
              end

              d_col = c[:duration_formatted].ljust(8)
              cv_col = Color.c(c[:conversions].to_s.ljust(4), c[:conversions].positive? ? Color::GREEN : Color::GRAY)
              ch_col = "#{Color.c(c[:channel], Color::CYAN)} [#{Color.c(c[:source_medium], Color::GRAY)}]"

              puts "#{s_col} | #{u_col} | #{e_col} | #{b_col} | #{d_col} | #{cv_col} | #{ch_col}"
            end

            total_s = channels.sum { |c| c[:sessions] }
            total_u = channels.sum { |c| c[:users] }
            total_cv = channels.sum { |c| c[:conversions] }
            puts "\nTotal Channels: #{channels.size} | Total Sessions: #{total_s} | Total Users: #{total_u} | Conversions: #{total_cv}\n\n"
          end

          if options[:csv]
            csv_rows = channels.map do |c|
              [c[:channel], c[:source_medium], c[:sessions], c[:users], "#{c[:engagement_rate]}%", "#{c[:bounce_rate]}%", c[:duration_seconds], c[:conversions]]
            end
            write_csv(options[:csv], %w[Channel SourceMedium Sessions Users EngagementRate BounceRate DurationSeconds Conversions], csv_rows)
            puts Color.c("📁 Exported Channel Acquisition report to #{options[:csv]}", Color::CYAN) unless options[:json]
          end
        else
          handle_ga4_api_error(res, property_id, hostname, options)
        end

      else
        if options[:json]
          puts JSON.pretty_generate({ error: "Unknown command: #{command}" })
        else
          puts Color.c("❌ Unknown command: '#{command}'. Run 'gsc --help' for options.", Color::RED)
        end
        exit 1 unless options[:in_dashboard]
      end
    end

    def self.resolve_sort_params(field, order)
      canonical_field = case field&.to_s&.downcase&.strip
      when 'imp', 'impr', 'impressions'
        :impressions
      when 'pos', 'rank', 'position'
        :position
      when 'ctr'
        :ctr
      when 'clicks', 'click'
        :clicks
      when nil, ''
        nil
      else
        field.to_s.downcase.strip.to_sym
      end

      canonical_order = if order && !order.to_s.strip.empty?
        order.to_s.downcase.strip.start_with?('asc') ? :asc : :desc
      elsif canonical_field == :position
        :asc
      else
        :desc
      end

      [canonical_field, canonical_order]
    end

    def self.sort_analytics_rows(rows, sort_field, order)
      field, dir = resolve_sort_params(sort_field, order)

      if field
        rows.sort do |a, b|
          val_a = a[field] || 0
          val_b = b[field] || 0
          cmp = val_a <=> val_b
          cmp = (cmp.nil? ? 0 : cmp)
          dir == :asc ? cmp : -cmp
        end
      else
        # Default intelligent sort:
        # 1. Clicks DESC
        # 2. Impressions DESC
        # 3. Position ASC
        rows.sort do |a, b|
          clicks_cmp = (b[:clicks] || 0) <=> (a[:clicks] || 0)
          if clicks_cmp.zero?
            imp_cmp = (b[:impressions] || 0) <=> (a[:impressions] || 0)
            if imp_cmp.zero?
              (a[:position] || 999.0) <=> (b[:position] || 999.0)
            else
              imp_cmp
            end
          else
            clicks_cmp
          end
        end
      end
    end

    def self.handle_connect_wizard
      puts BANNER
      puts "#{Color::BOLD}🪄  GSC INTERACTIVE SETUP WIZARD#{Color::RESET}\n"

      key_file = nil

      # 0. Check if a key is already configured
      existing_key = Auth.find_key(nil)
      if existing_key && File.exist?(existing_key)
        sa = JSON.parse(File.read(existing_key)) rescue {}
        if sa['client_email']
          puts "🔑 Found existing key already configured:"
          puts "   #{Color.c(existing_key, Color::CYAN)} (#{sa['client_email']})"
          print "Keep and test this key? [Y/n]: "
          choice = $stdin.gets&.strip
          if choice.nil? || choice.empty? || choice.downcase == 'y'
            key_file = existing_key
          end
        end
      end

      # 1. Check ~/Downloads for recent Google Cloud keys (if permitted by OS)
      unless key_file
        begin
          downloads_dir = File.expand_path('~/Downloads')
          if Dir.exist?(downloads_dir)
            recent_keys = Dir.glob(File.join(downloads_dir, '*.json')).select do |f|
              next false if (File.size(f) rescue 999_999) > 50_000 # Service account keys are ~2KB
              content = File.read(f) rescue ""
              content.include?('"client_email"') && content.include?('"private_key"')
            end.sort_by { |f| File.mtime(f) rescue Time.at(0) }.reverse

            if recent_keys.any?
              latest = recent_keys.first
              sa = JSON.parse(File.read(latest)) rescue {}
              if sa['client_email']
                puts "🔍 Found recently downloaded service account key in Downloads:"
                puts "   #{Color.c(File.basename(latest), Color::CYAN)} (#{sa['client_email']})"
                print "Use this key? [Y/n]: "
                choice = $stdin.gets&.strip
                if choice.nil? || choice.empty? || choice.downcase == 'y'
                  key_file = latest
                end
              end
            end
          end
        rescue Errno::EPERM, StandardError
          # Permission to ~/Downloads restricted by macOS TCC - fallback gracefully to drag & drop
        end
      end

      # 2. Prompt drag and drop if not selected
      unless key_file
        puts "\n👉 #{Color::BOLD}Drag and drop your downloaded Google Cloud JSON key into this terminal#{Color::RESET}"
        print "(or paste the file path): "
        input = $stdin.gets&.strip
        if input.nil? || input.empty?
          puts Color.c("Setup cancelled.", Color::YELLOW)
          exit 0
        end

        # Clean drag-and-drop escaped paths in mac terminal (escaped spaces or quotes)
        cleaned_path = input.gsub(/^['"]|['"]$/, '').gsub('\\ ', ' ')
        cleaned_path = File.expand_path(cleaned_path)
        unless File.exist?(cleaned_path)
          puts Color.c("❌ Error: File not found at: #{cleaned_path}", Color::RED)
          exit 1
        end
        key_file = cleaned_path
      end

      # 3. Validate JSON
      begin
        sa = JSON.parse(File.read(key_file))
        unless sa['client_email'] && sa['private_key']
          puts Color.c("❌ Error: Selected JSON file is missing client_email or private_key.", Color::RED)
          exit 1
        end
      rescue StandardError => e
        puts Color.c("❌ Error parsing JSON: #{e.message}", Color::RED)
        exit 1
      end

      # 4. Save to ~/.config/gsc/service-account.json (with strict 0600 file permissions)
      dest = File.join(Config::CONFIG_DIR, 'service-account.json')
      FileUtils.mkdir_p(Config::CONFIG_DIR)
      File.chmod(0700, Config::CONFIG_DIR) rescue nil
      FileUtils.cp(key_file, dest) unless File.expand_path(key_file) == File.expand_path(dest)
      File.chmod(0600, dest) rescue nil
      Config.set_key_path(dest)
      puts Color.c("\n✅ Key configured at: #{dest}", Color::GREEN, Color::BOLD)
      puts "   Service Account: #{Color.c(sa['client_email'], Color::CYAN)}"

      # 5. Live test connection
      print "\n🔄 Testing connection to Google OAuth2 API... "
      token = nil
      begin
        token = Auth.fetch_access_token(sa)
        puts Color.c("Connected! (Token acquired)", Color::GREEN)
      rescue StandardError => e
        puts Color.c("Failed! #{e.message}", Color::RED)
        exit 1
      end

      # 6. Fetch verified domains
      print "🌐 Querying verified Search Console domain properties... "
      client = Client.new(token: token)
      api = API.new(client)
      sites_res = api.list_sites

      if sites_res[:ok]
        entries = sites_res.dig(:data, 'siteEntry') || []
        if entries.empty?
          puts Color.c("\n⚠️  No domain properties found in Search Console yet.", Color::YELLOW)
          puts "\n#{Color::BOLD}Next Step:#{Color::RESET}"
          puts "1. Go to: https://search.google.com/search-console/"
          puts "2. In Settings > Users and permissions, click 'Add user'"
          puts "3. Paste: #{Color.c(sa['client_email'], Color::CYAN)}"
          puts "4. Set permission to #{Color::BOLD}Owner#{Color::RESET} and click Add."
          puts "\nThen run #{Color.c('gsc domains', Color::CYAN)} anytime to verify!"
        else
          puts Color.c("Found #{entries.size} properties!\n", Color::GREEN)
          puts "#{Color::BOLD}Available Search Console Domains:#{Color::RESET}"
          entries.each_with_index do |s, idx|
            puts "  #{idx + 1}) #{Color.c(s['siteUrl'], Color::CYAN)}"
          end

          print "\nChoose a default domain (1-#{entries.size}) [1]: "
          choice = $stdin.gets&.strip
          idx = (choice && !choice.empty?) ? (choice.to_i - 1) : 0
          idx = 0 if idx < 0 || idx >= entries.size

          selected_url = entries[idx]['siteUrl']
          clean_dom = Config.set_default_domain(selected_url)
          puts Color.c("✅ Default domain set to: #{clean_dom}", Color::GREEN, Color::BOLD)
        end
      end

      puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
      puts "#{Color::BOLD}🎉 SETUP COMPLETE!#{Color::RESET}"
      puts "You can now run:"
      puts "   #{Color.c('gsc top-queries', Color::CYAN)}     - See your Google search rankings"
      puts "   #{Color.c('gsc performance', Color::CYAN)}     - 30-day search performance summary"
      puts "   #{Color.c('gsc audit', Color::CYAN)}           - Full automated SEO audit"
      puts "   #{Color.c('gsc open', Color::CYAN)}            - Reveal config folder in Finder"
      puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"
    end

    def self.handle_connect_ga4_wizard(options = {})
      puts BANNER
      puts "#{Color::BOLD}📊 GA4 INTERACTIVE LINKING WIZARD#{Color::RESET}\n"

      key_path = Auth.find_key(options[:key])
      unless key_path && File.exist?(key_path)
        puts Color.c("❌ Error: No Google Service Account key found.", Color::RED)
        puts "Please run #{Color.c('gsc connect', Color::GREEN, Color::BOLD)} first to set up your Google credentials."
        exit 1
      end

      sa = JSON.parse(File.read(key_path)) rescue {}
      sa_email = sa['client_email']
      unless sa_email
        puts Color.c("❌ Error: Could not read client_email from #{key_path}", Color::RED)
        exit 1
      end

      puts "🔑 Using Service Account: #{Color.c(sa_email, Color::CYAN, Color::BOLD)}\n\n"

      puts "#{Color::BOLD}STEP 1: Enable Google Analytics APIs#{Color::RESET}"
      puts "  Open Google Cloud Console (in your browser):"
      puts "  👉 #{Color.c('https://console.cloud.google.com/apis/library/analyticsdata.googleapis.com', Color::CYAN)} (Data API - for metrics)"
      puts "  👉 #{Color.c('https://console.cloud.google.com/apis/library/analyticsadmin.googleapis.com', Color::CYAN)} (Admin API - for auto-discovery)"
      puts "  Click the #{Color::BOLD}'ENABLE'#{Color::RESET} button on each page.\n\n"

      puts "#{Color::BOLD}STEP 2: Grant Viewer Access in Google Analytics 4#{Color::RESET}"
      puts "  1. Open Google Analytics: #{Color.c('https://analytics.google.com/', Color::CYAN)}"
      puts "  2. Click #{Color::BOLD}Admin#{Color::RESET} (gear icon at bottom-left of your sidebar)"
      puts "  3. In Property settings, click #{Color::BOLD}Property access management#{Color::RESET}"
      puts "  4. Click the blue #{Color::BOLD}'+'#{Color::RESET} button at top-right ➔ #{Color::BOLD}Add users#{Color::RESET}"
      puts "  5. Paste your service account email:"
      puts "     👉 #{Color.c(sa_email, Color::CYAN, Color::BOLD)}"
      puts "  6. Assign the #{Color::BOLD}Viewer#{Color::RESET} role, uncheck 'Notify new users', and click #{Color::BOLD}Add#{Color::RESET}.\n\n"

      puts "#{Color::BOLD}STEP 3: Find Your Numeric GA4 Property ID#{Color::RESET}"
      puts "  • Option A: Look at the top-left property switcher (under your property name)"
      puts "  • Option B: In #{Color::BOLD}Admin ➔ Property details#{Color::RESET}, copy the 9-digit #{Color::BOLD}Property ID#{Color::RESET} (e.g. 123456789)\n\n"

      default_dom = options[:domain] || Config.default_domain || 'example.com'
      print "Which domain should this GA4 property link to? [#{default_dom}]: "
      input_dom = $stdin.gets&.strip
      target_dom = (input_dom && !input_dom.empty?) ? input_dom : default_dom
      target_dom = target_dom.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')

      current_id = Config.ga4_property_id(target_dom)
      id_prompt = current_id ? " [#{current_id}]" : ""
      print "Enter your 9-digit GA4 Property ID#{id_prompt}: "
      input_id = $stdin.gets&.strip
      property_id = (input_id && !input_id.empty?) ? input_id : current_id

      if property_id.nil? || property_id.empty?
        puts Color.c("\nLinking cancelled.", Color::YELLOW)
        exit 0
      end

      clean_id = property_id.to_s.strip.sub(%r{^properties/}, '')
      puts "\n🔄 Testing connection to GA4 Property #{clean_id}..."

      begin
        token = Auth.fetch_access_token(sa)
        client = Client.new(token: token)
        api = API.new(client)

        test_res = api.query_ga4_report(clean_id, days: 7, limit: 1)
        if test_res[:ok]
          Config.set_ga4_property_id(clean_id, target_dom)
          puts Color.c("✅ Connection verified! Successfully queried Google Analytics Data API.", Color::GREEN, Color::BOLD)
          puts Color.c("🎉 Linked GA4 Property #{clean_id} to #{target_dom}!", Color::GREEN, Color::BOLD)
          puts "\nYou can now run:"
          puts "   #{Color.c('gsc ga4', Color::CYAN)}             - Landing page bounce rates, engagement rates & duration"
          puts "   #{Color.c('gsc correlation', Color::CYAN)}     - Merged GSC keyword rankings + GA4 on-site retention"
          puts "   #{Color.c('gsc audit', Color::CYAN)}           - Comprehensive 5-step SEO & GA4 health audit"
        else
          puts Color.c("\n⚠️ Live test returned error (#{test_res[:status]}): #{test_res.dig(:data, 'error', 'message')}", Color::YELLOW)
          print "Save Property ID anyway? [y/N]: "
          choice = $stdin.gets&.strip
          if choice =~ /^y/i
            Config.set_ga4_property_id(clean_id, target_dom)
            puts Color.c("💾 Saved Property ID #{clean_id} for #{target_dom}.", Color::GREEN)
            puts "Make sure to enable the API in Google Cloud and grant Viewer role in GA4 Admin."
          else
            puts Color.c("Setup aborted.", Color::YELLOW)
          end
        end
      rescue StandardError => e
        puts Color.c("\n❌ OAuth / Network Error: #{e.message}", Color::RED)
      end
      puts
    end

    def self.handle_open_command
      dir = Config::CONFIG_DIR
      FileUtils.mkdir_p(dir)
      puts "📂 Opening #{Color.c(dir, Color::CYAN)} in Finder..."
      if RUBY_PLATFORM =~ /darwin/
        system('open', dir)
      elsif RUBY_PLATFORM =~ /linux/
        system('xdg-open', dir, out: File::NULL, err: File::NULL) || system('open', dir, out: File::NULL, err: File::NULL)
      end
    end

def self.handle_google_trends_command(keyword, options)
  geo = options[:geo] || 'US'
  time = options[:time] || '5y'
  puts BANNER unless options[:json] || options[:in_dashboard]
  puts "📈 Querying Google Trends for: #{Color.c(keyword, Color::CYAN)} (Geo: #{geo.empty? ? 'Worldwide' : geo}, Time: #{time})...\n" unless options[:json]

  res = GoogleTrends.fetch(keyword, geo: geo, time: time)
  unless res[:ok]
    if options[:json]
      puts JSON.pretty_generate({ error: res[:error] })
    else
      puts Color.c("❌ Google Trends Error: #{res[:error]}", Color::RED)
    end
    return
  end

  if options[:json]
    puts JSON.pretty_generate(res)
    return
  end

  puts "#{Color::BOLD}Search Term:#{Color::RESET}      #{Color.c(res[:keyword], Color::CYAN, Color::BOLD)}"
  puts "#{Color::BOLD}Region / Geo:#{Color::RESET}     #{res[:geo]}"
  puts "#{Color::BOLD}Timeframe:#{Color::RESET}        #{res[:time]}"
  puts "#{Color::BOLD}Trend Velocity:#{Color::RESET}   #{Color.c(res[:velocity_badge], Color::GREEN, Color::BOLD)}"
  puts "#{Color::BOLD}Peak Demand:#{Color::RESET}      #{Color.c("#{res[:peak_score]}/100", Color::YELLOW)} (#{res[:peak_date]})"
  puts "#{Color::BOLD}Current Score:#{Color::RESET}    #{res[:current_score]} / 100"
  puts ""
  puts "#{Color::BOLD}Demand Trajectory:#{Color::RESET}"
  puts "  [ #{Color.c(res[:sparkline], Color::CYAN)} ]"
  puts ""

  if res[:regions].any?
    puts "#{Color::BOLD}🌍 Top Geographic Regions:#{Color::RESET}"
    res[:regions].each_with_index do |r, i|
      bar_len = [(r[:score] / 10.0).round, 10].min
      bar = "█" * bar_len + " " * (10 - bar_len)
      puts "  #{(i + 1).to_s.rjust(2)}. #{r[:name].ljust(22)} [#{Color.c(bar, Color::CYAN)}] #{r[:score].to_s.rjust(3)}/100"
    end
    puts ""
  end

  if res[:rising_queries].any?
    puts "#{Color::BOLD}🔥 Rising & Breakout Related Searches:#{Color::RESET}"
    res[:rising_queries].each do |q|
      badge_color = q[:growth] == 'Breakout' ? Color::GREEN : Color::YELLOW
      puts "  • #{q[:query].ljust(35)} [#{Color.c(q[:growth], badge_color, Color::BOLD)}]"
    end
    puts ""
  end

  if res[:top_queries].any?
    puts "#{Color::BOLD}💡 Top Related Searches:#{Color::RESET}"
    res[:top_queries].each do |q|
      puts "  • #{q[:query].ljust(35)} (#{q[:score]}/100)"
    end
    puts ""
  end
end

def self.render_keyword_table(keywords, limit: nil)
  displayed = limit ? keywords.first(limit) : keywords

  puts "#{Color::BOLD}Opp Score | Volume/mo | CPC     | Comp | Tier   | Trend% [12m] | GSC Status                  | Intent        | Keyword#{Color::RESET}"
  puts "--------------------------------------------------------------------------------------------------------------------------------"
  displayed.each do |r|
    score = r[:opportunity_score] || r['opportunity_score'] || 0
    score_color = if score >= 80 then Color::GREEN
                  elsif score >= 50 then Color::CYAN
                  else Color::YELLOW
                  end
    score_str = Color.c(score.to_s.rjust(9), score_color, Color::BOLD)

    vol = r[:volume] || r['volume'] || 0
    vol_str = vol.to_s.reverse.scan(/.{1,3}/).join(',').reverse.rjust(9)

    cpc = r[:cpc] || r['cpc'] || '$0.00'
    cpc_str = cpc.to_s.rjust(7)

    comp = r[:competition] || r['competition'] || 0.0
    comp_str = sprintf('%.2f', comp.to_f).rjust(4)

    tier = r[:competition_tier] || r['competition_tier'] || 'Low'
    tier_str = tier.to_s.ljust(6)

    trend_pct = (r[:trend_pct] || r['trend_pct'] || 0).to_i
    hist = r[:monthly_history] || r['monthly_history'] || {}
    spark = if hist.is_a?(Hash) && hist.size >= 3
              KeywordPlanner.render_sparkline(hist.values.reverse, max_points: 6)
            else
              ""
            end
    trend_raw = (trend_pct >= 0 ? "+#{trend_pct}%" : "#{trend_pct}%")
    trend_str = spark.empty? ? trend_raw.rjust(12) : "#{trend_raw.rjust(5)} #{spark}".ljust(12)

    gsc_data = r[:gsc] || r['gsc'] || {}
    gsc_status = gsc_data[:status] || gsc_data['status'] || '🚀 Untargeted'
    gsc_str = gsc_status.ljust(27)

    intent = r[:intent] || r['intent'] || 'Informational'
    intent_str = intent.to_s.ljust(13)

    kw = r[:keyword] || r['keyword'] || ''
    kw_str = Color.c(kw, Color::BOLD)

    puts "#{score_str} | #{vol_str} | #{cpc_str} | #{comp_str} | #{tier_str} | #{trend_str} | #{gsc_str} | #{intent_str} | #{kw_str}"
  end
  puts ""
end

def self.handle_saved_keywords_command(subcmd, target, options)
  hostname, site_url, _ = resolve_domain(options[:domain], nil, options)
  list = Config.list_saved_keywords(hostname)
  sub = subcmd.to_s.downcase

  if sub == 'delete' || sub == 'rm'
    if target.nil? || target.strip.empty?
      puts Color.c("❌ Error: Specify snapshot ID or filename to delete (e.g. gsc saved delete 1)", Color::RED)
      return
    end
    ok = Config.delete_saved_keywords(hostname, target)
    if ok
      puts Color.c("🗑️ Deleted keyword research snapshot: #{target}", Color::GREEN)
    else
      puts Color.c("❌ Snapshot not found: #{target}", Color::RED)
    end
    return
  end

  if sub == 'view' || sub == 'show'
    identifier = target || '1'
    data = Config.load_saved_keywords(hostname, identifier)
    if data.nil?
      puts Color.c("❌ Could not find saved snapshot '#{identifier}' for #{hostname}", Color::RED)
      return
    end

    if options[:json]
      puts JSON.pretty_generate(data)
      return
    end

    puts BANNER unless options[:in_dashboard]
    puts "📂 SAVED KEYWORD SNAPSHOT: #{Color.c(data['seed'].to_s, Color::CYAN, Color::BOLD)} (#{data['source']})"
    puts "   Domain: #{hostname} · Saved: #{data['savedAt']} · Total Keywords: #{data['totalKeywords']}\n\n"

    render_keyword_table(data['keywords'] || [], limit: options[:limit] || 50)
    puts Color.c("Showing Top #{[data['totalKeywords'], options[:limit] || 50].min} of #{data['totalKeywords']} keywords.", Color::GRAY)
    return
  end

  if sub == 'check' || sub == 'track' || sub == 'rankings'
    identifier = target || '1'
    data = Config.load_saved_keywords(hostname, identifier)
    if data.nil?
      puts Color.c("❌ Could not find saved snapshot '#{identifier}' for #{hostname}", Color::RED)
      return
    end

    puts BANNER unless options[:in_dashboard]
    puts "🔍 RE-CHECKING SAVED KEYWORDS AGAINST GOOGLE SEARCH CONSOLE"
    puts "   Snapshot: #{Color.c(data['seed'].to_s, Color::CYAN, Color::BOLD)} (#{data['totalKeywords']} keywords)"
    puts "   Target Property: #{Color.c(site_url || hostname, Color::CYAN)}\n\n"

    key_path = Auth.find_key(options[:key])
    unless key_path
      puts Color.c("❌ Error: Service account JSON key not found. Run gsc connect to configure.", Color::RED)
      return
    end

    service_account = JSON.parse(File.read(key_path))
    token = Auth.fetch_access_token(service_account)
    client = Client.new(token: token)
    api = API.new(client)

    raw_keywords = (data['keywords'] || []).map do |kw|
      {
        keyword: kw['keyword'] || kw[:keyword],
        volume: (kw['volume'] || kw[:volume] || 0).to_i,
        cpc: kw['cpc'] || kw[:cpc] || '$0.00',
        competition: (kw['competition'] || kw[:competition] || 0.0).to_f,
        competition_tier: kw['competition_tier'] || kw[:competition_tier] || 'Low',
        trend_pct: (kw['trend_pct'] || kw[:trend_pct] || 0).to_i,
        opportunity_score: (kw['opportunity_score'] || kw[:opportunity_score] || 0).to_i,
        intent: kw['intent'] || kw[:intent] || 'Informational',
        monthly_history: kw['monthly_history'] || kw[:monthly_history] || {}
      }
    end

    updated = KeywordPlanner.correlate_with_gsc(raw_keywords, api, site_url, days: options[:days] || 30)

    if options[:json]
      puts JSON.pretty_generate({
        domain: hostname,
        siteUrl: site_url,
        seed: data['seed'],
        checkedAt: Time.now.utc.iso8601,
        totalKeywords: updated.size,
        keywords: updated
      })
      return
    end

    render_keyword_table(updated, limit: options[:limit] || 50)

    # Calculate growth summary
    ranking_count = updated.count { |k| k.dig(:gsc, :status) != '🚀 Untargeted' }
    top3_count = updated.count { |k| k.dig(:gsc, :position).to_f > 0 && k.dig(:gsc, :position).to_f <= 3.0 }
    page1_count = updated.count { |k| k.dig(:gsc, :position).to_f > 3.0 && k.dig(:gsc, :position).to_f <= 10.0 }
    striking_count = updated.count { |k| k.dig(:gsc, :position).to_f > 10.0 && k.dig(:gsc, :position).to_f <= 20.0 }

    puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
    puts "#{Color::BOLD}📊 KEYWORD RANKING & OPPORTUNITY TRACKER (#{hostname})#{Color::RESET}"
    puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
    puts "  🏆 Top 3 Rankings:            #{Color.c(top3_count.to_s, Color::GREEN, Color::BOLD)}"
    puts "  🥇 Page 1 Rankings (4–10):    #{Color.c(page1_count.to_s, Color::GREEN, Color::BOLD)}"
    puts "  🎯 Striking Distance (11–20): #{Color.c(striking_count.to_s, Color::YELLOW, Color::BOLD)}"
    puts "  🚀 Untargeted / Unranked:      #{Color.c((updated.size - ranking_count).to_s, Color::GRAY)}"
    puts "  📈 Total Tracked Keywords:    #{updated.size}"
    puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"
    return
  end

  # Default: List saved snapshots
  if options[:json]
    puts JSON.pretty_generate({ domain: hostname, snapshots: list })
    return
  end

  puts BANNER unless options[:in_dashboard]
  puts "📁 SAVED KEYWORD RESEARCH ARCHIVES (#{Color.c(hostname, Color::CYAN, Color::BOLD)})"
  puts "   Location: #{Config.domain_keywords_dir(hostname)}\n\n"

  if list.empty?
    puts Color.c("ℹ️ No saved keyword research found for #{hostname}.", Color::YELLOW)
    puts "\n💡 Quick Start:"
    puts "   Run #{Color.c('gsc import docs/KW.md', Color::CYAN)} to import and save an export."
    puts "   Or run #{Color.c('gsc planner "moving boxes" --save', Color::CYAN)} to save search ideas."
    puts
    return
  end

  puts "#{Color::BOLD}  # | Date       | Source                | Keywords | Seed / File#{Color::RESET}"
  puts "  --------------------------------------------------------------------------------"
  list.each_with_index do |item, idx|
    num = "[#{idx + 1}]".rjust(4)
    date_str = item['savedAt'].to_s.split('T').first.ljust(10)
    source_str = item['source'].to_s.gsub('_', ' ').capitalize.ljust(21)
    kw_count = item['totalKeywords'].to_s.rjust(8)
    seed_str = Color.c(item['seed'].to_s, Color::CYAN)
    puts "#{Color.c(num, Color::CYAN, Color::BOLD)} | #{date_str} | #{source_str} | #{kw_count} | #{seed_str}"
  end

  puts "\n💡 Commands:"
  puts "   #{Color.c('gsc saved view 1', Color::CYAN)}    # View stored keywords & metrics"
  puts "   #{Color.c('gsc saved check 1', Color::GREEN)}   # Re-check live against Search Console rankings"
  puts "   #{Color.c('gsc saved delete 1', Color::RED)}  # Delete archive snapshot"
  puts
end


def self.handle_planner_import_command(filepath, options)
  src_arg = filepath.to_s.strip
  if src_arg.empty?
    # Check if clipboard has table content
    clip_sample = KeywordPlanner.read_clipboard.to_s
    if clip_sample.include?("\t") || clip_sample =~ /keyword/i
      src_arg = 'clipboard'
    else
      if options[:json]
        puts JSON.pretty_generate({ error: 'Please specify a file path or use clipboard (e.g. gsc import keywords.csv or gsc import clip)' })
      else
        puts Color.c("❌ Error: Please specify a file path to import or copy keyword data to clipboard.", Color::RED)
        puts "   Usage: #{Color.c('gsc import path/to/keywords.csv', Color::CYAN)}"
        puts "          #{Color.c('gsc import clip', Color::GREEN)}  (Imports directly from copied table)"
      end
      return
    end
  end

  puts BANNER unless options[:json] || options[:in_dashboard]
  src_label = src_arg =~ /clip/i ? 'macOS Clipboard' : src_arg
  puts "📥 Importing keyword dataset from: #{Color.c(src_label, Color::CYAN)}...\n" unless options[:json]

  raw_keywords = KeywordPlanner.import_file(src_arg)

  # Attempt GSC correlation if key and domain are available
  api = nil
  site_url = nil
  begin
    key_path = Auth.find_key(options[:key])
    if key_path
      service_account = JSON.parse(File.read(key_path))
      token = Auth.fetch_access_token(service_account)
      client = Client.new(token: token)
      api = API.new(client)
      hostname, site_url, _ = resolve_domain(options[:domain], nil, options)
      puts "🔗 Cross-referencing against Google Search Console: #{Color.c(site_url, Color::CYAN)}...\n" unless options[:json]
    end
  rescue StandardError
  end

  keywords = KeywordPlanner.correlate_with_gsc(raw_keywords, api, site_url, days: options[:days] || 30)
  limit = options[:limit] || 35
  displayed = keywords.first(limit)

  if options[:json]
    puts JSON.pretty_generate({
      file: filepath,
      totalKeywords: keywords.size,
      siteUrl: site_url,
      keywords: displayed
    })
    return
  end

render_keyword_table(keywords, limit: limit)

# Automatically save snapshot to domain research library
active_dom = hostname || Config.default_domain || 'global'
src_label = (src_arg =~ /clip/i) ? 'clipboard-export' : File.basename(src_arg, '.*')
saved_path = Config.save_keyword_research(active_dom, src_label, keywords, source: 'import')
puts Color.c("💾 Saved snapshot to domain archive: #{saved_path}", Color::CYAN)
puts "   Re-check anytime with: #{Color.c('gsc saved check 1', Color::GREEN)} or #{Color.c('gsc saved view 1', Color::YELLOW)}\n"
end

def self.handle_connect_ke_wizard(key_arg = nil)
  puts BANNER unless $stdout.tty? == false
  puts "#{Color::BOLD}🔑 KEYWORDS EVERYWHERE API SETUP#{Color::RESET}\n"

  key = key_arg.to_s.strip
  if key.empty?
    existing = Config.keywords_everywhere_api_key
    if existing && !existing.empty?
      masked = "#{existing[0..5]}...#{existing[-4..]}" rescue "******"
      puts "Current API Key: #{Color.c(masked, Color::CYAN)}"
      print "Enter new API key (or press Enter to keep current): "
      input = $stdin.gets&.strip
      key = input unless input.nil? || input.empty?
      key = existing if key.empty?
    else
      puts "Get your Keywords Everywhere API key at: #{Color.c('https://keywordseverywhere.com/', Color::UNDERLINE)}"
      print "Paste your Keywords Everywhere API Key: "
      key = $stdin.gets&.strip
    end
  end

  if key.nil? || key.empty?
    puts Color.c("\n❌ No API key provided.", Color::RED)
    return
  end

  puts "\n⏳ Validating key with Keywords Everywhere API..."
  acct = KeywordsEverywhere.check_account(key)
  if acct[:ok]
    Config.set_keywords_everywhere_api_key(key)
    fmt_credits = acct[:credits].to_s.reverse.gsub(/(\d{3})(?=\d)/, ',').reverse
    puts Color.c("\n✅ SUCCESS! Keywords Everywhere API key connected.", Color::GREEN, Color::BOLD)
    puts "   💰 Remaining Credits: #{Color.c(fmt_credits, Color::CYAN, Color::BOLD)}"
    puts "   📁 Saved to: #{Color.c(Config::CONFIG_FILE, Color::GRAY)}"

    if acct[:credits].to_i == 0
      puts "\n" + Color.c("ℹ️ FREE ACCOUNT DETECTED (0 REST API Credits)", Color::YELLOW, Color::BOLD)
      puts "Keywords Everywhere gives free accounts #{Color.c('500 free lookups/day in their Web UI', Color::GREEN)},"
      puts "while their REST API requires purchased credits (1 credit = 1 keyword).\n\n"
      puts "#{Color::BOLD}🚀 3 FAST WORKFLOWS YOU CAN USE RIGHT NOW:#{Color::RESET}"
      puts "  1. #{Color.c('Free 500/day on Web + 1-Click Clipboard Import:', Color::GREEN, Color::BOLD)}"
      puts "     • Check search volume at: #{Color.c('https://keywordseverywhere.com/tools/bulk-keywords-data', Color::UNDERLINE)}"
      puts "     • Click 'Copy' -> Run: #{Color.c('gsc import clip', Color::CYAN, Color::BOLD)}"
      puts "  2. #{Color.c('100% Free Live Google Trends (Breakout & Related terms):', Color::BLUE, Color::BOLD)}"
      puts "     • Run: #{Color.c('gsc trends "moving boxes"', Color::BLUE, Color::BOLD)}"
      puts "  3. #{Color.c('Top Up Credits for Automated Background CLI Lookups:', Color::GRAY, Color::BOLD)}"
      puts "     • Purchase credits at: https://keywordseverywhere.com/credit-packages.html"
      puts "     • Your key is already saved; it will work immediately upon top-up.\n"
    else
      puts "\nTry searching keywords:"
      puts "   #{Color.c('gsc ke "moving boxes"', Color::YELLOW)}"
    end
  else
    puts Color.c("\n❌ Invalid API Key: #{acct[:error]}", Color::RED)
    puts "Please check your key and try again: #{Color.c('gsc connect ke', Color::CYAN)}"
  end
end

def self.handle_ke_credits_command(options = {})
  acct = KeywordsEverywhere.check_account
  if options[:json]
    puts JSON.pretty_generate(acct)
    return
  end
  if acct[:ok]
    fmt_credits = acct[:credits].to_s.reverse.gsub(/(\d{3})(?=\d)/, ',').reverse
    puts "\n💰 #{Color::BOLD}Keywords Everywhere Account Credits:#{Color::RESET} #{Color.c(fmt_credits, Color::GREEN, Color::BOLD)}"
    if acct[:credits].to_i == 0
      puts "\n" + Color.c("ℹ️ You have 0 paid REST API credits remaining.", Color::YELLOW)
      puts "• Free Web Alternative: Check volume on keywordseverywhere.com, click 'Copy', then run: #{Color.c('gsc import clip', Color::CYAN)}"
      puts "• Free Live Trends: #{Color.c('gsc trends "moving boxes"', Color::BLUE)}"
      puts "• Top up credits at: https://keywordseverywhere.com/credit-packages.html"
    end
  else
    if acct[:error].to_s =~ /401|Unauthorized/i
      puts Color.c("\n❌ Invalid or expired API Key: #{acct[:error]}", Color::RED)
      puts "Update your key: #{Color.c('gsc connect ke', Color::CYAN)}"
    else
      puts Color.c("\n❌ Error: #{acct[:error]}", Color::RED)
      puts "Connect your key: #{Color.c('gsc connect ke', Color::CYAN)}"
    end
  end
end

def self.handle_ke_command(target, options = {})
  if target.nil? || target.strip.empty?
    puts Color.c("❌ Please provide a seed keyword or file path. e.g.: gsc ke 'moving boxes'", Color::RED)
    return
  end

  country = options[:country] || 'us'
  currency = options[:currency] || 'usd'
  limit = (options[:limit] || 25).to_i

  # Check if key is configured
unless KeywordsEverywhere.api_key
  if options[:json]
    puts JSON.pretty_generate({
      ok: false,
      error: "Keywords Everywhere API key not configured",
      recommendations: [
        { action: 'connect', cmd: 'gsc connect ke', desc: 'Connect Keywords Everywhere API key' },
        { action: 'google_trends', cmd: "gsc trends \"#{target}\"", desc: 'Use 100% free Google Trends without any API key' },
        { action: 'import_clipboard', cmd: 'gsc import clip', desc: 'Import 500 daily free web lookups from clipboard' }
      ]
    })
  else
    puts Color.c("\n❌ Keywords Everywhere API key not configured!\n", Color::RED, Color::BOLD)
    puts "#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
    puts "  1. Connect a key: #{Color.c('gsc connect ke', Color::CYAN, Color::BOLD)} (Get key at https://keywordseverywhere.com/)"
    puts "  2. Use 100% free Google Trends (No key needed!): #{Color.c("gsc trends \"#{target}\"", Color::BLUE, Color::BOLD)}"
    puts "  3. Use 500 free daily web lookups: Copy web table -> #{Color.c('gsc import clip', Color::GREEN, Color::BOLD)}\n"
  end
  return
end

  # Determine keyword list
  keywords_to_check = []
  is_file = File.exist?(target) || target.end_with?('.csv', '.tsv', '.txt')
  if is_file
    if File.exist?(target)
      content = File.read(target, encoding: 'UTF-8') rescue ''
      keywords_to_check = content.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
    else
      puts Color.c("❌ File not found: #{target}", Color::RED)
      return
    end
  else
    # Autocomplete expansion
    suggestions = KeywordPlanner.expand(target, country: country, limit: [limit, 50].min)
    keywords_to_check = ([target] + suggestions).uniq
  end

  keywords_to_check = keywords_to_check.first([limit, 100].max)

  puts "⏳ Fetching volume & CPC data from Keywords Everywhere API..." unless options[:json]

  # Fetch from Keywords Everywhere API
res = KeywordsEverywhere.fetch_data(keywords_to_check, country: country, currency: currency)
unless res[:ok]
  err_str = res[:error].to_s
  if options[:json]
    reason = if err_str =~ /402|Insufficient Credits/i
               'insufficient_credits'
             elsif err_str =~ /401|Unauthorized/i
               'unauthorized'
             elsif err_str =~ /429|Rate Limit/i
               'rate_limited'
             else
               'api_error'
             end
    puts JSON.pretty_generate({
      ok: false,
      error: err_str,
      reason: reason,
      recommendations: [
        { action: 'import_clipboard', cmd: 'gsc import clip', desc: 'Use 500 free daily web lookups on keywordseverywhere.com and import via clipboard' },
        { action: 'google_trends', cmd: "gsc trends \"#{target}\"", desc: '100% Free real-time search interest & rising breakout queries' },
        { action: 'gsc_analytics', cmd: 'gsc top-queries', desc: 'Real impressions & clicks from your active Google Search Console domain' },
        { action: 'topup', url: 'https://keywordseverywhere.com/credit-packages.html', desc: 'Purchase API credits to enable automated background CLI lookups' }
      ]
    })
    return
  end

  if err_str =~ /402|Insufficient Credits/i
    puts Color.c("\n💳 Keywords Everywhere: Insufficient API Credits (0 remaining)\n", Color::YELLOW, Color::BOLD)
    puts "Your API key is active, but Keywords Everywhere's REST API requires paid credits."
    puts "The 500 free lookups/day are available on their website.\n\n"
    puts "#{Color::BOLD}🚀 4 RECOMMENDED ALTERNATIVES (START RIGHT NOW):#{Color::RESET}\n"
    puts "  1. #{Color.c('Free 500 Lookups / Day on Web + 1-Click Clipboard Import', Color::GREEN, Color::BOLD)}"
    puts "     • Go to: #{Color.c('https://keywordseverywhere.com/tools/bulk-keywords-data', Color::UNDERLINE)}"
    puts "     • Enter keywords -> Click #{Color.c('Check Volume', Color::BOLD)} -> Click #{Color.c('Copy', Color::CYAN)}"
    puts "     • In your terminal, run:"
    puts "       #{Color.c('gsc import clip', Color::CYAN, Color::BOLD)}\n"
    puts "  2. #{Color.c('Google Trends Intelligence (100% Free, Zero Setup)', Color::BLUE, Color::BOLD)}"
    puts "     • Live interest curves, breakout queries, and seasonal demand:"
    puts "       #{Color.c("gsc trends \"#{target}\"", Color::BLUE, Color::BOLD)}\n"
    puts "  3. #{Color.c('Your Real Search Console Rankings & Opportunities', Color::MAGENTA, Color::BOLD)}"
    puts "     • High-impression queries and Page 2 striking-distance keywords:"
    puts "       #{Color.c('gsc top-queries', Color::MAGENTA, Color::BOLD)}  or  #{Color.c('gsc opportunities', Color::MAGENTA, Color::BOLD)}\n"
    puts "  4. #{Color.c('Top Up API Credits for Automated Background CLI Lookups', Color::GRAY, Color::BOLD)}"
    puts "     • Purchase credits at: #{Color.c('https://keywordseverywhere.com/credit-packages.html', Color::UNDERLINE)}"
    puts "     • Your key is already saved; it will work immediately once credited.\n"
  elsif err_str =~ /401|Unauthorized/i
    puts Color.c("\n🔑 Invalid or Expired Keywords Everywhere API Key", Color::RED, Color::BOLD)
    puts "Your API key was rejected by api.keywordseverywhere.com (HTTP 401).\n\n"
    puts "#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
    puts "  • Check or generate your API key at: #{Color.c('https://keywordseverywhere.com/first-install-addon.html', Color::UNDERLINE)}"
    puts "  • Reconnect key: #{Color.c('gsc connect ke <KEY>', Color::CYAN, Color::BOLD)}"
    puts "  • Or use free Google Trends without any key: #{Color.c("gsc trends \"#{target}\"", Color::BLUE)}"
  elsif err_str =~ /429|Rate Limit/i
    puts Color.c("\n⏳ Keywords Everywhere Rate Limit Exceeded", Color::YELLOW, Color::BOLD)
    puts "Too many requests were sent in a short period.\n\n"
    puts "#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
    puts "  • Wait 15-30 seconds and retry: #{Color.c("gsc ke \"#{target}\"", Color::CYAN)}"
    puts "  • Reduce batch size with: #{Color.c("gsc ke \"#{target}\" --limit 10", Color::CYAN)}"
  else
    puts Color.c("\n❌ Keywords Everywhere API Error: #{err_str}", Color::RED)
    puts "\n#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
    puts "  • Try free Google Trends instead: #{Color.c("gsc trends \"#{target}\"", Color::BLUE)}"
    puts "  • Or check account status with: #{Color.c('gsc ke-credits', Color::CYAN)}"
  end
  return
end

  items = res[:data]

  # Optional GSC correlation if site configured
  site_url = options[:site] || Config.default_domain
  has_gsc = false
  if site_url && Auth.find_key(options[:key])
    begin
      auth = Auth.new(Auth.find_key(options[:key]))
      api = API.new(auth.token)
      items = KeywordPlanner.correlate_with_gsc(items, api, site_url, days: options[:days] || 30)
      has_gsc = true
    rescue StandardError
      # Non-fatal
    end
  end

  # Sort by opportunity score descending, then volume
  items.sort_by! { |i| [-i[:opportunity_score].to_i, -i[:volume].to_i] }
  items = items.first(limit)

  if options[:json]
    puts JSON.pretty_generate({
      seed: target,
      provider: 'keywordseverywhere',
      country: country,
      currency: currency,
      count: items.size,
      siteUrl: site_url,
      keywords: items
    })
    return
  end

  # Terminal Table
  puts "\n#{Color::BOLD}🔍 KEYWORDS EVERYWHERE SEARCH DEMAND#{Color::RESET} (Seed: #{Color.c(target, Color::CYAN)})"
  puts "   Country: #{country.upcase} · Provider: Google Keyword Planner via Keywords Everywhere API"
  puts "   Correlated with GSC: #{has_gsc ? Color.c(site_url, Color::GREEN) : Color.c('None', Color::GRAY)}\n\n"

  printf "  %-34s %10s %8s %7s %10s  %-14s %s\n",
         "KEYWORD", "VOL/MO", "CPC", "COMP", "OPP SCORE", "INTENT", (has_gsc ? "GSC RANK STATUS" : "")
  puts "  " + ("─" * (has_gsc ? 110 : 85))

  items.each do |item|
    opp = item[:opportunity_score]
    opp_color = opp >= 70 ? Color::GREEN : (opp >= 45 ? Color::YELLOW : Color::GRAY)
    
    cpc_str = format("$%.2f", item[:cpc])
    vol_str = item[:volume] > 0 ? item[:volume].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse : '-'
    comp_str = format("%.2f", item[:competition])

    intent_color = case item[:intent]
                   when 'Transactional' then Color::GREEN
                   when 'Commercial'    then Color::CYAN
                   when 'Informational' then Color::MAGENTA
                   else                      Color::GRAY
                   end

    gsc_col = if has_gsc && item[:gsc]
                item[:gsc][:status]
              else
                ""
              end

    printf "  %-34s %10s %8s %7s   %s  %-14s %s\n",
           Color.c(item[:keyword].to_s[0..33], Color::BOLD),
           vol_str,
           cpc_str,
           comp_str,
           Color.c(format("%3d/100", opp), opp_color, Color::BOLD),
           Color.c(item[:intent], intent_color),
           gsc_col
  end

  puts "  " + ("─" * (has_gsc ? 110 : 85))
  puts "  💡 #{Color::BOLD}Opportunity Score (0-100):#{Color::RESET} High search volume + low ad competition index."
  puts
end


def self.handle_planner_expand_command(seed, options)
  if seed.nil? || seed.strip.empty?
    if options[:json]
      puts JSON.pretty_generate({ error: 'Please specify a seed keyword (e.g. gsc planner "moving boxes")' })
    else
      puts Color.c("❌ Error: Please specify a seed keyword.", Color::RED)
      puts "   Usage: #{Color.c('gsc planner "moving boxes"', Color::CYAN)}"
    end
    return
  end

  puts BANNER unless options[:json] || options[:in_dashboard]
  country = options[:country] || 'us'
  limit = options[:limit] || 40
  puts "💡 Expanding keyword ideas for seed: #{Color.c(seed, Color::CYAN)} (Country: #{country})...\n" unless options[:json]

  raw_keywords = KeywordPlanner.expand(seed, country: country, limit: limit)

  # Attempt GSC correlation
  api = nil
  site_url = nil
  begin
    key_path = Auth.find_key(options[:key])
    if key_path
      service_account = JSON.parse(File.read(key_path))
      token = Auth.fetch_access_token(service_account)
      client = Client.new(token: token)
      api = API.new(client)
      hostname, site_url, _ = resolve_domain(options[:domain], nil, options)
      puts "🔗 Cross-referencing against Google Search Console: #{Color.c(site_url, Color::CYAN)}...\n" unless options[:json]
    end
  rescue StandardError
  end

  keywords = KeywordPlanner.correlate_with_gsc(raw_keywords, api, site_url, days: options[:days] || 30)

  if options[:json]
    puts JSON.pretty_generate({
      seed: seed,
      country: country,
      siteUrl: site_url,
      count: keywords.size,
      suggestions: keywords
    })
    return
  end

  puts "#{Color::BOLD}Intent        | GSC Status                  | Keyword Suggestion#{Color::RESET}"
  puts "--------------------------------------------------------------------------------------------------"
  keywords.each do |r|
    intent_color = case r[:intent]
                   when 'Commercial' then Color::YELLOW
                   when 'Transactional' then Color::GREEN
                   when 'Informational' then Color::CYAN
                   else Color::GRAY
                   end
    intent_str = Color.c(r[:intent].ljust(13), intent_color)
    gsc_status = r.dig(:gsc, :status) || '🚀 Untargeted'
    gsc_str = gsc_status.ljust(27)
    kw_str = Color.c(r[:keyword], Color::BOLD)

    puts "#{intent_str} | #{gsc_str} | #{kw_str}"
  end
  puts ""
  puts Color.c("Total Keyword Ideas Generated: #{keywords.size}", Color::GRAY)
  puts ""
end


    def self.print_version_info(options)
      if options[:json]
        puts JSON.pretty_generate({
          name: 'gsc',
          version: VERSION,
          ruby: RUBY_VERSION,
          platform: RUBY_PLATFORM,
          executable: File.expand_path($PROGRAM_NAME),
          configFile: Config::CONFIG_FILE
        })
      else
        puts "#{Color::BOLD}gsc#{Color::RESET} version #{Color.c(VERSION, Color::GREEN, Color::BOLD)} (Ruby #{RUBY_VERSION} #{RUBY_PLATFORM})"
        puts "   Executable: #{File.expand_path($PROGRAM_NAME)}"
        puts "   Config:     #{Config::CONFIG_FILE}"
      end
    end

    def self.handle_update_command(options)
      repo_url = Config.load['update_url'] || ENV['GSC_UPDATE_URL'] || DEFAULT_UPDATE_URL

      uri = URI(repo_url)
      raise "Security Error: Update URL must use HTTPS: #{repo_url}" unless uri.scheme == 'https'

      puts "🔄 Checking for updates from: #{Color.c(repo_url, Color::CYAN)}..." unless options[:json]

      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 6
        http.read_timeout = 10

        req = Net::HTTP::Get.new(uri.request_uri)
        req['User-Agent'] = "gsc-cli/#{VERSION}"
        res = http.request(req)

        if res.code != '200'
          raise "Could not fetch update from #{repo_url} (HTTP #{res.code})"
        end

        remote_script = res.body
        remote_version = remote_script[/VERSION\s*=\s*['"]([^'"]+)['"]/, 1] || 'unknown'

        if remote_version == VERSION
          if options[:json]
            puts JSON.pretty_generate({ status: 'up-to-date', currentVersion: VERSION })
          else
            puts Color.c("✨ You are already running the latest version of gsc (#{VERSION})!", Color::GREEN, Color::BOLD)
          end
          return
        end

        # Validate syntax of downloaded script
        require 'tempfile'
        temp = Tempfile.new(['gsc-update', '.rb'])
        temp.write(remote_script)
        temp.close

        syntax_ok = system('ruby', '-c', temp.path, out: File::NULL, err: File::NULL)
        unless syntax_ok
          temp.unlink
          raise "Downloaded script failed Ruby syntax verification."
        end

        target_bin = File.expand_path($PROGRAM_NAME)
        dest_paths = [target_bin]
        default_local = File.expand_path('~/.local/bin/gsc')
        dest_paths << default_local if File.exist?(default_local) && !dest_paths.include?(default_local)

        dest_paths.each do |path|
          File.write(path, remote_script)
          File.chmod(0755, path)
        end
        temp.unlink

        if options[:json]
          puts JSON.pretty_generate({ status: 'updated', from: VERSION, to: remote_version, paths: dest_paths })
        else
          puts Color.c("🎉 Successfully updated gsc from v#{VERSION} to v#{remote_version}!", Color::GREEN, Color::BOLD)
          puts "   Updated binary: #{dest_paths.join(', ')}"
        end
      rescue StandardError => e
        if options[:json]
          puts JSON.pretty_generate({ error: e.message })
        else
          puts Color.c("❌ Update failed: #{e.message}", Color::RED)
          puts "💡 To change update URL, run: #{Color.c('gsc config set-update-url <url>', Color::CYAN)}"
        end
        exit 1
      end
    end

    
def self.copy_to_clipboard(text)
  if RUBY_PLATFORM =~ /darwin/i
    IO.popen("pbcopy", "w") { |io| io.write(text) }
    true
  elsif system("which xclip > /dev/null 2>&1")
    IO.popen("xclip -selection clipboard", "w") { |io| io.write(text) }
    true
  elsif system("which wl-copy > /dev/null 2>&1")
    IO.popen("wl-copy", "w") { |io| io.write(text) }
    true
  else
    false
  end
rescue StandardError
  false
end

def self.handle_prompts_command(target, extra, options = {})
  domain = options[:domain] || Config.default_domain || 'example.com'

  # JSON mode: either full catalog or single rendered prompt
  if options[:json]
    if target && (target =~ /^\d+$/ || ['master', 'mega', 'all'].include?(target.downcase))
      item = Prompts.find(target.to_i)
      if item
        rendered = Prompts.render_prompt(item[:id], domain: domain, seed: options[:seed], url: options[:url])
        puts JSON.pretty_generate(item.merge(rendered_prompt: rendered, activeDomain: domain))
      else
        puts JSON.pretty_generate({ error: "Playbook ##{target} not found" })
      end
    else
      list = Prompts.all.map do |p|
        p.merge(rendered_prompt: Prompts.render_prompt(p[:id], domain: domain, seed: options[:seed], url: options[:url]))
      end
      puts JSON.pretty_generate({
        playbookCount: list.size,
        activeDomain: domain,
        playbooks: list
      })
    end
    return
  end

  # If a specific ID was passed: e.g. `gsc prompt 1`
if target && (target =~ /^\d+$/ || ['master', 'mega', 'all'].include?(target.downcase))
  target_id = target =~ /^\d+$/ ? target.to_i : 0
  show_playbook_detail(target_id, domain, options)
  return
end

  # Interactive Playbook Explorer
  loop do
    puts BANNER unless options[:in_dashboard]
    puts "#{Color::BOLD}🤖 26 AUTONOMOUS AI SEO PLAYBOOKS & PROMPTS#{Color::RESET} (Domain: #{Color.c(domain, Color::CYAN)})"
    puts "   Select any playbook to inspect, copy to clipboard, or run directly.\n"

    current_cat = nil
    Prompts.all.each do |p|
      if p[:category] != current_cat
        current_cat = p[:category]
        puts "\n" + Color.c(p[:category_name], Color::BOLD, Color::MAGENTA)
      end
      id_str = Color.c("[#{p[:id].to_s.rjust(2)}]", Color::CYAN, Color::BOLD)
      title_str = p[:title].ljust(44)
      impact_str = Color.c(p[:impact], Color::GRAY)
      puts "  #{id_str} #{title_str} #{impact_str}"
    end

    puts "\n" + ("─" * 70)
    print "\nEnter Playbook # (0-25), search term, or 'q' to exit: "
    input = $stdin.gets&.strip
    break if input.nil? || input.empty? || ['q', 'exit', 'quit'].include?(input.downcase)

    if input =~ /^\d+$/
      choice = input.to_i
      item = Prompts.find(choice)
      if item
        action = show_playbook_detail(choice, domain, options)
        break if action == :exit
      else
        puts Color.c("❌ Invalid choice. Please choose 0-#{Prompts.all.size - 1}", Color::RED)
      end
    else
      # Search term
      matches = Prompts.all.select do |p|
        p[:title].downcase.include?(input.downcase) ||
        p[:category].downcase.include?(input.downcase) ||
        p[:template].downcase.include?(input.downcase)
      end
      if matches.empty?
        puts Color.c("\n❌ No playbooks matched '#{input}'.", Color::YELLOW)
        sleep 1.2
      else
        puts "\n" + Color.c("🔍 Search Results for '#{input}':", Color::GREEN, Color::BOLD)
        matches.each do |p|
          puts "  #{Color.c("[#{p[:id].to_s.rjust(2)}]", Color::CYAN, Color::BOLD)} #{p[:title].ljust(44)} #{Color.c(p[:impact], Color::GRAY)}"
        end
        print "\nEnter Playbook # to view (or Enter to go back): "
        sub_choice = $stdin.gets&.strip
        if sub_choice =~ /^\d+$/
          show_playbook_detail(sub_choice.to_i, domain, options)
        end
      end
    end
  end
end

def self.show_playbook_detail(id, domain, options = {})
  item = Prompts.find(id)
  unless item
    puts Color.c("❌ Playbook ##{id} not found.", Color::RED)
    return
  end

  rendered = Prompts.render_prompt(id, domain: domain, seed: options[:seed], url: options[:url])

  puts "\n" + ("═" * 70)
  puts "#{Color::BOLD}📋 PLAYBOOK ##{item[:id]}: #{item[:title].upcase}#{Color::RESET}"
  puts "   Category: #{item[:category_name]} · #{Color.c(item[:impact], Color::GREEN)}"
  puts "   Underlying CLI Command: #{Color.c(item[:cli_command], Color::CYAN)}"
  puts ("─" * 70)
  puts "\n#{Color::BOLD}🤖 READY-TO-PASTE PROMPT FOR ANTIGRAVITY / CLAUDE / CHATGPT:#{Color::RESET}\n\n"
  puts Color.c(rendered, Color::YELLOW)
  puts "\n" + ("─" * 70)

  # Auto-copy if --copy requested
  if options[:copy]
    copied = copy_to_clipboard(rendered)
    if copied
      puts Color.c("📋 Copied to clipboard automatically!", Color::GREEN, Color::BOLD)
      return
    end
  end

  print "\n[c] Copy to Clipboard | [r] Run CLI Command Now | [Enter] Back: "
  sub = $stdin.gets&.strip&.downcase
  case sub
  when 'c', 'copy'
    copied = copy_to_clipboard(rendered)
    if copied
      puts Color.c("\n✅ Copied prompt to clipboard! Paste it into Antigravity or Claude.\n", Color::GREEN, Color::BOLD)
    else
      puts Color.c("\n❌ Clipboard tool not available.\n", Color::RED)
    end
    print "Press Enter to continue..."
    $stdin.gets
  when 'r', 'run'
    cmd_to_run = item[:cli_command].sub(/ --json$/, '')
    puts "\n🚀 Running: #{Color.c(cmd_to_run, Color::CYAN, Color::BOLD)}...\n\n"
    system("gsc #{cmd_to_run.sub(/^gsc /, '')}")
    print "\nPress Enter to continue..."
    $stdin.gets
  when 'q', 'quit', 'exit'
    return :exit
  end
end


def self.handle_page_audit_command(target, site_url, api, options = {})
  url_or_path = target || "https://#{Config.default_domain || 'example.com'}"
  puts BANNER unless options[:json] || options[:in_dashboard]

  analyzer = PageAnalyzer.new(url_or_path)
  puts "🔍 Auditing On-Page DOM & GSC Performance for: #{Color.c(url_or_path, Color::CYAN)}...\n" unless options[:json]

  data = analyzer.fetch_and_analyze(
    check_links: options[:check_links] || false,
    gsc_api: api,
    active_domain: site_url
  )

  if options[:json]
    puts JSON.pretty_generate(data)
    return
  end

  # 1. URL & Status Header
  status_color = data[:http_status] == 200 ? Color::GREEN : Color::YELLOW
  puts "📍 URL:           #{Color.c(data[:url], Color::CYAN, Color::BOLD)}"
  puts "⚡ HTTP Status:   #{Color.c(data[:http_status].to_s, status_color, Color::BOLD)} (#{data[:response_time_ms]}ms) | Indexability: #{Color.c(data[:indexability][:status], data[:indexability][:status] == 'INDEXABLE' ? Color::GREEN : Color::RED, Color::BOLD)}"
  puts "─" * 80

  # 2. On-Page Overview
  title = data[:title]
  t_color = title[:ok] ? Color::GREEN : Color::YELLOW
  puts "\n#{Color::BOLD}📑 ON-PAGE METADATA (Detailed SEO Engine):#{Color::RESET}"
  puts "   Title:         #{Color.c(title[:text].empty? ? '(Missing)' : title[:text], Color::BOLD)} [#{Color.c("#{title[:length]} chars / ~#{title[:pixel_est]}px", t_color)}]"
  meta = data[:meta_description]
  m_color = meta[:ok] ? Color::GREEN : Color::YELLOW
  puts "   Meta Desc:     #{meta[:text].empty? ? Color.c('(Missing)', Color::YELLOW) : meta[:text]} [#{Color.c("#{meta[:length]} chars", m_color)}]"
  canon = data[:canonical]
  canon_str = canon[:url] ? (canon[:self_referencing] ? "#{canon[:url]} (Self-Referencing ✅)" : "#{canon[:url]} (Canonicalised ⚠️)") : '(None)'
  puts "   Canonical:     #{canon_str}"
  puts "   Word Count:    #{data[:stats][:word_count]} words (~#{data[:stats][:reading_time_mins]} min read)"

  # 3. Headings Tree
  h = data[:headings]
  h_badge = h[:h1_count] == 1 ? Color.c("1x H1 ✅", Color::GREEN) : Color.c("#{h[:h1_count]}x H1 ⚠️", Color::RED)
  puts "\n#{Color::BOLD}🏷️ HEADINGS HIERARCHY (#{h[:count]} total, #{h_badge}):#{Color::RESET}"
  h[:list].first(8).each do |heading|
    indent = "   " + ("  " * (heading[:tag][1].to_i - 1))
    tag_badge = Color.c("[#{heading[:tag].upcase}]", Color::MAGENTA)
    puts "#{indent}#{tag_badge} #{heading[:text]}"
  end
  puts "   ... and #{h[:count] - 8} more headings" if h[:count] > 8

  # 4. Images & Links
  img = data[:images]
  img_color = img[:missing_alt_count] == 0 ? Color::GREEN : Color::YELLOW
  puts "\n#{Color::BOLD}🖼️ IMAGES & LINKS:#{Color::RESET}"
  puts "   Images:        #{img[:total]} total (#{Color.c("#{img[:missing_alt_count]} missing alt tags", img_color)})"
  if img[:missing_alt_count] > 0
    img[:missing_alt_images].first(3).each do |i|
      puts "                  ⚠️ Missing Alt: #{Color.c(i[:src].to_s[0..60], Color::GRAY)}"
    end
  end
  lnk = data[:links]
  puts "   Links:         #{lnk[:total]} total (#{lnk[:internal_count]} Internal, #{lnk[:external_count]} External, #{lnk[:nofollow_count]} Nofollow)"
  if data.dig(:links, :verification)
    broken = data[:links][:verification].reject { |l| l[:ok] }
    if broken.empty?
      puts "   Link Health:   #{Color.c('All verified links OK (HTTP 200) ✅', Color::GREEN)}"
    else
      puts "   Broken Links:  #{Color.c("#{broken.size} dead links found 🔴", Color::RED, Color::BOLD)}"
      broken.each do |b|
        puts "                  ❌ [HTTP #{b[:status]}] #{b[:href]} (Anchor: #{b[:anchor]})"
      end
    end
  elsif !options[:check_links]
    puts "   Link Health:   #{Color.c('(Pass --check-links to test HTTP status of every link)', Color::GRAY)}"
  end

  # 5. Schema Structured Data
  s_list = data[:schema]
  puts "\n#{Color::BOLD}💎 STRUCTURED DATA (Schema.org JSON-LD):#{Color::RESET}"
  if s_list.empty?
    puts "   #{Color.c('No JSON-LD schema found on this page.', Color::YELLOW)}"
  else
    types = s_list.flat_map { |s| s[:types] }.compact.uniq
    puts "   Detected Schemas: #{Color.c(types.join(', '), Color::GREEN, Color::BOLD)}"
  end

  # 6. Off-Page GSC Performance
  if data[:gsc]
    g = data[:gsc]
    puts "\n#{Color::BOLD}📊 GOOGLE SEARCH CONSOLE PERFORMANCE (Past 90 Days):#{Color::RESET}"
    puts "   Total Clicks:       #{Color.c(g[:total_clicks].to_s, Color::CYAN, Color::BOLD)}"
    puts "   Total Impressions:  #{Color.c(g[:total_impressions].to_s, Color::CYAN, Color::BOLD)}"
    puts "   Average CTR:        #{Color.c("#{g[:ctr]}%", Color::CYAN, Color::BOLD)}"
    puts "   Average Position:   #{Color.c(g[:avg_position].to_s, Color::CYAN, Color::BOLD)}"
    if g[:top_queries] && !g[:top_queries].empty?
      puts "   Top Ranking Queries:"
      g[:top_queries].each do |q|
        puts "     • #{Color.c(q[:query], Color::YELLOW)} (Pos #{q[:position]}, #{q[:impressions]} imp, #{q[:clicks]} clicks)"
      end
    end
  end

  # 7. Actionable Issues Checklist
  puts "\n" + ("─" * 80)
  if data[:issues].empty?
    puts Color.c("✅ EXCELLENT! No SEO defects or hierarchy flaws detected.", Color::GREEN, Color::BOLD)
  else
    puts "#{Color::BOLD}⚠️ ACTIONABLE ISSUES FOUND (#{data[:issues].size}):#{Color::RESET}"
    data[:issues].each do |issue|
      badge = issue[:level] == :error || issue[:level] == :critical ? Color.c("[ERROR]", Color::RED, Color::BOLD) : Color.c("[WARN]", Color::YELLOW, Color::BOLD)
      puts "   #{badge} #{issue[:message]}"
    end
  end
  puts ("─" * 80) + "\n"
end

def self.handle_site_crawl_command(target, site_url, api, options = {})
  sitemap_target = target || "https://#{Config.default_domain || 'example.com'}/sitemap.xml"
  puts BANNER unless options[:json] || options[:in_dashboard]
  puts "🕷️ Starting Comprehensive Site Audit & Broken Link Crawler..." unless options[:json]
  puts "   Target: #{Color.c(sitemap_target, Color::CYAN)}" unless options[:json]
  puts "   Link Verification: #{options[:check_links] ? Color.c('Enabled (testing all links)', Color::GREEN) : Color.c('Disabled (use --check-links to verify)', Color::GRAY)}" unless options[:json]
  puts "" unless options[:json]

  crawler = SiteCrawler.new(sitemap_target, options.merge(gsc_api: api, active_domain: site_url))

  summary = crawler.run do |url, current, total|
    unless options[:json]
      print "\r\e[K⏳ [#{current}/#{total}] Crawling & auditing: #{Color.c(url[0..60], Color::CYAN)}"
      $stdout.flush
    end
  end

  puts "\n" unless options[:json]

  # If --report requested
  if options[:report]
    report_file = crawler.generate_markdown_report(options[:report])
    puts Color.c("📝 Exported Comprehensive Markdown Audit Report to: #{report_file}\n", Color::GREEN, Color::BOLD) unless options[:json]
  end

  if options[:json]
    puts JSON.pretty_generate({
      summary: summary,
      broken_links: crawler.broken_links,
      missing_alts: crawler.missing_alts,
      heading_issues: crawler.heading_issues,
      title_issues: crawler.title_issues,
      canonical_issues: crawler.canonical_issues,
      results: crawler.results
    })
    return
  end

  # Print Summary Table
  puts ("═" * 80)
  puts "#{Color::BOLD}📊 SITE AUDIT SUMMARY REPORT#{Color::RESET}"
  puts ("─" * 80)
  puts "  Pages Audited:           #{Color.c(summary[:total_pages].to_s, Color::BOLD)}"
  puts "  Total Issues Detected:   #{Color.c(summary[:total_issues].to_s, summary[:total_issues] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
  puts "  Broken Links (404/500):  #{Color.c(summary[:broken_links_count].to_s, summary[:broken_links_count] == 0 ? Color::GREEN : Color::RED, Color::BOLD)}"
  puts "  Images Missing Alt:      #{Color.c(summary[:missing_alts_count].to_s, summary[:missing_alts_count] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
  puts "  H1 Heading Flaws:        #{Color.c(summary[:heading_issues_count].to_s, summary[:heading_issues_count] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
  puts "  Title/Meta Flaws:        #{Color.c(summary[:title_meta_issues_count].to_s, summary[:title_meta_issues_count] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
  puts ("═" * 80)

  if summary[:broken_links_count] > 0
    puts "\n#{Color::BOLD}🚨 BROKEN LINKS DETECTED:#{Color::RESET}"
    crawler.broken_links.first(10).each do |b|
      puts "  ❌ [HTTP #{b[:status]}] #{b[:href]}"
      puts "     Found on: #{Color.c(b[:source_page], Color::GRAY)}"
    end
  end

  if summary[:missing_alts_count] > 0
    puts "\n#{Color::BOLD}🖼️ TOP IMAGES MISSING ALT ATTRIBUTES:#{Color::RESET}"
    crawler.missing_alts.first(5).each do |img|
      puts "  ⚠️ #{Color.c(img[:src], Color::YELLOW)} (on #{img[:page_url]})"
    end
  end

  puts "\n💡 Run with #{Color.c('--report docs/seo/site_audit.md', Color::CYAN)} to generate full AI-actionable Markdown report." unless options[:report]
  puts ""
end

def self.handle_skills_command(subcommand, options)
      gemini_dir  = File.expand_path('~/.gemini/config/skills/gsc')
      gemini_path = File.join(gemini_dir, 'SKILL.md')

      claude_dir  = File.expand_path('~/.claude/skills/gsc')
      claude_path = File.join(claude_dir, 'SKILL.md')

      local_dir   = File.expand_path('.agents/skills/gsc')
      local_path  = File.join(local_dir, 'SKILL.md')

      case subcommand
      when 'install', 'setup', 'update'
        installed = []

        # 1. Google Antigravity / Gemini
        if Dir.exist?(File.expand_path('~/.gemini')) || (!Dir.exist?(File.expand_path('~/.claude')) && !options[:local])
          FileUtils.mkdir_p(gemini_dir)
          File.write(gemini_path, SKILL_MD_CONTENT)
          installed << { platform: 'Antigravity / Gemini', path: gemini_path }
        end

        # 2. Claude Code
        if Dir.exist?(File.expand_path('~/.claude'))
          FileUtils.mkdir_p(claude_dir)
          File.write(claude_path, SKILL_MD_CONTENT)
          installed << { platform: 'Claude Code', path: claude_path }
        end

        # 3. Universal Workspace (.agents/skills/gsc)
        if options[:local] || Dir.exist?(File.expand_path('.agents'))
          FileUtils.mkdir_p(local_dir)
          File.write(local_path, SKILL_MD_CONTENT)
          installed << { platform: 'Universal Workspace (.agents)', path: local_path }
        end

        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', installed: installed })
        else
          puts BANNER
          puts Color.c("✅ Agent Skill installed successfully across detected platforms:", Color::GREEN, Color::BOLD)
          installed.each do |inst|
            puts "   • #{Color.c(inst[:platform], Color::BOLD)}: #{Color.c(inst[:path], Color::CYAN)}"
          end
          puts "\nAI agents will now automatically detect and trigger GSC commands for SEO and indexing tasks."
          puts
        end
      when 'show', 'cat', 'raw'
        puts SKILL_MD_CONTENT
      else
        installed = []
        installed << { platform: 'Antigravity / Gemini', path: gemini_path } if File.exist?(gemini_path)
        installed << { platform: 'Claude Code', path: claude_path } if File.exist?(claude_path)
        installed << { platform: 'Universal Workspace (.agents)', path: local_path } if File.exist?(local_path)

        if options[:json]
          puts JSON.pretty_generate({
            skill: 'gsc',
            installed: !installed.empty?,
            locations: installed,
            description: 'Automates Google Search Console, Google Indexing API, live URL index inspection, sitemap batch submission, and search ranking analytics.'
          })
          return
        end

        puts BANNER
        puts "#{Color::BOLD}🤖 GSC AI AGENT SKILL (Platform-Agnostic):#{Color::RESET}"
        if installed.empty?
          puts "   Status:   #{Color.c('⚠️ Not currently installed', Color::YELLOW, Color::BOLD)}"
          puts "   Install:  Run #{Color.c('gsc skills install', Color::CYAN)} to auto-detect and install for your agent."
        else
          puts "   Status:   #{Color.c('✅ Installed and active', Color::GREEN, Color::BOLD)}"
          installed.each do |inst|
            puts "   • #{inst[:platform]}: #{Color.c(inst[:path], Color::CYAN)}"
          end
        end
        puts
        puts "#{Color::BOLD}Agent Features & Capabilities:#{Color::RESET}"
        puts "   • #{Color.c('gsc top-queries --json', Color::CYAN)}      - Query real SERP rankings, impressions, and CTR"
        puts "   • #{Color.c('gsc inspect <url> --json', Color::CYAN)}    - Live index status & Googlebot crawl verdict"
        puts "   • #{Color.c('gsc index <url> --json', Color::CYAN)}      - Instant Googlebot re-crawl notification"
        puts "   • #{Color.c('gsc audit --json', Color::CYAN)}            - Automated 4-step SEO & indexing health audit"
        puts "   • #{Color.c('gsc domains --json', Color::CYAN)}          - List verified properties & active domain"
        puts
        puts "#{Color::BOLD}Available subcommands:#{Color::RESET}"
        puts "   #{Color.c('gsc skills', Color::CYAN)}                    Display skill status across agent platforms"
        puts "   #{Color.c('gsc skills install', Color::CYAN)}            Auto-install to ~/.gemini, ~/.claude, and .agents"
        puts "   #{Color.c('gsc skills show', Color::CYAN)}               Print raw SKILL.md markdown for any agent"
        puts
      end
    end

    def self.print_where_info(options)
      key_path = Auth.find_key(options[:key])
      sa = key_path ? (JSON.parse(File.read(key_path)) rescue {}) : {}

      if options[:json]
        puts JSON.pretty_generate({
          executable: File.expand_path($PROGRAM_NAME),
          configDirectory: Config::CONFIG_DIR,
          configFile: Config::CONFIG_FILE,
          activeKey: key_path,
          serviceAccount: sa['client_email'],
          activeDomain: Config.default_domain
        })
        return
      end

      puts BANNER
      puts "#{Color::BOLD}📍 GSC CLI INSTALLATION & ENVIRONMENT:#{Color::RESET}"
      puts "   Executable:       #{Color.c(File.expand_path($PROGRAM_NAME), Color::CYAN)}"
      puts "   Config Directory: #{Color.c(Config::CONFIG_DIR, Color::CYAN)}"
      puts "   Config File:      #{Color.c(Config::CONFIG_FILE, Color::CYAN)}"
      if key_path
        puts "   Active Key:       #{Color.c(key_path, Color::GREEN)} (#{sa['client_email']})"
      else
        puts "   Active Key:       #{Color.c('None found (run: gsc connect)', Color::YELLOW)}"
      end
      active_dom = Config.default_domain
      puts "   Active Domain:    #{active_dom ? Color.c(active_dom, Color::GREEN, Color::BOLD) : Color.c('(none - run: gsc use <domain>)', Color::GRAY)}"
      puts
    end

    def self.fetch_available_domains
      domains = []
      key_path = Auth.find_key
      if key_path && File.exist?(key_path)
        begin
          sa = JSON.parse(File.read(key_path))
          token = Auth.fetch_access_token(sa)
          client = Client.new(token: token)
          api = API.new(client)
          res = api.list_sites
          if res[:ok]
            (res.dig(:data, 'siteEntry') || []).each do |s|
              clean = s['siteUrl'].sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')
              domains << clean unless domains.include?(clean)
            end
          end
        rescue StandardError
          # fallback to config
        end
      end

      Config.ga4_properties.keys.each do |d|
        domains << d unless domains.include?(d)
      end

      domains.sort
    end

    def self.handle_use_command(domain_arg, options)
      domains = fetch_available_domains
      active = Config.default_domain

      if domain_arg.nil? || domain_arg.empty?
        if options[:json]
          puts JSON.pretty_generate({ activeDomain: active, availableDomains: domains })
          return
        end

        puts BANNER
        if active
          puts "Current active domain is: #{Color.c(active, Color::GREEN, Color::BOLD)}\n\n"
        else
          puts Color.c("No active domain is currently set.\n\n", Color::YELLOW)
        end

        if domains.empty?
          puts "No domains configured or accessible yet."
          puts "Usage: gsc use <domain>"
          return
        end

        puts "#{Color::BOLD} #  | Domain                       | GA4 Link Status#{Color::RESET}"
        puts "------------------------------------------------------------------"
        domains.each_with_index do |dom, idx|
          num_str = Color.c("[#{idx + 1}]".ljust(4), Color::CYAN, Color::BOLD)
          ga4_id = Config.ga4_property_id(dom)
          ga4_str = ga4_id ? Color.c("[GA4: #{ga4_id}]", Color::MAGENTA) : Color.c("[GA4: Not linked]", Color::GRAY)
          suffix = (dom == active) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""
          puts "#{num_str}| #{dom.ljust(28)} | #{ga4_str}#{suffix}"
        end
        puts "------------------------------------------------------------------"

        if $stdin.tty?
          print "\nSelect domain number (1-#{domains.size}) to switch active, or press Enter to keep current: "
          choice = $stdin.gets&.strip
          if choice && choice =~ /^\d+$/
            num = choice.to_i
            if num >= 1 && num <= domains.size
              domain_arg = domains[num - 1]
            else
              puts Color.c("Invalid selection.", Color::YELLOW)
              return
            end
          elsif choice && !choice.empty? && choice != 'q'
            domain_arg = choice
          else
            return
          end
        else
          puts "\nTo switch domains, run: #{Color.c('gsc use <number|domain>', Color::CYAN)}"
          return
        end
      elsif domain_arg =~ /^\d+$/
        num = domain_arg.to_i
        if num >= 1 && num <= domains.size
          domain_arg = domains[num - 1]
        else
          puts Color.c("❌ Error: Invalid domain number #{num}. Must be between 1 and #{domains.size}.", Color::RED)
          exit 1
        end
      end

      clean = Config.set_default_domain(domain_arg)
      if options[:json]
        puts JSON.pretty_generate({ status: 'ok', activeDomain: clean })
        return
      end
      if options[:in_dashboard]
        puts Color.c("✅ Switched active domain to: #{clean}", Color::GREEN, Color::BOLD)
        return
      end


      puts BANNER
      puts Color.c("✅ Active default domain set to: #{clean}", Color::GREEN, Color::BOLD)
      puts Color.c("   Saved to #{Config::CONFIG_FILE}", Color::GRAY)
      puts "\nNow all commands (#{Color.c('gsc top-queries')}, #{Color.c('gsc audit')}, #{Color.c('gsc performance')}) will automatically target #{Color.c(clean, Color::CYAN)} without needing -d!"
      puts
    end

    def self.handle_config_command(subcommand, subvalue, subextra_or_options = nil, maybe_options = {})
      if subextra_or_options.is_a?(Hash)
        options = subextra_or_options
        subextra = nil
      else
        subextra = subextra_or_options
        options = maybe_options || {}
      end
      case subcommand
      when 'set'
        key = subvalue.to_s.strip
        val = subextra.to_s.strip
        if key.empty? || val.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Usage: gsc config set <key> <value>' })
          else
            puts Color.c("❌ Error: Please specify key and value.", Color::RED)
            puts "Example: gsc config set opr_api_key opr_live_xxxx"
            puts "Example: gsc config set pagespeed_api_key AIzaSyxxxx"
          end
          exit 1
        end

        Config.set(key, val)
        if key == 'opr_api_key'
          Config.set('openpagerank_api_key', val)
        elsif key == 'openpagerank_api_key'
          Config.set('opr_api_key', val)
        end

        masked = val.length > 8 ? "#{val[0..7]}...#{val[-4..-1]}" : "***"
        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', key: key, value: masked, configFile: Config::CONFIG_FILE })
        else
          puts BANNER
          puts Color.c("✅ Saved configuration: #{Color.c(key, Color::CYAN)} = #{Color.c(masked, Color::GREEN)}", Color::GREEN, Color::BOLD)
          puts Color.c("   📁 Stored in #{Config::CONFIG_FILE}", Color::GRAY)
        end
        return

      when 'get'
        key = subvalue.to_s.strip
        val = Config.get(key)
        if options[:json]
          puts JSON.pretty_generate({ key: key, value: val })
        else
          puts val || "(not set)"
        end
        return

      when 'set-domain', 'domain'
        if subvalue.nil? || subvalue.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Please specify a domain' })
          else
            puts Color.c("❌ Error: Please specify a domain.", Color::RED)
          end
          exit 1
        end
        clean = Config.set_default_domain(subvalue)
        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', defaultDomain: clean })
        else
          puts BANNER
          puts Color.c("✅ Default domain updated to: #{clean}", Color::GREEN, Color::BOLD)
        end
      when 'set-key', 'key'
        if subvalue.nil? || !File.exist?(subvalue)
          if options[:json]
            puts JSON.pretty_generate({ error: "Key file does not exist: #{subvalue}" })
          else
            puts Color.c("❌ Error: Key file does not exist: #{subvalue}", Color::RED)
          end
          exit 1
        end
        dest = File.join(Config::CONFIG_DIR, 'service-account.json')
        FileUtils.mkdir_p(Config::CONFIG_DIR)
        File.chmod(0700, Config::CONFIG_DIR) rescue nil
        FileUtils.cp(subvalue, dest)
        File.chmod(0600, dest) rescue nil
        Config.set_key_path(dest)
        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', keyPath: dest })
        else
          puts BANNER
          puts Color.c("✅ Service account key copied to: #{dest}", Color::GREEN, Color::BOLD)
        end
      when 'set-update-url', 'update-url'
        if subvalue.nil? || subvalue.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Please specify an update URL' })
          else
            puts Color.c("❌ Error: Please specify an update URL.", Color::RED)
          end
          exit 1
        end
        Config.save('update_url' => subvalue)
        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', updateUrl: subvalue })
        else
          puts BANNER
          puts Color.c("✅ Update source URL saved to: #{subvalue}", Color::GREEN, Color::BOLD)
        end
      when 'set-ga4', 'ga4'
        if subvalue.nil? || subvalue.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Please specify a numeric GA4 Property ID' })
          else
            puts Color.c("❌ Error: Please specify a numeric GA4 Property ID.", Color::RED)
            puts "Example: gsc config set-ga4 123456789 [-d example.com]"
          end
          exit 1
        end
        target_dom = options[:domain] || Config.default_domain
        saved_id = Config.set_ga4_property_id(subvalue, target_dom)
        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', domain: target_dom, ga4PropertyId: saved_id })
        else
          puts BANNER
          dom_str = target_dom ? " for domain #{Color.c(target_dom, Color::CYAN)}" : ""
          puts Color.c("✅ GA4 Property #{Color.c(saved_id, Color::MAGENTA, Color::BOLD)} linked#{dom_str}!", Color::GREEN, Color::BOLD)
        end
      when 'unlink-ga4'
        target_dom = options[:domain] || Config.default_domain
        Config.unlink_ga4_property(target_dom)
        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', unlinkedDomain: target_dom })
        else
          puts BANNER
          puts Color.c("✅ Unlinked GA4 property for domain #{Color.c(target_dom, Color::CYAN)}.", Color::GREEN)
        end
      else
        cfg = Config.load
        key_path = Auth.find_key(options[:key])
        sa = key_path ? (JSON.parse(File.read(key_path)) rescue {}) : {}

        if options[:json]
          puts JSON.pretty_generate(cfg.merge({
            configFile: Config::CONFIG_FILE,
            keyLocation: key_path,
            serviceAccount: sa['client_email']
          }))
          return
        end

        puts BANNER
        puts "#{Color::BOLD}⚙️  GSC CLI CONFIGURATION:#{Color::RESET}"
        puts "   Config File:     #{Color.c(Config::CONFIG_FILE, Color::CYAN)}"
        puts "   Default Domain:  #{cfg['default_domain'] ? Color.c(cfg['default_domain'], Color::GREEN, Color::BOLD) : Color.c('(not set - run: gsc use <domain>)', Color::GRAY)}"
        if key_path
          puts "   Key Location:    #{Color.c(key_path, Color::CYAN)}"
          puts "   Service Account: #{Color.c(sa['client_email'], Color::GREEN)}"
        else
          puts "   Key Location:    #{Color.c('Not found', Color::RED)}"
        end
        opr = cfg['opr_api_key'] || cfg['openpagerank_api_key']
        if opr
          m_opr = opr.length > 8 ? "#{opr[0..7]}...#{opr[-4..-1]}" : "***"
          puts "   OpenPageRank:    #{Color.c(m_opr, Color::GREEN)} (Active)"
        else
          puts "   OpenPageRank:    #{Color.c('(not set - run: gsc config set opr_api_key <key>)', Color::GRAY)}"
        end

        ps = cfg['pagespeed_api_key']
        if ps
          m_ps = ps.length > 8 ? "#{ps[0..7]}...#{ps[-4..-1]}" : "***"
          puts "   PageSpeed API:   #{Color.c(m_ps, Color::GREEN)} (Active)"
        end

        ke = cfg['keywords_everywhere_api_key']
        if ke
          m_ke = ke.length > 8 ? "#{ke[0..7]}...#{ke[-4..-1]}" : "***"
          puts "   Keywords Evr:    #{Color.c(m_ke, Color::GREEN)} (Active)"
        end

        puts "
   #{Color::BOLD}Linked GA4 Properties per Domain:#{Color::RESET}"
        ga4_props = cfg['ga4_properties'] || {}
        if ga4_props.empty?
          puts "      #{Color.c('(None linked yet. Use: gsc config set-ga4 <id> -d <domain>)', Color::GRAY)}"
        else
          ga4_props.each do |dom, pid|
            active_star = (dom == cfg['default_domain']) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN)}" : ""
            puts "      • #{Color.c(dom, Color::CYAN)} ➔ #{Color.c(pid, Color::MAGENTA, Color::BOLD)}#{active_star}"
          end
        end
        puts
        puts "#{Color::BOLD}Configuration shortcuts:#{Color::RESET}"
        puts "   gsc connect                  Interactive setup wizard (drag & drop key)"
        puts "   gsc use <domain>             Set active default domain"
        puts "   gsc config set <key> <val>   Set API key (e.g. opr_api_key, pagespeed_api_key)"
        puts "   gsc config get <key>         Read a stored configuration value"
        puts "   gsc config set-ga4 <id>      Link a GA4 Property ID to domain"
        puts "   gsc open                     Open config directory in Finder"
        puts "   gsc where                    Show install path and paths summary"
        puts
      end
    end

    def self.resolve_domain(domain_arg, target_arg, options = {})
      raw = domain_arg
      if raw.nil? || raw.empty?
        if target_arg && target_arg.start_with?('http://', 'https://')
          raw = URI(target_arg).hostname
        else
          raw = ENV['GSC_DOMAIN'] || Config.default_domain
        end
      end

      if raw.nil? || raw.empty?
        if options[:json]
          puts JSON.pretty_generate({ error: 'No target domain specified. Run gsc use <domain> or pass -d <domain>.' })
        else
          puts Color.c("\n⚠️  No target domain specified!", Color::YELLOW, Color::BOLD)
          puts "Please specify a domain using one of the following:"
          puts "  1. Set a global active domain:  #{Color.c('gsc use <domain>', Color::CYAN)}"
          puts "  2. Pass domain flag:            #{Color.c('gsc <command> -d <domain>', Color::CYAN)}"
          puts "  3. Set environment variable:    #{Color.c('export GSC_DOMAIN=<domain>', Color::CYAN)}"
          puts
        end
        exit 1
      end

      if raw.start_with?('sc-domain:')
        hostname = raw.sub('sc-domain:', '')
        site_url = raw
      elsif raw.start_with?('http://', 'https://')
        uri = URI(raw)
        hostname = uri.hostname
        site_url = raw.end_with?('/') ? raw : "#{raw}/"
      else
        hostname = raw.chomp('/')
        site_url = "sc-domain:#{hostname}"
      end

      https_origin = "https://#{hostname}"
      [hostname, site_url, https_origin]
    end

    def self.require_target!(target, example, options = {})
      return if target && !target.empty?

      if options[:json]
        puts JSON.pretty_generate({ error: 'Target URL is required', example: "gsc #{example}" })
      else
        puts Color.c("❌ Error: Please provide a URL target.", Color::RED)
        puts "Example: gsc #{example}"
      end
      exit 1
    end

    def self.simulate_dry_run?(options)
      if options[:dry_run]
        puts Color.c('⚠️ [DRY-RUN] Request simulated. No live API call made.', Color::YELLOW) unless options[:json]
        true
      else
        false
      end
    end

    def self.print_batch_summary(success, fail, total)
      puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
      puts "#{Color::BOLD}🎉 BATCH INDEXATION COMPLETE#{Color::RESET}"
      puts "   ✅ Successfully Submitted: #{Color.c(success.to_s, Color::GREEN, Color::BOLD)} / #{total}"
      puts "   ❌ Failed Requests:        #{Color.c(fail.to_s, Color::RED, Color::BOLD)}" if fail > 0
      puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"
    end

    def self.write_csv(path, headers, rows)
      File.open(path, 'w') do |f|
        f.puts headers.join(',')
        rows.each do |row|
          escaped = row.map do |v|
            str = v.to_s
            # Mitigate CSV Formula Injection (prepend single quote if leading char is =, +, -, @, tab, or CR)
            str = "'#{str}" if str =~ /\A[=+\-@\t\r]/
            "\"#{str.gsub('"', '""')}\""
          end
          f.puts escaped.join(',')
        end
      end
    end

    def self.normalize_path(url_or_path)
      return '/' if url_or_path.nil? || url_or_path.empty?
      p = url_or_path.to_s.sub(%r{^https?://[^/]+}, '').split('?').first.split('#').first.downcase.chomp('/')
      p.empty? ? '/' : p
    end

    def self.format_duration(seconds)
      sec = seconds.to_i
      return "0s" if sec <= 0
      m = sec / 60
      s = sec % 60
      m > 0 ? "#{m}m #{s}s" : "#{s}s"
    end

    def self.expected_ctr_for(pos)
      case pos
      when 0.0...1.5 then 28.0
      when 1.5...2.5 then 15.0
      when 2.5...3.5 then 11.0
      when 3.5...4.5 then 8.0
      when 4.5...6.0 then 6.0
      when 6.0...8.0 then 4.5
      else 3.0
      end
    end

    def self.format_number(n)
      n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    COUNTRY_NAMES = {
      'usa' => 'United States 🇺🇸',
      'gbr' => 'United Kingdom 🇬🇧',
      'can' => 'Canada 🇨🇦',
      'aus' => 'Australia 🇦🇺',
      'ind' => 'India 🇮🇳',
      'bra' => 'Brazil 🇧🇷',
      'deu' => 'Germany 🇩🇪',
      'fra' => 'France 🇫🇷',
      'esp' => 'Spain 🇪🇸',
      'ita' => 'Italy 🇮🇹',
      'mex' => 'Mexico 🇲🇽',
      'jpn' => 'Japan 🇯🇵',
      'kor' => 'South Korea 🇰🇷',
      'nld' => 'Netherlands 🇳🇱',
      'swe' => 'Sweden 🇸🇪',
      'nor' => 'Norway 🇳🇴',
      'dnk' => 'Denmark 🇩🇰',
      'fin' => 'Finland 🇫🇮',
      'che' => 'Switzerland 🇨🇭',
      'aut' => 'Austria 🇦🇹',
      'bel' => 'Belgium 🇧🇪',
      'irl' => 'Ireland 🇮🇪',
      'nzl' => 'New Zealand 🇳🇿',
      'sgp' => 'Singapore 🇸🇬',
      'hkg' => 'Hong Kong 🇭🇰',
      'are' => 'UAE 🇦🇪',
      'sau' => 'Saudi Arabia 🇸🇦',
      'kwt' => 'Kuwait 🇰🇼',
      'isr' => 'Israel 🇮🇱',
      'tur' => 'Turkey 🇹🇷',
      'pol' => 'Poland 🇵🇱',
      'ukr' => 'Ukraine 🇺🇦',
      'zaf' => 'South Africa 🇿🇦',
      'col' => 'Colombia 🇨🇴',
      'arg' => 'Argentina 🇦🇷',
      'chl' => 'Chile 🇨🇱',
      'per' => 'Peru 🇵🇪',
      'pak' => 'Pakistan 🇵🇰',
      'bgd' => 'Bangladesh 🇧🇩',
      'phl' => 'Philippines 🇵🇭',
      'vnm' => 'Vietnam 🇻🇳',
      'tha' => 'Thailand 🇹🇭',
      'mys' => 'Malaysia 🇲🇾',
      'idn' => 'Indonesia 🇮🇩',
      'chn' => 'China 🇨🇳',
      'twn' => 'Taiwan 🇹🇼',
      'prt' => 'Portugal 🇵🇹',
      'grc' => 'Greece 🇬🇷',
      'cze' => 'Czech Republic 🇨🇿',
      'rou' => 'Romania 🇷🇴',
      'hun' => 'Hungary 🇭🇺',
      'egy' => 'Egypt 🇪🇬',
      'nga' => 'Nigeria 🇳🇬',
      'ken' => 'Kenya 🇰🇪',
      'mar' => 'Morocco 🇲🇦',
      'arm' => 'Armenia 🇦🇲',
      'aze' => 'Azerbaijan 🇦🇿',
      'bgr' => 'Bulgaria 🇧🇬',
      'bhr' => 'Bahrain 🇧🇭',
      'brn' => 'Brunei 🇧🇳',
      'civ' => 'Ivory Coast 🇨🇮',
      'cyp' => 'Cyprus 🇨🇾',
      'dom' => 'Dominican Rep. 🇩🇴',
      'dza' => 'Algeria 🇩🇿',
      'gtm' => 'Guatemala 🇬🇹',
      'hrv' => 'Croatia 🇭🇷',
      'irn' => 'Iran 🇮🇷',
      'irq' => 'Iraq 🇮🇶',
      'jam' => 'Jamaica 🇯🇲',
      'jor' => 'Jordan 🇯🇴',
      'lby' => 'Libya 🇱🇾',
      'ltu' => 'Lithuania 🇱🇹',
      'lva' => 'Latvia 🇱🇻',
      'est' => 'Estonia 🇪🇪',
      'qat' => 'Qatar 🇶🇦',
      'omn' => 'Oman 🇴🇲',
      'srb' => 'Serbia 🇷🇸',
      'svk' => 'Slovakia 🇸🇰',
      'svn' => 'Slovenia 🇸🇮',
      'isl' => 'Iceland 🇮🇸',
      'lux' => 'Luxembourg 🇱🇺',
      'lka' => 'Sri Lanka 🇱🇰',
      'npl' => 'Nepal 🇳🇵',
      'tun' => 'Tunisia 🇹🇳',
      'gha' => 'Ghana 🇬🇭'
    }.freeze

    def self.format_country(code)
      COUNTRY_NAMES[code.to_s.downcase] || code.to_s.upcase
    end

    def self.format_device(dev)
      case dev.to_s.upcase
      when 'DESKTOP' then '💻 Desktop'
      when 'MOBILE'  then '📱 Mobile'
      when 'TABLET'  then '📟 Tablet'
      else dev.to_s.capitalize
      end
    end

    APPEARANCE_NAMES = {
      'REVIEW_SNIPPET'        => '⭐ Review Snippets',
      'PRODUCT_SNIPPETS'      => '🏷️ Product Snippets',
      'MERCHANT_LISTINGS'     => '🏪 Merchant Listings',
      'PAGE_EXPERIENCE'       => '⚡ Page Experience',
      'GOOD_PAGE_EXPERIENCE'  => '✅ Good Page Experience',
      'FAQ'                   => '❓ FAQ Rich Results',
      'VIDEO'                 => '🎥 Video Snippets',
      'RECIPE'                => '🍲 Recipe Rich Results',
      'EVENT'                 => '📅 Event Listings',
      'HOW_TO'                => '📋 How-To Rich Results',
      'SUBMIT_ACTION'         => '📝 Sitelinks Searchbox',
      'AMP_ARTICLE'           => '⚡ AMP Article',
      'ORGANIC_SHOPPING'      => '🛍️ Organic Shopping',
      'TRANSLATED_RESULT'     => '🌐 Translated Result'
    }.freeze

    def self.format_appearance(type)
      APPEARANCE_NAMES[type.to_s.upcase] || type.to_s.tr('_', ' ').capitalize
    end

    def self.print_devices_table(rows)
      puts "\n#{Color::BOLD}📱 DEVICE BREAKDOWN (Search Traffic)#{Color::RESET}"
      puts "Device       | Clicks   | Impressions | CTR    | Position | Clicks Share"
      puts "-------------------------------------------------------------------------"
      rows.each do |r|
        d_name = format_device(r[:device]).ljust(12)
        c_str = format_number(r[:clicks]).ljust(8)
        i_str = format_number(r[:impressions]).ljust(11)
        ctr_str = "#{r[:ctr]}%".ljust(6)
        pos_str = r[:position].to_s.ljust(8)
        share_str = r[:share].to_s
        puts "#{d_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{share_str}"
      end
    end

    def self.print_countries_table(rows)
      puts "\n#{Color::BOLD}🌍 TOP COUNTRIES (Search Demand)#{Color::RESET}"
      puts "Country                | Clicks   | Impressions | CTR    | Position"
      puts "-------------------------------------------------------------------------"
      rows.each do |r|
        c_name = format_country(r[:country])[0..21].ljust(22)
        c_str = format_number(r[:clicks]).ljust(8)
        i_str = format_number(r[:impressions]).ljust(11)
        ctr_str = "#{r[:ctr]}%".ljust(6)
        pos_str = r[:position].to_s
        puts "#{c_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str}"
      end
    end

    def self.print_snippets_table(rows)
      puts "\n#{Color::BOLD}✨ SEARCH APPEARANCE & RICH SNIPPETS#{Color::RESET}"
      if rows.empty?
        puts Color.c("  (No rich snippet enhancements detected in this date range)\n", Color::GRAY)
      else
        puts "Appearance Type        | Clicks   | Impressions | CTR    | Position"
        puts "-------------------------------------------------------------------------"
        rows.each do |r|
          t_name = format_appearance(r[:type])[0..21].ljust(22)
          c_str = format_number(r[:clicks]).ljust(8)
          i_str = format_number(r[:impressions]).ljust(11)
          ctr_str = "#{r[:ctr]}%".ljust(6)
          pos_str = r[:position].to_s
          puts "#{t_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str}"
        end
      end
    end

    def self.print_cities_table(rows, property_id = nil)
      prop_label = property_id ? " [Property #{property_id}]" : ""
      puts "\n#{Color::BOLD}🏙️ TOP CITIES & ON-SITE ENGAGEMENT#{prop_label}#{Color::RESET}"
      if rows.empty?
        puts Color.c("  (No city-level behavioral data available in GA4)\n", Color::GRAY)
      else
        puts "City                 | Country            | Sessions | Bounce | Avg Time"
        puts "-------------------------------------------------------------------------"
        rows.each do |r|
          city_str = r[:city][0..19].ljust(20)
          cntry_str = r[:country][0..17].ljust(18)
          sess_str = format_number(r[:sessions]).ljust(8)
          bounce_str = "#{r[:bounce_rate]}".ljust(6)
          dur_str = r[:duration].to_s
          puts "#{city_str} | #{cntry_str} | #{sess_str} | #{bounce_str} | #{dur_str}"
        end
      end
    end

    def self.print_mini_queries_table(rows)
      puts "\n#{Color::BOLD}🔍 TOP SEARCH QUERIES#{Color::RESET}"
      puts "Clicks | Impressions | CTR    | Position | Query"
      puts "-------------------------------------------------------------------------"
      rows.each do |r|
        c_str = format_number(r[:clicks]).ljust(6)
        i_str = format_number(r[:impressions]).ljust(11)
        ctr_str = "#{r[:ctr]}%".ljust(6)
        pos_str = r[:position].to_s.ljust(8)
        q_str = Color.c(r[:query], Color::YELLOW)
        puts "#{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{q_str}"
      end
    end

    def self.print_mini_pages_table(rows)
      puts "\n#{Color::BOLD}📄 TOP LANDING PAGES#{Color::RESET}"
      puts "Clicks | Impressions | CTR    | Position | Page Path"
      puts "-------------------------------------------------------------------------"
      rows.each do |r|
        c_str = format_number(r[:clicks]).ljust(6)
        i_str = format_number(r[:impressions]).ljust(11)
        ctr_str = "#{r[:ctr]}%".ljust(6)
        pos_str = r[:position].to_s.ljust(8)
        p_str = Color.c(r[:path], Color::CYAN)
        puts "#{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{p_str}"
      end
    end

    def self.run_comprehensive_audit(api, site_url, hostname, https_origin, options)
      days = options[:days] || 30
      puts "🔍 Running 360° Comprehensive SEO & Growth Audit for #{Color.c(hostname, Color::CYAN)} (Past #{days} days)...\n" unless options[:json]

      # 1. Check Sites Permission
      sites_res = api.list_sites
      access_ok = false
      if sites_res[:ok]
        entries = sites_res.dig(:data, 'siteEntry') || []
        access_ok = entries.any? { |s| s['siteUrl'] == site_url || s['siteUrl'].include?(hostname) }
      end

      # 2. Performance Totals
      perf_res = api.query_analytics(site_url, days: days, dimensions: [])
      perf_row = perf_res.dig(:data, 'rows', 0) || { 'clicks' => 0, 'impressions' => 0, 'ctr' => 0, 'position' => 0 }
      total_clicks = perf_row['clicks'] || 0
      total_imp    = perf_row['impressions'] || 0
      avg_ctr      = ((perf_row['ctr'] || 0) * 100).round(2)
      avg_pos      = (perf_row['position'] || 0).round(1)

      # 3. Homepage Live Inspection
      home_res = api.inspect_url("#{https_origin}/", site_url)
      idx_res = home_res.dig(:data, 'inspectionResult', 'indexStatusResult') || {}
      verdict          = idx_res['verdict'] || 'UNKNOWN'
      coverage         = idx_res['coverageState'] || 'Unknown'
      google_canonical = idx_res['googleCanonical'] || "#{https_origin}/"
      user_canonical   = idx_res['userCanonical'] || "#{https_origin}/"
      crawled_as       = idx_res['crawlingUserAgent'] || idx_res['crawledAs'] || 'Googlebot Mobile'
      last_crawl_raw   = idx_res['lastCrawlTime']
      last_crawl       = last_crawl_raw ? last_crawl_raw.split('T').first : 'Unknown'
      canonical_match  = google_canonical.chomp('/') == user_canonical.chomp('/') || google_canonical.include?(hostname)

      # 4. Registered Sitemaps
      sm_res = api.list_sitemaps(site_url)
      sitemaps = sm_res[:ok] ? (sm_res.dig(:data, 'sitemap') || []) : []
      sm_errors = sitemaps.sum { |s| (s['errors'] || 0).to_i }
      sm_warnings = sitemaps.sum { |s| (s['warnings'] || 0).to_i }

      # 5. Queries & Pages Analytics (500 rows)
      qp_res = api.query_analytics(site_url, days: days, dimensions: %w[query page], row_limit: 500)
      qp_rows = qp_res[:ok] ? (qp_res.dig(:data, 'rows') || []) : []

      # 5a. Striking Distance Opportunities (pos 7.0..20.0, min 5 imp)
      opportunities = qp_rows.select { |r| r['position'] >= 7.0 && r['position'] <= 20.0 && r['impressions'] >= 5 }
                             .map do |r|
                               c = r['clicks'] || 0
                               i = r['impressions'] || 0
                               pos = r['position'].round(1)
                               potential_clicks = [((i * 0.12) - c).round, 1].max
                               score = (potential_clicks * (1.0 / [pos - 2.0, 1.0].max) * 10.0).round(1)
                               { query: r['keys'][0], page: r['keys'][1], position: pos, impressions: i, clicks: c, potential_gain: potential_clicks, score: score }
                             end.sort_by { |o| -o[:score] }.first(5)

      # 5b. CTR Click-Bleed Underperformers (pos <= 10.0, min 15 imp, actual < exp * 0.70)
      underperformers = qp_rows.select { |r| r['position'] <= 10.0 && r['impressions'] >= 15 }
                               .map do |r|
                                 pos_val = r['position'].round(1)
                                 actual = ((r['ctr'] || 0) * 100).round(2)
                                 exp = expected_ctr_for(pos_val)
                                 gap = (exp - actual).round(2)
                                 lost = [((r['impressions'] * (gap / 100.0))).round, 1].max
                                 { query: r['keys'][0], page: r['keys'][1], position: pos_val, impressions: r['impressions'], clicks: r['clicks'], actual_ctr: actual, expected_ctr: exp, gap: gap, lost_clicks: lost }
                               end.select { |u| u[:gap] >= 2.0 && u[:actual_ctr] < (u[:expected_ctr] * 0.70) }
                               .sort_by { |u| -u[:lost_clicks] }.first(5)

      # 5c. Keyword Cannibalization (queries with > 1 distinct pages)
      by_query = qp_rows.group_by { |r| r['keys'][0] }
      cannibalized = by_query.select { |_q, list| list.map { |r| r['keys'][1] }.uniq.size > 1 }
                             .map do |q, list|
                               pages = list.map do |r|
                                 { page: r['keys'][1], impressions: r['impressions'], clicks: r['clicks'], position: r['position'].round(1) }
                               end.sort_by { |p| -p[:impressions] }
                               total_q_imp = pages.sum { |p| p[:impressions] }
                               { query: q, total_impressions: total_q_imp, pages: pages }
                             end.sort_by { |c| -c[:total_impressions] }.first(3)

      # 6. Device Breakdown
      dev_res = api.query_analytics(site_url, days: days, dimensions: ['device'])
      devices_data = (dev_res[:ok] ? (dev_res.dig(:data, 'rows') || []) : []).map do |r|
        c = r['clicks'] || 0
        i = r['impressions'] || 0
        ctr = ((r['ctr'] || 0) * 100).round(2)
        pos = (r['position'] || 0).round(1)
        share = total_clicks > 0 ? "#{(c.to_f / total_clicks * 100).round(1)}%" : "-"
        { device: r['keys'].first, clicks: c, impressions: i, ctr: ctr, position: pos, share: share }
      end.sort_by { |r| -r[:clicks] }

      desk_dev = devices_data.find { |d| d[:device] == 'DESKTOP' }
      mob_dev  = devices_data.find { |d| d[:device] == 'MOBILE' }
      mobile_deficit = desk_dev && mob_dev && desk_dev[:ctr] >= 1.0 && mob_dev[:ctr] < (desk_dev[:ctr] * 0.6)

      # 7. Search Appearance & Rich Snippets
      snip_res = api.query_analytics(site_url, days: days, dimensions: ['searchAppearance'], row_limit: 10)
      snippets_data = (snip_res[:ok] ? (snip_res.dig(:data, 'rows') || []) : []).map do |r|
        { type: r['keys'].first, clicks: r['clicks'] || 0, impressions: r['impressions'] || 0, ctr: ((r['ctr'] || 0) * 100).round(2), position: (r['position'] || 0).round(1) }
      end

      # 8. GA4 Behavioral Metrics
      ga4_prop = options[:property] || Config.ga4_property_id(hostname)
      ga4_data = nil
      high_bounce_pages = []
      if ga4_prop
        ga4_res = api.query_ga4_report(ga4_prop, days: days, limit: 50, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        if ga4_res[:ok]
          raw_ga4 = ga4_res.dig(:data, 'rows') || []
          tot_sess = raw_ga4.sum { |r| r.dig('metricValues', 0, 'value').to_i }
          tot_bounce = raw_ga4.sum { |r| r.dig('metricValues', 3, 'value').to_f * r.dig('metricValues', 0, 'value').to_i }
          overall_bounce = tot_sess.positive? ? (tot_bounce / tot_sess * 100.0).round(1) : 0.0
          tot_dur = raw_ga4.sum { |r| r.dig('metricValues', 4, 'value').to_f * r.dig('metricValues', 0, 'value').to_i }
          overall_dur = tot_sess.positive? ? (tot_dur / tot_sess).round : 0

          high_bounce_pages = raw_ga4.map do |r|
            path = r.dig('dimensionValues', 0, 'value')
            sess = r.dig('metricValues', 0, 'value').to_i
            bounce = ((r.dig('metricValues', 3, 'value') || 0).to_f * 100).round(1)
            dur = (r.dig('metricValues', 4, 'value') || 0).to_f.round
            { path: path, sessions: sess, bounce_rate: bounce, duration: format_duration(dur) }
          end.select { |p| p[:sessions] >= 10 && p[:bounce_rate] >= 80.0 }.sort_by { |p| -p[:sessions] }.first(5)

          ga4_data = {
            linked: true,
            property_id: ga4_prop,
            sessions: tot_sess,
            bounce_rate: overall_bounce,
            avg_duration_sec: overall_dur,
            avg_duration: format_duration(overall_dur),
            high_bounce_pages: high_bounce_pages
          }
        end
      end

      # 9. Compute Overall SEO Health Score
      score = 100
      score -= 20 if verdict != 'PASS'
      score -= 10 if sitemaps.empty?
      score -= 10 if sm_errors > 0
      score -= 10 unless canonical_match
      score -= 15 if avg_ctr < 0.5
      score -= 10 if avg_ctr >= 0.5 && avg_ctr < 1.0
      score -= 10 if avg_pos > 30.0
      score -= [underperformers.size * 5, 10].min
      score -= [cannibalized.size * 5, 10].min
      score -= 5 if mobile_deficit
      if ga4_data && ga4_data[:sessions] > 0
        score -= 15 if ga4_data[:bounce_rate] > 85.0
        score -= 10 if ga4_data[:bounce_rate] > 75.0 && ga4_data[:bounce_rate] <= 85.0
        score += 5  if ga4_data[:bounce_rate] <= 60.0
      end
      score += 5 unless snippets_data.empty?
      score = [[score, 20].max, 100].min

      grade = case score
              when 88..100 then 'A'
              when 75...88 then 'B'
              when 60...75 then 'C'
              else 'D'
              end

      grade_label = case grade
                    when 'A' then 'EXCELLENT - DOMINATING SERPS'
                    when 'B' then 'GOOD - HIGH-LEVERAGE GROWTH WINS AVAILABLE'
                    when 'C' then 'NEEDS ATTENTION - CLICK BLEED & CONFLICTS DETECTED'
                    else 'CRITICAL - INDEXING, CANNIBALIZATION OR RETENTION FRICTION'
                    end

      # 10. Prioritized Action Plan Engine
      action_plan = []

      # High Priority
      if cannibalized.any?
        top_c = cannibalized.first
        conflicting_pages = top_c[:pages].map { |p| p[:page].sub(%r{^https?://[^/]+}, '') }
        action_plan << {
          priority: 'high',
          title: "Consolidate Keyword Cannibalization on \"#{top_c[:query]}\"",
          detail: "Search intent is split across #{top_c[:pages].size} competing URLs (#{conflicting_pages.join(', ')}). Consolidate internal links and canonical signals to #{top_c[:pages].first[:page].sub(%r{^https?://[^/]+}, '')} to unify Page 1 ranking power."
        }
      end

      if underperformers.any?
        top_u = underperformers.first
        action_plan << {
          priority: 'high',
          title: "Recover ~#{top_u[:lost_clicks]} Lost Clicks/mo on \"#{top_u[:query]}\"",
          detail: "Currently ranking Pos #{top_u[:position]} on #{top_u[:page].sub(%r{^https?://[^/]+}, '')} with #{top_u[:actual_ctr]}% CTR (expected benchmark ~#{top_u[:expected_ctr]}%). Rewrite `<title>` and meta description with numbers or benefit hooks to double click-through."
        }
      end

      if sm_errors > 0
        err_sm = sitemaps.find { |s| (s['errors'] || 0).to_i > 0 }
        action_plan << {
          priority: 'high',
          title: "Resolve Sitemap Errors in Search Console",
          detail: "Sitemap #{err_sm['path']} has #{err_sm['errors']} errors. Clean up 404s or resubmit current sitemap-index.xml."
        }
      end

      if verdict != 'PASS'
        action_plan << {
          priority: 'high',
          title: "Resolve Homepage Indexation Blocker",
          detail: "Homepage Googlebot verdict is #{verdict} (#{coverage}). Inspect URL in Search Console to resolve indexing eligibility."
        }
      end

      # Medium Priority
      if opportunities.any?
        top_o = opportunities.first
        action_plan << {
          priority: 'medium',
          title: "Push Striking-Distance Keyword \"#{top_o[:query]}\" to Top 3",
          detail: "Currently Pos #{top_o[:position]} with #{top_o[:impressions]} impressions on #{top_o[:page].sub(%r{^https?://[^/]+}, '')}. Add a dedicated H2 section and clear answering copy to unlock ~+#{top_o[:potential_gain]} clicks/mo."
        }
      end

      if high_bounce_pages.any?
        top_hb = high_bounce_pages.first
        action_plan << {
          priority: 'medium',
          title: "Address High Bounce Rate (#{top_hb[:bounce_rate]}%) on #{top_hb[:path]}",
          detail: "Page received #{top_hb[:sessions]} sessions with #{top_hb[:duration]} average time. Audit above-the-fold LCP speed and ensure page content directly satisfies searcher intent."
        }
      end

      if mobile_deficit
        action_plan << {
          priority: 'medium',
          title: "Audit Mobile Viewport & Responsive CTR",
          detail: "Mobile CTR (#{mob_dev[:ctr]}%) is significantly trailing Desktop (#{desk_dev[:ctr]}%). Test page on real devices for mobile layout shift, font readability, or button touch targets."
        }
      end

      # Quick Wins / Optimization
      if snippets_data.empty?
        action_plan << {
          priority: 'low',
          title: "Implement Structured Data (Schema.org)",
          detail: "No rich snippet enhancements active. Add Product, FAQ, or Organization JSON-LD markup to earn rich SERP real estate."
        }
      else
        snippet_labels = snippets_data.map { |s| format_appearance(s[:type]) }.join(', ')
        action_plan << {
          priority: 'low',
          title: "Maintain Rich Snippets",
          detail: "#{snippet_labels} currently active. Monitor Google Rich Results Test to maintain snippet coverage."
        }
      end

      audit_payload = {
        domain: hostname,
        siteUrl: site_url,
        healthScore: score,
        grade: grade,
        gradeLabel: grade_label,
        days: days,
        totals: {
          clicks: total_clicks,
          impressions: total_imp,
          ctr: avg_ctr,
          position: avg_pos
        },
        technical: {
          homepageVerdict: verdict,
          coverageState: coverage,
          googleCanonical: google_canonical,
          userCanonical: user_canonical,
          canonicalMatch: canonical_match,
          crawledAs: crawled_as,
          lastCrawl: last_crawl,
          sitemapsCount: sitemaps.size,
          sitemapsErrors: sm_errors,
          sitemapsWarnings: sm_warnings,
          sitemaps: sitemaps
        },
        opportunities: opportunities,
        underperformers: underperformers,
        cannibalization: cannibalized,
        devices: devices_data,
        mobileDeficit: mobile_deficit,
        snippets: snippets_data,
        ga4: ga4_data,
        actionPlan: action_plan
      }

      if options[:json]
        puts JSON.pretty_generate(audit_payload)
      else
        print_comprehensive_audit(audit_payload)

        if options[:csv]
          csv_rows = action_plan.map { |a| [a[:priority], a[:title], a[:detail]] }
          write_csv(options[:csv], %w[Priority Title Recommendation], csv_rows)
          puts Color.c("📁 Exported prioritized action plan to #{options[:csv]}\n", Color::CYAN)
        end
      end
    end

    def self.print_comprehensive_audit(d)
      score = d[:healthScore]
      score_colored = if score >= 80
        Color.c("#{score} / 100", Color::GREEN, Color::BOLD)
      elsif score >= 65
        Color.c("#{score} / 100", Color::YELLOW, Color::BOLD)
      else
        Color.c("#{score} / 100", Color::RED, Color::BOLD)
      end

      puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}"
      puts "#{Color::BOLD}🎯 OVERALL SEO HEALTH SCORE: #{score_colored} #{Color::BOLD}[GRADE #{d[:grade]} - #{d[:gradeLabel]}]#{Color::RESET}"
      puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}"

      idx_status = d[:technical][:homepageVerdict] == 'PASS' ? Color.c('✅ PASS (100% Eligible)', Color::GREEN) : Color.c("⚠️ #{d[:technical][:homepageVerdict]}", Color::YELLOW)
      ctr_status = d[:totals][:ctr] >= 1.5 ? Color.c("✅ #{d[:totals][:ctr]}% CTR (Healthy)", Color::GREEN) : Color.c("⚠️ #{d[:totals][:ctr]}% CTR (Below Benchmark)", Color::YELLOW)
      cann_status = d[:cannibalization].empty? ? Color.c('✅ 0 Conflicts', Color::GREEN) : Color.c("🔴 #{d[:cannibalization].size} Query Conflicts Detected", Color::RED, Color::BOLD)

      bounce_status = if d[:ga4] && d[:ga4][:linked] && d[:ga4][:sessions] > 0
        b = d[:ga4][:bounce_rate]
        b <= 65.0 ? Color.c("✅ #{b}% Bounce Rate (Strong)", Color::GREEN) : (b <= 80.0 ? Color.c("🟡 #{b}% Bounce Rate (Moderate)", Color::YELLOW) : Color.c("🔴 #{b}% Bounce Rate (High)", Color::RED, Color::BOLD))
      else
        Color.c('ℹ️ GA4 Not Linked', Color::GRAY)
      end

      puts "  • Technical Indexing:    #{idx_status}"
      puts "  • SERP Click Efficiency: #{ctr_status}"
      puts "  • SERP Cannibalization:  #{cann_status}"
      puts "  • On-Site Retention:     #{bounce_status}"
      puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}\n"

      # 1. 30-Day Performance Overview
      puts "#{Color::BOLD}📊 30-DAY PERFORMANCE OVERVIEW#{Color::RESET}"
      puts "  • Organic Search Clicks:     #{Color.c(format_number(d[:totals][:clicks]), Color::GREEN, Color::BOLD)}"
      puts "  • Total SERP Impressions:    #{Color.c(format_number(d[:totals][:impressions]), Color::MAGENTA, Color::BOLD)}"
      puts "  • Average Search Position:   #{Color.c(d[:totals][:position].to_s, Color::YELLOW, Color::BOLD)}"
      puts "  • Average SERP CTR:          #{Color.c("#{d[:totals][:ctr]}%", Color::CYAN, Color::BOLD)}"
      if d[:ga4] && d[:ga4][:linked] && d[:ga4][:sessions] > 0
        puts "  • GA4 Total Sessions:        #{Color.c(format_number(d[:ga4][:sessions]), Color::MAGENTA, Color::BOLD)} [Property #{d[:ga4][:property_id]}]"
        puts "  • GA4 Average Bounce Rate:   #{Color.c("#{d[:ga4][:bounce_rate]}%", Color::YELLOW, Color::BOLD)}"
        puts "  • GA4 Avg Session Duration:  #{Color.c(d[:ga4][:avg_duration].to_s, Color::CYAN, Color::BOLD)}"
      end
      puts

      # 2. Technical Crawl & Indexation Health
      tech = d[:technical]
      puts "#{Color::BOLD}🛠️  1. TECHNICAL CRAWL & INDEXATION HEALTH#{Color::RESET}"
      v_color = tech[:homepageVerdict] == 'PASS' ? Color.c('✅ PASS (Indexed & Eligible for SERPs)', Color::GREEN, Color::BOLD) : Color.c("⚠️ #{tech[:homepageVerdict]}", Color::RED, Color::BOLD)
      puts "  • Homepage Googlebot Verdict:  #{v_color}"
      puts "  • Google Index Coverage State: #{tech[:coverageState]}"
      c_match = tech[:canonicalMatch] ? Color.c("Matches declared canonical", Color::GREEN) : Color.c("⚠️ Canonical Mismatch Detected", Color::YELLOW)
      puts "  • Google-Selected Canonical:   #{tech[:googleCanonical]} (#{c_match})"
      puts "  • Crawl User-Agent:            Googlebot #{tech[:crawledAs]} (Mobile-First Indexing)"
      puts "  • Last Googlebot Crawl:        #{tech[:lastCrawl]}"
      sm_text = tech[:sitemapsCount] > 0 ? Color.c("#{tech[:sitemapsCount]} registered in Search Console", Color::GREEN) : Color.c("⚠️ No sitemaps found", Color::YELLOW)
      puts "  • XML Sitemaps:                #{sm_text}"
      if tech[:sitemapsErrors] > 0
        err_sms = tech[:sitemaps].select { |s| (s['errors'] || 0).to_i > 0 }
        err_sms.each do |sm|
          last_dl = sm['lastDownloaded'] ? sm['lastDownloaded'].split('T').first : 'Unknown'
          puts "    #{Color.c("⚠️ Notice: #{sm['path']} has #{sm['errors']} error (Last downloaded: #{last_dl}).", Color::YELLOW)}"
        end
      end
      puts

      # 3. Striking Distance Opportunities
      puts "#{Color::BOLD}🎯 2. HIGH-IMPACT STRIKING-DISTANCE KEYWORDS (Page 2 ➔ Page 1 Quick Wins)#{Color::RESET}"
      if d[:opportunities].empty?
        puts Color.c("  ℹ️ No striking-distance queries found (pos 7–20 with >= 5 impressions).", Color::GRAY)
      else
        puts "Pos   | Impressions | Clicks | Est. Unlock  | Target Query & Landing Page"
        puts "--------------------------------------------------------------------------------"
        d[:opportunities].each do |o|
          pos_str  = o[:position].to_s.ljust(5)
          imp_str  = format_number(o[:impressions]).ljust(11)
          c_str    = format_number(o[:clicks]).ljust(6)
          gain_str = "+#{format_number(o[:potential_gain])}/mo".ljust(12)
          page_short = o[:page].sub(%r{^https?://[^/]+}, '')
          page_short = '/' if page_short.empty?
          puts "#{Color.c(pos_str, Color::YELLOW)} | #{imp_str} | #{c_str} | #{Color.c(gain_str, Color::GREEN, Color::BOLD)} | #{Color.c(o[:query], Color::BOLD)} ➔ #{Color.c(page_short, Color::CYAN)}"
        end
        puts "💡 #{Color::BOLD}Action:#{Color::RESET} Add an H2 subheading and dedicated answering copy on these pages to push into the Top 3."
      end
      puts

      # 4. CTR Click-Bleed & Hook Deficits
      puts "#{Color::BOLD}⚡ 3. CTR CLICK-BLEED & TITLE HOOK DEFICITS (Top 10 Rankings)#{Color::RESET}"
      if d[:underperformers].empty?
        puts Color.c("  ✅ No critical Top 10 CTR click-bleed detected. Existing Page 1 rankings are converting at or above expected benchmarks.", Color::GREEN)
      else
        puts "Pos   | Impressions | Actual CTR | Expected | Lost Clicks  | Target Query & Landing Page"
        puts "----------------------------------------------------------------------------------------"
        d[:underperformers].each do |u|
          pos_str  = u[:position].to_s.ljust(5)
          imp_str  = format_number(u[:impressions]).ljust(11)
          act_str  = "#{u[:actual_ctr]}%".ljust(10)
          exp_str  = "~#{u[:expected_ctr]}%".ljust(8)
          lost_str = "~#{format_number(u[:lost_clicks])}/mo".ljust(12)
          page_short = u[:page].sub(%r{^https?://[^/]+}, '')
          page_short = '/' if page_short.empty?
          puts "#{Color.c(pos_str, Color::GREEN)} | #{imp_str} | #{Color.c(act_str, Color::RED)} | #{exp_str} | #{Color.c(lost_str, Color::YELLOW, Color::BOLD)} | #{Color.c(u[:query], Color::BOLD)} ➔ #{Color.c(page_short, Color::CYAN)}"
        end
        puts "💡 #{Color::BOLD}Action:#{Color::RESET} Rewrite the <title> tag and meta description with numbers, brackets, or clear benefit hooks to recover lost clicks immediately."
      end
      puts

      # 5. Keyword Cannibalization
      puts "#{Color::BOLD}🔀 4. KEYWORD CANNIBALIZATION (Multiple URLs Splitting SERP Equity)#{Color::RESET}"
      if d[:cannibalization].empty?
        puts Color.c("  ✅ Clean URL architecture! No internal keyword cannibalization detected.", Color::GREEN)
      else
        d[:cannibalization].each do |c|
          puts "  #{Color.c('⚠️ Conflict:', Color::RED, Color::BOLD)} Query #{Color.c("\"#{c[:query]}\"", Color::BOLD)} (#{format_number(c[:total_impressions])} total imp) split across #{c[:pages].size} competing URLs:"
          c[:pages].each do |p|
            p_short = p[:page].sub(%r{^https?://[^/]+}, '')
            p_short = '/' if p_short.empty?
            puts "     ↳ Pos #{p[:position].to_s.ljust(4)} (#{format_number(p[:impressions]).rjust(4)} imp, #{p[:clicks]} clicks) ➔ #{Color.c(p_short, Color::CYAN)}"
          end
        end
        puts "  💡 #{Color::BOLD}Fix:#{Color::RESET} Consolidate canonical signals or point internal links to 1 primary URL to concentrate ranking authority."
      end
      puts

      # 6. Device Experience & Parity
      puts "#{Color::BOLD}📱 5. DEVICE EXPERIENCE & SERP PARITY#{Color::RESET}"
      puts "Device       | Clicks   | Impressions | CTR    | Position | Clicks Share"
      puts "-------------------------------------------------------------------------"
      d[:devices].each do |r|
        d_name = format_device(r[:device]).ljust(12)
        c_str = format_number(r[:clicks]).ljust(8)
        i_str = format_number(r[:impressions]).ljust(11)
        ctr_str = "#{r[:ctr]}%".ljust(6)
        pos_str = r[:position].to_s.ljust(8)
        share_str = r[:share].to_s
        puts "#{d_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{share_str}"
      end
      if d[:mobileDeficit]
        puts "  #{Color.c('⚠️ Mobile CTR Alert: Mobile CTR is significantly lower than Desktop. Audit mobile LCP speed and small-screen snippet readability.', Color::YELLOW)}"
      end
      puts

      # 7. GA4 Retention & High-Bounce Alerts
      if d[:ga4] && d[:ga4][:linked]
        puts "#{Color::BOLD}📈 6. ON-SITE RETENTION & HIGH-BOUNCE ALERTS (via GA4)#{Color::RESET}"
        puts "  • 30-Day GA4 Sessions:        #{format_number(d[:ga4][:sessions])}"
        puts "  • Overall Bounce Rate:         #{d[:ga4][:bounce_rate]}%"
        puts "  • Average Session Duration:    #{d[:ga4][:avg_duration]}"
        if d[:ga4][:high_bounce_pages].empty?
          puts Color.c("  ✅ No critical high-bounce landing pages (>80% with >= 10 sessions) detected.", Color::GREEN)
        else
          puts "  • Highest-Bounce Landing Pages (>= 10 sessions, >= 80% bounce):"
          d[:ga4][:high_bounce_pages].each_with_index do |hb, idx|
            puts "    #{idx + 1}. #{Color.c(hb[:path].ljust(30), Color::CYAN)} ➔ #{Color.c("#{hb[:sessions]} sess", Color::BOLD)} | #{Color.c("#{hb[:bounce_rate]}% bounce", Color::RED)} | #{hb[:duration]} avg"
          end
        end
        puts
      end

      # 8. Prioritized Action Plan
      puts "#{Color::BOLD}📋 7. PRIORITIZED ACTION PLAN (THE REAL VALUE ROADMAP)#{Color::RESET}"
      high_p = d[:actionPlan].select { |a| a[:priority] == 'high' }
      med_p  = d[:actionPlan].select { |a| a[:priority] == 'medium' }
      low_p  = d[:actionPlan].select { |a| a[:priority] == 'low' }

      idx = 1
      if high_p.any?
        puts "  #{Color.c('[🔴 HIGH PRIORITY - IMMEDIATE VALUE WINS]', Color::RED, Color::BOLD)}"
        high_p.each do |item|
          puts "    #{idx}. #{Color::BOLD}#{item[:title]}#{Color::RESET}"
          puts "       #{item[:detail]}"
          idx += 1
        end
      end

      if med_p.any?
        puts "  #{Color.c('[🟡 MEDIUM PRIORITY - HIGH-LEVERAGE GROWTH]', Color::YELLOW, Color::BOLD)}"
        med_p.each do |item|
          puts "    #{idx}. #{Color::BOLD}#{item[:title]}#{Color::RESET}"
          puts "       #{item[:detail]}"
          idx += 1
        end
      end

      if low_p.any?
        puts "  #{Color.c('[🟢 QUICK WIN / TECHNICAL MAINTENANCE]', Color::GREEN, Color::BOLD)}"
        low_p.each do |item|
          puts "    #{idx}. #{Color::BOLD}#{item[:title]}#{Color::RESET}"
          puts "       #{item[:detail]}"
          idx += 1
        end
      end
      puts
    end

    def self.handle_ga4_api_error(res, property_id, hostname, options)
      msg = res.dig(:data, 'error', 'message') || res[:data].to_s
      status = res[:status]

      if options[:json]
        puts JSON.pretty_generate({ error: msg, status: status })
        return
      end

      puts Color.c("\n❌ Google Analytics API Error (#{status}): #{msg}", Color::RED, Color::BOLD)

      # Check if error is due to Google Cloud API not being enabled
      is_disabled_api = msg =~ /has not been used in project|SERVICE_DISABLED|is disabled|enable it by visiting/i ||
                        (res.dig(:data, 'error', 'details')&.any? { |d| d['reason'] == 'SERVICE_DISABLED' } rescue false)

      if is_disabled_api
        url = msg[/https:\/\/[^\s]+/, 0] || (res.dig(:data, 'error', 'details', 0, 'links', 0, 'url') rescue nil)
        puts "\n#{Color.c("⚙️  ACTION REQUIRED: Google Cloud API Not Enabled", Color::YELLOW, Color::BOLD)}"
        puts "The requested Google Analytics API is disabled in your Google Cloud Project."
        if url
          puts "\n👉 #{Color::BOLD}Click this link to enable it in 1 click:#{Color::RESET}"
          puts "   #{Color.c(url, Color::CYAN, Color::BOLD)}"
        end
        puts "\nAfter clicking #{Color::BOLD}'ENABLE'#{Color::RESET} in Google Cloud Console, wait 1–2 minutes for Google propagation and retry."
        puts
        return
      end

      if status == 403
        sa_key = Auth.find_key
        sa_email = (JSON.parse(File.read(sa_key))['client_email'] rescue nil) if sa_key
        puts "\n#{Color::BOLD}How to Fix 403 (Permission Denied):#{Color::RESET}"
        puts "1. Copy your Service Account email:"
        if sa_email
          puts "   👉 #{Color.c(sa_email, Color::CYAN, Color::BOLD)}"
        else
          puts "   👉 (Check your service account JSON key)"
        end
        puts "2. Open Google Analytics: #{Color.c('https://analytics.google.com/', Color::CYAN)}"
        puts "3. Click ⚙️ #{Color::BOLD}Admin#{Color::RESET} (bottom-left corner)"
        if property_id && !property_id.to_s.strip.empty?
          puts "4. In Property Settings, click #{Color::BOLD}Property Access Management#{Color::RESET} (for Property #{property_id})"
        else
          puts "4. Click #{Color::BOLD}Account Access Management#{Color::RESET} (or Property Access Management)"
        end
        puts "5. Click the blue #{Color::BOLD}'+'#{Color::RESET} button (top-right) ➔ #{Color::BOLD}Add users#{Color::RESET}"
        puts "6. Paste your service account email and assign the #{Color::BOLD}Viewer#{Color::RESET} role."
        puts
      elsif status == 404
        puts "\nProperty ID '#{property_id}' was not found. Please verify your numeric GA4 Property ID.\n"
      end
    end

    def self.print_setup_instructions
      puts Color.c("\n❌ Error: Google Service Account Key JSON not found!\n", Color::RED, Color::BOLD)
      puts <<~SETUP
        #{Color::BOLD}QUICK SETUP GUIDE (2 Minutes):#{Color::RESET}

        #{Color::CYAN}1. Google Cloud Console:#{Color::RESET}
           • Go to: https://console.cloud.google.com/
           • In 'APIs & Services' > 'Library', enable:
             - #{Color::BOLD}Web Search Indexing API#{Color::RESET}
             - #{Color::BOLD}Google Search Console API#{Color::RESET}
             - #{Color::BOLD}Google Analytics Data API#{Color::RESET} (for on-site metrics & retention)
             - #{Color::BOLD}Google Analytics Admin API#{Color::RESET} (for auto-discovering GA4 properties)
           • In 'IAM & Admin' > 'Service Accounts', create a service account.
           • Click the service account > 'Keys' > 'Add Key' > 'Create new key' > 'JSON'.
           • Download the key.

        #{Color::CYAN}2. Run 1-Click Connect:#{Color::RESET}
           • Run: #{Color.c('gsc connect', Color::GREEN, Color::BOLD)}
           • It will automatically find the key in Downloads or let you drag & drop it!

        #{Color::CYAN}3. Google Search Console Permissions:#{Color::RESET}
           • Copy your Service Account email (shown during gsc connect).
           • Go to: https://search.google.com/search-console/
           • Select your property > 'Settings' > 'Users and permissions'.
           • Click #{Color::BOLD}'Add User'#{Color::RESET} with permission #{Color::BOLD}Owner#{Color::RESET}.

        Then re-run: #{Color::BOLD}gsc domains#{Color::RESET} to verify!
      SETUP
    end

def self.print_main_menu_shortcuts
  puts "#{Color::BOLD}📂 Command Groups (Type letter to explore sub-shortcuts):#{Color::RESET}"
  puts "  #{Color.c('[k]', Color::CYAN, Color::BOLD)} Keywords & Trends    #{Color.c('[a]', Color::YELLOW, Color::BOLD)} Search Analytics    #{Color.c('[g]', Color::MAGENTA, Color::BOLD)} GA4 & Realtime"
  puts "  #{Color.c('[i]', Color::GREEN, Color::BOLD)} Indexing & Sitemaps  #{Color.c('[s]', Color::BLUE, Color::BOLD)} Setup & Config      #{Color.c('[?]', Color::WHITE, Color::BOLD)} All Commands"
  puts
  puts "#{Color::BOLD}⚡ Quick Shortcuts (Run directly from any prompt):#{Color::RESET}"
  puts "  #{Color.c('[pb]', Color::MAGENTA, Color::BOLD)}  AI Playbooks  #{Color.c('[p]', Color::YELLOW, Color::BOLD)}   Performance   #{Color.c('[tq]', Color::YELLOW, Color::BOLD)} Top Queries   #{Color.c('[tp]', Color::YELLOW, Color::BOLD)} Top Pages"
  puts "  #{Color.c('[o]', Color::YELLOW, Color::BOLD)}   Opportunities   #{Color.c('[u]', Color::YELLOW, Color::BOLD)}   Underperf     #{Color.c('[aud]', Color::CYAN, Color::BOLD)} Full Audit   #{Color.c('[r]', Color::GREEN, Color::BOLD)} GA4 Realtime"
  puts "  #{Color.c('[tr]', Color::CYAN, Color::BOLD)}  Trends <query>  #{Color.c('[kp]', Color::CYAN, Color::BOLD)}  Planner <kw>  #{Color.c('[ke]', Color::YELLOW, Color::BOLD)} Keywords <kw> #{Color.c('[imp]', Color::CYAN, Color::BOLD)} Import File"
  puts "  #{Color.c('[q]', Color::GRAY, Color::BOLD)}   Quit (or exit)"
  puts
end

def self.print_keywords_menu
  puts "\n#{Color::BOLD}📈 GOOGLE TRENDS & KEYWORD INTELLIGENCE:#{Color::RESET}"
  puts "  #{Color.c('[tr]  trends <query>', Color::CYAN, Color::BOLD)}       Real-time Google Trends 5-year/12-month demand & velocity"
  puts "  #{Color.c('[kp]  planner <seed>', Color::CYAN, Color::BOLD)}       Free autocomplete keyword expander & intent classifier"
  puts "  #{Color.c('[ke]  ke <query>', Color::YELLOW, Color::BOLD)}           Keywords Everywhere exact monthly volume, CPC & competition"
  puts "  #{Color.c('[imp] import <file>', Color::CYAN, Color::BOLD)}        Import Keywords Everywhere TSV/CSV or Google Ads export"
  puts "  #{Color.c('[sv]  saved', Color::GREEN, Color::BOLD)}                List saved domain keyword research snapshots"
  puts "  #{Color.c('[chk] check [id]', Color::GREEN, Color::BOLD)}           Re-check saved keywords against live Search Console rankings"
  puts "  #{Color.c('[cr]  ke-credits', Color::YELLOW, Color::BOLD)}           Check remaining Keywords Everywhere account balance"
  puts "  #{Color.c('[ck]  connect ke [key]', Color::GREEN, Color::BOLD)}     Connect Keywords Everywhere API key"
  puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
  puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
  puts
end

def self.print_analytics_menu
  puts "\n#{Color::BOLD}📊 SEARCH ANALYTICS & MONITORING:#{Color::RESET}"
  puts "  #{Color.c('[p]   performance', Color::YELLOW, Color::BOLD)}          Executive dashboard: Totals, Devices, Countries, Snippets, Queries"
  puts "  #{Color.c('[tq]  top-queries', Color::YELLOW, Color::BOLD)}          Top search queries, rankings, impressions, CTR, and position"
  puts "  #{Color.c('[tp]  top-pages', Color::YELLOW, Color::BOLD)}            Top landing pages driving clicks and impressions"
  puts "  #{Color.c('[o]   opportunities', Color::YELLOW, Color::BOLD)}        Striking-distance Page 2 queries (Pos 7–20) to push to Top 3"
  puts "  #{Color.c('[u]   underperformers', Color::YELLOW, Color::BOLD)}      Top 10 ranking queries with low CTR (title & meta win hooks)"
  puts "  #{Color.c('[c]   cannibalization', Color::RED, Color::BOLD)}      Detect multiple internal URLs competing for the same search query"
  puts "  #{Color.c('[d]   decay', Color::RED, Color::BOLD)}                28-day period-over-period trend analysis (decaying vs surging)"
  puts "  #{Color.c('[aud] audit', Color::CYAN, Color::BOLD)}                Automated 4-step comprehensive SEO & indexing health audit"
  puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
  puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
  puts
end

def self.print_ga4_menu
  puts "\n#{Color::BOLD}📈 GOOGLE ANALYTICS 4 (GA4) & POST-CLICK BEHAVIOR:#{Color::RESET}"
  puts "  #{Color.c('[r]   realtime [--watch]', Color::GREEN, Color::BOLD)}   Live active visitors, pages, and countries right now"
  puts "  #{Color.c('[ga]  ga4 [--organic]', Color::MAGENTA, Color::BOLD)}      Landing page bounce rates, engagement rates, sessions, duration"
  puts "  #{Color.c('[co]  correlation', Color::MAGENTA, Color::BOLD)}          Merge GSC keyword rankings with GA4 bounce rates per landing page"
  puts "  #{Color.c('[ad]  ads', Color::MAGENTA, Color::BOLD)}                  Google Ads campaign performance (Clicks, Cost, CPC, CPA, Conv)"
  puts "  #{Color.c('[ch]  channels', Color::MAGENTA, Color::BOLD)}             Omnichannel acquisition breakdown (Organic, Paid, Direct, Referral)"
  puts "  #{Color.c('[cg]  connect-ga4', Color::GREEN, Color::BOLD)}          Interactive GA4 linking wizard"
  puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
  puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
  puts
end

def self.print_indexing_menu
  puts "\n#{Color::BOLD}🔍 GOOGLEBOT INDEXING & SITEMAPS:#{Color::RESET}"
  puts "  #{Color.c('[ins] inspect <url>', Color::CYAN, Color::BOLD)}        Live Search Console URL inspection (verdict, coverage, canonical)"
  puts "  #{Color.c('[idx] index <url>', Color::GREEN, Color::BOLD)}          Notify Googlebot to crawl/index a URL immediately (URL_UPDATED)"
  puts "  #{Color.c('[rm]  remove <url>', Color::RED, Color::BOLD)}         Notify Googlebot a URL has been deleted (URL_DELETED)"
  puts "  #{Color.c('[map] sitemaps', Color::MAGENTA, Color::BOLD)}             List submitted sitemaps in Search Console and crawl status"
  puts "  #{Color.c('[sub] sitemaps-submit <url>', Color::MAGENTA, Color::BOLD)} Submit new XML sitemap to Google Search Console"
  puts "  #{Color.c('[bi]  inspect-sitemap <file>', Color::CYAN, Color::BOLD)} Bulk inspect all sitemap URLs in XML file"
  puts "  #{Color.c('[z]   zombies <sitemap>', Color::RED, Color::BOLD)}     Detect 90-day zero-impression pages wasting crawl budget"
  puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
  puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
  puts
end

def self.print_setup_menu
  puts "\n#{Color::BOLD}⚙️ SETUP, DOMAINS & CONFIGURATION:#{Color::RESET}"
  puts "  #{Color.c('[1-N] <num>', Color::CYAN, Color::BOLD)}                Switch active domain by number"
  puts "  #{Color.c('[c]   connect', Color::GREEN, Color::BOLD)}              1-Click Setup Wizard: auto-detects key or drag & drop"
  puts "  #{Color.c('[cg]  connect-ga4', Color::GREEN, Color::BOLD)}          Interactive GA4 linking wizard"
  puts "  #{Color.c('[ck]  connect ke [key]', Color::GREEN, Color::BOLD)}     Connect Keywords Everywhere API key"
  puts "  #{Color.c('[o]   open', Color::GREEN, Color::BOLD)}                 Reveal configuration directory (~/.config/gsc) in Finder"
  puts "  #{Color.c('[w]   where', Color::GREEN, Color::BOLD)}                Inspect CLI installation path, active credentials, and config"
  puts "  #{Color.c('[v]   version', Color::GREEN, Color::BOLD)}              Show version and runtime environment"
  puts "  #{Color.c('[u]   update', Color::GREEN, Color::BOLD)}               Fetch latest release from GitHub and self-update"
  puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
  puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
  puts
end

def self.handle_interactive_shell(options = {})
  puts BANNER

  domains = fetch_available_domains
  active = Config.default_domain
  if (active.nil? || active.empty?) && domains.any?
    active = Config.set_default_domain(domains.first)
  end

  if active
    puts "Active Target Domain: #{Color.c(active, Color::GREEN, Color::BOLD)}"
  else
    puts Color.c("No active domain configured. Run 'connect' to configure.", Color::YELLOW)
  end
  puts

  if domains.any?
    puts "#{Color::BOLD}🌐 Verified Domains (Type number 1-#{domains.size} to switch):#{Color::RESET}"
    domains.each_with_index do |dom, idx|
      marker = (dom == active) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""
      ga4_id = Config.ga4_property_id(dom)
      ga4_str = ga4_id ? Color.c("[GA4: #{ga4_id}]", Color::MAGENTA) : ""
      puts "  #{Color.c("[#{idx + 1}]", Color::CYAN, Color::BOLD)} #{dom.ljust(26)} #{ga4_str}#{marker}"
    end
    puts
  end

  print_main_menu_shortcuts

  current_group = nil

  loop do
    current_dom = Config.default_domain || 'no-domain'
    prompt_label = current_group ? "gsc [#{current_dom}] (#{current_group})> " : "gsc [#{current_dom}]> "
    print "#{Color::BOLD}#{Color::CYAN}#{prompt_label}#{Color::RESET}"

    raw = $stdin.gets
    break if raw.nil?

    input = raw.strip

    if input.empty?
      next
    end

    # Universal quit
    if %w[q quit exit bye :q q!].include?(input.downcase)
      break
    end

    # Return to main menu from sub-group
    if %w[b back .. main].include?(input.downcase)
      if current_group
        current_group = nil
        puts Color.c("↩ Back to main menu.\n", Color::DIM)
        print_main_menu_shortcuts
      end
      next
    end

    # Show help/menu
    if %w[? help menu commands].include?(input.downcase) || input == ' '
      if current_group == :keywords
        print_keywords_menu
      elsif current_group == :analytics
        print_analytics_menu
      elsif current_group == :ga4
        print_ga4_menu
      elsif current_group == :indexing
        print_indexing_menu
      elsif current_group == :setup
        print_setup_menu
      else
        print_main_menu_shortcuts
        print_commands_help
      end
      next
    end

    # Number: domain switch
    if input =~ /^\d+$/
      handle_use_command(input, options.merge(in_dashboard: true))
      puts
      next
    end

    # Group switches from main menu
    if current_group.nil?
      case input.downcase
      when 'k', 'keywords'
        current_group = :keywords
        print_keywords_menu
        next
      when 'a', 'analytics'
        current_group = :analytics
        print_analytics_menu
        next
      when 'g', 'ga4', 'traffic'
        current_group = :ga4
        print_ga4_menu
        next
      when 'i', 'indexing', 'sitemaps'
        current_group = :indexing
        print_indexing_menu
        next
      when 's', 'setup', 'config'
        current_group = :setup
        print_setup_menu
        next
      end
    end

    # Built-in clear
    if %w[clear cls].include?(input.downcase)
      print "\e[H\e[2J"
      next
    end

    # Domains list
    if %w[domains list].include?(input.downcase)
      doms = fetch_available_domains
      puts "\n🌐 Verified Domains:"
      doms.each_with_index do |d, idx|
        marker = (d == Config.default_domain) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""
        puts "  #{Color.c("[#{idx + 1}]", Color::CYAN, Color::BOLD)} #{d}#{marker}"
      end
      puts
      next
    end

    # Shellwords parse
    require 'shellwords'
    cmd_args = Shellwords.split(input) rescue input.split
    first = cmd_args[0].downcase

    # Sub-menu and global shortcut resolution
    resolved_cmd = case first
                   # Analytics
                   when 'p', 'perf' then 'performance'
                   when 'tq', 'queries', 'query' then 'top-queries'
                   when 'tp', 'pages' then 'top-pages'
                   when 'o', 'opp' then 'opportunities'
                   when 'u', 'under', 'low' then 'underperformers'
                   when 'c', 'conflicts', 'cann' then 'cannibalization'
                   when 'd', 'decay' then 'decay'
                   when 'aud', 'audit' then 'audit'
                   # Keywords & Trends
                   when 'tr', 'trends' then 'trends'
                   when 'kp', 'planner' then 'planner'
                   when 'ke' then 'ke'
                   when 'imp', 'import', 'pi' then 'import'
                   when 'cr', 'credits', 'kec' then 'ke-credits'
when 'sv', 'saved', 'research' then 'saved'
when 'chk', 'check' then 'check'
when 'pb', 'prompts', 'prompt', 'playbooks', 'playbook' then 'prompts'

                   # GA4
                   when 'r', 'live' then 'realtime'
                   when 'ga', 'bounce' then 'ga4'
                   when 'co', 'corr' then 'correlation'
                   when 'ad', 'ads' then 'ads'
                   when 'ch', 'channels' then 'channels'
                   # Indexing & Sitemaps
                   when 'ins', 'inspect' then 'inspect'
                   when 'idx', 'index' then 'index'
                   when 'rm', 'remove' then 'remove'
                   when 'map', 'sitemaps' then 'sitemaps-list'
                   when 'sub', 'sitemaps-submit' then 'sitemaps-submit'
                   when 'bi', 'inspect-sitemap' then 'inspect-sitemap'
                   when 'z', 'zombies' then 'zombies'
                   # Setup
                   when 'cg', 'connect-ga4' then 'connect-ga4'
                   when 'w', 'where' then 'where'
                   when 'v', 'version' then 'version'
                   else first
                   end

    # Special case for ck -> connect ke
    if first == 'ck'
      cmd_args = ['connect', 'ke'] + cmd_args[1..]
    else
      cmd_args[0] = resolved_cmd
    end

    begin
      self.run(cmd_args + ['--in-dashboard'])
    rescue Interrupt
      puts "\n(Action cancelled)"
    rescue StandardError => e
      puts Color.c("❌ Error: #{e.message}", Color::RED)
    end

    puts
  end

  puts Color.c("\n👋 Exited interactive mode.", Color::DIM)
end

def self.print_commands_help
      puts <<~COMMANDS

        #{Color::BOLD}SETUP, CONFIGURATION & DOMAIN SWITCHING:#{Color::RESET}
          #{Color.c('connect', Color::GREEN)}                       1-Click Setup Wizard: auto-detects key or drag & drop
          #{Color.c('open', Color::GREEN)}                          Reveal config folder (~/.config/gsc) in Finder
          #{Color.c('use <domain>', Color::GREEN)}                 Set default active domain (saved in ~/.config/gsc/config.json)
          #{Color.c('where', Color::GREEN)}                        Show CLI location, active credentials, and config path
          #{Color.c('config', Color::GREEN)}                       View or update current CLI configuration
          #{Color.c('domains', Color::GREEN)}                      List all verified Search Console properties (highlights active)
          #{Color.c('version', Color::GREEN)}                      Show CLI version and runtime environment
          #{Color.c('update', Color::GREEN)}                       Fetch latest version from GitHub and self-update

        #{Color::BOLD}GOOGLE TRENDS & KEYWORD INTELLIGENCE:#{Color::RESET}
          #{Color.c('trends <keyword>', Color::CYAN).ljust(38)} Real-time Google Trends search demand, velocity & breakouts
          #{Color.c('planner <seed>', Color::CYAN).ljust(38)} Autocomplete expansion, search intent & opportunity scoring
          #{Color.c('planner-import <file>', Color::CYAN).ljust(38)} Import Google Ads Keyword Planner CSV/TSV export & score
          #{Color.c('ke <keyword|file>', Color::YELLOW).ljust(38)} Keywords Everywhere exact monthly volume, CPC & competition
          #{Color.c('ke-credits', Color::YELLOW).ljust(38)} Check remaining Keywords Everywhere account balance
          #{Color.c('connect ke [key]', Color::GREEN).ljust(38)} Connect Keywords Everywhere API key (~/.config/gsc/config.json)

#{Color::BOLD}SEARCH ANALYTICS & MONITORING:#{Color::RESET}
          #{Color.c('performance', Color::YELLOW)}                  Executive dashboard: Totals, Devices, Countries, Snippets, Queries, Pages, Cities
          #{Color.c('top-queries', Color::YELLOW)}                  Top search queries, impressions, CTR, and average rankings
          #{Color.c('top-pages', Color::YELLOW)}                    Top indexed pages driving clicks & impressions
          #{Color.c('devices', Color::YELLOW)}                      Device breakdown (Desktop, Mobile, Tablet) with clicks share
          #{Color.c('countries', Color::YELLOW)}                    Geographic search demand by country (with flags & CTR)
          #{Color.c('cities', Color::YELLOW)}                       Top visitor cities, volume, bounce rates & retention (via GA4)
          #{Color.c('snippets', Color::YELLOW)}                     Search appearance & rich snippets (Reviews, Products, FAQs)
          #{Color.c('audit', Color::CYAN)}                        Automated 4-step SEO & Indexing Health Check

        #{Color::BOLD}ENTERPRISE GROWTH & AUDIT INTELLIGENCE:#{Color::RESET}
          #{Color.c('opportunities', Color::YELLOW)}                Striking-distance queries (Pos 7–20) to push to Page 1 / Top 3
          #{Color.c('underperformers', Color::YELLOW)}              Top 10 queries with low CTR (easy title & meta hook wins)
          #{Color.c('cannibalization', Color::RED)}                Detect multiple URLs competing for the same query
          #{Color.c('decay [--compare 28]', Color::RED)}           Period-over-period trend analysis (Decaying vs Surging)
          #{Color.c('zombies [sitemap]', Color::RED)}              Detect zero-impression pages in sitemap wasting crawl budget

        #{Color::BOLD}GOOGLE ANALYTICS 4 (GA4) & POST-CLICK BEHAVIOR:#{Color::RESET}
          #{Color.c('connect-ga4', Color::MAGENTA)}                 Interactive GA4 linking wizard (walks through setup & tests live)
          #{Color.c('config set-ga4 <id>', Color::MAGENTA)}         Link a GA4 Property ID to active domain (stored in config)
          #{Color.c('config unlink-ga4', Color::MAGENTA)}           Unlink GA4 Property ID from active domain
          #{Color.c('realtime [--watch]', Color::MAGENTA)}          Live active visitors, pages, and countries right now
          #{Color.c('ga4 [--organic]', Color::MAGENTA)}             Landing page bounce rates, engagement rates, sessions, duration
          #{Color.c('correlation [--organic]', Color::MAGENTA)}     Merge GSC keyword rankings with GA4 bounce rates per landing page
          #{Color.c('ads [--days 30]', Color::MAGENTA)}             Google Ads campaign performance (Clicks, Cost, CPC, CPA, Conv)
          #{Color.c('channels [--days 30]', Color::MAGENTA)}        Omnichannel acquisition breakdown (Organic, Paid, Direct, Referral)
          #{Color.c('ga4-properties', Color::MAGENTA)}              Discover all GA4 Property IDs accessible by your service account

        #{Color::BOLD}INDEXING & SITEMAP COMMANDS:#{Color::RESET}
          #{Color.c('index <url>', Color::GREEN)}                  Notify Googlebot to crawl/index a URL (URL_UPDATED)
          #{Color.c('remove <url>', Color::GREEN)}                 Notify Googlebot a URL has been deleted (URL_DELETED)
          #{Color.c('status <url>', Color::GREEN)}                 Check Google Indexing API metadata for a URL
          #{Color.c('inspect <url>', Color::CYAN)}                Live Search Console URL inspection (coverage, canonical, crawl date)
          #{Color.c('inspect-sitemap [path|url]', Color::CYAN)}  Bulk inspect all sitemap URLs & generate health report
          #{Color.c('index-sitemap [path|url]', Color::GREEN)}    Submit all URLs in an XML sitemap for batch indexing
          #{Color.c('sitemaps-list', Color::MAGENTA)}                List submitted sitemaps in Search Console & status
          #{Color.c('sitemaps-submit <url>', Color::MAGENTA)}        Submit / re-submit an XML sitemap to Search Console

        #{Color::BOLD}AGENT & PROGRAMMATIC INTEGRATION:#{Color::RESET}
          #{Color.c('skills [install|show]', Color::CYAN)}        Inspect, install, or export the AI Agent Skill
          #{Color.c('-j, --json', Color::CYAN)}                   Machine-readable JSON output for all commands

        #{Color::BOLD}EXAMPLES BY WORKFLOW:#{Color::RESET}

        #{Color.c('1. Domain Setup & Switching:', Color::CYAN, Color::BOLD)}
          gsc connect                                  # Interactive 1-click credential setup
          gsc domains                                  # List all verified properties (choose by number)
          gsc use                                      # Interactive numbered domain switcher
          gsc use 2                                    # Switch active domain by number
          gsc use example.com                          # Switch active domain by name
          gsc where                                    # Inspect CLI path, active key, and config file

        #{Color.c('2. GA4 Linking & Analytics:', Color::CYAN, Color::BOLD)}
          gsc connect-ga4                              # Interactive GA4 linking wizard
          gsc config set-ga4 123456789                 # Link GA4 property ID to active domain
          gsc ga4-properties                           # Discover accessible GA4 properties
          gsc ga4 --organic                            # View landing page bounce rates & engagement
          gsc correlation                              # Correlate SERP rankings with on-site bounce rates
          gsc ads                                      # Google Ads campaign performance, cost & CPC
          gsc channels                                 # Omnichannel traffic sources (Organic, Paid, Direct)

        #{Color.c('3. Live Realtime Visitor Monitoring:', Color::CYAN, Color::BOLD)}
          gsc realtime                                 # Snapshot of active visitors, URLs & countries
          gsc realtime --watch                         # Stream live visitors in terminal (refreshes every 5s)
          gsc realtime -d example.com --watch 3        # Stream specific domain every 3s
          gsc realtime --json                          # Machine-readable JSON output for live dashboards

        #{Color.c('4. Search Performance & Multi-Dimensional Analytics:', Color::CYAN, Color::BOLD)}
          gsc performance                              # Executive 360° dashboard (Devices, Countries, Snippets, Cities)
          gsc devices                                  # Desktop vs Mobile vs Tablet search traffic breakdown
          gsc countries --limit 20                     # Top countries driving organic search impressions & clicks
          gsc cities --limit 20                        # Top visitor cities and behavioral retention (via GA4)
          gsc snippets                                 # Rich snippet appearances (Review stars, Product listings, FAQs)
          gsc top-queries                              # Top search keywords, impressions, CTR, position
          gsc top-queries -s imp --days 7              # Sort queries by highest impression volume
          gsc top-pages -s clicks                      # Top traffic-driving landing pages
          gsc opportunities --min-imp 10               # Striking-distance queries (Pos 7–20) to push to Top 3
          gsc underperformers                          # Fix low CTR titles on existing Top 10 rankings
          gsc cannibalization                          # Detect internal URL ranking conflicts
          gsc decay --compare 28                       # Compare last 28 days vs prior 28 days
          gsc zombies public/sitemap.xml               # Find zero-impression crawl waste pages
          gsc audit                                    # Comprehensive 4-step SEO & GA4 health audit

        #{Color.c('5. Google Indexing & Sitemaps:', Color::CYAN, Color::BOLD)}
          gsc inspect https://example.com/pricing      # Live Google index check (coverage, canonical, date)
          gsc index https://example.com/new-page       # Notify Googlebot to crawl/index URL immediately
          gsc remove https://example.com/deleted-page  # Notify Googlebot a page has been removed
          gsc status https://example.com/page          # Check Google Indexing API submission status
          gsc sitemaps-list                            # List submitted sitemaps in Search Console
          gsc sitemaps-submit https://example.com/sitemap.xml # Submit new XML sitemap to Google
          gsc index-sitemap public/sitemap.xml         # Batch submit all sitemap URLs to Google Indexing API
          gsc inspect-sitemap public/sitemap.xml       # Bulk inspect indexation status for all sitemap URLs

        #{Color.c('6. Agent & JSON Export:', Color::CYAN, Color::BOLD)}
          gsc top-queries --json                       # Clean JSON output for AI agents & pipelines
          gsc top-pages --csv pages.csv                # Export top pages to CSV
          gsc skills show                              # View the AI Agent Skill prompt
          gsc skills install                           # Install agent skill to ~/.gemini/config
        #{Color.c('7. Trends, Autocomplete & Keyword Intelligence:', Color::CYAN, Color::BOLD)}
          gsc trends "moving boxes"                    # Google Trends search interest & regional demand
          gsc trends "packing supplies" --geo US       # Filter trends to United States
          gsc trends "storage bins" --time 12m         # 12-month interest timeline & momentum
          gsc planner "moving checklist"               # Free autocomplete expansion & opportunity scoring
          gsc planner-import keywords.csv              # Import Google Ads Keyword Planner export & rank
          gsc ke "moving boxes"                        # Keywords Everywhere search volume, CPC & competition
          gsc ke-credits                               # Check remaining Keywords Everywhere credit balance
          gsc connect ke                               # Link Keywords Everywhere API key

      COMMANDS
    end
  end
end

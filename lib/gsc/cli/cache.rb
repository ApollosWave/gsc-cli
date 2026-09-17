# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../cache_manager' if File.exist?(File.expand_path('../cache_manager.rb', __dir__))

module GSC
  class CLI
    module Cache
      module_function

      def run(action, target, extra, options, api = nil)
        mgr = GSC::CacheManager.new

        subcmd = action.to_s.downcase.strip
        subcmd = 'status' if subcmd.empty? || subcmd == 'cache'

        case subcmd
        when 'status', 'info', 'stats'
          handle_status(mgr, options)
        when 'warm', 'sync', 'fetch'
          handle_warm(mgr, target || options[:domain], options, api)
        when 'query', 'queries', 'search', 'q'
          handle_query(mgr, target, options)
        when 'pages', 'page', 'p'
          handle_pages(mgr, target, options)
        when 'diff', 'compare'
          handle_diff(mgr, target || options[:domain], extra, options)
        when 'clear', 'reset', 'drop'
          handle_clear(mgr, target || options[:domain], options)
        else
          # If target was provided as a search term directly: `gsc cache "seo audit"`
          handle_query(mgr, action, options)
        end
      end

      def handle_status(mgr, options)
        stats = mgr.status
        if options[:json]
          puts JSON.pretty_generate(stats)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "💾 #{Color::BOLD}LOCAL QUERY & ANALYTICS CACHE STATUS#{Color::RESET}"
        puts "─" * 70
        puts "  ⚙️ Storage Engine  : #{Color.c(stats[:engine].to_s.upcase, Color::GREEN, Color::BOLD)}"
        puts "  📁 Database Path   : #{stats[:path]}"
        puts "  📊 Database Size   : #{Color.c(stats[:formatted_size], Color::CYAN, Color::BOLD)}"
        puts "  🔎 Cached Queries  : #{Color.c(Base.format_number(stats[:total_queries]), Color::YELLOW, Color::BOLD)}"
        puts "  📄 Cached Pages    : #{Color.c(Base.format_number(stats[:total_pages]), Color::YELLOW, Color::BOLD)}"
        puts "  🌐 Cached Domains  : #{stats[:domains].empty? ? '(none)' : stats[:domains].join(', ')}"
        puts "  🕒 Last Updated    : #{stats[:last_updated] || 'Never'}"
        puts "  📸 Snapshots Count : #{stats[:snapshots].size}"
        puts "─" * 70
        puts "💡 #{Color::DIM}Run 'gsc cache warm' to sync Search Console data into local offline storage.#{Color::RESET}\n"
      end

      def handle_warm(mgr, domain_arg, options, api)
        hostname, site_url, _origin = Base.resolve_domain(domain_arg, nil, options)
        days = options[:days] || 30
        limit = options[:limit] || 5000

        unless api
          key_path = Auth.find_key(options[:key])
          Auth.validate_key_file!(key_path, options)
          sa = JSON.parse(File.read(key_path))
          token = Auth.fetch_access_token(sa)
          client = Client.new(token: token)
          api = API.new(client)
        end

        unless options[:json]
          puts Base::BANNER unless options[:in_dashboard]
          puts "🔥 #{Color::BOLD}WARMING LOCAL QUERY CACHE#{Color::RESET} for #{Color.c(hostname, Color::CYAN, Color::BOLD)} (Past #{days} days)..."
        end

        res = mgr.warm(site_url, api, days: days, limit: limit)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        puts "✅ Successfully warmed local cache in #{Color.c("#{res[:elapsed_ms]}ms", Color::GREEN, Color::BOLD)}!"
        puts "  • Saved Queries : #{Color.c(Base.format_number(res[:queries_saved]), Color::YELLOW, Color::BOLD)}"
        puts "  • Saved Pages   : #{Color.c(Base.format_number(res[:pages_saved]), Color::YELLOW, Color::BOLD)}"
        puts "  • Snapshot Date : #{res[:snapshot_date]}"
        puts "\n💡 #{Color::DIM}You can now query instantly offline: 'gsc cache query [term]'#{Color::RESET}\n"
      end

      def handle_query(mgr, search_term, options)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        domain = options[:domain]
        sort = options[:sort] || 'clicks'
        order = options[:order] || 'desc'
        limit = options[:limit] || 50
        min_clicks = options[:min_clicks] || 0
        min_imp = options[:min_imp] || 0

        rows = mgr.query(
          domain: domain,
          search: search_term,
          min_clicks: min_clicks,
          min_impressions: min_imp,
          sort: sort,
          order: order,
          limit: limit
        )

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        if options[:json]
          puts JSON.pretty_generate({ total: rows.size, elapsed_ms: elapsed_ms, rows: rows })
          return
        end

        if options[:csv]
          Base.write_csv(options[:csv], %w[Domain Query Page Clicks Impressions CTR Position Date], rows.map { |r| [r[:domain], r[:query], r[:page], r[:clicks], r[:impressions], r[:ctr], r[:position], r[:snapshot_date]] })
          puts Color.c("📁 Exported #{rows.size} cached query rows to #{options[:csv]} (#{elapsed_ms}ms)\n", Color::CYAN)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        search_label = search_term && !search_term.strip.empty? ? " matching #{Color.c("\"#{search_term}\"", Color::CYAN)}" : ""
        puts "⚡ #{Color::BOLD}OFFLINE CACHED SEARCH QUERIES#{Color::RESET}#{search_label} (#{Color.c("#{elapsed_ms}ms response", Color::GREEN)})"
        puts "─" * 90

        if rows.empty?
          puts "  (No cached queries found. Run 'gsc cache warm' to populate local database)"
          puts "─" * 90
          return
        end

        puts "%-42s %8s %10s %8s %8s" % ['Query', 'Clicks', 'Impressions', 'CTR', 'Position']
        puts "─" * 90
        rows.each do |r|
          q_str = r[:query].length > 40 ? "#{r[:query][0..37]}..." : r[:query]
          ctr_str = "#{r[:ctr]}%"
          puts "%-42s %8s %10s %8s %8s" % [
            Color.c(q_str, Color::BOLD),
            Color.c(Base.format_number(r[:clicks]), Color::GREEN),
            Base.format_number(r[:impressions]),
            ctr_str,
            Color.c(r[:position].to_s, Color::CYAN)
          ]
        end
        puts "─" * 90
        puts "Showing #{rows.size} cached queries | Instant sub-10ms offline response (0 Google API quota used)\n"
      end

      def handle_pages(mgr, search_term, options)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        domain = options[:domain]
        sort = options[:sort] || 'clicks'
        order = options[:order] || 'desc'
        limit = options[:limit] || 50
        min_clicks = options[:min_clicks] || 0

        rows = mgr.pages(
          domain: domain,
          search: search_term,
          min_clicks: min_clicks,
          sort: sort,
          order: order,
          limit: limit
        )

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        if options[:json]
          puts JSON.pretty_generate({ total: rows.size, elapsed_ms: elapsed_ms, rows: rows })
          return
        end

        if options[:csv]
          Base.write_csv(options[:csv], %w[Domain Page Clicks Impressions CTR Position Date], rows.map { |r| [r[:domain], r[:page], r[:clicks], r[:impressions], r[:ctr], r[:position], r[:snapshot_date]] })
          puts Color.c("📁 Exported #{rows.size} cached pages to #{options[:csv]} (#{elapsed_ms}ms)\n", Color::CYAN)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "⚡ #{Color::BOLD}OFFLINE CACHED LANDING PAGES#{Color::RESET} (#{Color.c("#{elapsed_ms}ms response", Color::GREEN)})"
        puts "─" * 90

        if rows.empty?
          puts "  (No cached pages found. Run 'gsc cache warm' to populate local database)"
          puts "─" * 90
          return
        end

        puts "%-48s %8s %10s %8s %8s" % ['Page Path', 'Clicks', 'Impressions', 'CTR', 'Position']
        puts "─" * 90
        rows.each do |r|
          p_str = Base.normalize_path(r[:page])
          p_str = p_str.length > 46 ? "#{p_str[0..43]}..." : p_str
          puts "%-48s %8s %10s %8s %8s" % [
            Color.c(p_str, Color::CYAN),
            Color.c(Base.format_number(r[:clicks]), Color::GREEN),
            Base.format_number(r[:impressions]),
            "#{r[:ctr]}%",
            r[:position]
          ]
        end
        puts "─" * 90
        puts "Showing #{rows.size} cached pages | Instant sub-10ms offline response\n"
      end

      def handle_diff(mgr, domain_arg, second_arg, options)
        hostname, _site_url, _origin = Base.resolve_domain(domain_arg, nil, options)
        old_date = options[:old_date] || second_arg
        new_date = options[:new_date]

        res = mgr.diff(hostname, old_date, new_date)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "📊 #{Color::BOLD}HISTORIC OFFLINE QUERY DIFF:#{Color::RESET} #{Color.c(hostname, Color::CYAN, Color::BOLD)}"
        puts "  Comparing: #{Color.c(res[:old_date] || 'Previous', Color::YELLOW)} ➔ #{Color.c(res[:new_date] || 'Current', Color::GREEN)}"
        puts "─" * 80
        puts "  📈 Surging Winners  : #{Color.c(res[:summary][:winners_count].to_s, Color::GREEN, Color::BOLD)}"
        puts "  📉 Decaying Losers   : #{Color.c(res[:summary][:losers_count].to_s, Color::RED, Color::BOLD)}"
        puts "  ✨ New Discovered    : #{Color.c(res[:summary][:new_queries_count].to_s, Color::CYAN, Color::BOLD)}"
        puts "  🗑️ Dropped Queries   : #{Color.c(res[:summary][:dropped_queries_count].to_s, Color::MAGENTA, Color::BOLD)}"
        puts "─" * 80

        if res[:winners].any?
          puts "\n#{Color::BOLD}🚀 Top Surging Queries (Clicks Gained):#{Color::RESET}"
          res[:winners].first(5).each do |w|
            puts "  • #{Color.c(w[:query], Color::BOLD)}: +#{w[:click_delta]} clicks (#{w[:old_clicks]} ➔ #{w[:new_clicks]}), rank delta: #{w[:pos_delta] > 0 ? "+#{w[:pos_delta]}" : w[:pos_delta]}"
          end
        end

        if res[:losers].any?
          puts "\n#{Color::BOLD}⚠️ Top Decaying Queries (Clicks Lost):#{Color::RESET}"
          res[:losers].first(5).each do |l|
            puts "  • #{Color.c(l[:query], Color::BOLD)}: #{l[:click_delta]} clicks (#{l[:old_clicks]} ➔ #{l[:new_clicks]}), rank delta: #{l[:pos_delta]}"
          end
        end

        puts ""
      end

      def handle_clear(mgr, domain_arg, options)
        all = options[:all] || domain_arg == 'all'
        domain = all ? nil : domain_arg

        res = mgr.clear(domain: domain, all: all)
        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        if all
          puts "🗑️ #{Color.c('Cleared all cached data from local database.', Color::GREEN, Color::BOLD)}"
        else
          puts "🗑️ #{Color.c("Cleared cached data for domain: #{res[:domain]}", Color::GREEN, Color::BOLD)}"
        end
      end
    end
  end
end

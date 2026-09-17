# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../brand_segmenter' if File.exist?(File.expand_path('../brand_segmenter.rb', __dir__))
require_relative '../ctr_curve' if File.exist?(File.expand_path('../ctr_curve.rb', __dir__))
require_relative '../decay_predictor' if File.exist?(File.expand_path('../decay_predictor.rb', __dir__))

module GSC
  class CLI
    module Analytics
      module_function

      def run(command, target, extra, options, api, site_url, hostname, https_origin)
        case command
        when 'performance', 'perf', 'p'
          handle_performance(api, site_url, hostname, options)
        when 'top-queries', 'queries', 'query', 'tq'
          handle_top_queries(api, site_url, options)
        when 'brand', 'brand-split', 'brand-segmentation'
          handle_brand(api, site_url, options)
        when 'top-pages', 'pages'
          handle_top_pages(api, site_url, options)
        when 'ctr-curve', 'ctr-simulator', 'traffic-gain'
          handle_ctr_curve(api, site_url, options)
        when 'decay', 'trends-decay', 'd'
          handle_decay(api, site_url, options)
        when 'devices'
          handle_devices(api, site_url, options)
        when 'countries'
          handle_countries(api, site_url, options)
        when 'snippets', 'appearance', 'search-appearance'
          handle_snippets(api, site_url, options)
        when 'cities'
          handle_cities(api, hostname, options)
        else
          raise "Unknown analytics command: #{command}"
        end
      end

      def handle_performance(api, site_url, hostname, options)
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
              { city: city, country: country, sessions: sess, bounce_rate: "#{bounce}%", duration: Base.format_duration(dur) }
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
          puts "  🔵 Total Clicks:       #{Color.c(Base.format_number(total_clicks), Color::GREEN, Color::BOLD)}"
          puts "  🟣 Total Impressions:  #{Color.c(Base.format_number(total_imp), Color::MAGENTA, Color::BOLD)}"
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
      end

      def handle_top_queries(api, site_url, options)
        sort_field, sort_order = Base.resolve_sort_params(options[:sort], options[:order])
        sort_desc = sort_field ? "sorted by #{sort_field} #{sort_order}" : "sorted by clicks & impressions"
        filter_tag = if options[:brand]
                       " #{Color.c('[BRAND ONLY]', Color::GREEN)}"
                     elsif options[:non_brand]
                       " #{Color.c('[NON-BRAND ONLY]', Color::MAGENTA)}"
                     else
                       ""
                     end
        puts "📊 Fetching top search queries for #{Color.c(site_url, Color::CYAN)}#{filter_tag} (Past #{options[:days]} days, #{sort_desc})...\n" unless options[:json]

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

          if options[:brand] || options[:non_brand]
            segmenter = GSC::BrandSegmenter.new(domain: site_url, custom_brand: options[:brand_name])
            raw_rows = if options[:brand]
                         raw_rows.select { |r| segmenter.brand?(r[:query]) }
                       else
                         raw_rows.reject { |r| segmenter.brand?(r[:query]) }
                       end
          end

          sorted_rows = Base.sort_analytics_rows(raw_rows, options[:sort], options[:order])
          rows = options[:all] ? sorted_rows : sorted_rows.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(rows)
          elsif rows.empty?
            puts Color.c("ℹ️ No search query data recorded matching criteria in the last #{options[:days]} days.", Color::YELLOW)
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
              Base.write_csv(options[:csv], %w[Query Clicks Impressions CTR Position], csv_data)
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
      end

      def handle_brand(api, site_url, options)
        puts "🏷️  Analyzing Brand vs. Non-Brand Search Query Segmentation for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days)...\n" unless options[:json]

        res = api.query_all_analytics(site_url, days: options[:days], dimensions: ['query'])
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

          segmenter = GSC::BrandSegmenter.new(domain: site_url, custom_brand: options[:brand_name])
          segmented = segmenter.segment(raw_rows)
          summary = segmented[:summary]

          if options[:json]
            puts JSON.pretty_generate({
              domain: site_url,
              brand_tokens: segmenter.brand_tokens,
              summary: summary,
              top_brand: segmented[:brand].first(options[:limit] || 10),
              top_non_brand: segmented[:non_brand].first(options[:limit] || 10)
            })
          else
            puts "Identified Brand Tokens: #{Color.c(segmenter.brand_tokens.join(', '), Color::YELLOW)}"
            puts "Total Search Queries:   #{summary[:total_queries]}\n\n"

            puts "#{Color::BOLD}Segment    | Queries | Clicks (% Share) | Imp (% Share)    | CTR    | Avg Pos#{Color::RESET}"
            puts "----------------------------------------------------------------------------------"
            b = summary[:brand]
            nb = summary[:non_brand]
            puts "#{Color.c('Brand', Color::GREEN).ljust(20)} | #{b[:queries_count].to_s.ljust(7)} | #{b[:clicks].to_s.ljust(4)} (#{b[:click_share]}%)     | #{b[:impressions].to_s.ljust(5)} (#{b[:impression_share]}%)   | #{b[:ctr]}%".ljust(64) + "| #{b[:avg_position]}"
            puts "#{Color.c('Non-Brand', Color::MAGENTA).ljust(20)} | #{nb[:queries_count].to_s.ljust(7)} | #{nb[:clicks].to_s.ljust(4)} (#{nb[:click_share]}%)     | #{nb[:impressions].to_s.ljust(5)} (#{nb[:impression_share]}%)   | #{nb[:ctr]}%".ljust(64) + "| #{nb[:avg_position]}"
            puts "----------------------------------------------------------------------------------"

            puts "\n#{Color::BOLD}Top Brand Queries:#{Color::RESET}"
            if segmented[:brand].empty?
              puts Color.c("  (None detected)", Color::GRAY)
            else
              segmented[:brand].first(options[:limit] || 5).each do |q|
                puts "  • #{Color.c(q[:query], Color::GREEN)}: #{q[:clicks]} clicks, #{q[:impressions]} imp, pos #{q[:position]}"
              end
            end

            puts "\n#{Color::BOLD}Top Non-Brand (Discovery) Queries:#{Color::RESET}"
            if segmented[:non_brand].empty?
              puts Color.c("  (None detected)", Color::GRAY)
            else
              segmented[:non_brand].first(options[:limit] || 5).each do |q|
                puts "  • #{Color.c(q[:query], Color::MAGENTA)}: #{q[:clicks]} clicks, #{q[:impressions]} imp, pos #{q[:position]}"
              end
            end
            puts
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end
      end

      def handle_top_pages(api, site_url, options)
        sort_field, sort_order = Base.resolve_sort_params(options[:sort], options[:order])
        sort_desc = sort_field ? "sorted by #{sort_field} #{sort_order}" : "sorted by clicks & impressions"
        puts "📄 Fetching top landing pages for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days, #{sort_desc})...\n" unless options[:json]

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

          sorted_rows = Base.sort_analytics_rows(raw_rows, options[:sort], options[:order])
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
              Base.write_csv(options[:csv], %w[Page Clicks Impressions CTR Position], csv_data)
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
      end

      def handle_ctr_curve(api, site_url, options)
        target_pos = options[:target_pos] || 3
        min_imp    = options[:min_imp] || 10
        limit      = options[:limit] || 20

        puts "📈 Modeling SERP CTR Curve & Traffic Gains for #{Color.c(site_url, Color::CYAN)} (Target: Pos #{target_pos}, Min #{min_imp} imp, Past #{options[:days]} days)...\n" unless options[:json]

        res = api.query_all_analytics(site_url, days: options[:days], dimensions: ['query'])
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

          sim = GSC::CtrCurve.simulate(raw_rows, target_pos: target_pos, min_imp: min_imp)
          opportunities = sim[:opportunities].first(limit)

          if options[:json]
            puts JSON.pretty_generate(sim)
          else
            puts "Target SERP Benchmark: Position #{target_pos} (#{sim[:target_ctr]}% Expected CTR)"
            puts "Total Search Queries Modeled: #{sim[:total_queries_analyzed]}"
            puts Color.c("\n🚀 Incremental Organic Potential: +#{sim[:total_incremental_clicks]} clicks/month if ranked at Top #{target_pos}!\n", Color::GREEN, Color::BOLD)

            if opportunities.empty?
              puts Color.c("ℹ️ No ranking queries met the threshold of >= #{min_imp} impressions.", Color::YELLOW)
            else
              puts "#{Color::BOLD}Clicks | +Gain  | Imp     | Pos   | Act CTR | Exp CTR | Query#{Color::RESET}"
              puts "----------------------------------------------------------------------------------"
              opportunities.each do |o|
                clicks   = o[:current_clicks].to_s.ljust(6)
                gain     = "+#{o[:incremental_clicks]}".ljust(6)
                imp      = o[:impressions].to_s.ljust(9)
                pos      = o[:current_position].to_s.ljust(5)
                act_ctr  = "#{o[:current_ctr]}%".ljust(7)
                exp_ctr  = "#{o[:expected_ctr]}%".ljust(7)
                gain_col = o[:incremental_clicks] > 0 ? Color.c(gain, Color::GREEN) : Color.c(gain, Color::GRAY)
                puts "#{clicks} | #{gain_col} | #{imp} | #{pos} | #{act_ctr} | #{exp_ctr} | #{Color.c(o[:query], Color::CYAN)}"
              end
              puts "\n#{Color.c("Showing top #{opportunities.size} highest-leverage ranking opportunities", Color::GRAY)}\n"

              if sim[:underperformers].any?
                puts "\n#{Color::BOLD}🎯 Immediate Snippet CTR Fixes (Page 1 Rankings Underperforming CTR Benchmark):#{Color::RESET}"
                sim[:underperformers].first(5).each do |u|
                  loss = [((u[:expected_ctr] / 100.0) * u[:impressions]).round - u[:current_clicks], 0].max
                  puts "  • #{Color.c(u[:query], Color::YELLOW)}: Pos #{u[:current_position]} (Actual: #{u[:current_ctr]}% vs Exp: #{u[:expected_ctr]}%) ➔ ~#{loss} clicks lost"
                end
              end
            end
            puts
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end
      end

      def handle_decay(api, site_url, options)
        window_days = options[:compare] || 28
        dim = options[:dimension] || 'page'
        dim_label = (dim == 'page') ? 'Landing Pages' : 'Search Queries'

        puts "📉 Analyzing ranking & traffic decay for #{Color.c(site_url, Color::CYAN)} (#{dim_label}, Past #{window_days}d)...\n" unless options[:json]

        end_current = Date.today - 2
        start_current = end_current - window_days

        ts_res = api.query_analytics(
          site_url,
          start_date: start_current.iso8601,
          end_date: end_current.iso8601,
          dimensions: [dim, 'date'],
          row_limit: 5000
        )

        if ts_res[:ok]
          raw_rows = ts_res.dig(:data, 'rows') || []
          analysis = GSC::DecayPredictor.analyze_timeseries(raw_rows, dimension: dim, min_imp: options[:min_imp] || 10)

          if options[:json]
            puts JSON.pretty_generate(analysis)
          else
            score_color = analysis[:health_score] >= 80 ? Color::GREEN : (analysis[:health_score] >= 65 ? Color::YELLOW : Color::RED)
            puts "#{Color::BOLD}📊 SEARCH CONSOLE CONTENT DECAY & VELOCITY AUDIT#{Color::RESET}"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
            puts "  Health Score:          #{Color.c("#{analysis[:health_score]}/100 [Grade #{analysis[:health_grade]}]", score_color, Color::BOLD)}"
            puts "  Evaluated #{dim_label}: #{analysis[:total_evaluated]}"
            puts "  🔻 Decaying Assets:    #{Color.c(analysis[:decaying_count].to_s, Color::RED, Color::BOLD)}"
            puts "  🚀 Surging Assets:     #{Color.c(analysis[:surging_count].to_s, Color::GREEN, Color::BOLD)}"
            puts "  ⚖️  Stable Assets:      #{Color.c(analysis[:stable_count].to_s, Color::CYAN)}"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"

            limit = options[:limit] || 15
            if analysis[:decaying].any?
              puts "#{Color::BOLD}🔻 TOP DECAYING #{dim_label.upcase} (Slope & Velocity Loss):#{Color::RESET}"
              analysis[:decaying].first(limit).each_with_index do |d, i|
                sev_color = case d[:severity]
                            when 'CRITICAL' then Color::RED
                            when 'HIGH'     then Color::YELLOW
                            else                 Color::CYAN
                            end
                badge = Color.c("[#{d[:classification]}]", sev_color, Color::BOLD)
                w_str = d[:weekly_impressions].join(' → ')
                slope_str = Color.c("#{d[:impression_slope]} imp/wk", Color::RED)
                drift_str = d[:position_drift] > 0 ? Color.c("Rank Drift: +#{d[:position_drift]}", Color::YELLOW) : "Rank Drift: #{d[:position_drift]}"

                entity_display = (dim == 'page') ? d[:entity].sub(%r{^https?://[^/]+}, '') : "\"#{d[:entity]}\""
                entity_display = '/' if entity_display.empty?

                puts "#{Color::BOLD}#{i + 1}. #{badge} #{entity_display}#{Color::RESET}"
                puts "   • Weekly Imp:   #{w_str} (Slope: #{slope_str})"
                puts "   • Velocity:     7d: #{d[:vel_7d_imp_pct]}% | 14d: #{d[:vel_14d_imp_pct]}% | 28d: #{d[:vel_28d_imp_pct]}%"
                puts "   • SERP Position: Prior: #{d[:prior_position] || '-'} → Curr: #{d[:current_position] || '-'} (#{drift_str})"
                if d[:projected_monthly_clicks_lost] > 0
                  puts "   • Traffic Risk: #{Color.c("~#{d[:projected_monthly_clicks_lost]} clicks/mo lost", Color::RED)} if slope continues"
                end
                puts "   👉 #{Color.c('Prescription:', Color::BOLD)} #{d[:prescription]}\n\n"
              end
            else
              puts Color.c("✅ Zero content decay detected! All #{dim_label.downcase} maintain positive or stable velocity slopes.\n", Color::GREEN)
            end

            if analysis[:surging].any?
              puts "#{Color::BOLD}🚀 TOP SURGING #{dim_label.upcase} (Positive Velocity):#{Color::RESET}"
              analysis[:surging].first(limit).each do |s|
                entity_display = (dim == 'page') ? s[:entity].sub(%r{^https?://[^/]+}, '') : "\"#{s[:entity]}\""
                entity_display = '/' if entity_display.empty?
                gain_str = Color.c("+#{s[:vel_14d_imp_pct]}%", Color::GREEN, Color::BOLD)
                puts "   • #{entity_display.ljust(45)} | 14d Gain: #{gain_str} | Slope: +#{s[:impression_slope]} imp/wk"
              end
              puts
            end

            if options[:csv]
              csv_rows = analysis[:decaying].map do |d|
                [d[:entity], d[:classification], d[:severity], d[:total_impressions], d[:total_clicks], d[:vel_7d_imp_pct], d[:vel_14d_imp_pct], d[:vel_28d_imp_pct], d[:impression_slope], d[:click_slope], d[:prior_position], d[:current_position], d[:position_drift], d[:projected_monthly_clicks_lost], d[:prescription]]
              end
              Base.write_csv(options[:csv], %w[Entity Classification Severity TotalImpressions TotalClicks Vel7dImpPct Vel14dImpPct Vel28dImpPct ImpSlope ClickSlope PriorPosition CurrentPosition PositionDrift ProjectedClicksLost Prescription], csv_rows)
              puts Color.c("📁 Exported decay & velocity analysis to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          err = ts_res[:data]
          if options[:json]
            puts JSON.pretty_generate({ error: err })
          else
            puts Color.c("❌ Search Analytics Error: #{Base.format_api_error(err)}", Color::RED)
          end
        end
      end

      def handle_devices(api, site_url, options)
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
              Base.write_csv(options[:csv], %w[Device Clicks Impressions CTR Position Share], rows.map { |r| [r[:device], r[:clicks], r[:impressions], r[:ctr], r[:position], r[:share]] })
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
      end

      def handle_countries(api, site_url, options)
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
              Base.write_csv(options[:csv], %w[Country Clicks Impressions CTR Position], rows.map { |r| [r[:country], r[:clicks], r[:impressions], r[:ctr], r[:position]] })
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
      end

      def handle_snippets(api, site_url, options)
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
              Base.write_csv(options[:csv], %w[AppearanceType Clicks Impressions CTR Position], rows.map { |r| [r[:type], r[:clicks], r[:impressions], r[:ctr], r[:position]] })
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
      end

      def handle_cities(api, hostname, options)
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
            { city: city, country: country, sessions: sess, bounce_rate: "#{bounce}%", duration: Base.format_duration(dur) }
          end

          if options[:json]
            puts JSON.pretty_generate(rows)
          elsif rows.empty?
            puts Color.c("ℹ️ No city data recorded in the last #{options[:days]} days.", Color::YELLOW)
          else
            print_cities_table(rows, property_id)
            puts
            if options[:csv]
              Base.write_csv(options[:csv], %w[City Country Sessions BounceRate AvgDuration], rows.map { |r| [r[:city], r[:country], r[:sessions], r[:bounce_rate], r[:duration]] })
              puts Color.c("📁 Exported city breakdown to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          puts Color.c("❌ GA4 API Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end
      end

      # Table formatters
      def print_devices_table(rows)
        puts "\n#{Color::BOLD}📱 DEVICE BREAKDOWN (Search Traffic)#{Color::RESET}"
        puts "Device       | Clicks   | Impressions | CTR    | Position | Clicks Share"
        puts "-------------------------------------------------------------------------"
        rows.each do |r|
          d_name = Base.format_device(r[:device]).ljust(12)
          c_str = Base.format_number(r[:clicks]).ljust(8)
          i_str = Base.format_number(r[:impressions]).ljust(11)
          ctr_str = "#{r[:ctr]}%".ljust(6)
          pos_str = r[:position].to_s.ljust(8)
          share_str = r[:share].to_s
          puts "#{d_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{share_str}"
        end
      end

      def print_countries_table(rows)
        puts "\n#{Color::BOLD}🌍 TOP COUNTRIES (Search Demand)#{Color::RESET}"
        puts "Country                | Clicks   | Impressions | CTR    | Position"
        puts "-------------------------------------------------------------------------"
        rows.each do |r|
          c_name = Base.format_country(r[:country])[0..21].ljust(22)
          c_str = Base.format_number(r[:clicks]).ljust(8)
          i_str = Base.format_number(r[:impressions]).ljust(11)
          ctr_str = "#{r[:ctr]}%".ljust(6)
          pos_str = r[:position].to_s
          puts "#{c_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str}"
        end
      end

      def print_snippets_table(rows)
        puts "\n#{Color::BOLD}✨ SEARCH APPEARANCE & RICH SNIPPETS#{Color::RESET}"
        if rows.empty?
          puts Color.c("  (No rich snippet enhancements detected in this date range)\n", Color::GRAY)
        else
          puts "Appearance Type        | Clicks   | Impressions | CTR    | Position"
          puts "-------------------------------------------------------------------------"
          rows.each do |r|
            t_name = Base.format_appearance(r[:type])[0..21].ljust(22)
            c_str = Base.format_number(r[:clicks]).ljust(8)
            i_str = Base.format_number(r[:impressions]).ljust(11)
            ctr_str = "#{r[:ctr]}%".ljust(6)
            pos_str = r[:position].to_s
            puts "#{t_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str}"
          end
        end
      end

      def print_cities_table(rows, property_id = nil)
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
            sess_str = Base.format_number(r[:sessions]).ljust(8)
            bounce_str = "#{r[:bounce_rate]}".ljust(6)
            dur_str = r[:duration].to_s
            puts "#{city_str} | #{cntry_str} | #{sess_str} | #{bounce_str} | #{dur_str}"
          end
        end
      end

      def print_mini_queries_table(rows)
        puts "\n#{Color::BOLD}🔍 TOP SEARCH QUERIES#{Color::RESET}"
        puts "Clicks | Impressions | CTR    | Position | Query"
        puts "-------------------------------------------------------------------------"
        rows.each do |r|
          c_str = Base.format_number(r[:clicks]).ljust(6)
          i_str = Base.format_number(r[:impressions]).ljust(11)
          ctr_str = "#{r[:ctr]}%".ljust(6)
          pos_str = r[:position].to_s.ljust(8)
          q_str = Color.c(r[:query], Color::YELLOW)
          puts "#{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{q_str}"
        end
      end

      def print_mini_pages_table(rows)
        puts "\n#{Color::BOLD}📄 TOP LANDING PAGES#{Color::RESET}"
        puts "Clicks | Impressions | CTR    | Position | Page Path"
        puts "-------------------------------------------------------------------------"
        rows.each do |r|
          c_str = Base.format_number(r[:clicks]).ljust(6)
          i_str = Base.format_number(r[:impressions]).ljust(11)
          ctr_str = "#{r[:ctr]}%".ljust(6)
          pos_str = r[:position].to_s.ljust(8)
          p_str = Color.c(r[:path], Color::CYAN)
          puts "#{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{p_str}"
        end
      end
    end
  end
end

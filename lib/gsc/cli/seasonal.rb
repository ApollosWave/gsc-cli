# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../seasonal_predictor'
require_relative '../google_trends'

module GSC
  class CLI
    module Seasonal
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        predictor = GSC::SeasonalPredictor.new(target, options)

        # Mode A: Keyword Deep-Dive (if target is provided and doesn't look like domain flag)
        if target && !target.strip.empty? && target !~ /^https?:\/\// && target !~ /\.(com|org|net|io|app|co|dev|store)$/
          handle_keyword_deep_dive(predictor, target, options)
        else
          # Mode B: GSC Portfolio Seasonal Radar (queries domain GSC data)
          handle_domain_portfolio_radar(predictor, api, site_url, hostname, options)
        end
      end

      def handle_keyword_deep_dive(predictor, keyword, options)
        geo = options[:geo] || 'US'
        time = options[:time] || '5y'

        data = predictor.analyze_keyword(keyword, geo: geo, time: time)

        if data[:ok] == false
          if options[:json]
            puts JSON.pretty_generate(data)
          else
            puts Color.c("\n⚠️ #{data[:error]}", Color::YELLOW, Color::BOLD)
          end
          return
        end

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "🍁 #{Color::BOLD}SEASONAL DEMAND & 60-DAY SPIKE PREDICTOR:#{Color::RESET} #{Color.c(keyword, Color::CYAN, Color::BOLD)} [Geo: #{geo} | Window: #{time}]"
        puts "─" * 80

        pattern = data[:classification]
        runway = data[:runway]
        stats = data[:monthly_stats]

        urgency_color = case runway[:urgency]
                        when 'CRITICAL' then Color::RED
                        when 'HIGH'     then Color::YELLOW
                        when 'MODERATE' then Color::CYAN
                        else                 Color::GREEN
                        end

        puts "🏷️  Seasonality Profile: #{Color.c(pattern[:label], Color::BOLD)}"
        puts "   #{Color::DIM}#{pattern[:description]}#{Color::RESET}"
        puts "\n📈 Annual Baseline Score: #{Color.c(stats[:annual_baseline].to_s, Color::BOLD)} / 100"
        puts "🏆 Historical Peak Month: #{Color.c(stats[:peak_month_name], Color::MAGENTA, Color::BOLD)} (Index: #{stats[:peak_index]} — #{stats[:peak_multiplier]}x normal volume)"
        puts "❄️  Annual Trough Month:  #{Color.c(stats[:trough_month_name], Color::BLUE)} (Index: #{stats[:trough_index]})"
        puts

        # Render 12-Month Calendar Bar Chart
        puts "📅 #{Color::BOLD}12-MONTH SEASONAL TRAJECTORY (5-Year Historical Average):#{Color::RESET}"
        puts predictor.render_ascii_calendar(stats, runway[:current_month])
        puts

        # 60-Day Runway Alarm
        puts "⏱️  #{Color::BOLD}60-DAY GOOGLEBOT RUNWAY & OPTIMIZATION COUNTDOWN:#{Color::RESET}"
        puts "   • Current Month Status : #{Color.c(runway[:current_month_name], Color::BOLD)} (Index: #{runway[:current_month_index]})"
        puts "   • Next Major Spike     : #{Color.c(runway[:spike_month_name], Color::MAGENTA, Color::BOLD)} (#{Color.c("#{runway[:spike_multiplier]}x surge", Color::BOLD)})"
        puts "   • Googlebot Cutoff Date: #{Color.c(runway[:publish_deadline], urgency_color, Color::BOLD)} (#{Color.c("#{runway[:days_to_deadline]} days remaining", urgency_color, Color::BOLD)})"
        puts "   • Strategic Urgency    : [#{Color.c(runway[:urgency], urgency_color, Color::BOLD)}]"
        puts "\n💡 #{Color::BOLD}Actionable Recommendation:#{Color::RESET}"
        puts "   #{Color.c(runway[:recommendation], Color::BOLD)}"
        puts

        # Tactical Pre-Spike SEO Checklist
        puts "🛠️  #{Color::BOLD}PRE-SPIKE CAPTURE CHECKLIST (Publish 30 Days Before Peak):#{Color::RESET}"
        puts "   1. [Titles]: Refresh title tag with current year hook (<580px desktop limit via `gsc titles`)."
        puts "   2. [Headings]: Add high-intent FAQ questions under H2/H3 (`gsc questions \"#{keyword}\"`)."
        puts "   3. [Internal Links]: Boost link equity by linking from top authority hubs (`gsc orphans`)."
        puts "   4. [Schema]: Inject FAQPage and Product structured data for rich snippets (`gsc schema gen`)."
        puts "   5. [Instant Crawl]: Trigger immediate re-indexation upon publication (`gsc index <url>`)."
        puts "\n" + ("─" * 80) + "\n"
      end

      def handle_domain_portfolio_radar(predictor, api, site_url, hostname, options)
        unless api
          puts Color.c("\n❌ Error: Google Search Console authentication required for portfolio radar.", Color::RED, Color::BOLD)
          puts "   Run with keyword for single-term search: #{Color.c('gsc seasonal <keyword>', Color::CYAN)}"
          puts "   Or connect your domain via #{Color.c('gsc connect', Color::GREEN)}"
          return
        end

        limit = options[:limit] || 25
        days = options[:days] || 30
        min_imp = options[:min_imp] || 15

        puts Base::BANNER unless options[:json] || options[:in_dashboard]
        puts "📡 #{Color::BOLD}SEASONAL PORTFOLIO RADAR (Top Queries for #{hostname}):#{Color::RESET}" unless options[:json]
        puts "   Scanning top GSC keywords for impending 30–60 day seasonal demand spikes...\n" unless options[:json]

        # Fetch top queries
        res = api.query_analytics(site_url, days: days, dimensions: ['query'], row_limit: [limit * 2, 50].max)
        rows = res.is_a?(Hash) ? (res.dig(:data, 'rows') || res['rows'] || []) : []

        filtered_rows = rows.select { |r| (r['impressions'] || 0) >= min_imp }

        if filtered_rows.empty?
          puts Color.c("ℹ️ No queries found meeting minimum impression threshold (#{min_imp}).", Color::YELLOW) unless options[:json]
          return
        end

        curr_month = Date.today.month
        portfolio_results = []

        filtered_rows.first(limit).each do |r|
          query_text = (r['keys'] || []).first.to_s.strip
          next if query_text.empty?

          clicks = (r['clicks'] || 0).to_i
          impressions = (r['impressions'] || 0).to_i
          position = (r['position'] || 0.0).to_f.round(1)

          analysis = predictor.analyze_keyword(query_text)
          runway = analysis[:runway]
          pattern = analysis[:classification]
          stats = analysis[:monthly_stats]

          # Calculate Seasonal Striking-Distance ROI
          roi = predictor.calculate_seasonal_roi(clicks, impressions, position, runway[:spike_multiplier])

          portfolio_results << {
            query: query_text,
            clicks: clicks,
            impressions: impressions,
            position: position,
            pattern: pattern[:pattern],
            pattern_label: pattern[:label],
            current_month_index: runway[:current_month_index],
            peak_month_name: stats[:peak_month_name],
            peak_multiplier: stats[:peak_multiplier],
            spike_month_name: runway[:spike_month_name],
            spike_multiplier: runway[:spike_multiplier],
            is_spiking_soon: runway[:is_spiking_soon],
            days_to_deadline: runway[:days_to_deadline],
            urgency: runway[:urgency],
            seasonal_monthly_click_gain: roi[:seasonal_monthly_click_gain],
            peak_90d_click_harvest: roi[:peak_90d_click_harvest]
          }
        end

        if options[:json]
          puts JSON.pretty_generate({
            domain: hostname,
            audited_queries_count: portfolio_results.size,
            queries: portfolio_results
          })
          return
        end

        if options[:csv]
          csv_rows = portfolio_results.map do |p|
            [
              p[:query], p[:clicks], p[:impressions], p[:position],
              p[:pattern], p[:peak_month_name], p[:peak_multiplier],
              p[:spike_month_name], p[:spike_multiplier], p[:days_to_deadline],
              p[:urgency], p[:seasonal_monthly_click_gain]
            ]
          end
          headers = %w[Query Clicks Impressions Position Pattern PeakMonth PeakMultiplier SpikeMonth SpikeMultiplier DaysToDeadline Urgency ProjectedSeasonalClickGain]
          Base.write_csv(options[:csv], headers, csv_rows)
          puts Color.c("📁 Exported seasonal radar portfolio to #{options[:csv]}", Color::CYAN)
          return
        end

        # Segment queries
        spiking_soon = portfolio_results.select { |p| p[:is_spiking_soon] }.sort_by { |p| -p[:seasonal_monthly_click_gain] }
        evergreen    = portfolio_results.select { |p| p[:pattern] == 'EVERGREEN' }
        cooling      = portfolio_results.select { |p| p[:current_month_index] < 80 && !p[:is_spiking_soon] }

        puts "─" * 90
        puts "🚀 #{Color::BOLD}IMPENDING SEASONAL SPIKES (Next 30–60 Days — Immediate Optimization Window):#{Color::RESET}"
        puts "─" * 90

        if spiking_soon.empty?
          puts "   (No aggressive seasonal surges detected in the next 60 days across audited queries)"
        else
          puts format(
            "   %-30s | %-6s | %-8s | %-12s | %-8s | %-12s",
            "SEARCH QUERY", "RANK", "SURGE", "PEAK MONTH", "DAYS LEFT", "PEAK GAIN"
          )
          puts "   " + ("─" * 86)

          spiking_soon.each do |s|
            gain_str = "+#{s[:seasonal_monthly_click_gain]} clicks/mo"
            urg_color = s[:days_to_deadline] <= 21 ? Color::RED : Color::YELLOW

            puts format(
              "   %-30s | %-6s | %-8s | %-12s | %-8s | %-12s",
              Color.c(s[:query][0..28].ljust(30), Color::BOLD),
              "##{s[:position]}",
              Color.c("#{s[:spike_multiplier]}x", Color::MAGENTA, Color::BOLD),
              s[:spike_month_name],
              Color.c("#{s[:days_to_deadline]}d", urg_color, Color::BOLD),
              Color.c(gain_str, Color::GREEN, Color::BOLD)
            )
          end
        end

        puts "\n" + ("─" * 90)
        puts "❄️  #{Color::BOLD}ENTERING SEASONAL TROUGH (Cooling Demand — False Alarm Defense):#{Color::RESET}"
        puts "─" * 90

        if cooling.empty?
          puts "   (No audited queries currently entering severe seasonal troughs)"
        else
          cooling.first(5).each do |c|
            puts "   • \"#{Color.c(c[:query], Color::BOLD)}\" (SI: #{c[:current_month_index]} — Normal seasonal lull. Do NOT panic if clicks drop)."
          end
        end

        puts "\n" + ("─" * 90) + "\n"
      end
    end
  end
end

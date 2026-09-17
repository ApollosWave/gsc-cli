# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'date'
require_relative 'base'
require_relative '../sparkline'
require_relative '../color'

module GSC
  class CLI
    module Sparkline
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        days = (options[:days] || 28).to_i
        metric_filter = (options[:metric] || 'all').to_s.downcase

        # 1. Mode A: Raw numbers passed via --data or comma-separated target
        if options[:data] || (target && target.match?(/^\d+(?:,\s*\d+)+$/))
          raw_data = (options[:data] || target).split(',').map(&:strip).map(&:to_f)
          render_raw_data(raw_data, options)
          return
        end

        # 2. Mode B: Live Search Console query over time
        filter_query = nil
        filter_page = nil

        if target && target.start_with?('/')
          filter_page = target
        elsif target && target.match?(%r{^https?://})
          filter_page = target
        elsif target && !target.empty?
          filter_query = target
        end

        # Also check extra arguments if multi-word query was given
        if extra && extra.is_a?(String) && !extra.empty?
          filter_query = "#{filter_query} #{extra}".strip
        end

        daily_rows = fetch_daily_analytics(api, site_url, days, filter_query, filter_page)

        if daily_rows.empty?
          msg = "No daily time-series performance data found for #{site_url || 'current domain'} over the past #{days} days."
          if options[:json]
            puts JSON.pretty_generate({ error: msg })
          else
            puts Color.yellow("⚠️ Notice: #{msg}")
          end
          return
        end

        result = process_time_series(daily_rows, site_url, days, filter_query, filter_page, options)

        if options[:json]
          puts JSON.pretty_generate(result)
          return
        end

        render_terminal(result, metric_filter, options)

        if options[:csv]
          export_csv(result, options[:csv])
        end
      end

      def fetch_daily_analytics(api, site_url, days, query, page)
        return [] unless api && site_url

        filters = []
        filters << { dimension: 'query', operator: 'contains', expression: query } if query
        filters << { dimension: 'page', operator: 'contains', expression: page } if page

        res = api.query_analytics(site_url, days: days, dimensions: ['date'], filters: filters, row_limit: 500)
        if res[:ok]
          (res.dig(:data, 'rows') || []).sort_by { |r| r['keys'].first }
        else
          []
        end
      rescue StandardError
        []
      end

      def process_time_series(rows, site_url, days, query, page, options)
        dates = rows.map { |r| r['keys'].first }
        clicks = rows.map { |r| (r['clicks'] || 0).to_i }
        impressions = rows.map { |r| (r['impressions'] || 0).to_i }
        positions = rows.map { |r| (r['position'] || 0.0).round(1) }
        ctrs = rows.map { |r| (r['ctr'] ? r['ctr'] * 100.0 : 0.0).round(2) }

        height = [options[:height] || 5, 2].max

        metrics = {
          clicks: {
            label: 'Clicks',
            values: clicks,
            total: clicks.sum,
            average: (clicks.sum.to_f / [clicks.size, 1].max).round(1),
            sparkline: GSC::Sparkline.render(clicks, colored: true),
            chart: GSC::Sparkline.chart(clicks, height: height, dates: dates),
            momentum: GSC::Sparkline.momentum(clicks)
          },
          impressions: {
            label: 'Impressions',
            values: impressions,
            total: impressions.sum,
            average: (impressions.sum.to_f / [impressions.size, 1].max).round(1),
            sparkline: GSC::Sparkline.render(impressions, colored: true),
            chart: GSC::Sparkline.chart(impressions, height: height, dates: dates),
            momentum: GSC::Sparkline.momentum(impressions)
          },
          position: {
            label: 'Avg Position',
            values: positions,
            average: (positions.sum.to_f / [positions.size, 1].max).round(1),
            sparkline: GSC::Sparkline.render(positions, invert: true, colored: true),
            chart: GSC::Sparkline.chart(positions, height: height, dates: dates),
            momentum: GSC::Sparkline.momentum(positions)
          },
          ctr: {
            label: 'CTR (%)',
            values: ctrs,
            average: (ctrs.sum.to_f / [ctrs.size, 1].max).round(2),
            sparkline: GSC::Sparkline.render(ctrs, colored: true),
            chart: GSC::Sparkline.chart(ctrs, height: height, dates: dates),
            momentum: GSC::Sparkline.momentum(ctrs)
          }
        }

        {
          site_url: site_url,
          days: days,
          filter_query: query,
          filter_page: page,
          data_points: rows.size,
          start_date: dates.first,
          end_date: dates.last,
          dates: dates,
          metrics: metrics
        }
      end

      def render_terminal(res, metric_filter, options)
        target_desc = if res[:filter_query]
                        "Query: \"#{res[:filter_query]}\""
                      elsif res[:filter_page]
                        "Page: #{res[:filter_page]}"
                      else
                        "Site-wide Performance"
                      end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("📈 VISUAL TREND SPARKLINES & TRAJECTORY CHARTS (#{res[:days]} Days)")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "  • Target Scope:   #{Color.cyan(target_desc)}"
        puts "  • Time Window:    #{res[:start_date]} to #{res[:end_date]} (#{res[:data_points]} daily points)"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        # 1. Primary ASCII Visual Chart (Clicks or chosen metric)
        primary_key = metric_filter == 'all' ? :clicks : metric_filter.to_sym
        primary_m = res[:metrics][primary_key] || res[:metrics][:clicks]

        puts "#{Color.bold("DAILY #{primary_m[:label].upcase} TRAJECTORY (ASCII TERMINAL CHART):")}\n"
        puts primary_m[:chart]
        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        # 2. Comparative Metrics Table with Sparklines & Velocity
        puts "#{Color.bold("30-DAY METRIC SUMMARY & MOMENTUM VECTOR:")}\n\n"
        printf " %-14s %-20s %-12s %-10s %s\n", "Metric", "Sparkline (28d)", "Avg / Day", "Total", "Momentum Rate"
        puts " ---------------------------------------------------------------------------------------"

        res[:metrics].each do |key, m|
          next if metric_filter != 'all' && metric_filter != key.to_s

          total_display = m[:total] ? m[:total].to_s : "—"
          avg_display = key == :ctr ? "#{m[:average]}%" : (key == :position ? "Pos #{m[:average]}" : m[:average].to_s)
          mom_str = m[:momentum][:velocity]

          printf " %-14s [ %s ] %-12s %-10s %s\n", m[:label], m[:sparkline], avg_display, total_display, mom_str
        end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def render_raw_data(data, options)
        spark = GSC::Sparkline.render(data, colored: true)
        chart = GSC::Sparkline.chart(data, height: options[:height] || 5)
        mom = GSC::Sparkline.momentum(data)

        if options[:json]
          puts JSON.pretty_generate({
            points: data.size,
            values: data,
            min: data.min,
            max: data.max,
            average: (data.sum / data.size.to_f).round(2),
            sparkline: spark,
            momentum: mom
          })
          return
        end

        puts "\n#{Color.bold("ASCII DATA CHART (#{data.size} points):")}\n"
        puts chart
        puts "\nSparkline: [ #{spark} ] | Momentum: #{mom[:velocity]}\n"
      end

      def export_csv(res, file_path)
        dates = res[:dates]
        clicks = res[:metrics][:clicks][:values]
        impressions = res[:metrics][:impressions][:values]
        positions = res[:metrics][:position][:values]
        ctrs = res[:metrics][:ctr][:values]

        headers = %w[Date Clicks Impressions Position CTR]
        rows = dates.each_with_index.map do |d, i|
          [d, clicks[i] || 0, impressions[i] || 0, positions[i] || 0.0, ctrs[i] || 0.0]
        end

        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported daily sparkline points to #{file_path}")
      end
    end
  end
end

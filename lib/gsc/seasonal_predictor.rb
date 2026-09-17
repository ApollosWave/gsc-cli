# frozen_string_literal: true

require 'date'
require 'time'
require 'json'
require_relative 'color'
require_relative 'google_trends'

module GSC
  class SeasonalPredictor
    MONTH_NAMES = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

    attr_reader :keyword_or_domain, :options

    def initialize(keyword_or_domain = nil, options = {})
      @keyword_or_domain = keyword_or_domain
      @options = options || {}
    end

    # Analyze single keyword seasonality using 5-year trends data
    def analyze_keyword(keyword, geo: 'US', time: '5y')
      trends_data = GoogleTrends.fetch(keyword, geo: geo, time: time)
      points = trends_data[:points] || []

      # If live trends returns empty or fails, report genuine status
      if points.empty?
        return {
          ok: false,
          error: "Google Trends data currently unavailable or rate-limited for '#{keyword}'.",
          keyword: keyword,
          geo: geo,
          time: time,
          points_count: 0
        }
      end

      monthly_stats = decompose_monthly_seasonality(points)
      runway = detect_runway_and_deadlines(monthly_stats)
      classification = classify_seasonality_pattern(monthly_stats)

      {
        ok: true,
        keyword: keyword,
        geo: geo,
        time: time,
        sparkline: trends_data[:sparkline],
        monthly_stats: monthly_stats,
        runway: runway,
        classification: classification,
        points_count: points.size
      }
    end

    # Group time series points into 12 calendar months and compute Seasonality Index (SI)
    def decompose_monthly_seasonality(points)
      buckets = Hash.new { |h, k| h[k] = [] }

      points.each do |pt|
        d_str = pt[:date].to_s
        score = pt[:score].to_i
        
        # Parse month from formatted date e.g. "2023-11-15", "Nov 2023", or Unix timestamp
        month = parse_month_number(d_str)
        buckets[month] << score if month && month >= 1 && month <= 12
      end

      # Ensure all 12 months exist
      1.upto(12) { |m| buckets[m] = [50] if buckets[m].empty? }

      month_averages = {}
      buckets.each do |m, scores|
        month_averages[m] = scores.sum.to_f / [scores.size, 1].max
      end

      annual_baseline = month_averages.values.sum.to_f / 12.0
      annual_baseline = 1.0 if annual_baseline.zero?

      monthly_indices = {}
      1.upto(12) do |m|
        avg_score = month_averages[m]
        si = ((avg_score / annual_baseline) * 100).round
        monthly_indices[m] = {
          month: m,
          month_name: MONTH_NAMES[m - 1],
          avg_score: avg_score.round(1),
          seasonality_index: si,
          relative_multiplier: (si / 100.0).round(2),
          sample_points: buckets[m].size
        }
      end

      # Identify peak and trough months
      peak_m = monthly_indices.values.max_by { |v| v[:seasonality_index] }
      trough_m = monthly_indices.values.min_by { |v| v[:seasonality_index] }

      {
        months: monthly_indices,
        annual_baseline: annual_baseline.round(1),
        peak_month: peak_m[:month],
        peak_month_name: peak_m[:month_name],
        peak_index: peak_m[:seasonality_index],
        peak_multiplier: peak_m[:relative_multiplier],
        trough_month: trough_m[:month],
        trough_month_name: trough_m[:month_name],
        trough_index: trough_m[:seasonality_index]
      }
    end

    # The 60-Day Runway & Publish Deadline Calculator
    def detect_runway_and_deadlines(monthly_stats, current_date = Date.today)
      curr_m = current_date.month
      curr_y = current_date.year
      months = monthly_stats[:months]

      upcoming_3m = [1, 2, 3].map do |offset|
        target_m = ((curr_m - 1 + offset) % 12) + 1
        months[target_m]
      end

      # Find highest impending surge
      spike_target = upcoming_3m.find { |m| m[:seasonality_index] >= 125 } || upcoming_3m.max_by { |m| m[:seasonality_index] }
      is_significant_spike = spike_target[:seasonality_index] >= 120

      target_month_num = spike_target[:month]
      months_away = ((target_month_num - curr_m) % 12)
      months_away = 12 if months_away.zero?

      # Calculate estimated peak start date
      target_year = (curr_m + months_away > 12) ? curr_y + 1 : curr_y
      peak_start_date = Date.new(target_year, target_month_num, 1)

      # Googlebot indexing runway: recommend publishing 35 days before peak starts
      publish_deadline = peak_start_date - 35
      days_to_deadline = (publish_deadline - current_date).to_i

      urgency = if days_to_deadline <= 14
                  'CRITICAL'
                elsif days_to_deadline <= 45
                  'HIGH'
                elsif days_to_deadline <= 75
                  'MODERATE'
                else
                  'EARLY_PLANNING'
                end

      {
        current_month: curr_m,
        current_month_name: MONTH_NAMES[curr_m - 1],
        current_month_index: months[curr_m][:seasonality_index],
        is_spiking_soon: is_significant_spike,
        spike_month: target_month_num,
        spike_month_name: spike_target[:month_name],
        spike_index: spike_target[:seasonality_index],
        spike_multiplier: spike_target[:relative_multiplier],
        months_away: months_away,
        peak_start_date: peak_start_date.iso8601,
        publish_deadline: publish_deadline.iso8601,
        days_to_deadline: [days_to_deadline, 0].max,
        urgency: urgency,
        recommendation: generate_action_recommendation(urgency, spike_target[:month_name], days_to_deadline, spike_target[:relative_multiplier])
      }
    end

    # Classify seasonality profile
    def classify_seasonality_pattern(monthly_stats)
      peak_m = monthly_stats[:peak_month]
      peak_idx = monthly_stats[:peak_index]
      trough_idx = monthly_stats[:trough_index]
      spread = peak_idx - trough_idx

      if spread < 30
        {
          pattern: 'EVERGREEN',
          label: '🌲 Evergreen / Consistent Demand',
          description: 'Steady year-round search volume with minimal cyclical variation (<30% swing).'
        }
      elsif [10, 11, 12].include?(peak_m)
        {
          pattern: 'Q4_HOLIDAY',
          label: '🎁 Q4 Holiday & Black Friday Peak',
          description: 'Massive surge in November/December driven by holiday gift buying and year-end budgets.'
        }
      elsif [6, 7, 8].include?(peak_m)
        {
          pattern: 'Q3_SUMMER',
          label: '☀️ Summer Surge (Q3)',
          description: 'High summer demand peaking June–August; cooling rapidly by September.'
        }
      elsif [1, 2].include?(peak_m)
        {
          pattern: 'Q1_NEW_YEAR',
          label: '🎯 New Year & Resolution Spike (Q1)',
          description: 'January/February surge driven by new year resolutions, renewals, or fresh fiscal budgets.'
        }
      elsif [3, 4, 5].include?(peak_m)
        {
          pattern: 'Q2_SPRING',
          label: '🌱 Spring Refresh & Tax Season (Q2)',
          description: 'Demand rises through spring, peaking March through May.'
        }
      else
        {
          pattern: 'CYCLICAL',
          label: '🔄 Seasonal Cyclical Demand',
          description: "Distinct peak concentrated around #{monthly_stats[:peak_month_name]} (#{peak_idx} SI)."
        }
      end
    end

    # False-Flag Penalty vs Seasonal Trough Detector
    def diagnose_traffic_drop(query, gsc_change_pct, current_month = Date.today.month, monthly_stats = nil)
      stats = monthly_stats || analyze_keyword(query)[:monthly_stats]
      months = stats[:months]
      prev_m = current_month == 1 ? 12 : current_month - 1

      curr_si = months[current_month][:seasonality_index] || 1.0
      prev_si = months[prev_m][:seasonality_index] || 1.0
      expected_seasonal_change = prev_si.to_f > 0 ? (((curr_si - prev_si).to_f / prev_si) * 100).round : 0

      # If traffic dropped and historical trends drop similarly
      is_seasonal_trough = (gsc_change_pct < -15 && expected_seasonal_change < -15)
      deviation = (gsc_change_pct - expected_seasonal_change).round

      verdict = if is_seasonal_trough && deviation.abs <= 25
                  :seasonal_cycle
                elsif gsc_change_pct < -25 && expected_seasonal_change >= -10
                  :potential_algorithmic_penalty
                elsif gsc_change_pct > 15 && expected_seasonal_change <= 0
                  :outperforming_seasonality
                else
                  :normal_variance
                end

      {
        query: query,
        gsc_change_pct: gsc_change_pct,
        expected_seasonal_change_pct: expected_seasonal_change,
        deviation_pct: deviation,
        verdict: verdict,
        explanation: format_verdict_explanation(verdict, query, gsc_change_pct, expected_seasonal_change)
      }
    end

    # Seasonal Striking-Distance ROI Multiplier
    # Combines CTR Curve from Turn 4 with Seasonal Surge Multipliers
    def calculate_seasonal_roi(gsc_clicks, gsc_impressions, gsc_position, peak_multiplier, target_pos: 3)
      curr_pos = [gsc_position.to_f, 1.0].max
      target = [target_pos.to_f, 1.0].max

      # Turn 4 empirical CTR Curve model
      ctr_curve = {
        1 => 0.285, 2 => 0.157, 3 => 0.110, 4 => 0.080, 5 => 0.055,
        6 => 0.042, 7 => 0.032, 8 => 0.024, 9 => 0.019, 10 => 0.014
      }

      curr_ctr = ctr_curve[curr_pos.round] || [0.01, (1.0 / (curr_pos * 8))].max
      target_ctr = ctr_curve[target.round] || 0.110

      # Standard 30-day baseline projection
      baseline_lift = gsc_impressions * (target_ctr - curr_ctr)
      baseline_lift = [baseline_lift, 0.0].max

      # Seasonal Peak Surge Multiplier
      peak_monthly_clicks = (baseline_lift * peak_multiplier).round
      peak_90d_clicks = (peak_monthly_clicks * 2.5).round # Peak surge lasts ~2.5 months

      {
        current_position: curr_pos.round(1),
        target_position: target.round,
        current_ctr_pct: (curr_ctr * 100).round(2),
        target_ctr_pct: (target_ctr * 100).round(2),
        baseline_monthly_click_gain: baseline_lift.round,
        peak_surge_multiplier: peak_multiplier,
        seasonal_monthly_click_gain: peak_monthly_clicks,
        peak_90d_click_harvest: peak_90d_clicks,
        roi_multiplier: peak_multiplier
      }
    end

    # Render a 12-Month ASCII Calendar Bar Chart
    def render_ascii_calendar(monthly_stats, current_month = Date.today.month)
      months = monthly_stats[:months]
      peak_m = monthly_stats[:peak_month]
      trough_m = monthly_stats[:trough_month]

      out = []
      out << "   #{Color::BOLD}MONTH   SEASONALITY INDEX (SI)   DEMAND TRAJECTORY#{Color::RESET}"
      out << "   " + ("─" * 65)

      1.upto(12) do |m|
        info = months[m]
        si = info[:seasonality_index]
        name = info[:month_name]
        
        # Max bar width 28 chars (where 100 SI = 14 chars)
        bar_len = [((si / 200.0) * 28).round, 1].max
        bar_len = [bar_len, 32].min

        is_current = (m == current_month)
        is_peak = (m == peak_m)
        is_trough = (m == trough_m)

        bar_char = "█"
        bar_str = bar_char * bar_len

        colored_bar = if is_peak
                        Color.c(bar_str, Color::MAGENTA, Color::BOLD)
                      elsif si >= 125
                        Color.c(bar_str, Color::RED, Color::BOLD)
                      elsif si >= 100
                        Color.c(bar_str, Color::GREEN)
                      elsif is_trough
                        Color.c(bar_str, Color::BLUE)
                      else
                        Color.c(bar_str, Color::YELLOW)
                      end

        badge = []
        badge << Color.c("👈 CURRENT", Color::CYAN, Color::BOLD) if is_current
        badge << Color.c("🏆 PEAK (#{info[:relative_multiplier]}x)", Color::MAGENTA, Color::BOLD) if is_peak
        badge << Color.c("❄️ TROUGH", Color::BLUE) if is_trough && !is_peak

        si_formatted = si.to_s.rjust(3)
        m_display = is_current ? Color.c(name, Color::CYAN, Color::BOLD) : name

        out << "   #{m_display.ljust(6)}  #{Color.c(si_formatted, Color::BOLD)} | #{colored_bar.ljust(35)} #{badge.join(' ')}"
      end

      out << "   " + ("─" * 65)
      out << "   #{Color::DIM}100 = Annual Average Baseline | >125 = Surge Season | <75 = Low Trough#{Color::RESET}"
      out.join("\n")
    end

    private

    def parse_month_number(date_str)
      # Format: "YYYY-MM-DD"
      if date_str =~ /^\d{4}-(\d{2})-\d{2}/
        return $1.to_i
      end

      # Format: "Jan 2023" or "Nov 15, 2023"
      MONTH_NAMES.each_with_index do |name, idx|
        return idx + 1 if date_str.downcase.include?(name.downcase)
      end

      # Epoch timestamp fallback
      if date_str =~ /^\d{10,}$/
        return Time.at(date_str.to_i).utc.month rescue 1
      end

      nil
    end

    def generate_action_recommendation(urgency, spike_month, days_left, multiplier)
      case urgency
      when 'CRITICAL'
        "🚨 URGENT: Demand spikes in #{spike_month} (#{multiplier}x surge)! Only #{days_left} days before Googlebot indexing cutoff. Publish updated headings, FAQ schema, and internal links immediately."
      when 'HIGH'
        "⚡ OPTIMIZE NOW: #{days_left} days remaining until freeze. Begin title tag rewrites and expand product/landing page content before the #{spike_month} #{multiplier}x surge."
      when 'MODERATE'
        "📅 PREPARE BRIEFS: #{days_left} days left. Finalize seasonal keyword targets and schedule new content to publish 30 days ahead of the #{spike_month} peak."
      else
        "🌲 EVERGREEN/MONITOR: Steady demand ahead. Review quarterly to ensure stable rankings."
      end
    end

    def format_verdict_explanation(verdict, query, gsc_change, expected_change)
      case verdict
      when :seasonal_cycle
        "✅ False alarm! GSC clicks dropped #{gsc_change}%, matching the expected seasonal trough of #{expected_change}%. Do NOT panic or rewrite URLs; demand naturally rebounds."
      when :potential_algorithmic_penalty
        "⚠️ Potential ranking loss detected: GSC traffic plunged #{gsc_change}%, but historical search volume only dipped #{expected_change}%. Investigate search positions and technical crawl logs."
      when :outperforming_seasonality
        "🚀 Remarkable organic gain: GSC clicks climbed +#{gsc_change}% despite a flat/cooling seasonal macro trend (#{expected_change}%). Your market share is expanding!"
      else
        "ℹ️ Normal traffic variance within standard expected boundaries (#{gsc_change}% vs #{expected_change}% seasonal expectation)."
      end
    end
  end
end

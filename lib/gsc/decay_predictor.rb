# frozen_string_literal: true

require 'date'

module GSC
  class DecayPredictor
    # Minimum impressions over the 28-day window to evaluate decay
    DEFAULT_MIN_IMP = 10

    def self.analyze_timeseries(rows, dimension: 'page', min_imp: DEFAULT_MIN_IMP)
      # rows is array of { "keys" => [entity, "YYYY-MM-DD"], "clicks" => n, "impressions" => n, "position" => f }
      # Group by entity
      entity_days = Hash.new { |h, k| h[k] = {} }
      all_dates = []

      rows.each do |r|
        entity = r['keys'][0]
        date_str = r['keys'][1]
        all_dates << date_str
        entity_days[entity][date_str] = {
          clicks: (r['clicks'] || 0).to_i,
          impressions: (r['impressions'] || 0).to_i,
          position: (r['position'] || 0.0).to_f
        }
      end

      all_dates = all_dates.uniq.sort
      return empty_result(dimension) if all_dates.empty?

      # Partition the dates into 4 chronological buckets (oldest to newest)
      # total dates usually 28 (or whatever was queried)
      chunk_size = (all_dates.size / 4.0).ceil
      chunk_size = 1 if chunk_size < 1

      w4_dates = all_dates[0...chunk_size] || []
      w3_dates = all_dates[chunk_size...(chunk_size * 2)] || []
      w2_dates = all_dates[(chunk_size * 2)...(chunk_size * 3)] || []
      w1_dates = all_dates[(chunk_size * 3)..] || []

      results = []

      entity_days.each do |entity, days|
        w4 = sum_window(days, w4_dates)
        w3 = sum_window(days, w3_dates)
        w2 = sum_window(days, w2_dates)
        w1 = sum_window(days, w1_dates)

        total_imp = w1[:impressions] + w2[:impressions] + w3[:impressions] + w4[:impressions]
        total_clicks = w1[:clicks] + w2[:clicks] + w3[:clicks] + w4[:clicks]

        next if total_imp < min_imp

        # 7-day velocity: Compare W1 (latest 7d) vs W2 (prior 7d)
        w1_clicks = w1[:clicks]
        w2_clicks = w2[:clicks]
        w1_imp    = w1[:impressions]
        w2_imp    = w2[:impressions]

        vel_7d_clicks_pct = calc_pct_change(w1_clicks, w2_clicks)
        vel_7d_imp_pct    = calc_pct_change(w1_imp, w2_imp)

        # 14-day velocity: (W1 + W2) vs (W3 + W4)
        h1_clicks = w1_clicks + w2_clicks
        h2_clicks = w3[:clicks] + w4[:clicks]
        h1_imp    = w1_imp + w2_imp
        h2_imp    = w3[:impressions] + w4[:impressions]

        vel_14d_clicks_pct = calc_pct_change(h1_clicks, h2_clicks)
        vel_14d_imp_pct    = calc_pct_change(h1_imp, h2_imp)

        # 28-day Macro Velocity: W1 vs W4
        vel_28d_clicks_pct = calc_pct_change(w1_clicks, w4[:clicks])
        vel_28d_imp_pct    = calc_pct_change(w1_imp, w4[:impressions])

        # Historical linear regression slope across the 4 weeks:
        # x = [1, 2, 3, 4], y = [w4_imp, w3_imp, w2_imp, w1_imp]
        imp_series = [w4[:impressions], w3[:impressions], w2[:impressions], w1[:impressions]]
        click_series = [w4[:clicks], w3[:clicks], w2[:clicks], w1[:clicks]]
        pos_series = [w4[:position], w3[:position], w2[:position], w1[:position]].compact

        imp_slope = calc_slope(imp_series)
        click_slope = calc_slope(click_series)
        pos_drift = (w1[:position] && w4[:position]) ? (w1[:position] - w4[:position]).round(1) : 0.0

        # Classification
        classification, severity = classify_decay(
          vel_7d_imp_pct: vel_7d_imp_pct,
          vel_14d_imp_pct: vel_14d_imp_pct,
          vel_28d_imp_pct: vel_28d_imp_pct,
          imp_slope: imp_slope,
          pos_drift: pos_drift,
          total_imp: total_imp,
          w1: w1,
          w4: w4
        )

        # Projected loss if trend continues for 30 days
        projected_monthly_clicks_lost = 0
        if click_slope.negative?
          projected_monthly_clicks_lost = [(-click_slope * 4).round, w1_clicks * 4].min
        end

        prescription = formulate_prescription(
          classification: classification,
          pos_drift: pos_drift,
          vel_7d_imp_pct: vel_7d_imp_pct,
          vel_14d_imp_pct: vel_14d_imp_pct,
          w1_imp: w1_imp,
          w1_clicks: w1_clicks,
          entity: entity,
          dimension: dimension
        )

        results << {
          entity: entity,
          dimension: dimension,
          classification: classification,
          severity: severity,
          total_impressions: total_imp,
          total_clicks: total_clicks,
          current_7d_impressions: w1_imp,
          prior_7d_impressions: w2_imp,
          current_7d_clicks: w1_clicks,
          prior_7d_clicks: w2_clicks,
          vel_7d_imp_pct: vel_7d_imp_pct,
          vel_7d_clicks_pct: vel_7d_clicks_pct,
          vel_14d_imp_pct: vel_14d_imp_pct,
          vel_14d_clicks_pct: vel_14d_clicks_pct,
          vel_28d_imp_pct: vel_28d_imp_pct,
          vel_28d_clicks_pct: vel_28d_clicks_pct,
          weekly_impressions: imp_series,
          weekly_clicks: click_series,
          impression_slope: imp_slope.round(2),
          click_slope: click_slope.round(2),
          current_position: w1[:position] ? w1[:position].round(1) : nil,
          prior_position: w4[:position] ? w4[:position].round(1) : nil,
          position_drift: pos_drift,
          projected_monthly_clicks_lost: projected_monthly_clicks_lost,
          prescription: prescription
        }
      end

      # Sort: Critical decay first, then by negative slope
      decaying_items = results.select { |r| %w[CRITICAL_COLLAPSE ACCELERATING_DECAY STEADY_EROSION].include?(r[:classification]) }
                              .sort_by { |r| [severity_weight(r[:severity]), r[:impression_slope]] }

      surging_items = results.select { |r| r[:classification] == 'SURGING' }
                             .sort_by { |r| -r[:vel_14d_imp_pct] }

      stable_items = results.select { |r| r[:classification] == 'STABLE' }

      health_score = calculate_health_score(results)

      {
        dimension: dimension,
        total_evaluated: results.size,
        decaying_count: decaying_items.size,
        surging_count: surging_items.size,
        stable_count: stable_items.size,
        health_score: health_score,
        health_grade: grade_for_score(health_score),
        decaying: decaying_items,
        surging: surging_items,
        date_range: {
          oldest: all_dates.first,
          newest: all_dates.last,
          total_days: all_dates.size
        }
      }
    end

    def self.sum_window(days_map, dates)
      clicks = 0
      impressions = 0
      positions = []
      weighted_pos_sum = 0.0
      weighted_pos_imp = 0

      dates.each do |d|
        entry = days_map[d]
        next unless entry

        clicks += entry[:clicks]
        impressions += entry[:impressions]
        if entry[:position] && entry[:position] > 0
          positions << entry[:position]
          if entry[:impressions] > 0
            weighted_pos_sum += (entry[:position] * entry[:impressions])
            weighted_pos_imp += entry[:impressions]
          end
        end
      end

      avg_pos = if weighted_pos_imp > 0
                  weighted_pos_sum / weighted_pos_imp.to_f
                elsif positions.any?
                  positions.sum / positions.size.to_f
                else
                  nil
                end

      { clicks: clicks, impressions: impressions, position: avg_pos }
    end

    def self.calc_pct_change(curr, prior)
      return 0.0 if prior.to_f.zero? && curr.to_f.zero?
      return 100.0 if prior.to_f.zero? && curr.positive?
      return -100.0 if curr.to_f.zero? && prior.positive?

      (((curr - prior) / prior.to_f) * 100.0).round(1)
    end

    def self.calc_slope(series)
      # x = [1, 2, 3, 4], y = series
      n = series.size
      return 0.0 if n < 2

      x_coords = (1..n).to_a
      x_mean = x_coords.sum / n.to_f
      y_mean = series.sum / n.to_f

      numerator = 0.0
      denominator = 0.0

      n.times do |i|
        x_diff = x_coords[i] - x_mean
        y_diff = series[i] - y_mean
        numerator += (x_diff * y_diff)
        denominator += (x_diff**2)
      end

      return 0.0 if denominator.zero?

      numerator / denominator
    end

    def self.classify_decay(vel_7d_imp_pct:, vel_14d_imp_pct:, vel_28d_imp_pct:, imp_slope:, pos_drift:, total_imp:, w1:, w4:)
      # pos_drift > 0 means current position number is higher (e.g. dropped from 5 to 9 => +4 drift)
      if (vel_14d_imp_pct <= -50.0 && total_imp >= 20) || (w1[:impressions].zero? && w4[:impressions] >= 10)
        ['CRITICAL_COLLAPSE', 'CRITICAL']
      elsif vel_7d_imp_pct <= -35.0 && vel_7d_imp_pct < (vel_14d_imp_pct - 15.0)
        ['ACCELERATING_DECAY', 'HIGH']
      elsif imp_slope.negative? && (vel_14d_imp_pct <= -20.0 || pos_drift >= 3.0)
        ['STEADY_EROSION', 'MODERATE']
      elsif vel_14d_imp_pct >= 25.0 || imp_slope >= 5.0
        ['SURGING', 'INFO']
      else
        ['STABLE', 'LOW']
      end
    end

    def self.formulate_prescription(classification:, pos_drift:, vel_7d_imp_pct:, vel_14d_imp_pct:, w1_imp:, w1_clicks:, entity:, dimension:)
      case classification
      when 'CRITICAL_COLLAPSE'
        if pos_drift >= 5.0
          "🚨 Severe SERP Ranking Drop (+#{pos_drift} pos): Inspect for indexability errors, manual actions, or lost canonical tag."
        elsif w1_imp.zero?
          "💀 Zero Search Impressions in Past 7 Days: Run 'gsc inspect #{entity}' to verify Googlebot coverage."
        else
          "⚠️ High-Volume Collapse (#{vel_14d_imp_pct}% over 14d): Prioritize emergency content refresh and re-index via 'gsc index #{entity}'."
        end
      when 'ACCELERATING_DECAY'
        "⚡ Rapid 7-Day Traffic Drop (#{vel_7d_imp_pct}%): Competitor surge detected. Enhance headline hook and verify schema."
      when 'STEADY_EROSION'
        if pos_drift >= 2.0
          "📉 Gradual Position Drift (+#{pos_drift}): Update dated statistics, expand FAQ answers, and add 2-3 internal links."
        else
          "📉 Search Demand Erosion (#{vel_14d_imp_pct}%): Content freshness fatigue. Add 2026 insights and interactive widgets."
        end
      when 'SURGING'
        "🚀 Surging Velocity (+#{vel_14d_imp_pct}%): Momentum window! Add related internal links to capture additional cluster queries."
      else
        "✅ Consistent Performance: Maintain current on-page content and monitor monthly."
      end
    end

    def self.severity_weight(sev)
      case sev
      when 'CRITICAL' then 1
      when 'HIGH'     then 2
      when 'MODERATE' then 3
      else                 4
      end
    end

    def self.calculate_health_score(results)
      return 100 if results.empty?

      critical = results.count { |r| r[:severity] == 'CRITICAL' }
      high     = results.count { |r| r[:severity] == 'HIGH' }
      moderate = results.count { |r| r[:severity] == 'MODERATE' }

      score = 100 - (critical * 25) - (high * 15) - (moderate * 5)
      [[score, 0].max, 100].min
    end

    def self.grade_for_score(score)
      case score
      when 90..100 then 'A'
      when 80..89  then 'B'
      when 70..79  then 'C'
      when 60..69  then 'D'
      else              'F'
      end
    end

    def self.empty_result(dim)
      {
        dimension: dim,
        total_evaluated: 0,
        decaying_count: 0,
        surging_count: 0,
        stable_count: 0,
        health_score: 100,
        health_grade: 'A',
        decaying: [],
        surging: [],
        date_range: {}
      }
    end
  end
end

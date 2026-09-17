# frozen_string_literal: true

module GSC
  class CtrCurve
    # Empirical Google Organic SERP CTR Curve benchmark (Ahrefs / Backlinko / Advanced Web Ranking composite)
    BENCHMARK_CTR = {
      1 => 28.0,
      2 => 15.5,
      3 => 11.0,
      4 => 8.0,
      5 => 6.0,
      6 => 4.5,
      7 => 3.5,
      8 => 2.8,
      9 => 2.2,
      10 => 1.8,
      11 => 1.4,
      12 => 1.2,
      13 => 1.0,
      14 => 0.9,
      15 => 0.8,
      16 => 0.7,
      17 => 0.6,
      18 => 0.5,
      19 => 0.4,
      20 => 0.4
    }.freeze

    DEFAULT_PAGE2_CTR = 0.5
    DEFAULT_PAGE3_CTR = 0.2

    def self.benchmark_for(position)
      pos = position.to_f.round
      return BENCHMARK_CTR[1] if pos <= 1
      return BENCHMARK_CTR[pos] if BENCHMARK_CTR.key?(pos)
      return DEFAULT_PAGE2_CTR if pos <= 20

      DEFAULT_PAGE3_CTR
    end

    def self.project(rows, target_pos: 3, min_imp: 10)
      target_pos = target_pos.to_i
      target_pos = 3 if target_pos <= 0
      target_ctr = benchmark_for(target_pos)

      analyzed = []
      total_incremental = 0
      underperforming_queries = []

      rows.each do |row|
        imp = row[:impressions] || row['impressions'] || 0
        next if imp < min_imp

        clicks = row[:clicks] || row['clicks'] || 0
        actual_ctr = if imp > 0
                       (clicks.to_f / imp * 100.0).round(2)
                     elsif (row[:ctr] || row['ctr'])
                       (row[:ctr] || row['ctr']).to_f.round(2)
                     else
                       0.0
                     end
        pos = (row[:position] || row['position'] || 100.0).to_f.round(1)
        expected_ctr = benchmark_for(pos)

        # Gain projection if ranking moved to target_pos
        projected_clicks = ((target_ctr / 100.0) * imp).round
        incremental_clicks = [projected_clicks - clicks, 0].max

        # Priority score: Higher incremental clicks and closer to top page 1 = higher leverage
        proximity_factor = [1.0, (25.0 - [pos, 25.0].min) / 20.0].max
        opportunity_score = (incremental_clicks * proximity_factor).round(1)

        # Flag title tag optimization wins: ranking on Page 1 (<=10) but CTR is < 50% of benchmark
        is_underperforming = pos <= 10.0 && actual_ctr < (expected_ctr * 0.6) && imp >= 20

        data = {
          query: row[:query] || row['query'],
          current_position: pos,
          target_position: target_pos,
          impressions: imp,
          current_clicks: clicks,
          current_ctr: actual_ctr,
          expected_ctr: expected_ctr,
          target_ctr: target_ctr,
          projected_clicks: projected_clicks,
          simulated_clicks: projected_clicks, # alias for backward compatibility
          incremental_clicks: incremental_clicks,
          opportunity_score: opportunity_score,
          underperforming: is_underperforming
        }

        analyzed << data
        total_incremental += incremental_clicks
        underperforming_queries << data if is_underperforming
      end

      # Sort by highest opportunity score
      analyzed.sort_by! { |r| -r[:opportunity_score] }
      underperforming_queries.sort_by! { |r| -r[:impressions] }

      {
        target_position: target_pos,
        target_ctr: target_ctr,
        total_queries_analyzed: analyzed.size,
        total_incremental_clicks: total_incremental,
        opportunities: analyzed,
        underperformers: underperforming_queries
      }
    end

    class << self
      alias simulate project
    end
  end
end

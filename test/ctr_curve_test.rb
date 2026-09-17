# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/ctr_curve'

class CtrCurveTest < Minitest::Test
  def test_benchmark_curve_returns_expected_ctrs
    assert_equal 28.0, GSC::CtrCurve.benchmark_for(1)
    assert_equal 15.5, GSC::CtrCurve.benchmark_for(2)
    assert_equal 11.0, GSC::CtrCurve.benchmark_for(3)
    assert_equal 1.8, GSC::CtrCurve.benchmark_for(10)
    assert_equal 0.8, GSC::CtrCurve.benchmark_for(15)
    assert_equal 0.2, GSC::CtrCurve.benchmark_for(25)
  end

  def test_simulate_calculates_gain_and_identifies_underperformers
    rows = [
      # Query ranking at pos 7 with 1,000 imp and 10 clicks (1.0% CTR vs 3.5% exp CTR)
      { query: 'technical seo audit', clicks: 10, impressions: 1000, ctr: 1.0, position: 7.0 },
      # Query ranking at pos 15 with 500 imp and 2 clicks
      { query: 'schema markup tutorial', clicks: 2, impressions: 500, ctr: 0.4, position: 15.0 },
      # Query with low impressions (should be skipped by min_imp)
      { query: 'rare search term', clicks: 0, impressions: 5, ctr: 0.0, position: 20.0 }
    ]

    result = GSC::CtrCurve.simulate(rows, target_pos: 3, min_imp: 10)

    assert_equal 3, result[:target_position]
    assert_equal 11.0, result[:target_ctr]
    assert_equal 2, result[:total_queries_analyzed]

    # pos 7: target 11% of 1000 = 110 clicks. Incremental = 110 - 10 = 100 clicks
    opp = result[:opportunities].first
    assert_equal 'technical seo audit', opp[:query]
    assert_equal 110, opp[:simulated_clicks]
    assert_equal 100, opp[:incremental_clicks]
    assert opp[:underperforming] # 1.0% is < 3.5% * 0.6 = 2.1%

    assert_equal 1, result[:underperformers].size
    assert_equal 'technical seo audit', result[:underperformers].first[:query]
  end
end

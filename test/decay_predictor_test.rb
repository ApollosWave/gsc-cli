# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class DecayPredictorTest < Minitest::Test
  def test_calc_slope
    # Rising slope
    assert_equal 2.0, GSC::DecayPredictor.calc_slope([2, 4, 6, 8])
    # Falling slope
    assert_equal(-3.0, GSC::DecayPredictor.calc_slope([12, 9, 6, 3]))
    # Flat slope
    assert_equal 0.0, GSC::DecayPredictor.calc_slope([5, 5, 5, 5])
  end

  def test_calc_pct_change
    assert_equal 100.0, GSC::DecayPredictor.calc_pct_change(20, 10)
    assert_equal(-50.0, GSC::DecayPredictor.calc_pct_change(10, 20))
    assert_equal 0.0, GSC::DecayPredictor.calc_pct_change(0, 0)
    assert_equal 100.0, GSC::DecayPredictor.calc_pct_change(15, 0)
    assert_equal(-100.0, GSC::DecayPredictor.calc_pct_change(0, 15))
  end

  def test_decay_analysis_detects_collapse_and_erosion
    dates = (1..28).map { |d| "2026-08-%02d" % d }
    rows = []

    # Page 1: Collapsing page (starts high, crashes to 0)
    dates[0..6].each { |d| rows << { 'keys' => ['https://example.com/dying', d], 'clicks' => 5, 'impressions' => 50, 'position' => 3.0 } }
    dates[7..13].each { |d| rows << { 'keys' => ['https://example.com/dying', d], 'clicks' => 3, 'impressions' => 30, 'position' => 6.0 } }
    dates[14..20].each { |d| rows << { 'keys' => ['https://example.com/dying', d], 'clicks' => 1, 'impressions' => 10, 'position' => 12.0 } }
    dates[21..27].each { |d| rows << { 'keys' => ['https://example.com/dying', d], 'clicks' => 0, 'impressions' => 0, 'position' => 45.0 } }

    # Page 2: Surging page (starts low, explodes upwards)
    dates[0..6].each { |d| rows << { 'keys' => ['https://example.com/winner', d], 'clicks' => 1, 'impressions' => 10, 'position' => 15.0 } }
    dates[7..13].each { |d| rows << { 'keys' => ['https://example.com/winner', d], 'clicks' => 2, 'impressions' => 20, 'position' => 10.0 } }
    dates[14..20].each { |d| rows << { 'keys' => ['https://example.com/winner', d], 'clicks' => 5, 'impressions' => 50, 'position' => 5.0 } }
    dates[21..27].each { |d| rows << { 'keys' => ['https://example.com/winner', d], 'clicks' => 10, 'impressions' => 100, 'position' => 2.0 } }

    # Page 3: Stable page
    dates.each { |d| rows << { 'keys' => ['https://example.com/rock', d], 'clicks' => 2, 'impressions' => 25, 'position' => 4.0 } }

    res = GSC::DecayPredictor.analyze_timeseries(rows, dimension: 'page', min_imp: 10)

    assert_equal 'page', res[:dimension]
    assert_equal 3, res[:total_evaluated]
    assert_equal 1, res[:decaying_count]
    assert_equal 1, res[:surging_count]
    assert_equal 1, res[:stable_count]

    dying = res[:decaying].first
    assert_equal 'https://example.com/dying', dying[:entity]
    assert_equal 'CRITICAL_COLLAPSE', dying[:classification]
    assert dying[:impression_slope].negative?
    assert_includes dying[:prescription], 'SERP'

    winner = res[:surging].first
    assert_equal 'https://example.com/winner', winner[:entity]
    assert_equal 'SURGING', winner[:classification]
    assert winner[:impression_slope].positive?
  end

  def test_empty_rows_returns_safe_defaults
    res = GSC::DecayPredictor.analyze_timeseries([], dimension: 'query')
    assert_equal 0, res[:total_evaluated]
    assert_equal 100, res[:health_score]
    assert_equal 'A', res[:health_grade]
    assert_empty res[:decaying]
  end
end

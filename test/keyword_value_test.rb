# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/keyword_value'

class KeywordValueTest < Minitest::Test
  def setup
    @domain = 'zerocramp.com'
    @options = { aov: 120.0, conv_rate: 0.03, margin: 0.70, target_pos: 3 }
    @kv = GSC::KeywordValue.new(@options, nil, @domain)
  end

  def test_analyze_execution_and_financial_structure_unauthenticated
    res = @kv.analyze

    assert_equal 'zerocramp.com', res[:domain]
    assert_equal 120.0, res[:parameters][:aov]
    assert_equal 3.0, res[:parameters][:conversion_rate_pct]
    assert_equal 70.0, res[:parameters][:profit_margin_pct]
    assert_equal 3, res[:parameters][:target_position]

    f = res[:financials]
    assert_equal 0.0, f[:current_monthly_revenue]
    assert_equal 0.0, f[:potential_monthly_revenue]
    assert_equal 0.0, f[:unlocked_monthly_upside]
    assert_equal 0.0, f[:unlocked_annual_pipeline_upside]

    assert_empty res[:keywords]
  end

  def test_analyze_execution_and_financial_structure_authenticated
    mock_api = Object.new
    def mock_api.search_analytics(domain, options = {})
      {
        'rows' => [
          { 'keys' => ['buy acoustic pain relief coupon'], 'clicks' => 100, 'impressions' => 5000, 'ctr' => 0.02, 'position' => 5.0 }
        ]
      }
    end

    kv = GSC::KeywordValue.new(@options, mock_api, @domain)
    res = kv.analyze

    assert_equal 'zerocramp.com', res[:domain]
    f = res[:financials]
    assert f[:current_monthly_revenue] > 0
    assert f[:potential_monthly_revenue] > 0
    assert f[:unlocked_monthly_upside] >= 0
    assert_equal (f[:unlocked_monthly_upside] * 12).round(2), f[:unlocked_annual_pipeline_upside]

    refute_empty res[:keywords]
  end

  def test_buyer_intent_multiplier_and_striking_distance
    custom_rows = [
      # High-intent buyer keyword on page 1 striking distance (pos 5.0)
      { query: 'buy acoustic pain relief coupon', clicks: 100, impressions: 5000, ctr: 2.0, position: 5.0 },
      # Low-intent informational query already at pos 1.0
      { query: 'what is dysmenorrhea', clicks: 2000, impressions: 50000, ctr: 4.0, position: 1.0 }
    ]

    kv = GSC::KeywordValue.new({ aov: 100.0, conv_rate: 0.02 }, nil, @domain)
    target_ctr = GSC::CtrCurve.benchmark_for(3) # 11.0%

    analyzed = custom_rows.map { |r| kv.send(:analyze_row, r, target_ctr) }
    buy_kw = analyzed.find { |k| k[:query].include?('buy') }
    info_kw = analyzed.find { |k| k[:query].include?('what is') }

    assert_equal :transactional, buy_kw[:intent]
    # Transactional intent has 2.0x multiplier: 0.02 * 2.0 = 0.04 (4.0%)
    assert_equal 4.0, buy_kw[:effective_conv_rate]
    assert buy_kw[:monthly_revenue_upside] > 0
    assert buy_kw[:value_score] >= 70
    assert_includes buy_kw[:action], 'Striking Distance'

    assert_equal :informational, info_kw[:intent]
    # Pos 1.0 already top 3
    assert_equal 0.0, info_kw[:monthly_revenue_upside]
    assert_includes info_kw[:action], 'Top 3 Defend'
  end

  def test_custom_target_position
    mock_api = Object.new
    def mock_api.search_analytics(domain, options = {})
      {
        'rows' => [
          { 'keys' => ['buy acoustic pain relief coupon'], 'clicks' => 100, 'impressions' => 5000, 'ctr' => 0.02, 'position' => 5.0 }
        ]
      }
    end

    # Target position 1 instead of 3
    kv_pos1 = GSC::KeywordValue.new({ aov: 100.0, target_pos: 1 }, mock_api, @domain)
    res = kv_pos1.analyze

    assert_equal 1, res[:parameters][:target_position]
    assert res[:financials][:potential_monthly_revenue] > 0
  end
end

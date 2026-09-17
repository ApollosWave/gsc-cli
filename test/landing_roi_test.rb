# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/landing_roi'

class LandingRoiTest < Minitest::Test
  def setup
    @analyzer = GSC::LandingRoi.new(
      aov: 100.0,
      conv_rate: 0.03, # 3%
      benchmark_bounce: 40.0,
      cpc: 2.00
    )
  end

  def test_analyzes_single_page_with_revenue_leak
    page = {
      url: 'https://example.com/checkout-guide',
      clicks: 1000,
      impressions: 25000,
      position: 3.2,
      ctr: 4.0,
      sessions: 980,
      bounce_rate: 70.0,
      duration: 25.0
    }

    result = @analyzer.analyze_single_page(page)

    assert_equal 'https://example.com/checkout-guide', result[:url]
    assert_equal 1000, result[:clicks]
    assert_equal 70.0, result[:bounce_rate]
    # excess_bounce = 70.0 - 40.0 = 30%
    # lost_visitors = 1000 * 0.30 = 300
    assert_equal 300, result[:lost_visitors]
    # monthly_revenue_leak = 300 * 0.03 * 100 = $900.00
    assert_equal 900.00, result[:monthly_revenue_leak]
    # annual = 900 * 12 = 10,800
    assert_equal 10800.00, result[:annual_revenue_leak]
    # engaged_clicks = 700 -> actual_revenue_est = 700 * 0.03 * 100 = 2100.00
    assert_equal 2100.00, result[:actual_revenue_est]
    assert_equal :revenue_leaker, result[:quadrant]
    assert result[:pehi_score] < 50
    assert result[:prescriptions].any? { |p| p =~ /HIGH BOUNCE/ }
    assert result[:prescriptions].any? { |p| p =~ /LOW TIME ON PAGE/ }
  end

  def test_analyzes_cash_cow_page
    page = {
      url: 'https://example.com/core-product',
      clicks: 500,
      impressions: 10000,
      position: 1.8,
      ctr: 5.0,
      sessions: 490,
      bounce_rate: 32.0,
      duration: 140.0
    }

    result = @analyzer.analyze_single_page(page)

    assert_equal 0, result[:lost_visitors]
    assert_equal 0.0, result[:monthly_revenue_leak]
    assert_equal :cash_cow, result[:quadrant]
    assert result[:pehi_score] >= 80
    assert result[:prescriptions].any? { |p| p =~ /HEALTHY ENGAGEMENT/ }
  end

  def test_analyzes_hidden_gem_page
    page = {
      url: 'https://example.com/niche-feature',
      clicks: 15,
      impressions: 1200,
      position: 8.5,
      ctr: 1.25,
      sessions: 15,
      bounce_rate: 28.0,
      duration: 95.0
    }

    result = @analyzer.analyze_single_page(page)

    assert_equal :hidden_gem, result[:quadrant]
    assert result[:prescriptions].any? { |p| p =~ /HIDDEN HIGH CONVERTER/ }
  end

  def test_analyzes_multiple_pages_aggregation
    pages = [
      { url: '/leak', clicks: 1000, bounce_rate: 70.0, duration: 20.0 },
      { url: '/cow', clicks: 500, bounce_rate: 30.0, duration: 150.0 },
      { url: '/gem', clicks: 10, bounce_rate: 25.0, duration: 90.0 }
    ]

    report = @analyzer.analyze_pages(pages)

    assert_equal 3, report[:total_pages]
    assert_equal 1510, report[:total_clicks]
    assert_equal 300, report[:total_lost_visitors]
    assert_equal 900.00, report[:total_monthly_leak]
    assert_equal 10800.00, report[:total_annual_leak]
    assert_equal 1, report[:quadrants][:revenue_leakers]
    assert_equal 1, report[:quadrants][:cash_cows]
    assert_equal 1, report[:quadrants][:hidden_gems]
    assert_equal '/leak', report[:pages].first[:url] # sorted by highest leak
  end

  def test_handles_zero_clicks_gracefully
    page = { url: '/empty', clicks: 0, bounce_rate: 80.0, duration: 0.0 }
    result = @analyzer.analyze_single_page(page)

    assert_equal 0, result[:lost_visitors]
    assert_equal 0.0, result[:monthly_revenue_leak]
    assert_equal :zombie, result[:quadrant]
  end
end

# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class SpeedCorrelatorTest < Minitest::Test
  def test_initialization_defaults
    sc = GSC::SpeedCorrelator.new('https://example.com/product', domain: 'example.com', days: 14, strategy: 'DESKTOP')
    assert_equal 'https://example.com/product', sc.url
    assert_equal 'example.com', sc.domain
    assert_equal 14, sc.days
    assert_equal 'desktop', sc.strategy
  end

  def test_days_and_url_normalization
    sc = GSC::SpeedCorrelator.new('', domain: 'exampleapp.com', days: 2)
    assert_equal 'https://exampleapp.com/', sc.url
    assert_equal 7, sc.days # bounded to minimum 7 days
  end

  def test_compute_cwv_correlation_passed
    sc = GSC::SpeedCorrelator.new('https://example.com')
    cwv = { lcp_val: 1.8, cls_val: 0.04 }
    gsc = { impressions: 1500, clicks: 45, position: 8.2, ctr: 3.0 }

    res = sc.send(:compute_cwv_correlation, cwv, gsc)
    assert res[:overall_cwv_pass]
    assert_equal 'GOOD', res[:lcp_status]
    assert_equal 'GOOD', res[:cls_status]
    assert_includes res[:algorithmic_status], 'OPTIMAL'
  end

  def test_compute_cwv_correlation_poor
    sc = GSC::SpeedCorrelator.new('https://example.com')
    cwv = { lcp_val: 4.8, cls_val: 0.28 }
    gsc = { impressions: 800, clicks: 12, position: 22.4, ctr: 1.5 }

    res = sc.send(:compute_cwv_correlation, cwv, gsc)
    refute res[:overall_cwv_pass]
    assert_equal 'POOR', res[:lcp_status]
    assert_equal 'POOR', res[:cls_status]
    assert_includes res[:algorithmic_status], 'HIGH ALGORITHMIC DRAG'
  end

  def test_calculate_projected_lift
    sc = GSC::SpeedCorrelator.new('https://example.com')
    cwv = { lcp_val: 4.2 }
    gsc = { impressions: 1000, clicks: 20, position: 15.0, ctr: 2.0 }

    lift = sc.send(:calculate_projected_lift, cwv, gsc)
    assert_equal 28.0, lift[:potential_lift_percentage]
    assert_equal 1280, lift[:projected_impressions]
    assert_equal 280, lift[:incremental_impressions_gain]
    assert lift[:projected_position] < 15.0 # rank improved (lower position is better)
    assert lift[:projected_incremental_monthly_clicks] > 0
  end

  def test_build_dom_opportunities
    sc = GSC::SpeedCorrelator.new('https://example.com')
    opps = sc.send(:build_dom_opportunities, 3, 2, 4, 650)

    assert_equal 4, opps.size
    assert_equal 'render-blocking-css', opps[0][:id]
    assert_includes opps[0][:display], '540 ms'
    assert_equal 'defer-scripts', opps[1][:id]
    assert_equal 'image-dimensions', opps[2][:id]
    assert_equal 'server-response-time', opps[3][:id]
  end

  def test_full_correlation_pipeline
    sc = GSC::SpeedCorrelator.new('https://example.com')
    sc.define_singleton_method(:profile_core_web_vitals) do |_url, _strat|
      {
        source: 'Mock Test Profiler',
        performance_score: 72,
        seo_score: 95,
        lcp_val: 2.8,
        lcp_display: '2.8 s',
        cls_val: 0.05,
        cls_display: '0.05',
        fcp_val: 1.4,
        fcp_display: '1.4 s',
        tbt_val: 180,
        tbt_display: '180 ms',
        opportunities: [{ id: 'opt1', title: 'Compress Images', savings_ms: 220, display: '220ms' }]
      }
    end

    sc.define_singleton_method(:fetch_gsc_performance) do |_url, _dom, _days|
      {
        available: true,
        period_days: 28,
        impressions: 3400,
        clicks: 85,
        ctr: 2.5,
        position: 9.4
      }
    end

    res = sc.correlate
    assert_equal 'https://example.com', res[:url]
    assert_equal 72, res[:core_web_vitals][:performance_score]
    assert_equal 3400, res[:gsc_performance][:impressions]
    assert_equal 'NEEDS_IMPROVEMENT', res[:correlation_diagnosis][:lcp_status]
    assert res[:projections][:potential_lift_percentage] > 0
    assert res[:action_plan].any?
  end
end

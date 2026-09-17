# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class TitleOptimizerTest < Minitest::Test
  def setup
    @optimizer = GSC::TitleOptimizer.new('https://example.com')
  end

  def test_pixel_width_estimation_proportionality
    wide_str = "WWWWWWWWWW"
    narrow_str = "iiiiiiiiii"

    wide_px = GSC::TitleOptimizer.estimate_pixel_width(wide_str)
    narrow_px = GSC::TitleOptimizer.estimate_pixel_width(narrow_str)

    assert wide_px > narrow_px * 2.5
    assert_equal 135.0, wide_px
    assert_equal 45.0, narrow_px
  end

  def test_truncate_to_pixel_width
    short = "ExampleApp | SEO Intelligence"
    assert_equal short, GSC::TitleOptimizer.truncate_to_pixel_width(short, 580.0)

    long = "ExampleApp® Official: #1 Search Console & Technical SEO Audit Engine for High-Growth Engineering Teams Worldwide"
    truncated = GSC::TitleOptimizer.truncate_to_pixel_width(long, 580.0)

    assert truncated.end_with?('...')
    assert GSC::TitleOptimizer.estimate_pixel_width(truncated) <= 580.0
  end

  def test_evaluate_title_status
    missing_status, _ = @optimizer.send(:evaluate_title_status, '', 0, 0.0)
    assert_equal :missing, missing_status

    short_status, _ = @optimizer.send(:evaluate_title_status, 'Home', 4, 40.0)
    assert_equal :too_short, short_status

    desk_status, _ = @optimizer.send(:evaluate_title_status, 'A' * 65, 65, 595.0)
    assert_equal :desktop_overflow, desk_status

    crit_status, _ = @optimizer.send(:evaluate_title_status, 'W' * 80, 80, 750.0)
    assert_equal :critical_overflow, crit_status

    opt_status, _ = @optimizer.send(:evaluate_title_status, 'ExampleApp | Fast SEO Analytics Tool', 36, 480.0)
    assert_equal :optimal, opt_status
  end

  def test_synthesize_rewrites_generates_three_variations_under_limit
    long_title = "ExampleApp® Official: The #1 Best Search Console Analytics Tool & High-Converting Technical SEO Engine for Modern Teams"
    h1 = "ExampleApp Search Analytics Tool"
    url = "https://example.com/features/search-analytics"

    rewrites = @optimizer.send(:synthesize_rewrites, url, long_title, h1, 820.0)
    assert_equal 3, rewrites.size

    rewrites.each do |r|
      assert r[:pixel_width] <= 580.0, "Rewrite #{r[:title]} exceeds 580px (#{r[:pixel_width]}px)"
      assert r[:fits_serp]
      refute_empty r[:title]
    end

    types = rewrites.map { |r| r[:type] }
    assert_includes types, 'Primary Hook + Clean Brand'
    assert_includes types, 'Action / Benefit-Driven Hook'
    assert_includes types, 'Compact Exact-Intent Match'
  end

  def test_site_summary_calculation
    @optimizer.instance_variable_set(:@results, [
      { status: :optimal, pixel_width: 480.0 },
      { status: :optimal, pixel_width: 510.0 },
      { status: :desktop_overflow, pixel_width: 595.0 },
      { status: :critical_overflow, pixel_width: 680.0 }
    ])

    summary = @optimizer.send(:calculate_site_summary)
    assert_equal 4, summary[:total_pages]
    assert_equal 2, summary[:counts][:optimal]
    assert_equal 1, summary[:counts][:desktop_overflow]
    assert_equal 1, summary[:counts][:critical_overflow]
    assert_equal 50.0, summary[:percentages][:optimal_pct]
    assert_equal 50.0, summary[:percentages][:overflow_pct]
    assert summary[:health_score] < 85
  end
end

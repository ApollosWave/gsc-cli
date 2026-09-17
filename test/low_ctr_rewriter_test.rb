# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/low_ctr_rewriter'

class LowCtrRewriterTest < Minitest::Test
  def setup
    @sample_rows = [
      # Page 1: High impressions, rank 3 (expected ~11.0%), actual CTR 2.0% -> Severe click hemorrhage
      { 'keys' => ['technical seo audit tool', 'https://example.com/seo-audit'], 'impressions' => 5000, 'clicks' => 100, 'position' => 3.2, 'ctr' => 0.02 },
      { 'keys' => ['best technical seo scanner', 'https://example.com/seo-audit'], 'impressions' => 2000, 'clicks' => 30, 'position' => 3.8, 'ctr' => 0.015 },
      # Page 2: Good CTR, rank 1 (expected 28%), actual CTR 27.5% -> Healthy, not leaking
      { 'keys' => ['exampleapp', 'https://example.com/'], 'impressions' => 1000, 'clicks' => 275, 'position' => 1.1, 'ctr' => 0.275 },
      # Page 3: Rank 8 (expected 2.8%), actual CTR 0.5%, 1500 imp -> Moderate leak
      { 'keys' => ['free technical seo checklist', 'https://example.com/seo-checklist'], 'impressions' => 1500, 'clicks' => 8, 'position' => 8.1, 'ctr' => 0.005 }
    ]
  end

  def test_normalize_rows
    rewriter = GSC::LowCtrRewriter.new(@sample_rows)
    normalized = rewriter.send(:normalize_rows, @sample_rows)

    assert_equal 4, normalized.size
    assert_equal 'technical seo audit tool', normalized[0][:query]
    assert_equal 'https://example.com/seo-audit', normalized[0][:page]
    assert_equal 5000, normalized[0][:impressions]
    assert_equal 100, normalized[0][:clicks]
    assert_equal 3.2, normalized[0][:position]
    assert_equal 2.0, normalized[0][:ctr]
  end

  def test_benchmark_ctr_for
    rewriter = GSC::LowCtrRewriter.new([])
    assert_equal 28.0, rewriter.send(:benchmark_ctr_for, 1.0)
    assert_equal 15.5, rewriter.send(:benchmark_ctr_for, 2.0)
    assert_equal 11.0, rewriter.send(:benchmark_ctr_for, 3.0)
    assert_equal 8.0, rewriter.send(:benchmark_ctr_for, 4.0)
    assert_equal 6.0, rewriter.send(:benchmark_ctr_for, 5.0)
    assert_equal 1.8, rewriter.send(:benchmark_ctr_for, 10.0)
  end

  def test_analyze_identifies_leaking_pages_and_revenue
    result = GSC::LowCtrRewriter.analyze(@sample_rows, brand: 'ExampleApp', min_imp: 50, cpc: 2.00)

    assert result[:total_leaking_pages] >= 2
    assert result[:total_monthly_lost_clicks] > 500
    assert result[:estimated_monthly_value_lost] > 1000.0
    assert_equal 2.00, result[:cpc_used]

    top_leaker = result[:pages].first
    assert_equal 'https://example.com/seo-audit', top_leaker[:url]
    assert_equal 'technical seo audit tool', top_leaker[:primary_query]
    assert_equal 7000, top_leaker[:impressions]
    assert_equal 130, top_leaker[:clicks]
    assert_includes [:critical, :high], top_leaker[:severity]
    assert top_leaker[:lost_clicks] > 400
  end

  def test_synthesizes_three_hooks_within_serp_pixel_limits
    hooks = GSC::LowCtrRewriter.generate_title_hooks('technical seo audit tool', 'ExampleApp', 'https://example.com/seo-audit')

    assert_equal 3, hooks.size
    types = hooks.map { |h| h[:type] }
    assert_includes types, 'Authority & Power-Number Hook'
    assert_includes types, 'Benefit & Velocity Hook'
    assert_includes types, 'Curiosity & Information-Gain Hook'

    hooks.each do |hook|
      assert hook[:fits_serp], "Hook '#{hook[:title]}' exceeds 560px (got #{hook[:pixel_width]}px)"
      assert hook[:pixel_width] <= 560.0
      assert hook[:char_count] <= 65
      assert hook[:title].include?('Exampleapp') || hook[:title].include?('ExampleApp')
    end
  end

  def test_synthesizes_meta_description
    meta = GSC::LowCtrRewriter.generate_meta_description('technical seo audit tool', 'ExampleApp')

    refute_nil meta
    assert meta.length >= 70
    assert meta.length <= 160
    assert meta.downcase.include?('exampleapp')
  end

  def test_projected_recovery_math
    result = GSC::LowCtrRewriter.analyze(@sample_rows, min_imp: 50)
    rec = result[:projected_recovery]

    total = result[:total_monthly_lost_clicks]
    assert_equal (total * 0.25).round, rec[:conservative_25pct]
    assert_equal (total * 0.50).round, rec[:realistic_50pct]
    assert_equal total, rec[:full_parity_100pct]
  end

  def test_handles_empty_or_non_leaking_gracefully
    healthy_rows = [
      { 'keys' => ['brand login', 'https://example.com/login'], 'impressions' => 100, 'clicks' => 50, 'position' => 1.0, 'ctr' => 0.50 }
    ]
    result = GSC::LowCtrRewriter.analyze(healthy_rows, min_imp: 50)

    assert_equal 0, result[:total_leaking_pages]
    assert_equal 0, result[:total_monthly_lost_clicks]
    assert_equal 0.0, result[:estimated_monthly_value_lost]
    assert_empty result[:pages]
  end
end

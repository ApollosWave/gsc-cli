# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/report_generator'

class ReportGeneratorTest < Minitest::Test
  def setup
    @options = { days: 14, title: "Q1 Organic Performance Audit" }
    @domain = "teststore.com"
  end

  def test_generate_report_structure_unauthenticated
    res = GSC::ReportGenerator.generate(@options, nil, @domain)

    assert_equal "Q1 Organic Performance Audit", res[:title]
    assert_equal "teststore.com", res[:domain]
    assert_equal 14, res[:period_days]
    refute_nil res[:generated_at]

    # Check zero-mock performance metrics when unauthenticated
    perf = res[:performance]
    assert_equal 0, perf[:clicks]
    assert_equal 0, perf[:impressions]
    assert_equal 0.0, perf[:ctr]
    assert_equal 0.0, perf[:position]
    assert_includes perf[:momentum], "Connect Search Console"

    # Check live dynamic pillar scores
    scores = res[:scores]
    assert scores[:overall_health] >= 0 && scores[:overall_health] <= 100
    assert scores[:geo_citability] >= 0 && scores[:geo_citability] <= 100
    assert scores[:technical_cwv] >= 0 && scores[:technical_cwv] <= 100

    # Unauthenticated has zero fake opportunities
    assert_empty res[:opportunities]
    refute_empty res[:priorities]
  end

  def test_generate_report_structure_authenticated
    mock_api = Object.new
    def mock_api.search_analytics(domain, options = {})
      if options[:dimensions] == ['date']
        { 'rows' => [{ 'keys' => ['2026-09-10'], 'clicks' => 500, 'impressions' => 12000, 'ctr' => 0.0416, 'position' => 8.2 }] }
      elsif options[:dimensions] == ['query']
        { 'rows' => [{ 'keys' => ['test organic query'], 'clicks' => 45, 'impressions' => 1200, 'ctr' => 0.0375, 'position' => 9.4 }] }
      else
        { 'rows' => [] }
      end
    end

    res = GSC::ReportGenerator.generate(@options, mock_api, @domain)
    perf = res[:performance]
    assert_equal 500, perf[:clicks]
    assert_equal 12000, perf[:impressions]
    refute_empty res[:opportunities]
    assert_equal 'test organic query', res[:opportunities].first[:query]
  end

  def test_html_dashboard_generation
    res = GSC::ReportGenerator.generate(@options, nil, @domain)
    html = res[:html]

    assert_includes html, '<!DOCTYPE html>'
    assert_includes html, 'Q1 Organic Performance Audit'
    assert_includes html, 'teststore.com'
    assert_includes html, '<table'
    assert_includes html, 'Strategic Engineering Roadmap'
    assert_includes html, 'gsc-cli v2.2'
  end

  def test_markdown_report_generation
    res = GSC::ReportGenerator.generate(@options, nil, @domain)
    md = res[:markdown]

    assert_includes md, '# Q1 Organic Performance Audit'
    assert_includes md, '## 1. Executive Performance Scorecard'
    assert_includes md, '## 2. Comprehensive Pillar Ratings'
    assert_includes md, '## 3. High-ROI Striking-Distance Keywords'
    assert_includes md, '## 4. Priority Executive Action Roadmap'
    assert_includes md, 'gsc-cli'
  end
end

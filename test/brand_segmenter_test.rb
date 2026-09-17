# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/brand_segmenter'

class BrandSegmenterTest < Minitest::Test
  def setup
    @segmenter = GSC::BrandSegmenter.new(domain: 'exampleapp.com')
  end

  def test_identifies_brand_tokens_from_domain
    assert_includes @segmenter.brand_tokens, 'exampleapp'
    assert_includes @segmenter.brand_tokens, 'example'
  end

  def test_classifies_brand_queries
    assert @segmenter.brand?('example')
    assert @segmenter.brand?('example app')
    assert @segmenter.brand?('example login')
    assert @segmenter.brand?('download example')
  end

  def test_classifies_non_brand_queries
    refute @segmenter.brand?('technical seo audit tools')
    refute @segmenter.brand?('core web vitals test guide')
    refute @segmenter.brand?('search console indexation error')
    refute @segmenter.brand?('best organic keyword trackers')
  end

  def test_custom_brand_override
    custom = GSC::BrandSegmenter.new(domain: 'example.com', custom_brand: 'MegaStore Pro')
    assert custom.brand?('megastore pro discount code')
    assert custom.brand?('megastore deals')
    refute custom.brand?('cheap running shoes')
  end

  def test_segment_calculates_correct_summary
    rows = [
      { query: 'example login', clicks: 10, impressions: 100, ctr: 10.0, position: 1.0 },
      { query: 'example pricing', clicks: 5, impressions: 50, ctr: 10.0, position: 2.0 },
      { query: 'technical seo audit tips', clicks: 1, impressions: 200, ctr: 0.5, position: 15.0 },
      { query: 'increase organic traffic', clicks: 0, impressions: 100, ctr: 0.0, position: 22.0 }
    ]

    result = @segmenter.segment(rows)
    assert_equal 2, result[:brand].size
    assert_equal 2, result[:non_brand].size

    summary = result[:summary]
    assert_equal 4, summary[:total_queries]
    assert_equal 15, summary[:brand][:clicks]
    assert_equal 150, summary[:brand][:impressions]
    assert_equal 1, summary[:non_brand][:clicks]
    assert_equal 300, summary[:non_brand][:impressions]
    assert_in_delta 93.75, summary[:brand][:click_share], 0.1 # 15 / 16
    assert_in_delta 6.25, summary[:non_brand][:click_share], 0.1 # 1 / 16
  end
end

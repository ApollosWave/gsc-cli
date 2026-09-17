# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../lib/gsc/page_speed'

class PageSpeedTest < Minitest::Test
  def test_initialization_defaults
    ps = GSC::PageSpeed.new('https://example.com')
    assert_equal 'https://example.com', ps.url
    assert_equal 'mobile', ps.strategy
  end

  def test_initialization_desktop_strategy
    ps = GSC::PageSpeed.new('https://example.com', strategy: 'DESKTOP')
    assert_equal 'desktop', ps.strategy
  end

  def test_parse_response_with_lab_and_url_crux
    ps = GSC::PageSpeed.new('https://example.com')

    sample_api_response = {
      'lighthouseResult' => {
        'categories' => {
          'performance' => { 'score' => 0.95 },
          'seo' => { 'score' => 1.0 }
        },
        'audits' => {
          'largest-contentful-paint' => { 'displayValue' => '1.5 s' },
          'first-contentful-paint' => { 'displayValue' => '1.1 s' },
          'cumulative-layout-shift' => { 'displayValue' => '0.01' },
          'total-blocking-time' => { 'displayValue' => '40 ms' },
          'speed-index' => { 'displayValue' => '1.8 s' },
          'unused-javascript' => {
            'title' => 'Reduce unused JavaScript',
            'displayValue' => 'Potential savings of 45 KiB',
            'numericValue' => 250,
            'details' => { 'type' => 'opportunity', 'overallSavingsMs' => 250 }
          }
        }
      },
      'loadingExperience' => {
        'overall_category' => 'FAST',
        'metrics' => {
          'LARGEST_CONTENTFUL_PAINT_MS' => { 'percentile' => 1800, 'category' => 'FAST' },
          'INTERACTION_TO_NEXT_PAINT' => { 'percentile' => 120, 'category' => 'FAST' },
          'CUMULATIVE_LAYOUT_SHIFT_SCORE' => { 'percentile' => 4, 'category' => 'FAST' },
          'FIRST_CONTENTFUL_PAINT_MS' => { 'percentile' => 1400, 'category' => 'FAST' },
          'EXPERIMENTAL_TIME_TO_FIRST_BYTE' => { 'percentile' => 350, 'category' => 'FAST' }
        }
      }
    }

    data = ps.send(:parse_response, sample_api_response)

    assert_equal 95, data[:performance_score]
    assert_equal 100, data[:seo_score]
    assert_equal '1.5 s', data[:metrics][:lcp]
    assert_equal '1.1 s', data[:metrics][:fcp]
    assert_equal '0.01', data[:metrics][:cls]
    assert_equal '40 ms', data[:metrics][:tbt]
    assert_equal '1.8 s', data[:metrics][:speed_index]

    # CrUX Field telemetry
    assert_equal :url, data[:field_source]
    assert_equal 'FAST', data[:overall_category]
    assert_equal 'PASSED', data[:cwv_assessment]
    assert_equal 1800, data[:field_data]['LARGEST_CONTENTFUL_PAINT_MS'][:percentile]
    assert_equal 'FAST', data[:field_data]['LARGEST_CONTENTFUL_PAINT_MS'][:category]
    assert_equal 120, data[:field_data]['INTERACTION_TO_NEXT_PAINT'][:percentile]

    # Opportunities
    assert_equal 1, data[:opportunities].size
    assert_equal 'Reduce unused JavaScript', data[:opportunities].first[:title]
  end

  def test_cwv_assessment_passed_when_ttfb_is_average
    ps = GSC::PageSpeed.new('https://example.com')

    sample_api_response = {
      'lighthouseResult' => { 'categories' => {}, 'audits' => {} },
      'loadingExperience' => {
        'overall_category' => 'AVERAGE', # Google legacy API returns AVERAGE because TTFB is AVERAGE
        'metrics' => {
          'LARGEST_CONTENTFUL_PAINT_MS' => { 'percentile' => 1230, 'category' => 'FAST' },
          'INTERACTION_TO_NEXT_PAINT' => { 'percentile' => 69, 'category' => 'FAST' },
          'CUMULATIVE_LAYOUT_SHIFT_SCORE' => { 'percentile' => 0, 'category' => 'FAST' },
          'FIRST_CONTENTFUL_PAINT_MS' => { 'percentile' => 1150, 'category' => 'FAST' },
          'EXPERIMENTAL_TIME_TO_FIRST_BYTE' => { 'percentile' => 973, 'category' => 'AVERAGE' }
        }
      }
    }

    data = ps.send(:parse_response, sample_api_response)

    # Core Web Vitals assessment evaluates only LCP, INP, and CLS
    assert_equal 'AVERAGE', data[:overall_category]
    assert_equal 'PASSED', data[:cwv_assessment]
  end

  def test_parse_response_with_origin_crux_fallback
    ps = GSC::PageSpeed.new('https://example.com/subpage')

    sample_api_response = {
      'lighthouseResult' => {
        'categories' => {
          'performance' => { 'score' => 0.88 },
          'seo' => { 'score' => 0.90 }
        },
        'audits' => {}
      },
      'loadingExperience' => {
        'initial_url' => 'https://example.com/subpage'
        # No metrics array at URL level (low traffic subpage)
      },
      'originLoadingExperience' => {
        'overall_category' => 'AVERAGE',
        'metrics' => {
          'LARGEST_CONTENTFUL_PAINT_MS' => { 'percentile' => 2600, 'category' => 'AVERAGE' }
        }
      }
    }

    data = ps.send(:parse_response, sample_api_response)

    assert_equal :origin, data[:field_source]
    assert_equal 'AVERAGE', data[:overall_category]
    assert_equal 2600, data[:field_data]['LARGEST_CONTENTFUL_PAINT_MS'][:percentile]
  end

  def test_parse_response_with_insufficient_crux_traffic
    ps = GSC::PageSpeed.new('https://new-brand-site.com')

    sample_api_response = {
      'lighthouseResult' => {
        'categories' => {
          'performance' => { 'score' => 0.98 },
          'seo' => { 'score' => 1.0 }
        },
        'audits' => {}
      },
      'loadingExperience' => {},
      'originLoadingExperience' => {}
    }

    data = ps.send(:parse_response, sample_api_response)

    assert_nil data[:field_source]
    assert_nil data[:overall_category]
    assert_empty data[:field_data]
  end
end

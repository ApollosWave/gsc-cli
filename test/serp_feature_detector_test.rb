# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class SerpFeatureDetectorTest < Minitest::Test
  def test_intent_classification
    d_info = GSC::SerpFeatureDetector.new('what is technical seo')
    assert_equal 'Informational', d_info.send(:classify_intent, 'what is technical seo')[:primary]

    d_comm = GSC::SerpFeatureDetector.new('best seo audit tools for developers')
    assert_equal 'Commercial', d_comm.send(:classify_intent, 'best seo audit tools for developers')[:primary]

    d_trans = GSC::SerpFeatureDetector.new('buy seo software license')
    assert_equal 'Transactional', d_trans.send(:classify_intent, 'buy seo software license')[:primary]

    d_local = GSC::SerpFeatureDetector.new('seo agency near me')
    assert_equal 'Local', d_local.send(:classify_intent, 'seo agency near me')[:primary]

    d_nav = GSC::SerpFeatureDetector.new('exampleapp login')
    assert_equal 'Navigational', d_nav.send(:classify_intent, 'exampleapp login')[:primary]
  end

  def test_ai_overview_detection
    d = GSC::SerpFeatureDetector.new('how to fix website cls font loading')
    intent = { primary: 'Informational', secondary: 'Research' }
    aio = d.send(:detect_ai_overview, 'how to fix website cls font loading', intent)

    assert aio[:detected]
    assert aio[:probability_pct] >= 75
    assert_equal 850, aio[:displacement_pixels]
    assert_includes aio[:impact], 'displaces'
  end

  def test_featured_snippet_formatting_recipes
    d = GSC::SerpFeatureDetector.new('test')

    # Paragraph recipe
    fs_p = d.send(:detect_featured_snippet, 'what is technical seo', { primary: 'Informational' })
    assert_equal 'paragraph', fs_p[:target_format]
    assert_includes fs_p[:capture_prescription], '42–55 word'

    # Ordered list recipe
    fs_l = d.send(:detect_featured_snippet, 'how to setup canonical tags', { primary: 'Informational' })
    assert_equal 'ordered_list', fs_l[:target_format]
    assert_includes fs_l[:capture_prescription], '<ol><li>'

    # Table recipe
    fs_t = d.send(:detect_featured_snippet, 'server side rendering vs static site generation', { primary: 'Commercial' })
    assert_equal 'table', fs_t[:target_format]
    assert_includes fs_t[:capture_prescription], '<table>'

    # Unordered list recipe
    fs_u = d.send(:detect_featured_snippet, 'best seo audit tools', { primary: 'Commercial' })
    assert_equal 'unordered_list', fs_u[:target_format]
    assert_includes fs_u[:capture_prescription], '<ul><li>'
  end

  def test_local_pack_detection
    d = GSC::SerpFeatureDetector.new('test')
    assert d.send(:detect_local_pack, 'web development agency in new york')[:detected]
    refute d.send(:detect_local_pack, 'what is technical seo')[:detected]
  end

  def test_zero_click_risk_calculation
    d = GSC::SerpFeatureDetector.new('test')
    risk = d.send(
      :calculate_zero_click_risk,
      ai_overview: { detected: true },
      featured_snippet: { detected: true },
      paa_count: 5,
      local_pack: { detected: false },
      shopping_pack: { detected: false },
      video_carousel: { detected: true }
    )

    assert risk[:score] >= 75
    assert_includes %w[HIGH SEVERE], risk[:level]
    assert_includes risk[:estimated_organic_ctr_suppression], '-'
  end

  def test_full_detection_structure
    d = GSC::SerpFeatureDetector.new('what is technical seo')
    # stub live web calls to ensure deterministic unit tests
    d.define_singleton_method(:extract_live_paa_questions) do |_q|
      ['how to check technical seo', 'what is technical seo checklist']
    end
    d.define_singleton_method(:sample_live_serp) do |_q|
      [{ position: 1, title: 'ExampleApp SEO', url: 'https://example.com', domain: 'example.com', snippet: 'Best SEO audit tool' }]
    end

    result = d.detect
    assert_equal 'what is technical seo', result[:query]
    assert_equal 'Informational', result[:intent][:primary]
    assert result[:features][:ai_overview][:detected]
    assert result[:features][:featured_snippet][:detected]
    assert result[:features][:people_also_ask][:detected]
    assert_equal 2, result[:features][:people_also_ask][:count]
    assert_equal 1, result[:serp_sampling].size
    assert result[:playbook].any?
  end
end

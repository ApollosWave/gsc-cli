# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class StrikingPlaybookTest < Minitest::Test
  class MockApi
    attr_accessor :rows

    def initialize(rows)
      @rows = rows
    end

    def query_analytics(_site, _options = {})
      {
        ok: true,
        data: { 'rows' => @rows }
      }
    end
  end

  class EmptyApi
    def query_analytics(_site, _options = {})
      { ok: false, data: 'Forbidden' }
    end
  end

  def test_generates_tactical_playbooks_for_striking_distance
    mock_rows = [
      { 'keys' => ['technical seo checklist', 'https://exampleseo.com/features/seo-checklist'], 'position' => 8.2, 'impressions' => 1200, 'clicks' => 30 },
      { 'keys' => ['schema markup generator', 'https://exampleseo.com/features/schema-generator'], 'position' => 12.5, 'impressions' => 800, 'clicks' => 10 },
      { 'keys' => ['core web vitals audit', 'https://exampleseo.com/features/cwv-audit'], 'position' => 17.1, 'impressions' => 500, 'clicks' => 2 },
      { 'keys' => ['exampleseo', 'https://exampleseo.com/'], 'position' => 1.2, 'impressions' => 2000, 'clicks' => 500 },
      { 'keys' => ['random query', 'https://exampleseo.com/'], 'position' => 35.0, 'impressions' => 100, 'clicks' => 0 }
    ]

    api = MockApi.new(mock_rows)
    result = GSC::StrikingPlaybook.generate(api, 'sc-domain:exampleseo.com', limit: 3)

    assert_equal 3, result[:playbooks].size
    assert result[:projected_monthly_clicks] > 100

    p1 = result[:playbooks].first
    assert_equal 'technical seo checklist', p1[:query]
    assert_equal :tier_1_expedite, p1[:tier]
    assert_equal 8.2, p1[:position]
    assert p1[:projected_gain] > 50

    # Title Rewrites
    assert_equal 3, p1[:title_rewrites].size
    p1[:title_rewrites].each do |title|
      assert title.length <= 60, "Title exceeds 60 chars: #{title}"
    end

    # Heading Recipes
    assert_match(/Why Technical Seo Checklist Is Essential/i, p1[:heading_recipes][:h2])
    assert_equal 2, p1[:heading_recipes][:h3s].size

    # Internal Link Anchors
    assert_equal 'technical seo checklist', p1[:internal_link_anchors][:exact]
    assert_includes p1[:internal_link_anchors][:branded], 'Exampleseo'

    # FAQ Snippet
    assert_match(/Technical Seo Checklist/i, p1[:faq_snippet][:question])
    assert p1[:faq_snippet][:answer].length > 40

    # Action Checklist
    assert_equal 6, p1[:action_checklist].size
  end

  def test_handles_empty_or_failed_api_gracefully
    result = GSC::StrikingPlaybook.generate(EmptyApi.new, 'sc-domain:example.com')
    assert_empty result[:playbooks]
    assert_equal 0, result[:projected_monthly_clicks]
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/aio_hunter'

class AioHunterTest < Minitest::Test
  def test_single_how_to_query_analysis
    hunter = GSC::AioHunter.new("how to optimize website speed")
    res = hunter.analyze

    assert_equal :query, res[:mode]
    assert_equal "how to optimize website speed", res[:query]
    assert_equal :informational_how_to, res[:intent]
    assert_operator res[:aio_presence][:probability_percent], :>=, 70
    assert res[:aio_presence][:detected]
    assert_equal "45%", res[:aio_presence][:ctr_suppression_estimate]
    assert res[:citation_analysis].key?(:citation_gap_index)
    refute_nil res[:citation_analysis][:eligibility_status]
    assert_equal "Direct Ordered List & Steps Schema", res[:capture_recipe][:strategy]
    assert_includes res[:capture_recipe][:recommended_schema], "HowTo"
  end

  def test_single_definitional_query_analysis
    hunter = GSC::AioHunter.new("what is technical seo")
    res = hunter.analyze

    assert_equal :query, res[:mode]
    assert_equal :informational_definition, res[:intent]
    assert_operator res[:aio_presence][:probability_percent], :>=, 70
    assert_equal "Authoritative Definitional Snippet", res[:capture_recipe][:strategy]
    assert_includes res[:capture_recipe][:direct_answer_draft], "Technical seo"
  end

  def test_portfolio_mode_analysis_unauthenticated
    hunter = GSC::AioHunter.new("example.com")
    res = hunter.analyze

    assert_equal :portfolio, res[:mode]
    assert_equal "example.com", res[:domain]
    assert_equal 0, res[:total_queries_audited]
    assert_empty res[:opportunities]
  end

  def test_portfolio_mode_analysis_authenticated
    mock_api = Object.new
    def mock_api.query_search_analytics(site_url, options = {})
      {
        'rows' => [
          { 'keys' => ['how to improve website speed'], 'clicks' => 80, 'impressions' => 2500, 'ctr' => 0.032, 'position' => 6.4 }
        ]
      }
    end

    hunter = GSC::AioHunter.new("example.com", {}, mock_api, "sc-domain:example.com")
    res = hunter.analyze

    assert_equal :portfolio, res[:mode]
    assert_equal 1, res[:total_queries_audited]
    refute_empty res[:opportunities]
    assert_equal "how to improve website speed", res[:opportunities].first[:query]
    assert res[:opportunities].first.key?(:opportunity_score)
  end

  def test_low_aio_probability_for_navigational_query
    hunter = GSC::AioHunter.new("exampleapp login")
    res = hunter.analyze

    assert_equal :query, res[:mode]
    assert_equal :navigational, res[:intent]
    assert_operator res[:aio_presence][:probability_percent], :<, 45
    refute res[:aio_presence][:detected]
  end
end

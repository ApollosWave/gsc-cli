# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/intent_shift'

class IntentShiftTest < Minitest::Test
  def setup
    @domain = 'shoepalace.com'
  end

  def test_classify_query_intents
    assert_equal :transactional, GSC::IntentShift.classify_query('buy running shoes online discount')
    assert_equal :commercial, GSC::IntentShift.classify_query('best marathon sneakers vs ultra boost review')
    assert_equal :informational, GSC::IntentShift.classify_query('how to break in new running shoes tutorial')
    assert_equal :navigational, GSC::IntentShift.classify_query('shoepalace portal account login', 'shoepalace')
    assert_equal :navigational, GSC::IntentShift.classify_query('customer support dashboard login')
  end

  def test_classify_page_intents
    assert_equal :transactional, GSC::IntentShift.classify_page('https://shoepalace.com/checkout')
    assert_equal :transactional, GSC::IntentShift.classify_page('https://shoepalace.com/products/vaporfly')
    assert_equal :informational, GSC::IntentShift.classify_page('https://shoepalace.com/blog/how-to-tie-laces')
    assert_equal :commercial, GSC::IntentShift.classify_page('https://shoepalace.com/reviews/nike-vs-adidas')
    assert_equal :navigational, GSC::IntentShift.classify_page('https://shoepalace.com/account/login')
    assert_equal :hybrid, GSC::IntentShift.classify_page('https://shoepalace.com/about-us')
  end

  def test_intent_shift_analysis_unauthenticated
    res = GSC::IntentShift.analyze({}, nil, @domain)

    assert_equal 'shoepalace.com', res[:domain]
    assert_equal 0, res[:total_queries_analyzed]
    assert_equal 0.0, res[:portfolio_volatility_pct]
    assert_equal 'N/A', res[:risk_grade]
    assert_empty res[:shifts]
    assert_empty res[:prescriptions]
  end

  def test_intent_shift_analysis_authenticated
    mock_api = Object.new
    def mock_api.search_analytics(domain, options = {})
      {
        'rows' => [
          { 'keys' => ['how to fix heel blisters', 'https://shoepalace.com/checkout'], 'clicks' => 50, 'impressions' => 2000, 'ctr' => 0.025, 'position' => 14.2 },
          { 'keys' => ['buy trail running shoes sale', 'https://shoepalace.com/blog/trail-gear'], 'clicks' => 200, 'impressions' => 3000, 'ctr' => 0.066, 'position' => 4.1 },
          { 'keys' => ['shoepalace login account', 'https://shoepalace.com/login'], 'clicks' => 500, 'impressions' => 600, 'ctr' => 0.833, 'position' => 1.0 }
        ]
      }
    end

    res = GSC::IntentShift.analyze({}, mock_api, @domain)

    assert_equal 'shoepalace.com', res[:domain]
    assert_equal 3, res[:total_queries_analyzed]
    refute_nil res[:portfolio_volatility_pct]
    assert_includes ['HIGH RISK', 'MODERATE', 'OPTIMAL'], res[:risk_grade]

    # Intent distribution
    dist = res[:intent_distribution]
    assert dist[:informational] >= 0
    assert dist[:transactional] >= 0
    assert dist[:commercial] >= 0
    assert dist[:navigational] >= 0

    # Shifts array
    refute_empty res[:shifts]
    mismatched = res[:shifts].select { |s| s[:has_mismatch] }
    assert mismatched.size > 0

    # Prescriptions
    refute_empty res[:prescriptions]
  end

  def test_specific_mismatch_scenarios
    # Scenario: Informational query landing on a transactional checkout page
    analyzer = GSC::IntentShift.new({}, nil, @domain)
    custom_rows = [
      { query: 'how to fix heel blisters', page: 'https://shoepalace.com/checkout', clicks: 50, impressions: 2000, ctr: 2.5, position: 14.2 },
      { query: 'buy trail running shoes sale', page: 'https://shoepalace.com/blog/trail-gear', clicks: 200, impressions: 3000, ctr: 6.6, position: 4.1 },
      { query: 'shoepalace login account', page: 'https://shoepalace.com/login', clicks: 500, impressions: 600, ctr: 83.3, position: 1.0 }
    ]

    shifts = analyzer.send(:detect_intent_shifts, custom_rows)
    summary = analyzer.send(:summarize_portfolio, shifts)

    assert_equal 3, summary[:total_queries_analyzed]
    assert_equal 2, summary[:mismatched_queries_count] # 1st and 2nd are mismatched
    assert_equal 66.7, summary[:portfolio_volatility_pct]
    assert_equal 'HIGH RISK', summary[:risk_grade]

    # Inspect the high-buying-intent mismatch
    buy_shift = shifts.find { |s| s[:query].include?('buy') }
    assert buy_shift[:has_mismatch]
    assert_includes buy_shift[:diagnosis], 'HIGH BUYING INTENT'
    assert_includes buy_shift[:prescription], 'checkout widgets'
  end
end

# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class QuestionsHarvesterTest < Minitest::Test
  def test_harvests_question_queries_and_classifies
    sample_rows = [
      {
        'keys' => ['how to inspect urls with search console', 'https://example.com/install'],
        'clicks' => 12,
        'impressions' => 140,
        'ctr' => 0.085,
        'position' => 4.2
      },
      {
        'keys' => ['can i index pages automatically with api', 'https://example.com/protection'],
        'clicks' => 3,
        'impressions' => 45,
        'ctr' => 0.066,
        'position' => 2.1
      },
      {
        'keys' => ['are amp pages still relevant in 2026', 'https://example.com/blog/amp'],
        'clicks' => 1,
        'impressions' => 20,
        'ctr' => 0.05,
        'position' => 14.5
      },
      {
        'keys' => ['regular brand keyword', 'https://example.com/'],
        'clicks' => 50,
        'impressions' => 500,
        'ctr' => 0.10,
        'position' => 1.0
      }
    ]

    res = GSC::QuestionsHarvester.harvest(sample_rows, min_imp: 5)

    assert_equal 3, res[:total_questions_harvested]
    assert_equal 2, res[:high_opportunity_count] # pos 4.2 and pos 14.5
    assert_equal 1, res[:defense_count]          # pos 2.1
    assert_equal 3, res[:pages_covered]

    first_q = res[:questions].first
    assert_equal 'HOW', first_q[:type]
    assert_equal 'How to inspect urls with search console?', first_q[:question]
    assert_equal 'HIGH_OPPORTUNITY', first_q[:tier]
    assert first_q[:opportunity_score] > 100
  end

  def test_filters_by_page
    sample_rows = [
      { 'keys' => ['how to setup analytics', 'https://example.com/analytics'], 'impressions' => 20, 'clicks' => 2, 'position' => 5.0 },
      { 'keys' => ['how to setup checkout', 'https://example.com/checkout'], 'impressions' => 30, 'clicks' => 3, 'position' => 6.0 }
    ]

    res = GSC::QuestionsHarvester.harvest(sample_rows, filter_page: 'checkout')
    assert_equal 1, res[:total_questions_harvested]
    assert_equal 'https://example.com/checkout', res[:questions].first[:page]
  end

  def test_generates_valid_schema_org_faq_page
    sample_rows = [
      { 'keys' => ['how does canonical url indexing work', 'https://example.com/canonical'], 'impressions' => 25, 'clicks' => 2, 'position' => 4.0 }
    ]

    res = GSC::QuestionsHarvester.harvest(sample_rows)
    schema = res[:recommended_faq_schemas]['https://example.com/canonical']

    assert schema
    assert_equal 'https://schema.org', schema['@context']
    assert_equal 'FAQPage', schema['@type']
    assert_equal 1, schema['mainEntity'].size
    assert_equal 'Question', schema['mainEntity'][0]['@type']
    assert_equal 'How does canonical url indexing work?', schema['mainEntity'][0]['name']
    assert_equal 'Answer', schema['mainEntity'][0]['acceptedAnswer']['@type']
  end
end

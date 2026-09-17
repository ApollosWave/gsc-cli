# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/cannibalization_analyzer'

class CannibalizationAnalyzerTest < Minitest::Test
  def test_detects_cannibalization_and_assigns_severity
    rows = [
      { 'keys' => ['technical seo audit', 'https://example.com/app'], 'clicks' => 10, 'impressions' => 60, 'position' => 3.2 },
      { 'keys' => ['technical seo audit', 'https://example.com/blog/seo-audit'], 'clicks' => 2, 'impressions' => 40, 'position' => 4.5 },
      { 'keys' => ['unique search term', 'https://example.com/page-unique'], 'clicks' => 5, 'impressions' => 100, 'position' => 1.0 }
    ]

    analysis = GSC::CannibalizationAnalyzer.analyze(rows, min_imp: 10)

    assert_equal 2, analysis[:total_queries_evaluated]
    assert_equal 1, analysis[:conflicts_count]
    assert_equal 1, analysis[:critical_count] # Both rank pos <= 20 and secondary has 40% share
    assert_equal 40, analysis[:total_diluted_impressions]

    conflict = analysis[:conflicts].first
    assert_equal 'technical seo audit', conflict[:query]
    assert_equal 'CRITICAL', conflict[:severity]
    assert_equal 2, conflict[:pages].size
    assert_equal 60.0, conflict[:pages][0][:impression_share]
    assert_equal 40.0, conflict[:pages][1][:impression_share]
  end

  def test_flip_flop_hazard_remedy
    # Secondary page ranks better (Pos 2.0) than primary page with most impressions (Pos 8.0)
    rows = [
      { 'keys' => ['test query', 'https://example.com/page-a'], 'clicks' => 1, 'impressions' => 100, 'position' => 8.0 },
      { 'keys' => ['test query', 'https://example.com/page-b'], 'clicks' => 5, 'impressions' => 80, 'position' => 2.0 }
    ]

    analysis = GSC::CannibalizationAnalyzer.analyze(rows, min_imp: 10)
    conflict = analysis[:conflicts].first
    assert_equal 'FLIP_FLOP_CONSOLIDATION', conflict[:remedy][:action]
  end

  def test_duplicate_slug_similarity_remedy
    rows = [
      { 'keys' => ['schema markup generator', 'https://example.com/features/schema-markup-jsonld-generator'], 'clicks' => 0, 'impressions' => 50, 'position' => 12.0 },
      { 'keys' => ['schema markup generator', 'https://example.com/features/jsonld-generator-schema-markup'], 'clicks' => 0, 'impressions' => 30, 'position' => 13.0 }
    ]

    analysis = GSC::CannibalizationAnalyzer.analyze(rows, min_imp: 10)
    conflict = analysis[:conflicts].first
    assert_equal '301_REDIRECT', conflict[:remedy][:action]
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/citation_simulator'

class CitationSimulatorTest < Minitest::Test
  def setup
    @html_sample = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>FastBoost: High Speed Web Engine - 45% Faster</title>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "FastBoost"
        }
        </script>
      </head>
      <body>
        <header><nav><a href="/">Home</a></nav></header>
        <main>
          <h1>How FastBoost Accelerates Website Speeds</h1>
          <div class="byline">Written by Dr. Jane Doe, Senior Systems Architect (Published 2026-03-15)</div>
          <p>FastBoost reduces mobile website abandonment by 45% by decreasing server response latency from 1,200ms to 180ms across all production websites.</p>
          <h2>Key Benchmark Comparisons</h2>
          <table>
            <tr><th>Metric</th><th>FastBoost</th><th>Standard</th></tr>
            <tr><td>LCP Latency</td><td>180ms</td><td>1,200ms</td></tr>
            <tr><td>Conversion Lift</td><td>+18.4%</td><td>Baseline</td></tr>
          </table>
          <p>In extensive benchmark testing, website completion improved by $12,500 in monthly revenue per 10,000 visitors.</p>
        </main>
        <footer><p>© 2026 FastBoost Inc.</p></footer>
      </body>
      </html>
    HTML
  end

  def test_simulate_with_explicit_query
    result = GSC::CitationSimulator.simulate(@html_sample, 'how does fastboost accelerate website speeds', model: 'perplexity')

    assert_equal 'perplexity', result[:model_profile]
    assert_equal 'how does fastboost accelerate website speeds', result[:target_query]
    assert result[:citation_likelihood_score] >= 70, "Should have high CLS score with rich data"
    assert_includes %w[A+ A B], result[:grade]
    assert_equal 'HIGH CITABILITY', result[:status]

    # Quotes
    assert result[:extracted_quotes].any?
    first_quote = result[:extracted_quotes].first
    assert first_quote.include?('FastBoost reduces mobile website') || first_quote.include?('45%')

    # Top cited chunk
    top_c = result[:top_cited_chunk]
    assert top_c[:facts_count] >= 2

    # Signals
    sig = result[:signals]
    assert_equal true, sig[:has_schema]
    assert_equal true, sig[:has_author]
    assert_equal true, sig[:has_published_date]
    assert_equal true, sig[:has_comparative_table]
  end

  def test_model_profiles_response_synthesis
    models = %w[perplexity chatgpt claude aio]
    models.each do |mod|
      res = GSC::CitationSimulator.simulate(@html_sample, 'website speed metrics', model: mod)
      assert_equal mod, res[:model_profile]
      assert res[:emulated_ai_response].is_a?(String)
      assert res[:emulated_ai_response].length > 20
    end
  end

  def test_auto_infer_query_when_empty
    result = GSC::CitationSimulator.simulate(@html_sample)
    assert_equal 'How FastBoost Accelerates Website Speeds', result[:target_query]
  end

  def test_thin_content_generates_low_score_and_prescriptions
    thin_html = '<html><body><p>We are a company that does things in today digital world.</p></body></html>'
    result = GSC::CitationSimulator.simulate(thin_html, 'company features')

    assert result[:citation_likelihood_score] < 50
    assert_includes %w[D F], result[:grade]
    assert result[:prescriptions].any?
    assert result[:prescriptions].any? { |p| p.include?('numerical metrics') || p.include?('Schema.org') }
  end
end

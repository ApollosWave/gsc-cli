# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class GeoAuditorTest < Minitest::Test
  def setup
    @auditor = GSC::GeoAuditor.new('https://example.com/guide')
  end

  def test_initialization_normalizes_url
    aud = GSC::GeoAuditor.new('example.com/test')
    assert_equal 'https://example.com/test', aud.url
  end

  def test_direct_answer_detection
    sample_html = <<~HTML
      <html>
        <body>
          <h2>What is Technical SEO for Modern Web Apps?</h2>
          <p>
            Technical SEO is the practice of optimizing website and server architecture to help search engine spiders crawl, interpret, and index every page efficiently, boosting organic visibility, Core Web Vitals performance, and search ranking outcomes across Google.
          </p>
          <h3>How to install ExampleApp?</h3>
          <p>ExampleApp installs in 1-click via the app store without modifying theme code.</p>
        </body>
      </html>
    HTML

    @auditor.instance_variable_set(:@html, sample_html)
    res = @auditor.send(:audit_direct_answers)

    assert_equal 2, res[:total_question_headings]
    assert_equal 2, res[:direct_answer_blocks_found]
    assert_equal 1, res[:optimal_answers_count] # First answer is 38 words (optimal: 30-80 words)
  end

  def test_factual_citability_detection
    sample_html = <<~HTML
      <html>
        <body>
          <p>In 2026, web apps generated $15,000 in additional organic value with a 18.5% boost in search visibility.</p>
          <ul>
            <li>Instant Core Web Vitals optimization</li>
            <li>Automated structured data validation</li>
            <li>Real-time search console indexing</li>
            <li>Dynamic metadata recommendations</li>
          </ul>
        </body>
      </html>
    HTML

    @auditor.instance_variable_set(:@html, sample_html)
    res = @auditor.send(:audit_factual_citability)

    assert_equal 1, res[:percentage_mentions]
    assert_equal 1, res[:currency_mentions]
    assert_equal 1, res[:recent_year_mentions]
    assert_equal 4, res[:bullet_list_items]
  end

  def test_entity_schema_detection
    sample_html = <<~HTML
      <html>
        <head>
          <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Organization",
            "name": "ExampleApp",
            "url": "https://example.com",
            "sameAs": [
              "https://www.wikidata.org/wiki/Q12345",
              "https://www.linkedin.com/company/exampleapp"
            ]
          }
          </script>
          <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "FAQPage",
            "mainEntity": []
          }
          </script>
        </head>
      </html>
    HTML

    @auditor.instance_variable_set(:@html, sample_html)
    res = @auditor.send(:audit_entity_schema)

    assert_equal 2, res[:schema_count]
    assert res[:has_organization_or_brand]
    assert res[:has_faq_or_howto]
    assert res[:wikidata_or_wikipedia_linked]
    assert res[:social_entity_linked]
  end

  def test_score_grade_mapping
    assert_includes @auditor.send(:score_grade, 95), 'Exceptional'
    assert_includes @auditor.send(:score_grade, 75), 'Good'
    assert_includes @auditor.send(:score_grade, 55), 'Moderate'
    assert_includes @auditor.send(:score_grade, 35), 'Poor'
  end
end

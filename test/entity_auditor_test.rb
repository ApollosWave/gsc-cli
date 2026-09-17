# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class EntityAuditorTest < Minitest::Test
  def test_extract_json_ld_single_and_array
    html = <<~HTML
      <html>
        <head>
          <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Organization",
              "name": "ExampleApp",
              "url": "https://example.com",
              "logo": "https://example.com/logo.png",
              "description": "High-converting search and performance tool.",
              "sameAs": [
                "https://www.wikidata.org/wiki/Q123456",
                "https://www.linkedin.com/company/exampleapp",
                "https://twitter.com/exampleapp"
              ],
              "knowsAbout": ["SEO Tools", "Conversion", "Search Intelligence"]
            }
          </script>
        </head>
        <body>
          <h1>Welcome to ExampleApp</h1>
        </body>
      </html>
    HTML

    res = GSC::EntityAuditor.audit('https://example.com', custom_html: html)

    assert_equal 1, res[:entities_found]
    assert res[:score] >= 80, "Expected score >= 80, got #{res[:score]}"
    assert_equal 'A', res[:grade]
    assert_equal 'https://www.wikidata.org/wiki/Q123456', res[:authoritative_links][:wikidata]
    assert_equal 'https://www.linkedin.com/company/exampleapp', res[:authoritative_links][:linkedin]
    assert_includes res[:findings].join, 'ExampleApp'
  end

  def test_audit_missing_entities_scores_zero_and_recommends
    html = '<html><head><title>No Schema Page</title></head><body>Hello</body></html>'
    res = GSC::EntityAuditor.audit('https://empty.example.com', custom_html: html)

    assert_equal 0, res[:entities_found]
    assert_equal 0, res[:score]
    assert_equal 'F', res[:grade]
    assert res[:recommendations].any? { |r| r.include?('Organization or Brand') }
    assert res[:recommended_json_ld].is_a?(Hash)
    assert_equal 'Organization', res[:recommended_json_ld]['@type']
  end

  def test_generate_template
    tmpl = GSC::EntityAuditor.generate_template('https://examplespeed.com/features')
    assert_equal 'https://schema.org', tmpl['@context']
    assert_equal 'Organization', tmpl['@type']
    assert_equal 'Examplespeed', tmpl['name']
    assert_equal 'https://examplespeed.com', tmpl['url']
    assert_equal 4, tmpl['sameAs'].size
  end
end

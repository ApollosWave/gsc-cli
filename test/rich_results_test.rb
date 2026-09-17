# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/rich_results'

class RichResultsTest < Minitest::Test
  def setup
    @auditor = GSC::RichResults.new
  end

  def test_extract_schemas_from_html
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Acoustic Cramp Relief Device",
          "image": ["https://example.com/device.jpg"],
          "offers": {
            "@type": "Offer",
            "price": "149.00",
            "priceCurrency": "USD",
            "availability": "https://schema.org/InStock",
            "priceValidUntil": "2026-12-31"
          }
        }
        </script>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "FAQPage",
          "mainEntity": [
            {
              "@type": "Question",
              "name": "How fast does it work?",
              "acceptedAnswer": {
                "@type": "Answer",
                "text": "Relief begins in 15-20 minutes."
              }
            }
          ]
        }
        </script>
      </head>
      <body><h1>Product Page</h1></body>
      </html>
    HTML

    res = @auditor.audit(html)

    assert_equal 2, res[:total_schemas_detected]
    assert res[:eligible_for_rich_results]
    assert_includes res[:eligible_features], 'Merchant Product Rich Card'
    assert_includes res[:eligible_features], 'Interactive FAQ Accordion'
    assert_equal 0, res[:critical_errors_count]
    assert_equal 'A+', res[:grade]
  end

  def test_disqualified_product_missing_offers_and_image
    broken_product_json = <<~JSON
      {
        "@context": "https://schema.org",
        "@type": "Product",
        "name": "Unpriced Prototype"
      }
    JSON

    res = @auditor.audit(broken_product_json)

    assert_equal 1, res[:total_schemas_detected]
    refute res[:eligible_for_rich_results]
    schema = res[:schemas].first
    refute schema[:eligible]
    assert schema[:errors].any? { |e| e.include?('Missing "image"') }
    assert schema[:errors].any? { |e| e.include?('Must provide at least one of "offers"') }

    # Verify auto-patch fix was generated
    refute_nil schema[:patch]
    assert schema[:patch]['offers']
    assert_equal '49.99', schema[:patch]['offers']['price']
    assert schema[:patch]['image']
  end

  def test_article_validation_and_author_url_warning
    article_html = <<~HTML
      <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Article",
        "headline": "Understanding Menstrual Pain Neurobiology",
        "image": "https://example.com/banner.jpg",
        "datePublished": "2026-03-01T08:00:00Z",
        "author": {
          "@type": "Person",
          "name": "Dr. Sarah Jenkins, MD"
        }
      }
      </script>
    HTML

    res = @auditor.audit(article_html)

    assert_equal 1, res[:total_schemas_detected]
    schema = res[:schemas].first
    assert schema[:eligible]
    assert_equal 0, schema[:errors].size
    # Warning for missing author profile URL (E-E-A-T)
    assert schema[:warnings].any? { |w| w.include?('Author missing "url"') }
  end

  def test_corrupted_json_handling
    bad_html = <<~HTML
      <script type="application/ld+json">
        { "name": "Broken JSON", invalid: syntax }
      </script>
    HTML

    res = @auditor.audit(bad_html)

    assert_equal 1, res[:total_schemas_detected]
    schema = res[:schemas].first
    refute schema[:eligible]
    assert_equal 'SyntaxError', schema[:type]
    assert schema[:errors].first.include?('JSON Syntax Error')
  end
end

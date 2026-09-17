# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class PageAnalyzerTest < Minitest::Test
  SAMPLE_HTML = <<~HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <title>Best SEO Analytics &amp; Audit Platforms | ExampleApp</title>
      <meta name="description" content="Discover smart SEO tools with Google Search Console tracking. Inspect URLs and audit rankings fast.">
      <link rel="canonical" href="https://example.com/tools">
      <meta name="robots" content="index, follow">
      <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Product",
        "name": "Smart SEO Analytics Engine",
        "offers": {
          "@type": "Offer",
          "price": "0.00"
        }
      }
      </script>
    </head>
    <body>
      <h1>Smart SEO Platform</h1>
      <h2>Why SEO Audits Work</h2>
      <p>Search made simple.</p>
      <h2>Tool Modules</h2>
      <h3>Audit Suite</h3>
      <img src="/images/tool1.jpg" alt="Small tool preview">
      <img src="/images/tool2.jpg">
      <a href="/pricing">Pricing</a>
      <a href="https://google.com" rel="nofollow">External Link</a>
    </body>
    </html>
  HTML

  def test_page_analyzer_parses_dom
    analyzer = GSC::PageAnalyzer.new("https://example.com/tools", html: SAMPLE_HTML)
    data = analyzer.fetch_and_analyze

    # Title & Meta
    assert_equal "Best SEO Analytics & Audit Platforms | ExampleApp", data[:title][:text]
    assert_equal 49, data[:title][:length]
    assert data[:title][:pixel_est] > 300
    assert data[:title][:ok]

    assert_includes data[:meta_description][:text], "Discover smart SEO tools"
    assert_equal 99, data[:meta_description][:length]
    assert data[:meta_description][:ok]

    # Canonical
    assert_equal "https://example.com/tools", data[:canonical][:url]
    assert data[:canonical][:self_referencing]

    # Indexability
    assert_equal "INDEXABLE", data[:indexability][:status]

    # Headings
    assert_equal 4, data[:headings][:count]
    assert_equal 1, data[:headings][:h1_count]
    assert_equal "Smart SEO Platform", data[:headings][:list].first[:text]

    # Images
    assert_equal 2, data[:images][:total]
    assert_equal 1, data[:images][:missing_alt_count]
    assert_equal "/images/tool2.jpg", data[:images][:missing_alt_images].first[:src]

    # Links
    assert_equal 2, data[:links][:total]
    assert_equal 1, data[:links][:internal_count]
    assert_equal 1, data[:links][:external_count]
    assert_equal 1, data[:links][:nofollow_count]

    # Schema
    assert_equal 1, data[:schema].size
    assert data[:schema].first[:valid]
    assert_includes data[:schema].first[:types], "Product"
    assert_includes data[:schema].first[:types], "Offer"
  end

  def test_flags_missing_h1_and_long_title
    bad_html = <<~HTML
      <html>
      <head>
        <title>This is a ridiculously long title that exceeds the recommended 60 character limit and will be truncated by Google in search results</title>
      </head>
      <body>
        <h2>No H1 here</h2>
      </body>
      </html>
    HTML

    analyzer = GSC::PageAnalyzer.new("https://example.com/bad", html: bad_html)
    data = analyzer.fetch_and_analyze

    assert_equal 0, data[:headings][:h1_count]
    refute data[:title][:ok]

    issues = data[:issues].map { |i| i[:message] }
    assert issues.any? { |m| m =~ /Missing <h1>/ }
    assert issues.any? { |m| m =~ /Title too long/ }
    assert issues.any? { |m| m =~ /Missing meta description/ }
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/image_seo'

class ImageSeoTest < Minitest::Test
  def setup
    @html_sample = <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Test Store</title></head>
      <body>
        <!-- Hero image with issues (legacy jpg, lazy loaded on hero, missing width/height) -->
        <img src="/images/hero-banner.jpg" alt="Summer Collection Promo" loading="lazy">

        <!-- Good modern image -->
        <picture>
          <img src="https://cdn.example.com/products/shoe.webp" alt="Running Shoes in Red" width="600" height="400" loading="lazy" decoding="async">
        </picture>

        <!-- Image missing alt & dimensions -->
        <img src="/assets/logo.png">

        <!-- Decorative image -->
        <img src="/assets/divider.svg" alt="" role="presentation" width="100" height="2">

        <!-- AVIF image with empty alt but not decorative -->
        <img src="https://example.com/icon.avif" alt="" width="32" height="32" loading="lazy">
      </body>
      </html>
    HTML
  end

  def test_extract_and_audit_images
    res = GSC::ImageSeo.audit(@html_sample)

    assert_equal 5, res[:total_images]
    assert res[:health_score] < 100.0, "Health score should reflect issues"
    assert_includes %w[A+ A B C D F], res[:grade]

    images = res[:images]
    assert_equal 5, images.size

    # Check Hero Image
    hero = images.first
    assert hero[:is_hero]
    assert_equal 'jpg', hero[:format]
    assert_includes hero[:issues], :legacy_format
    assert_includes hero[:issues], :missing_dimensions
    assert_includes hero[:issues], :lcp_lazy_loaded
    assert_includes hero[:issues], :hero_missing_priority

    # Check Modern WebP Image
    webp_img = images[1]
    refute webp_img[:is_hero]
    assert_equal 'webp', webp_img[:format]
    assert_equal 600, webp_img[:width]
    assert_equal 400, webp_img[:height]
    assert_equal 'Running Shoes in Red', webp_img[:alt]
    assert_empty webp_img[:issues]

    # Check Missing Alt & Dimensions Image
    logo_img = images[2]
    assert_includes logo_img[:issues], :missing_alt
    assert_includes logo_img[:issues], :missing_dimensions
    assert_includes logo_img[:issues], :legacy_format

    # Check Decorative Image
    decorative = images[3]
    assert decorative[:is_decorative]
    refute_includes decorative[:issues], :missing_alt
    refute_includes decorative[:issues], :empty_alt

    # Check Empty Alt Non-Decorative Image
    empty_alt_img = images[4]
    refute empty_alt_img[:is_decorative]
    assert_includes empty_alt_img[:issues], :empty_alt
  end

  def test_metrics_calculation
    res = GSC::ImageSeo.audit(@html_sample)
    m = res[:metrics]

    assert m[:alt_coverage_pct] >= 0.0 && m[:alt_coverage_pct] <= 100.0
    assert m[:dimension_coverage_pct] >= 0.0 && m[:dimension_coverage_pct] <= 100.0
    assert m[:modern_format_pct] >= 0.0 && m[:modern_format_pct] <= 100.0
    assert m[:lazy_loading_pct] >= 0.0 && m[:lazy_loading_pct] <= 100.0

    summary = res[:issues_summary]
    assert summary[:missing_alt] >= 1
    assert summary[:missing_dimensions] >= 1
    assert summary[:legacy_format] >= 2
    assert summary[:lcp_lazy_loaded] >= 1
  end

  def test_snippet_generation
    res = GSC::ImageSeo.audit(@html_sample)
    hero = res[:images].first

    picture_snippet = hero[:picture_tag_snippet]
    assert_includes picture_snippet, '<picture>'
    assert_includes picture_snippet, '<source srcset='
    assert_includes picture_snippet, 'fetchpriority="high"'

    nextjs_snippet = hero[:nextjs_snippet]
    assert_includes nextjs_snippet, '<Image'
    assert_includes nextjs_snippet, 'priority'
  end

  def test_empty_html_returns_perfect_score
    res = GSC::ImageSeo.audit("<html><body><p>No images here</p></body></html>")

    assert_equal 0, res[:total_images]
    assert_equal 100.0, res[:health_score]
    assert_equal 'A+', res[:grade]
    assert_empty res[:images]
  end

  def test_prescriptions_generated
    res = GSC::ImageSeo.audit(@html_sample)

    refute_empty res[:prescriptions]
    assert res[:prescriptions].any? { |p| p.include?('alt attribute') }
    assert res[:prescriptions].any? { |p| p.include?('width and height') }
    assert res[:prescriptions].any? { |p| p.include?('WebP or AVIF') }
    assert res[:prescriptions].any? { |p| p.include?('Largest Contentful Paint') }
  end
end

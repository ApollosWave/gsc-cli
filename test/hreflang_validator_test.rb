# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/hreflang_validator'

class HreflangValidatorTest < Minitest::Test
  def setup
    @html_valid = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Global Store</title>
        <link rel="alternate" hreflang="en-US" href="https://example.com/" />
        <link rel="alternate" hreflang="fr-FR" href="https://example.com/fr/" />
        <link rel="alternate" hreflang="de-DE" href="https://example.com/de/" />
        <link rel="alternate" hreflang="x-default" href="https://example.com/" />
      </head>
      <body><h1>Welcome</h1></body>
      </html>
    HTML

    @html_with_mistakes = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <!-- Missing self-reference to https://example.com/ -->
        <!-- Common mistake: en-uk instead of en-GB -->
        <link rel="alternate" hreflang="en-uk" href="https://example.com/uk/" />
        <!-- Common mistake: jp instead of ja or ja-JP -->
        <link rel="alternate" hreflang="jp" href="https://example.com/jp/" />
        <!-- Invalid region: es-LA -->
        <link rel="alternate" hreflang="es-la" href="https://example.com/latam/" />
        <!-- Uppercase language -->
        <link rel="alternate" hreflang="FR-FR" href="https://example.com/fr/" />
        <!-- No x-default -->
      </head>
      <body><h1>Test</h1></body>
      </html>
    HTML
  end

  def test_valid_hreflang_audit
    res = GSC::HreflangValidator.audit(@html_valid, check_reciprocity: false)

    assert_equal 4, res[:total_tags]
    assert res[:self_reference], "Should detect self-referencing hreflang tag"
    assert res[:has_x_default], "Should detect x-default fallback tag"
    assert_equal 0, res[:invalid_code_count], "Valid codes should have 0 errors"
    assert_equal 100.0, res[:health_score]
    assert_equal 'A+', res[:grade]

    # Verify cluster snippet generation
    snippets = res[:cluster_snippets]
    assert_includes snippets[:html], 'hreflang="en-US"'
    assert_includes snippets[:html], 'hreflang="x-default"'
    assert_includes snippets[:sitemap_xml], '<xhtml:link rel="alternate" hreflang="fr-FR"'
  end

  def test_detect_common_mistakes_and_corrections
    res = GSC::HreflangValidator.audit(@html_with_mistakes, check_reciprocity: false)

    assert_equal 4, res[:total_tags]
    refute res[:self_reference], "Should flag missing self-referencing tag"
    refute res[:has_x_default], "Should flag missing x-default"
    assert res[:health_score] < 70.0, "Score should reflect multiple deductions"

    tags = res[:tags]

    # Check en-uk error
    uk_tag = tags.find { |t| t[:hreflang] == 'en-uk' }
    assert_includes uk_tag[:issues], :common_mistake
    assert_includes uk_tag[:correction], 'en-GB'

    # Check jp error
    jp_tag = tags.find { |t| t[:hreflang] == 'jp' }
    assert_includes jp_tag[:issues], :common_mistake
    assert_includes jp_tag[:correction], 'ja'

    # Check es-la error
    es_la_tag = tags.find { |t| t[:hreflang] == 'es-la' }
    assert_includes es_la_tag[:issues], :common_mistake
    assert_includes es_la_tag[:correction], 'es-419'

    # Check uppercase language code error
    fr_tag = tags.find { |t| t[:hreflang] == 'FR-FR' }
    assert_includes fr_tag[:issues], :uppercase_language
  end

  def test_script_codes_and_un_m49
    html = <<~HTML
      <html><head>
        <link rel="alternate" hreflang="zh-Hans" href="https://example.com/zh-cn/" />
        <link rel="alternate" hreflang="zh-Hant" href="https://example.com/zh-tw/" />
        <link rel="alternate" hreflang="es-419" href="https://example.com/es-419/" />
        <link rel="alternate" hreflang="en" href="https://example.com/" />
        <link rel="alternate" hreflang="x-default" href="https://example.com/" />
      </head></html>
    HTML

    res = GSC::HreflangValidator.audit(html, check_reciprocity: false)
    assert_equal 5, res[:total_tags]
    assert_equal 0, res[:invalid_code_count]
    assert_equal 100.0, res[:health_score]
  end

  def test_empty_hreflang_tags
    html = "<html><head><title>No alternate links</title></head></html>"
    res = GSC::HreflangValidator.audit(html, check_reciprocity: false)

    assert_equal 0, res[:total_tags]
    assert_equal 50.0, res[:health_score]
    assert_equal 'C', res[:grade]
    refute res[:self_reference]
    refute res[:has_x_default]
  end

  def test_prescriptions_generated
    res = GSC::HreflangValidator.audit(@html_with_mistakes, check_reciprocity: false)

    refute_empty res[:prescriptions]
    assert res[:prescriptions].any? { |p| p.include?('self-referencing') }
    assert res[:prescriptions].any? { |p| p.include?('x-default') }
    assert res[:prescriptions].any? { |p| p.include?('en-GB') }
  end
end

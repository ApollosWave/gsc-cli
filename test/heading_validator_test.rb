# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class HeadingValidatorTest < Minitest::Test
  def test_perfect_heading_hierarchy
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <body>
        <h1>Main Page Topic</h1>
        <h2>Section One</h2>
        <h3>Detail A</h3>
        <h3>Detail B</h3>
        <h2>Section Two</h2>
        <h3>Detail C</h3>
      </body>
      </html>
    HTML

    res = GSC::HeadingValidator.analyze(html, target_keywords: 'main topic')

    assert_equal 100, res[:score]
    assert_equal 'A', res[:grade]
    assert_equal 3, res[:depth]
    assert_equal 6, res[:count]
    assert_equal 1, res[:h1_count]
    assert_equal 0, res[:empty_count]
    assert_empty res[:violations]
    assert res[:keyword_analysis][:h1_has_keyword]
    assert_includes res[:ascii_tree], '[H1] Main Page Topic'
    assert_includes res[:ascii_tree], '[H2] Section One'
    assert_includes res[:ascii_tree], '[H3] Detail A'
  end

  def test_detects_missing_h1_and_first_not_h1
    html = <<~HTML
      <html>
      <body>
        <h2>Accidental Subheading First</h2>
        <p>Text here...</p>
        <h3>Sub-detail</h3>
      </body>
      </html>
    HTML

    res = GSC::HeadingValidator.analyze(html)

    assert res[:score] < 70
    assert_includes ['D', 'F'], res[:grade]
    types = res[:violations].map { |v| v[:type] }
    assert_includes types, :first_not_h1
    assert_includes types, :missing_h1
    assert_equal 0, res[:h1_count]
  end

  def test_detects_multiple_h1_tags
    html = <<~HTML
      <html>
      <body>
        <h1>First Title</h1>
        <p>Text...</p>
        <h1>Second Title (Duplicate)</h1>
      </body>
      </html>
    HTML

    res = GSC::HeadingValidator.analyze(html)

    assert_equal 2, res[:h1_count]
    types = res[:violations].map { |v| v[:type] }
    assert_includes types, :multiple_h1
    assert res[:score] <= 85
  end

  def test_detects_skipped_levels_and_empty_headings
    html = <<~HTML
      <html>
      <body>
        <h1>Valid Start</h1>
        <h4>Skipped directly from H1 to H4</h4>
        <h2></h2>
        <h6>Jumped from H2 to H6</h6>
      </body>
      </html>
    HTML

    res = GSC::HeadingValidator.analyze(html)

    types = res[:violations].map { |v| v[:type] }
    assert_includes types, :skipped_level
    assert_includes types, :empty_heading
    assert_equal 1, res[:empty_count]

    # Verify violation descriptions
    skipped_v = res[:violations].find { |v| v[:type] == :skipped_level }
    assert_match(/jumped from <h1/i, skipped_v[:message])
  end
end

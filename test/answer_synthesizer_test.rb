# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class AnswerSynthesizerTest < Minitest::Test
  def test_synthesizes_definitional_answer
    result = GSC::AnswerSynthesizer.synthesize("what is technical seo", brand: "ExampleApp")

    assert_equal "definition", result[:intent_type]
    assert result[:word_count] >= 35
    assert result[:citability_score] >= 85
    assert_includes result[:direct_answer], "Technical Seo is"
    assert_equal 4, result[:key_points].size
    assert_match(/Empirical Benchmark Directive/i, result[:information_gain_stat])
    assert_includes result[:html_markup], 'itemtype="https://schema.org/WebPage"'
    assert_equal "Question", result[:schema_jsonld]["@type"]
    assert_equal "Answer", result[:schema_jsonld]["acceptedAnswer"]["@type"]
  end

  def test_synthesizes_how_to_steps_answer
    result = GSC::AnswerSynthesizer.synthesize("how to optimize website cls")

    assert_equal "steps", result[:intent_type]
    assert_includes result[:direct_answer], "teams systematically audit"
    assert result[:key_points].any? { |kp| kp.include?("1. Audit Current State") }
    assert_includes result[:schema_jsonld]["name"], "how to optimize website cls?"
  end

  def test_synthesizes_comparison_answer
    result = GSC::AnswerSynthesizer.synthesize("server side rendering vs static site generation")

    assert_equal "comparison", result[:intent_type]
    assert_includes result[:direct_answer], "primary distinction lies in"
    assert result[:key_points].any? { |kp| kp.include?("Architecture") }
  end
end

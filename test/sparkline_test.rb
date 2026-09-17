# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/sparkline'

class SparklineTest < Minitest::Test
  def test_render_basic_sparkline
    data = [10, 20, 30, 40, 50, 60, 70, 80]
    spark = GSC::Sparkline.render(data)

    assert_equal 8, spark.chars.size
    assert_equal "\u2581", spark.chars.first
    assert_equal "\u2588", spark.chars.last
  end

  def test_render_flatline
    data = [50, 50, 50, 50]
    spark = GSC::Sparkline.render(data)

    assert_equal 4, spark.chars.size
    assert spark.chars.all? { |c| c == "\u2585" }
  end

  def test_render_inverted_position
    # For positions: 1.0 (best) should be higher tick than 50.0
    positions = [1.0, 5.0, 15.0, 30.0, 50.0]
    spark = GSC::Sparkline.render(positions, invert: true)

    assert_equal "\u2588", spark.chars.first
    assert_equal "\u2581", spark.chars.last
  end

  def test_render_resample_max_points
    long_data = (1..100).to_a
    spark = GSC::Sparkline.render(long_data, max_points: 10)

    assert_equal 10, spark.chars.size
  end

  def test_chart_generation
    data = [100, 250, 400, 350, 500]
    dates = %w[2026-03-01 2026-03-07 2026-03-14 2026-03-21 2026-03-28]
    chart = GSC::Sparkline.chart(data, height: 4, dates: dates)

    lines = chart.split("\n")
    assert lines.size >= 5, "Chart should have Y rows + X axis + dates"
    assert lines.first.include?('500'), "Top line should have max value"
    assert lines[3].include?('100'), "Bottom line should have min value"
    assert chart.include?('┼─')
  end

  def test_momentum_calculation
    surging_data = [10, 10, 10, 30, 35, 40]
    mom = GSC::Sparkline.momentum(surging_data)
    assert_equal :surging, mom[:trend]
    assert mom[:change_pct] >= 25.0
    assert mom[:velocity].include?('SURGING')

    decaying_data = [50, 45, 40, 20, 15, 10]
    mom_dec = GSC::Sparkline.momentum(decaying_data)
    assert_includes %i[decaying collapsing], mom_dec[:trend]
    assert mom_dec[:change_pct] < -20.0

    stable_data = [20, 21, 20, 21, 20]
    mom_st = GSC::Sparkline.momentum(stable_data)
    assert_equal :stable, mom_st[:trend]
  end

  def test_empty_and_single_element
    assert_equal '', GSC::Sparkline.render([])
    assert_equal '▅', GSC::Sparkline.render([42])
    assert_equal '', GSC::Sparkline.chart([])
  end
end

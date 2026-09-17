# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class SeasonalPredictorTest < Minitest::Test
  def setup
    @predictor = GSC::SeasonalPredictor.new
  end

  def test_decompose_monthly_seasonality
    # Mock 24 data points spanning 2 years with strong Q4 surge
    points = [
      # Year 1
      { date: '2024-01-15', score: 30 }, { date: '2024-02-15', score: 25 },
      { date: '2024-03-15', score: 35 }, { date: '2024-04-15', score: 40 },
      { date: '2024-05-15', score: 45 }, { date: '2024-06-15', score: 50 },
      { date: '2024-07-15', score: 55 }, { date: '2024-08-15', score: 50 },
      { date: '2024-09-15', score: 60 }, { date: '2024-10-15', score: 75 },
      { date: '2024-11-15', score: 100 }, { date: '2024-12-15', score: 95 },
      # Year 2
      { date: '2025-01-15', score: 32 }, { date: '2025-02-15', score: 28 },
      { date: '2025-03-15', score: 38 }, { date: '2025-04-15', score: 42 },
      { date: '2025-05-15', score: 46 }, { date: '2025-06-15', score: 52 },
      { date: '2025-07-15', score: 58 }, { date: '2025-08-15', score: 52 },
      { date: '2025-09-15', score: 62 }, { date: '2025-10-15', score: 78 },
      { date: '2025-11-15', score: 100 }, { date: '2025-12-15', score: 98 }
    ]

    stats = @predictor.decompose_monthly_seasonality(points)

    assert_equal 12, stats[:months].size
    assert_equal 11, stats[:peak_month] # November
    assert_equal 'Nov', stats[:peak_month_name]
    assert stats[:peak_index] >= 170
    assert stats[:peak_multiplier] >= 1.7
    assert_equal 2, stats[:trough_month] # February
    assert_equal 'Feb', stats[:trough_month_name]
    assert stats[:trough_index] <= 60
  end

  def test_detect_runway_and_deadlines
    # Assume today is August 1st (peak in October gives ~26 days to Aug 27 deadline -> HIGH)
    fake_today = Date.new(2026, 8, 1)

    # Monthly stats with October (140) and November (195) peak
    monthly_stats = {
      months: {
        1 => { month: 1, month_name: 'Jan', seasonality_index: 60, relative_multiplier: 0.60 },
        2 => { month: 2, month_name: 'Feb', seasonality_index: 55, relative_multiplier: 0.55 },
        3 => { month: 3, month_name: 'Mar', seasonality_index: 70, relative_multiplier: 0.70 },
        4 => { month: 4, month_name: 'Apr', seasonality_index: 80, relative_multiplier: 0.80 },
        5 => { month: 5, month_name: 'May', seasonality_index: 85, relative_multiplier: 0.85 },
        6 => { month: 6, month_name: 'Jun', seasonality_index: 95, relative_multiplier: 0.95 },
        7 => { month: 7, month_name: 'Jul', seasonality_index: 100, relative_multiplier: 1.00 },
        8 => { month: 8, month_name: 'Aug', seasonality_index: 105, relative_multiplier: 1.05 },
        9 => { month: 9, month_name: 'Sep', seasonality_index: 115, relative_multiplier: 1.15 },
        10 => { month: 10, month_name: 'Oct', seasonality_index: 140, relative_multiplier: 1.40 },
        11 => { month: 11, month_name: 'Nov', seasonality_index: 195, relative_multiplier: 1.95 },
        12 => { month: 12, month_name: 'Dec', seasonality_index: 180, relative_multiplier: 1.80 }
      },
      peak_month: 11,
      peak_month_name: 'Nov',
      peak_index: 195,
      trough_month: 2,
      trough_month_name: 'Feb',
      trough_index: 55
    }

    runway = @predictor.detect_runway_and_deadlines(monthly_stats, fake_today)

    assert_equal 8, runway[:current_month]
    assert runway[:is_spiking_soon]
    assert_includes [10, 11], runway[:spike_month]
    assert_equal 'HIGH', runway[:urgency]
    assert runway[:days_to_deadline] > 0
    refute_nil runway[:publish_deadline]
    assert_includes runway[:recommendation], 'OPTIMIZE NOW'
  end

  def test_classify_seasonality_pattern
    # Evergreen test
    evergreen_stats = {
      peak_month: 7, peak_month_name: 'Jul', peak_index: 110,
      trough_month: 2, trough_month_name: 'Feb', trough_index: 92
    }
    c_ev = @predictor.classify_seasonality_pattern(evergreen_stats)
    assert_equal 'EVERGREEN', c_ev[:pattern]

    # Holiday test
    holiday_stats = {
      peak_month: 11, peak_month_name: 'Nov', peak_index: 190,
      trough_month: 2, trough_month_name: 'Feb', trough_index: 45
    }
    c_hol = @predictor.classify_seasonality_pattern(holiday_stats)
    assert_equal 'Q4_HOLIDAY', c_hol[:pattern]

    # Summer test
    summer_stats = {
      peak_month: 7, peak_month_name: 'Jul', peak_index: 180,
      trough_month: 12, trough_month_name: 'Dec', trough_index: 40
    }
    c_sum = @predictor.classify_seasonality_pattern(summer_stats)
    assert_equal 'Q3_SUMMER', c_sum[:pattern]
  end

  def test_diagnose_traffic_drop_false_alarm
    # Mock monthly stats where Jan = 150 SI, Feb = 90 SI (a -40% seasonal collapse)
    mock_stats = {
      months: {
        1 => { seasonality_index: 150 },
        2 => { seasonality_index: 90 }
      }
    }
    # GSC clicks dropped -35% in February, matching the -40% seasonal drop
    diagnosis = @predictor.diagnose_traffic_drop('holiday gift guides', -35, 2, mock_stats)

    assert_equal 'holiday gift guides', diagnosis[:query]
    assert_equal :seasonal_cycle, diagnosis[:verdict]
    assert_includes diagnosis[:explanation], 'False alarm'
  end

  def test_calculate_seasonal_roi
    # Query with 200 clicks, 5,000 impressions, ranking at position 7.5
    # Moving to position 3 with a 2.0x peak season surge
    roi = @predictor.calculate_seasonal_roi(200, 5000, 7.5, 2.0, target_pos: 3)

    assert_equal 7.5, roi[:current_position]
    assert_equal 3, roi[:target_position]
    assert roi[:seasonal_monthly_click_gain] > roi[:baseline_monthly_click_gain]
    assert_equal 2.0, roi[:roi_multiplier]
    assert roi[:peak_90d_click_harvest] > 0
  end

  def test_render_ascii_calendar
    monthly_stats = {
      months: {},
      peak_month: 11,
      peak_month_name: 'Nov',
      peak_index: 190,
      trough_month: 2,
      trough_month_name: 'Feb',
      trough_index: 50
    }

    1.upto(12) do |m|
      monthly_stats[:months][m] = {
        month: m,
        month_name: GSC::SeasonalPredictor::MONTH_NAMES[m - 1],
        seasonality_index: (m == 11 ? 190 : (m == 2 ? 50 : 100)),
        relative_multiplier: (m == 11 ? 1.9 : 1.0)
      }
    end

    rendered = @predictor.render_ascii_calendar(monthly_stats, 9)
    assert_includes rendered, 'SEASONALITY INDEX'
    assert_includes rendered, 'Nov'
    assert_includes rendered, 'CURRENT'
    assert_includes rendered, 'PEAK'
    assert_includes rendered, 'TROUGH'
  end

  def test_analyze_keyword_when_trends_unavailable
    # When Google Trends returns no points or rate-limits, return ok: false without fake harmonic sine wave
    res = @predictor.analyze_keyword('synthetic test query', geo: 'US', time: '5y')
    if res[:ok]
      assert_equal 'synthetic test query', res[:keyword]
      assert_equal 12, res[:monthly_stats][:months].size
    else
      refute res[:ok]
      assert_includes res[:error], 'Google Trends'
      assert_equal 0, res[:points_count]
    end
  end
end

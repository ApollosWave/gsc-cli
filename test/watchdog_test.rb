# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/watchdog'

class WatchdogTest < Minitest::Test
  def setup
    @domain = 'zerocramp.com'
    @watchdog = GSC::Watchdog.new({ threshold: 2.0 }, nil, @domain)
  end

  def test_check_execution_and_summary_structure_unauthenticated
    summary = @watchdog.check

    assert_equal 'zerocramp.com', summary[:domain]
    assert_equal 0, summary[:monitored_queries_count]
    refute_nil summary[:checked_at]
    assert_equal 'SERP HEALTH OPTIMAL', summary[:status]
    assert_empty summary[:alerts]
  end

  def test_check_execution_and_summary_structure_authenticated
    mock_api = Object.new
    def mock_api.search_analytics(domain, options = {})
      start_d = options[:start_date]
      # Return drops for previous vs current
      if start_d > (Date.today - 10).strftime('%Y-%m-%d')
        # curr
        { 'rows' => [{ 'keys' => ['natural pain relief'], 'position' => 8.5, 'clicks' => 50, 'ctr' => 0.031 }] }
      else
        # prev
        { 'rows' => [{ 'keys' => ['natural pain relief'], 'position' => 2.1, 'clicks' => 400, 'ctr' => 0.098 }] }
      end
    end

    watchdog = GSC::Watchdog.new({ threshold: 2.0 }, mock_api, @domain)
    summary = watchdog.check

    assert_equal 'zerocramp.com', summary[:domain]
    assert_equal 1, summary[:monitored_queries_count]
    refute_nil summary[:checked_at]
    assert_equal 'CRITICAL ANOMALIES', summary[:status]

    # Verify alerts structure
    refute_empty summary[:alerts]
    first_alert = summary[:alerts].first
    assert_equal 'natural pain relief', first_alert[:query]
    refute_nil first_alert[:message]
    assert_equal :critical, first_alert[:severity]
  end

  def test_anomaly_detection_with_custom_telemetry
    custom_telemetry = [
      # Severe position drop: pos 2.1 -> 8.5 (dropped 6.4 positions)
      { query: 'natural pain relief', current_position: 8.5, previous_position: 2.1, current_clicks: 50, previous_clicks: 400, current_ctr: 3.1, previous_ctr: 9.8 },
      # Stable rank but 50% CTR crash (pos 2.0, CTR 10% -> 5%)
      { query: 'period spasm hacks', current_position: 2.0, previous_position: 2.0, current_clicks: 100, previous_clicks: 200, current_ctr: 5.0, previous_ctr: 10.0 },
      # Perfectly stable query
      { query: 'zerocramp login', current_position: 1.0, previous_position: 1.0, current_clicks: 500, previous_clicks: 510, current_ctr: 70.0, previous_ctr: 71.0 }
    ]

    alerts = @watchdog.send(:detect_anomalies, custom_telemetry)
    summary = @watchdog.send(:synthesize_summary, custom_telemetry, alerts)

    assert_equal 2, alerts.size
    assert_equal 'CRITICAL ANOMALIES', summary[:status]
    assert_equal 1, summary[:critical_alerts_count]
    assert_equal 1, summary[:warning_alerts_count]

    pos_alert = alerts.find { |a| a[:type] == :position_drop }
    assert_equal :critical, pos_alert[:severity]
    assert_includes pos_alert[:message], 'dropped 6.4 positions'

    ctr_alert = alerts.find { |a| a[:type] == :ctr_anomaly }
    assert_equal :warning, ctr_alert[:severity]
    assert_includes ctr_alert[:message], 'CTR dropped 50.0%'
  end

  def test_crontab_generation
    crontab = @watchdog.generate_crontab_entry
    assert_includes crontab, '0 */6 * * *'
    assert_includes crontab, 'watch zerocramp.com --once'
    assert_includes crontab, '>> ~/.config/gsc/watch.log 2>&1'
  end

  def test_launchd_plist_generation
    plist = @watchdog.generate_launchd_plist
    assert_includes plist, '<plist version="1.0">'
    assert_includes plist, '<string>com.gsc.watchdog.zerocramp_com</string>'
    assert_includes plist, '<string>watch</string>'
    assert_includes plist, '<string>zerocramp.com</string>'
    assert_includes plist, '<key>StartInterval</key>'
  end

  def test_systemd_unit_generation
    unit = @watchdog.generate_systemd_unit
    assert_includes unit, '[Unit]'
    assert_includes unit, 'Description=GSC Continuous SEO Rank & CTR Volatility Watchdog for zerocramp.com'
    assert_includes unit, 'ExecStart='
    assert_includes unit, 'watch zerocramp.com --once'
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/mobile_parity'

class MobileParityTest < Minitest::Test
  def setup
    @domain = 'zerocramp.com'
    @auditor = GSC::MobileParity.new({}, nil, @domain)
  end

  def test_audit_execution_and_report_structure_unauthenticated
    res = @auditor.audit

    assert_equal 'zerocramp.com', res[:domain]
    assert_equal 0, res[:total_queries_analyzed]
    assert_equal 100, res[:health_score]
    assert_equal 'A', res[:grade]
    assert_empty res[:disparities]
    assert_empty res[:priority_remediations]
  end

  def test_audit_execution_and_report_structure_authenticated
    mock_api = Object.new
    def mock_api.search_analytics(domain, options = {})
      {
        'rows' => [
          { 'keys' => ['acoustic cramp relief device', 'DESKTOP'], 'clicks' => 500, 'impressions' => 4000, 'ctr' => 0.125, 'position' => 2.0 },
          { 'keys' => ['acoustic cramp relief device', 'MOBILE'],  'clicks' => 40,  'impressions' => 6000, 'ctr' => 0.0067, 'position' => 12.5 }
        ]
      }
    end

    auditor = GSC::MobileParity.new({}, mock_api, @domain)
    res = auditor.audit

    assert_equal 'zerocramp.com', res[:domain]
    assert_equal 1, res[:total_queries_analyzed]
    refute_nil res[:health_score]
    assert_includes ['A', 'B', 'C', 'F'], res[:grade]

    # Traffic distribution
    dist = res[:traffic_distribution]
    assert dist[:mobile_share_pct] > 0
    assert dist[:desktop_share_pct] > 0
    assert_equal 100.0, (dist[:mobile_share_pct] + dist[:desktop_share_pct]).round(1)

    # Disparities
    refute_empty res[:disparities]
    assert_equal 'acoustic cramp relief device', res[:disparities].first[:query]

    # Remediation
    refute_empty res[:priority_remediations]
  end

  def test_custom_parity_scenarios
    custom_pairs = [
      # Severe mobile demotion (Pos 2.0 desktop vs 12.5 mobile -> gap +10.5)
      {
        query: 'acoustic cramp relief device',
        desktop: { clicks: 500, impressions: 4000, ctr: 12.5, position: 2.0 },
        mobile:  { clicks: 40, impressions: 6000, ctr: 0.67, position: 12.5 }
      },
      # Perfect parity
      {
        query: 'zerocramp portal',
        desktop: { clicks: 100, impressions: 150, ctr: 66.67, position: 1.0 },
        mobile:  { clicks: 150, impressions: 220, ctr: 68.18, position: 1.0 }
      },
      # Mobile favored
      {
        query: 'on the go cramp hacks',
        desktop: { clicks: 50, impressions: 1000, ctr: 5.0, position: 8.0 },
        mobile:  { clicks: 180, impressions: 2000, ctr: 9.0, position: 3.5 }
      }
    ]

    analyzed = @auditor.send(:analyze_pairs, custom_pairs)
    report = @auditor.send(:synthesize_report, analyzed)

    assert_equal 3, report[:total_queries_analyzed]
    assert_equal 1, report[:critical_suppression_count]
    assert_equal 1, report[:parity_count]
    assert_equal 1, report[:mobile_favored_count]

    crit = analyzed.find { |a| a[:status] == :critical_suppression }
    assert_equal 10.5, crit[:pos_gap]
    assert crit[:lost_clicks] > 0
    assert_includes crit[:diagnosis], 'Severe Mobile Demotion'
    assert_includes crit[:remediation], 'mobile Core Web Vitals'

    favored = analyzed.find { |a| a[:status] == :mobile_advantaged }
    assert_equal(-4.5, favored[:pos_gap])
    assert_includes favored[:diagnosis], 'Mobile Favored'
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/zombie_purger'

class ZombiePurgerTest < Minitest::Test
  def setup
    @inventory = [
      'https://example.com/',
      'https://example.com/blog/ruby-performance-guide',
      'https://example.com/blog/ruby-performance-tips',
      'https://example.com/tag/ruby',
      'https://example.com/privacy-policy',
      'https://example.com/terms',
      'https://example.com/old-abandoned-page-2019'
    ]

    @gsc_pages = {
      'https://example.com' => { impressions: 15000, clicks: 450, position: 2.1 },
      'https://example.com/blog/ruby-performance-guide' => { impressions: 4200, clicks: 180, position: 4.3 }
      # All other URLs have 0 impressions in GSC
    }
  end

  def test_audit_detection_and_metrics
    result = GSC::ZombiePurger.audit(@inventory, @gsc_pages, days: 90)

    assert_equal 7, result[:total_inventory]
    assert_equal 2, result[:active_count]
    assert_equal 5, result[:zombie_count]

    # 5/7 = 71.4%
    assert_in_delta 71.4, result[:zombie_percentage], 0.1
    assert_in_delta 71.4, result[:cedi], 0.1
    assert_in_delta 28.6, result[:health_score], 0.1
    assert_equal 'F', result[:grade]

    # Wasted crawls
    assert_equal 5 * 6, result[:wasted_crawls_monthly]
    assert_equal 30 * 12, result[:wasted_crawls_annually]
  end

  def test_triage_actions_classification
    result = GSC::ZombiePurger.audit(@inventory, @gsc_pages)
    zombies = result[:zombies]

    # /blog/ruby-performance-tips should match /blog/ruby-performance-guide
    redirect_zombie = zombies.find { |z| z[:url].include?('ruby-performance-tips') }
    assert redirect_zombie, "Should find ruby-performance-tips zombie"
    assert_equal :redirect_301, redirect_zombie[:action]
    assert_equal 'https://example.com/blog/ruby-performance-guide', redirect_zombie[:target_url]

    # /tag/ruby should be purge_410
    tag_zombie = zombies.find { |z| z[:url].include?('/tag/ruby') }
    assert tag_zombie
    assert_equal :purge_410, tag_zombie[:action]

    # /privacy-policy and /terms should be noindex
    privacy_zombie = zombies.find { |z| z[:url].include?('privacy-policy') }
    assert privacy_zombie
    assert_equal :noindex, privacy_zombie[:action]

    terms_zombie = zombies.find { |z| z[:url].include?('terms') }
    assert terms_zombie
    assert_equal :noindex, terms_zombie[:action]

    # /old-abandoned-page-2019 should be purge_410
    abandoned_zombie = zombies.find { |z| z[:url].include?('old-abandoned-page') }
    assert abandoned_zombie
    assert_equal :purge_410, abandoned_zombie[:action]
  end

  def test_action_breakdown_counts
    result = GSC::ZombiePurger.audit(@inventory, @gsc_pages)
    brk = result[:action_breakdown]

    assert_equal 2, brk[:purge_410]
    assert_equal 1, brk[:redirect_301]
    assert_equal 2, brk[:noindex]
    assert_equal 0, brk[:consolidate]
  end

  def test_action_filtering
    result = GSC::ZombiePurger.audit(@inventory, @gsc_pages, action: 'redirect')
    assert_equal 1, result[:zombies].size
    assert_equal :redirect_301, result[:zombies].first[:action]
  end

  def test_server_rules_generators
    result = GSC::ZombiePurger.audit(@inventory, @gsc_pages)
    rules = result[:server_rules]

    assert rules[:nginx].include?('return 410;')
    assert rules[:nginx].include?('return 301 /blog/ruby-performance-guide;')

    assert rules[:htaccess].include?('RedirectGone /tag/ruby')
    assert rules[:htaccess].include?('Redirect 301 /blog/ruby-performance-tips /blog/ruby-performance-guide')

    assert rules[:redirects].include?('/tag/ruby   410!')
    assert rules[:redirects].include?('/blog/ruby-performance-tips   /blog/ruby-performance-guide   301')

    assert_equal '<meta name="robots" content="noindex, follow">', rules[:meta_robots]
  end

  def test_zero_zombies_scenario
    active_inv = ['https://example.com/p1', 'https://example.com/p2']
    active_gsc = {
      'https://example.com/p1' => { impressions: 100 },
      'https://example.com/p2' => { impressions: 200 }
    }
    result = GSC::ZombiePurger.audit(active_inv, active_gsc)

    assert_equal 0, result[:zombie_count]
    assert_equal 0.0, result[:cedi]
    assert_equal 100.0, result[:health_score]
    assert_equal 'A', result[:grade]
    assert_equal 0, result[:wasted_crawls_monthly]
  end
end

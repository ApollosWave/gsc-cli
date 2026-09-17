# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class FirewallScannerTest < Minitest::Test
  def setup
    @scanner = GSC::FirewallScanner.new('https://example.com')
  end

  def test_initialization_normalizes_url
    s = GSC::FirewallScanner.new('mysite.com')
    assert_equal 'https://mysite.com', s.url
    assert_equal 'mysite.com', s.uri.host
  end

  def test_robots_txt_parsing_wildcard_allow
    robots = <<~ROBOTS
      User-agent: *
      Disallow: /admin/
      Disallow: /checkout
      Allow: /
    ROBOTS

    parsed = @scanner.send(:parse_robots_rules, robots, 'GPTBot')
    assert_equal :restricted, parsed[:status]
    assert_equal '*', parsed[:matched_agent]
  end

  def test_robots_txt_parsing_explicit_disallow
    robots = <<~ROBOTS
      User-agent: *
      Allow: /

      User-agent: GPTBot
      Disallow: /

      User-agent: ClaudeBot
      Disallow: /
    ROBOTS

    gpt_parsed = @scanner.send(:parse_robots_rules, robots, 'GPTBot')
    assert_equal :blocked, gpt_parsed[:status]
    assert_equal 'GPTBot', gpt_parsed[:matched_agent]

    claude_parsed = @scanner.send(:parse_robots_rules, robots, 'ClaudeBot')
    assert_equal :blocked, claude_parsed[:status]

    perplexity_parsed = @scanner.send(:parse_robots_rules, robots, 'PerplexityBot')
    assert_equal :allowed, perplexity_parsed[:status]
  end

  def test_waf_challenge_detection_cloudflare_turnstile
    headers = { 'cf-ray' => '8932014890123-ORD', 'cf-mitigated' => 'challenge' }
    body = '<html><head><title>Just a moment...</title></head><body><div class="cf-turnstile"></div></body></html>'

    challenges = @scanner.send(:detect_waf_challenges, 403, headers, body)
    assert challenges.any? { |c| c.include?('Cloudflare Managed Challenge') }
    assert challenges.any? { |c| c.include?('Super Bot Fight Mode') }
  end

  def test_waf_challenge_detection_aws_waf
    headers = { 'x-amzn-waf-action' => 'block' }
    body = '403 Forbidden - Request blocked by AWS WAF'

    challenges = @scanner.send(:detect_waf_challenges, 403, headers, body)
    assert challenges.any? { |c| c.include?('AWS WAF Automated Block') }
  end

  def test_edge_infrastructure_detection
    mock_probes = [
      {
        id: :browser,
        headers: {
          'server' => 'cloudflare',
          'cf-ray' => '8a7bc0123-EWR',
          'cf-cache-status' => 'HIT'
        }
      }
    ]

    infra = @scanner.send(:detect_edge_infrastructure, mock_probes)
    cf = infra.find { |i| i[:name] == 'Cloudflare' }
    refute_nil cf
    assert_equal 'Edge CDN, DDoS & WAF', cf[:role]
  end

  def test_silent_blockade_detection
    mock_probes = [
      { id: :browser, name: 'Chrome', status: 200, verdict: :pass, challenges: [] },
      { id: :googlebot, name: 'Googlebot', status: 200, verdict: :pass, challenges: [] },
      { id: :gptbot, name: 'GPTBot', status: 403, verdict: :blocked, challenges: ['Cloudflare Super Bot Fight Mode (403/503 Block)'] },
      { id: :claudebot, name: 'ClaudeBot', status: 403, verdict: :challenge, challenges: ['Cloudflare Managed Challenge (Turnstile/JS Challenge)'] }
    ]

    mock_robots = { bots: { 'GPTBot' => { critical: true, status: :allowed } } }

    diag = @scanner.send(:analyze_blockade, mock_probes, mock_robots)
    assert diag[:silent_blockade_detected]
    assert_equal :critical, diag[:severity]
    assert_equal 2, diag[:blocked_probes].size
  end

  def test_scoring_and_grading
    robots_data = {
      bots: {
        'GPTBot' => { status: :allowed },
        'ChatGPT-User' => { status: :allowed },
        'ClaudeBot' => { status: :allowed },
        'PerplexityBot' => { status: :allowed },
        'Google-Extended' => { status: :allowed },
        'Applebot-Extended' => { status: :allowed }
      }
    }

    clean_probes = [
      { id: :browser, verdict: :pass },
      { id: :googlebot, verdict: :pass },
      { id: :gptbot, verdict: :pass },
      { id: :claudebot, verdict: :pass },
      { id: :perplexity, verdict: :pass }
    ]

    clean_blockade = { silent_blockade_detected: false, robots_critical_blocked: [] }

    score_res = @scanner.send(:calculate_score, robots_data, clean_probes, clean_blockade)
    assert_equal 100, score_res[:score]
    assert_equal 'A', score_res[:grade]

    # Test score with silent blockade penalty
    blocked_blockade = { silent_blockade_detected: true, robots_critical_blocked: ['GPTBot'] }
    blocked_probes = [
      { id: :browser, verdict: :pass },
      { id: :googlebot, verdict: :pass },
      { id: :gptbot, verdict: :blocked },
      { id: :claudebot, verdict: :blocked },
      { id: :perplexity, verdict: :pass }
    ]

    penalized = @scanner.send(:calculate_score, robots_data, blocked_probes, blocked_blockade)
    assert penalized[:score] < 70
    assert penalized[:breakdown][:penalties] >= 40
  end

  def test_remediation_recipes_cloudflare
    infra = [{ name: 'Cloudflare', role: 'Edge CDN' }]
    robots = { bots: {} }
    blockade = { silent_blockade_detected: true, robots_critical_blocked: ['ClaudeBot'] }

    recipes = @scanner.send(:generate_remediation_recipes, infra, robots, blockade)
    refute_nil recipes[:cloudflare_waf_rule]
    assert recipes[:cloudflare_waf_rule][:filter_expression].include?('GPTBot')
    assert recipes[:cloudflare_waf_rule][:filter_expression].include?('ClaudeBot')
    assert recipes[:cloudflare_waf_rule][:filter_expression].include?('PerplexityBot')
    assert recipes[:recommended_robots_txt].include?('User-agent: GPTBot')
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/security_scanner'

class SecurityScannerTest < Minitest::Test
  def setup
    @scanner = GSC::SecurityScanner.new('https://example.com')
  end

  def test_scan_mixed_content_active_and_passive
    html = <<~HTML
      <html>
        <head>
          <script src="http://insecure-cdn.com/app.js"></script>
          <link rel="stylesheet" href="http://insecure-cdn.com/style.css">
          <link href="https://secure-cdn.com/theme.css" rel="stylesheet">
        </head>
        <body>
          <img src="http://example.com/logo.png" alt="Logo">
          <img src="https://example.com/safe.png" alt="Safe">
          <iframe src="http://tracker.com/frame"></iframe>
          <audio src="http://example.com/podcast.mp3"></audio>
        </body>
      </html>
    HTML

    mixed = @scanner.send(:scan_mixed_content, html, 'https://example.com')

    assert_equal 5, mixed[:total]
    assert_equal 3, mixed[:active].size # script, link stylesheet, iframe
    assert_equal 2, mixed[:passive].size # img, audio
    assert mixed[:has_critical_active_blocks]

    active_urls = mixed[:active].map { |a| a[:url] }
    assert_includes active_urls, 'http://insecure-cdn.com/app.js'
    assert_includes active_urls, 'http://insecure-cdn.com/style.css'
    assert_includes active_urls, 'http://tracker.com/frame'

    passive_urls = mixed[:passive].map { |p| p[:url] }
    assert_includes passive_urls, 'http://example.com/logo.png'
    assert_includes passive_urls, 'http://example.com/podcast.mp3'
  end

  def test_evaluate_hsts_preload_eligibility
    # Eligible
    valid_hsts = 'max-age=31536000; includeSubDomains; preload'
    res = @scanner.send(:evaluate_hsts_preload, valid_hsts)
    assert res[:eligible]
    assert_empty res[:reasons]

    # Ineligible: short max age
    short_hsts = 'max-age=86400; includeSubDomains; preload'
    res_short = @scanner.send(:evaluate_hsts_preload, short_hsts)
    refute res_short[:eligible]
    assert res_short[:reasons].any? { |r| r.include?('max-age') }

    # Ineligible: missing includeSubDomains
    no_sub = 'max-age=31536000; preload'
    res_no_sub = @scanner.send(:evaluate_hsts_preload, no_sub)
    refute res_no_sub[:eligible]
    assert res_no_sub[:reasons].any? { |r| r.include?('includeSubDomains') }

    # Ineligible: missing preload
    no_pre = 'max-age=31536000; includeSubDomains'
    res_no_pre = @scanner.send(:evaluate_hsts_preload, no_pre)
    refute res_no_pre[:eligible]
    assert res_no_pre[:reasons].any? { |r| r.include?('preload') }
  end

  def test_audit_security_headers_and_leakage
    headers = {
      'strict-transport-security' => 'max-age=31536000; includeSubDomains; preload',
      'x-frame-options' => 'DENY',
      'x-content-type-options' => 'nosniff',
      'server' => 'Apache/2.4.41 (Ubuntu)',
      'x-powered-by' => 'PHP/7.4.3'
    }

    audit = @scanner.send(:audit_security_headers, headers)
    leaks = @scanner.send(:audit_leak_headers, headers)

    assert_equal 3, audit[:present].size
    assert_equal 3, audit[:missing].size # CSP, Referrer-Policy, Permissions-Policy
    assert_includes audit[:missing_headers], 'Content-Security-Policy'
    assert_includes audit[:missing_headers], 'Referrer-Policy'
    assert_includes audit[:missing_headers], 'Permissions-Policy'

    assert_equal 2, leaks.size
    assert_equal 'server', leaks[0][:header]
    assert_equal 'x-powered-by', leaks[1][:header]
  end

  def test_generate_server_rules
    missing = ['Strict-Transport-Security', 'X-Frame-Options', 'Content-Security-Policy']
    rules = @scanner.send(:generate_server_rules, missing)

    assert rules[:nginx].include?('add_header Strict-Transport-Security')
    assert rules[:nginx].include?('add_header X-Frame-Options "SAMEORIGIN"')
    assert rules[:nginx].include?('add_header Content-Security-Policy')
    assert rules[:nginx].include?('server_tokens off;')

    assert rules[:apache].include?('Header always set Strict-Transport-Security')
    assert rules[:apache].include?('Header always set X-Frame-Options')

    assert rules[:vercel_netlify].include?('Strict-Transport-Security:')
    assert rules[:vercel_netlify].include?('X-Frame-Options: SAMEORIGIN')
  end

  def test_calculate_security_score_and_grades
    # Perfect scenario
    mock_headers_audit = {
      present: [
        { header: 'Strict-Transport-Security', quality: :optimal },
        { header: 'Content-Security-Policy', quality: :optimal },
        { header: 'X-Frame-Options', quality: :optimal },
        { header: 'X-Content-Type-Options', quality: :optimal },
        { header: 'Referrer-Policy', quality: :optimal },
        { header: 'Permissions-Policy', quality: :optimal }
      ],
      missing: []
    }
    mock_leaks = []
    mock_mixed = { active: [], passive: [] }
    mock_ssl = { status: :valid, days_remaining: 120 }

    score_data = @scanner.send(:calculate_security_score, mock_headers_audit, mock_leaks, mock_mixed, mock_ssl)
    assert_equal 100, score_data[:score]
    assert_equal 'A+', score_data[:grade]

    # Vulnerable scenario: missing CSP, active mixed content, expiring SSL
    mock_headers_audit[:missing] = [
      { header: 'Content-Security-Policy', weight: 20, desc: 'XSS mitigation' }
    ]
    mock_mixed = { active: [{ url: 'http://test.com/script.js' }], passive: [] }
    mock_ssl = { status: :critical_expiry, days_remaining: 10 }

    bad_score = @scanner.send(:calculate_security_score, mock_headers_audit, mock_leaks, mock_mixed, mock_ssl)
    assert bad_score[:score] <= 45
    assert_includes ['D', 'F'], bad_score[:grade]
    assert bad_score[:recommendations].any? { |r| r.include?('active mixed content') }
    assert bad_score[:recommendations].any? { |r| r.include?('expires in 10 days') }
  end
end

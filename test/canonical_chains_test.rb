# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/canonical_chains'

class CanonicalChainsTest < Minitest::Test
  def setup
    @breaker = GSC::CanonicalChains.new
  end

  def with_stubbed_http_start(fake_proc)
    orig = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*args, **kwargs, &blk| fake_proc.call(*args, **kwargs, &blk) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, orig)
  end

  def test_generate_collapse_rules
    from_url = "https://example.com/old-blog/post-1"
    to_url = "https://example.com/new-articles/post-1"

    rules = @breaker.generate_collapse_rules(from_url, to_url)

    assert rules[:nginx].start_with?("rewrite ^")
    assert rules[:nginx].include?("https://example.com/new-articles/post-1 permanent;")
    assert rules[:apache].include?("RewriteRule ^old-blog/post-1/?$ https://example.com/new-articles/post-1 [R=301,L]")
    assert rules[:cloudflare].include?('(http.request.full_uri eq "https://example.com/old-blog/post-1") -> 301 to https://example.com/new-articles/post-1')
    assert rules[:vercel_netlify].include?("/old-blog/post-1 https://example.com/new-articles/post-1 301!")
  end

  def test_extract_canonical_html
    html_double_quotes = '<html><head><link rel="canonical" href="https://example.com/canonical-target" /></head></html>'
    extracted = @breaker.send(:extract_canonical_html, html_double_quotes, "https://example.com/source")
    assert_equal "https://example.com/canonical-target", extracted

    html_relative = '<html><head><link rel="canonical" href="/resolved-target" /></head></html>'
    extracted_rel = @breaker.send(:extract_canonical_html, html_relative, "https://example.com/source")
    assert_equal "https://example.com/resolved-target", extracted_rel

    html_href_first = '<html><head><link href="https://example.com/target-2" rel="canonical" /></head></html>'
    extracted_href_first = @breaker.send(:extract_canonical_html, html_href_first, "https://example.com/source")
    assert_equal "https://example.com/target-2", extracted_href_first
  end

  def test_extract_canonical_header
    header = '<https://example.com/header-target>; rel="canonical"'
    extracted = @breaker.send(:extract_canonical_header, header)
    assert_equal "https://example.com/header-target", extracted

    no_canonical = '<https://example.com/style.css>; rel="stylesheet"'
    assert_nil @breaker.send(:extract_canonical_header, no_canonical)
  end

  def test_extract_gsc_traffic
    urls = ["https://example.com/old-url", "https://example.com/canonical-url"]
    rows = [
      { "keys" => ["https://example.com/old-url", "best shoes"], "clicks" => 45, "impressions" => 900 },
      { "keys" => ["https://example.com/other-page", "irrelevant"], "clicks" => 10, "impressions" => 100 },
      { "keys" => ["https://example.com/canonical-url", "running shoes"], "clicks" => 120, "impressions" => 2500 }
    ]

    traffic = @breaker.send(:extract_gsc_traffic, urls, rows)
    assert_equal 165, traffic[:total_clicks]
    assert_equal 3400, traffic[:total_impressions]
    assert_equal 2, traffic[:queries].size
    assert_equal "running shoes", traffic[:queries].first[:query]
  end

  def test_audit_url_direct_healthy
    fake_http_start = lambda do |*args, **kwargs, &block|
      mock_http = Object.new
      mock_http.define_singleton_method(:request) do |req|
        res = Object.new
        res.define_singleton_method(:code) { "200" }
        res.define_singleton_method(:body) { '<html><head><link rel="canonical" href="https://example.com/page" /></head></html>' }
        res.define_singleton_method(:[]) { |h| nil }
        res
      end
      block.call(mock_http)
    end

    with_stubbed_http_start(fake_http_start) do
      audit = @breaker.audit_url("https://example.com/page")

      assert_equal 0, audit[:redirect_hops]
      assert_equal 100.0, audit[:equity_retention_pct]
      assert_equal 0.0, audit[:equity_loss_pct]
      assert_equal :healthy, audit[:severity]
      assert_equal false, audit[:loop_detected]
      assert_equal "https://example.com/page", audit[:canonical_url]
    end
  end

  def test_mixed_canonical_loop_detection
    hop_calls = 0
    fake_http_start = lambda do |*args, **kwargs, &block|
      mock_http = Object.new
      mock_http.define_singleton_method(:request) do |req|
        hop_calls += 1
        res = Object.new
        if hop_calls == 1
          res.define_singleton_method(:code) { "301" }
          res.define_singleton_method(:body) { "" }
          res.define_singleton_method(:[]) { |h| h.downcase == 'location' ? "https://example.com/b" : nil }
        else
          res.define_singleton_method(:code) { "200" }
          res.define_singleton_method(:body) { '<html><head><link rel="canonical" href="https://example.com/a" /></head></html>' }
          res.define_singleton_method(:[]) { |h| nil }
        end
        res
      end
      block.call(mock_http)
    end

    with_stubbed_http_start(fake_http_start) do
      audit = @breaker.audit_url("https://example.com/a")

      assert_equal true, audit[:canonical_loop]
      assert_equal true, audit[:loop_detected]
      assert_equal :mixed_canonical_loop, audit[:loop_type]
      assert_equal :critical, audit[:severity]
      assert_equal 0.0, audit[:equity_retention_pct]
      assert_equal 100.0, audit[:equity_loss_pct]
      assert audit[:issues].any? { |i| i[:code] == :loop }
    end
  end

  def test_multi_hop_redirect_chain_detection
    hop_calls = 0
    fake_http_start = lambda do |*args, **kwargs, &block|
      mock_http = Object.new
      mock_http.define_singleton_method(:request) do |req|
        hop_calls += 1
        res = Object.new
        case hop_calls
        when 1
          res.define_singleton_method(:code) { "301" }
          res.define_singleton_method(:body) { "" }
          res.define_singleton_method(:[]) { |h| h.downcase == 'location' ? "https://example.com/step-2" : nil }
        when 2
          res.define_singleton_method(:code) { "302" }
          res.define_singleton_method(:body) { "" }
          res.define_singleton_method(:[]) { |h| h.downcase == 'location' ? "https://example.com/final" : nil }
        else
          res.define_singleton_method(:code) { "200" }
          res.define_singleton_method(:body) { '<html><head><link rel="canonical" href="https://example.com/final" /></head></html>' }
          res.define_singleton_method(:[]) { |h| nil }
        end
        res
      end
      block.call(mock_http)
    end

    with_stubbed_http_start(fake_http_start) do
      audit = @breaker.audit_url("https://example.com/step-1")

      assert_equal 2, audit[:redirect_hops]
      assert_equal 3, audit[:total_hops]
      assert_in_delta 72.3, audit[:equity_retention_pct], 0.2
      assert_in_delta 27.8, audit[:equity_loss_pct], 0.2
      assert_equal :warning, audit[:severity]
      assert audit[:issues].any? { |i| i[:code] == :redirect_chain }
      assert audit[:server_rules][:nginx].include?("https://example.com/final")
    end
  end
end

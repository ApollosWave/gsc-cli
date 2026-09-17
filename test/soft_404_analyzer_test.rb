# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/soft_404_analyzer'

class Soft404AnalyzerTest < Minitest::Test
  def test_soft_404_diagnosed_on_200_ok_with_error_title
    mock_item = {
      url: "https://example.com/discontinued-shoe",
      status_code: 200,
      latency_ms: 80.0,
      body_size_bytes: 420,
      word_count: 28,
      title: "404 - Page Not Found | Store",
      h1: "Page Not Found",
      meta_robots: "",
      classification: :soft_404,
      is_soft_404: true,
      suggested_action: "Return HTTP 404/410 or 301 redirect to relevant parent hub",
      suggested_redirect: "/products",
      remediation_rules: {
        nginx: "rewrite ^/discontinued-shoe/?$ /products permanent;",
        htaccess: "Redirect 301 /discontinued-shoe /products"
      }
    }

    analyzer = GSC::Soft404Analyzer.new("https://example.com/discontinued-shoe", {
      mock_results: { "https://example.com/discontinued-shoe" => mock_item }
    })

    res = analyzer.analyze
    assert_equal 1, res[:total_urls_audited]
    item = res[:all_results].first

    assert_equal 200, item[:status_code]
    assert_equal :soft_404, item[:classification]
    assert item[:is_soft_404]
    assert_includes item[:remediation_rules][:nginx], "rewrite"
  end

  def test_hard_404_detected
    mock_item = {
      url: "https://example.com/missing-asset",
      status_code: 404,
      latency_ms: 95.0,
      body_size_bytes: 180,
      word_count: 12,
      title: "Not Found",
      h1: "404",
      meta_robots: "",
      classification: :hard_404,
      is_soft_404: false,
      suggested_action: "301 redirect to closely matched category or purge from sitemaps",
      suggested_redirect: "/",
      remediation_rules: {
        nginx: "rewrite ^/missing-asset/?$ / permanent;"
      }
    }

    analyzer = GSC::Soft404Analyzer.new("https://example.com/missing-asset", {
      mock_results: { "https://example.com/missing-asset" => mock_item }
    })

    res = analyzer.analyze
    item = res[:all_results].first

    assert_equal 404, item[:status_code]
    assert_equal :hard_404, item[:classification]
    refute item[:is_soft_404]
  end

  def test_healthy_page_evaluation
    mock_item = {
      url: "https://example.com/guide",
      status_code: 200,
      latency_ms: 110.0,
      body_size_bytes: 25400,
      word_count: 850,
      title: "Complete Technical SEO Architecture Guide",
      h1: "Technical SEO Guide",
      meta_robots: "",
      classification: :healthy_200,
      is_soft_404: false,
      suggested_action: "Optimal — verified healthy",
      suggested_redirect: "/",
      remediation_rules: {}
    }

    analyzer = GSC::Soft404Analyzer.new("https://example.com/guide", {
      mock_results: { "https://example.com/guide" => mock_item }
    })

    res = analyzer.analyze
    item = res[:all_results].first

    assert_equal 200, item[:status_code]
    assert_equal :healthy_200, item[:classification]
    refute item[:is_soft_404]
    assert_equal 100.0, res[:health_score]
    assert_equal 'A', res[:grade]
  end

  def test_batch_health_score_and_crawl_waste_calculation
    urls = ["https://example.com/page1", "https://example.com/page2"]
    analyzer = GSC::Soft404Analyzer.new(urls, {
      mock_results: {
        "https://example.com/page1" => { url: "https://example.com/page1", status_code: 200, classification: :healthy_200, is_soft_404: false },
        "https://example.com/page2" => { url: "https://example.com/page2", status_code: 404, classification: :hard_404, is_soft_404: false }
      }
    })
    res = analyzer.analyze

    assert_equal 2, res[:total_urls_audited]
    assert res[:summary].key?(:crawl_budget_waste_percent)
    assert res[:summary].key?(:healthy_count)
    assert_operator res[:health_score], :>=, 0.0
    assert_operator res[:health_score], :<=, 100.0
  end

  def test_multi_framework_remediation_rules
    analyzer = GSC::Soft404Analyzer.new("https://example.com/broken-link")
    rules = analyzer.send(:generate_server_rules, "https://example.com/broken-link", "/")

    assert_includes rules[:nginx], "rewrite ^/broken-link/?$ / permanent;"
    assert_includes rules[:caddy], "redir /broken-link / 301"
    assert_includes rules[:htaccess], "Redirect 301 /broken-link /"
    assert_includes rules[:cloudflare], "/broken-link / 301"
    assert_includes rules[:cloudflare_workers], "Response.redirect"
    assert_includes rules[:github_pages], "http-equiv=\"refresh\""
    assert_includes rules[:sveltekit], "redirect(301, '/')"
    assert_includes rules[:astro], "'/broken-link': '/'"
    assert_includes rules[:gatsby], "createRedirect({ fromPath: '/broken-link', toPath: '/', isPermanent: true })"
    assert_includes rules[:nextjs], "{ source: '/broken-link', destination: '/', permanent: true }"
    assert_includes rules[:webflow], "Old Path: /broken-link  ->  Redirect to Page: /"
    assert_includes rules[:shopify], "/broken-link,/"
  end

  def test_tech_stack_detection
    analyzer = GSC::Soft404Analyzer.new("https://example.com")

    # SvelteKit
    svelte = analyzer.send(:detect_tech_stack, { 'x-sveltekit-page' => 'true', 'server' => 'cloudflare' }, "")
    assert_equal 'SvelteKit', svelte[:framework]
    assert_equal 'sveltekit', svelte[:default_format]

    # Astro
    astro = analyzer.send(:detect_tech_stack, {}, '<div class="astro-XYZ123">hello</div>')
    assert_equal 'Astro', astro[:framework]
    assert_equal 'astro', astro[:default_format]

    # Gatsby
    gatsby = analyzer.send(:detect_tech_stack, {}, '<div id="___gatsby"></div>')
    assert_equal 'Gatsby', gatsby[:framework]
    assert_equal 'gatsby', gatsby[:default_format]

    # Next.js
    nextjs = analyzer.send(:detect_tech_stack, { 'x-powered-by' => 'Next.js' }, '')
    assert_equal 'Next.js', nextjs[:framework]
    assert_equal 'nextjs', nextjs[:default_format]

    # Webflow
    webflow = analyzer.send(:detect_tech_stack, {}, '<html class="w-mod-js"><meta name="generator" content="Webflow"></html>')
    assert_equal 'Webflow', webflow[:framework]
    assert_equal 'webflow', webflow[:default_format]

    # Caddy
    caddy = analyzer.send(:detect_tech_stack, { 'server' => 'caddy' }, '')
    assert_equal 'Caddy', caddy[:framework]
    assert_equal 'caddy', caddy[:default_format]
  end
end

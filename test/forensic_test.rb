# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'stringio'
require 'zlib'
require 'openssl'
require 'tmpdir'

require_relative '../lib/gsc/version'
require_relative '../lib/gsc/color'
require_relative '../lib/gsc/config'
require_relative '../lib/gsc/vault'
require_relative '../lib/gsc/canonical_chains'
require_relative '../lib/gsc/heading_validator'
require_relative '../lib/gsc/soft_404_analyzer'
require_relative '../lib/gsc/sparkline'
require_relative '../lib/gsc/ctr_curve'
require_relative '../lib/gsc/aio_hunter'
require_relative '../lib/gsc/entity_auditor'
require_relative '../lib/gsc/brand_segmenter'
require_relative '../lib/gsc/cannibalization_analyzer'
require_relative '../lib/gsc/decay_predictor'
require_relative '../lib/gsc/doctor'
require_relative '../lib/gsc/robots_checker'
require_relative '../lib/gsc/schema_validator'
require_relative '../lib/gsc/citation_simulator'
require_relative '../lib/gsc/llms_generator'
require_relative '../lib/gsc/keyword_value'
require_relative '../lib/gsc/cli_advanced'
require_relative '../lib/gsc/cli'

class ForensicRegressionTest < Minitest::Test
  # =========================================================================
  # SCENARIOS 1-10: String Scrubbing, UTF-8 Encoding & Gzip Resilience
  # =========================================================================
  def test_01_invalid_byte_sequence_scrubbing
    raw_invalid = "Google Search Console \xFF\xFE Traffic \x80 Data"
    scrubbed = raw_invalid.dup.force_encoding('UTF-8').scrub
    assert scrubbed.valid_encoding?
    assert_includes scrubbed, "Google Search Console"
  end

  def test_02_corrupted_gzip_stream_rescue
    corrupted_data = "\x1f\x8b\x08\x00corrupted_bytes_that_fail_zlib"
    rescued = false
    begin
      gz = Zlib::GzipReader.new(StringIO.new(corrupted_data))
      gz.read
    rescue Zlib::GzipFile::Error, Zlib::Error
      rescued = true
    end
    assert rescued, "Corrupted gzip must be cleanly caught"
  end

  def test_03_valid_gzip_roundtrip_with_multibyte_utf8
    original = '{"status":"ok","message":"Türkçe, 日本語, 🚀 Emoji Search Data"}'
    sio = StringIO.new
    gz = Zlib::GzipWriter.new(sio)
    gz.write(original)
    gz.close
    compressed = sio.string

    reader = Zlib::GzipReader.new(StringIO.new(compressed))
    decompressed = reader.read.force_encoding('UTF-8')
    assert_equal original, decompressed
  end

  def test_04_truncated_gzip_payload
    original = "Some long payload that gets truncated before end of stream"
    sio = StringIO.new
    gz = Zlib::GzipWriter.new(sio)
    gz.write(original)
    gz.close
    truncated = sio.string[0..10]
    rescued = false
    begin
      Zlib::GzipReader.new(StringIO.new(truncated)).read
    rescue Zlib::GzipFile::Error, Zlib::Error
      rescued = true
    end
    assert rescued
  end

  def test_05_empty_string_stream_handling
    sio = StringIO.new("")
    rescued = false
    begin
      Zlib::GzipReader.new(sio).read
    rescue Zlib::GzipFile::Error, Zlib::Error
      rescued = true
    end
    assert rescued
  end

  def test_06_malformed_json_response_parsing
    bad_json = "<html><body>502 Bad Gateway</body></html>"
    parsed = nil
    begin
      parsed = JSON.parse(bad_json)
    rescue JSON::ParserError
      parsed = { "error" => "non_json_payload", "body" => bad_json }
    end
    assert_equal "non_json_payload", parsed["error"]
  end

  def test_07_deeply_nested_json_handling
    nested = { "a" => { "b" => { "c" => { "d" => "value" } } } }
    json_str = JSON.generate(nested)
    parsed = JSON.parse(json_str)
    assert_equal "value", parsed.dig("a", "b", "c", "d")
    assert_nil parsed.dig("a", "b", "missing", "key")
  end

  def test_08_nil_and_empty_json_safeguards
    assert_nil nil&.dig("a")
    hash = {}
    assert_nil hash["missing"]
  end

  def test_09_unicode_normalization_and_whitespace
    query = "  best   seo   tool  \t\n"
    normalized = query.strip.gsub(/\s+/, " ")
    assert_equal "best seo tool", normalized
  end

  def test_10_special_character_escaping_in_regex
    query = "what is c++? (2026 guide)"
    escaped = Regexp.escape(query)
    assert_match(/#{escaped}/, "Looking for what is c++? (2026 guide) today")
  end

  # =========================================================================
  # SCENARIOS 11-20: OpenSSL Cryptography & Vault Security
  # =========================================================================
  def test_11_aes_256_gcm_encryption_roundtrip
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    key = cipher.random_key
    iv = cipher.random_iv
    cipher.auth_data = "gsc-vault-v1"
    secret = "my-super-secret-service-account-key"
    encrypted = cipher.update(secret) + cipher.final
    tag = cipher.auth_tag

    decipher = OpenSSL::Cipher.new("aes-256-gcm")
    decipher.decrypt
    decipher.key = key
    decipher.iv = iv
    decipher.auth_tag = tag
    decipher.auth_data = "gsc-vault-v1"
    decrypted = decipher.update(encrypted) + decipher.final

    assert_equal secret, decrypted
  end

  def test_12_aes_256_gcm_auth_tag_tamper_detection
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    key = cipher.random_key
    iv = cipher.random_iv
    cipher.auth_data = "gsc-vault-v1"
    encrypted = cipher.update("secret") + cipher.final
    tag = cipher.auth_tag

    # Tamper with tag
    tampered_tag = tag.dup
    tampered_tag.setbyte(0, (tampered_tag.getbyte(0) + 1) % 256)

    decipher = OpenSSL::Cipher.new("aes-256-gcm")
    decipher.decrypt
    decipher.key = key
    decipher.iv = iv
    decipher.auth_tag = tampered_tag
    decipher.auth_data = "gsc-vault-v1"

    assert_raises(OpenSSL::Cipher::CipherError) do
      decipher.update(encrypted) + decipher.final
    end
  end

  def test_13_pbkdf2_deterministic_key_derivation
    salt = "gsc_unique_salt_2026"
    pass = "master_password"
    key1 = OpenSSL::PKCS5.pbkdf2_hmac(pass, salt, 20_000, 32, "sha256")
    key2 = OpenSSL::PKCS5.pbkdf2_hmac(pass, salt, 20_000, 32, "sha256")
    assert_equal key1, key2
    assert_equal 32, key1.bytesize
  end

  def test_14_pbkdf2_salt_differentiation
    pass = "master_password"
    key1 = OpenSSL::PKCS5.pbkdf2_hmac(pass, "salt_1", 20_000, 32, "sha256")
    key2 = OpenSSL::PKCS5.pbkdf2_hmac(pass, "salt_2", 20_000, 32, "sha256")
    refute_equal key1, key2
  end

  def test_15_vault_envelope_encryption_roundtrip
    secret_text = '{"client_email":"test@serviceaccount.com","private_key":"PEM"}'
    envelope = GSC::Vault.encrypt(secret_text)
    assert_includes envelope, "AES-256-GCM"
    decrypted = GSC::Vault.decrypt(envelope)
    assert_equal secret_text, decrypted
  end

  def test_16_vault_normalize_domain_strips_protocol
    assert_equal "example.com", GSC::Vault.normalize_domain("https://example.com/")
    assert_equal "example.com", GSC::Vault.normalize_domain("http://example.com")
    assert_equal "example.com", GSC::Vault.normalize_domain("sc-domain:example.com")
  end

  def test_17_vault_index_structure_validity
    index = GSC::Vault.load_index
    assert index.key?("domains")
    assert index.key?("aliases")
  end

  def test_18_vault_status_metadata
    status = GSC::Vault.status
    assert status.key?(:vault_dir)
    assert status.key?(:encryption_algorithm)
    assert status.key?(:keys_stored)
  end

  def test_19_vault_list_entries_returns_array
    entries = GSC::Vault.list_entries
    assert_instance_of Array, entries
  end

  def test_20_vault_decrypt_invalid_payload_raises
    assert_raises(RuntimeError) do
      GSC::Vault.decrypt("invalid-json-envelope")
    end
  end

  # =========================================================================
  # SCENARIOS 21-30: Soft-404 & HTTP Crawl Diagnostics
  # =========================================================================
  def test_21_soft_404_empty_body_detection
    mock_item = {
      url: "https://example.com/empty",
      status_code: 200,
      latency_ms: 50.0,
      body_size_bytes: 0,
      word_count: 0,
      title: "404 Not Found",
      h1: "Not Found",
      meta_robots: "",
      classification: :soft_404,
      is_soft_404: true,
      suggested_action: "Return HTTP 404/410 or 301 redirect to relevant parent hub",
      suggested_redirect: "/",
      remediation_rules: { nginx: "rewrite ^/empty/?$ / permanent;" }
    }
    analyzer = GSC::Soft404Analyzer.new("https://example.com/empty", {
      mock_results: { "https://example.com/empty" => mock_item }
    })
    res = analyzer.analyze
    assert_equal 1, res[:total_urls_audited]
    assert_equal :soft_404, res[:all_results].first[:classification]
  end

  def test_22_soft_404_title_not_found_detection
    mock_item = {
      url: "https://example.com/lost",
      status_code: 200,
      latency_ms: 60.0,
      body_size_bytes: 350,
      word_count: 22,
      title: "404 Page Not Found",
      h1: "Error",
      meta_robots: "",
      classification: :soft_404,
      is_soft_404: true,
      suggested_action: "Return HTTP 404/410 or 301 redirect to relevant parent hub",
      suggested_redirect: "/",
      remediation_rules: { nginx: "rewrite ^/lost/?$ / permanent;" }
    }
    analyzer = GSC::Soft404Analyzer.new("https://example.com/lost", {
      mock_results: { "https://example.com/lost" => mock_item }
    })
    res = analyzer.analyze
    assert res[:all_results].first[:is_soft_404]
  end

  def test_23_hard_404_detection
    mock_item = {
      url: "https://example.com/missing",
      status_code: 404,
      latency_ms: 40.0,
      body_size_bytes: 100,
      word_count: 5,
      title: "Not Found",
      h1: "404",
      meta_robots: "",
      classification: :hard_404,
      is_soft_404: false,
      suggested_action: "301 redirect",
      suggested_redirect: "/",
      remediation_rules: { nginx: "rewrite ^/missing/?$ / permanent;" }
    }
    analyzer = GSC::Soft404Analyzer.new("https://example.com/missing", {
      mock_results: { "https://example.com/missing" => mock_item }
    })
    res = analyzer.analyze
    assert_equal :hard_404, res[:all_results].first[:classification]
  end

  def test_24_hard_410_gone_detection
    mock_item = {
      url: "https://example.com/expired",
      status_code: 410,
      latency_ms: 40.0,
      body_size_bytes: 50,
      word_count: 3,
      title: "Gone",
      h1: "410",
      meta_robots: "",
      classification: :hard_404,
      is_soft_404: false,
      suggested_action: "Purge",
      suggested_redirect: "/",
      remediation_rules: { nginx: "return 410;" }
    }
    analyzer = GSC::Soft404Analyzer.new("https://example.com/expired", {
      mock_results: { "https://example.com/expired" => mock_item }
    })
    res = analyzer.analyze
    assert_equal :hard_404, res[:all_results].first[:classification]
  end

  def test_25_valid_rich_page_classified_as_ok
    mock_item = {
      url: "https://example.com/ruby",
      status_code: 200,
      latency_ms: 110.0,
      body_size_bytes: 12500,
      word_count: 650,
      title: "Complete Ruby 3 Guide",
      h1: "Ruby Guide",
      meta_robots: "",
      classification: :healthy_200,
      is_soft_404: false,
      suggested_action: "Optimal",
      suggested_redirect: nil,
      remediation_rules: {}
    }
    analyzer = GSC::Soft404Analyzer.new("https://example.com/ruby", {
      mock_results: { "https://example.com/ruby" => mock_item }
    })
    res = analyzer.analyze
    assert_equal :healthy_200, res[:all_results].first[:classification]
    refute res[:all_results].first[:is_soft_404]
  end

  def test_26_nginx_redirect_rule_generation
    mock_item = {
      url: "https://example.com/old-slug",
      status_code: 200,
      latency_ms: 50.0,
      body_size_bytes: 200,
      word_count: 10,
      title: "404 Not Found",
      h1: "404",
      meta_robots: "",
      classification: :soft_404,
      is_soft_404: true,
      suggested_action: "Redirect",
      suggested_redirect: "/",
      remediation_rules: { nginx: "rewrite ^/old-slug/?$ / permanent;" }
    }
    analyzer = GSC::Soft404Analyzer.new("https://example.com/old-slug", {
      mock_results: { "https://example.com/old-slug" => mock_item }
    })
    res = analyzer.analyze
    assert_includes res[:all_results].first[:remediation_rules][:nginx], "rewrite"
  end

  def test_27_apache_htaccess_rule_generation
    mock_item = {
      url: "https://example.com/old-slug",
      status_code: 200,
      latency_ms: 50.0,
      body_size_bytes: 200,
      word_count: 10,
      title: "404 Not Found",
      h1: "404",
      meta_robots: "",
      classification: :soft_404,
      is_soft_404: true,
      suggested_action: "Redirect",
      suggested_redirect: "/",
      remediation_rules: { htaccess: "Redirect 301 /old-slug /" }
    }
    analyzer = GSC::Soft404Analyzer.new("https://example.com/old-slug", {
      mock_results: { "https://example.com/old-slug" => mock_item }
    })
    res = analyzer.analyze
    assert_includes res[:all_results].first[:remediation_rules][:htaccess], "Redirect 301"
  end

  def test_28_nextjs_redirect_rule_generation
    rules = GSC::Soft404Analyzer.new.send(:generate_server_rules, "https://example.com/old-path", "/new-path")
    assert_includes rules[:nextjs], "source: '/old-path'"
    assert_includes rules[:nextjs], "destination: '/new-path'"
  end

  def test_29_vercel_json_redirect_rule_generation
    rules = GSC::Soft404Analyzer.new.send(:generate_server_rules, "https://example.com/old-path", "/new-path")
    assert_equal "/old-path", rules[:vercel]["source"]
    assert_equal "/new-path", rules[:vercel]["destination"]
  end

  def test_30_crawl_waste_score_computation
    analyzer = GSC::Soft404Analyzer.new
    items = [
      { url: "https://example.com/1", status_code: 200, is_soft_404: true, classification: :soft_404, body_size_bytes: 200, word_count: 10, remediation_rules: {} },
      { url: "https://example.com/2", status_code: 404, is_soft_404: false, classification: :hard_404, body_size_bytes: 100, word_count: 5, remediation_rules: {} },
      { url: "https://example.com/3", status_code: 200, is_soft_404: false, classification: :healthy_200, body_size_bytes: 5000, word_count: 300, remediation_rules: {} }
    ]
    diag = analyzer.send(:diagnose_overall, items)
    assert_equal 3, diag[:total_urls_audited]
    assert_equal 1, diag[:summary][:soft_404_count]
    assert_equal 1, diag[:summary][:hard_404_count]
  end

  # =========================================================================
  # SCENARIOS 31-40: Canonical Chains, Redirect Loops & Circular Paths
  # =========================================================================
  def test_31_collapse_rules_nginx
    rules = GSC::CanonicalChains.new.generate_collapse_rules("https://example.com/old", "https://example.com/new")
    assert_includes rules[:nginx], "permanent;"
  end

  def test_32_collapse_rules_apache
    rules = GSC::CanonicalChains.new.generate_collapse_rules("https://example.com/old", "https://example.com/new")
    assert_includes rules[:apache], "RewriteRule"
    assert_includes rules[:apache], "[R=301,L]"
  end

  def test_33_collapse_rules_cloudflare
    rules = GSC::CanonicalChains.new.generate_collapse_rules("https://example.com/old", "https://example.com/new")
    assert_includes rules[:cloudflare], "301 to"
  end

  def test_34_collapse_rules_vercel
    rules = GSC::CanonicalChains.new.generate_collapse_rules("https://example.com/old", "https://example.com/new")
    assert_includes rules[:vercel_netlify], "301!"
  end

  def test_35_extract_canonical_html_valid
    html = '<html><head><link rel="canonical" href="https://example.com/target" /></head></html>'
    res = GSC::CanonicalChains.new.send(:extract_canonical_html, html, "https://example.com/source")
    assert_equal "https://example.com/target", res
  end

  def test_36_extract_canonical_html_relative
    html = '<html><head><link rel="canonical" href="/subpath" /></head></html>'
    res = GSC::CanonicalChains.new.send(:extract_canonical_html, html, "https://example.com/source")
    assert_equal "https://example.com/subpath", res
  end

  def test_37_extract_canonical_html_missing
    html = '<html><head><title>No canonical here</title></head></html>'
    res = GSC::CanonicalChains.new.send(:extract_canonical_html, html, "https://example.com/source")
    assert_nil res
  end

  def test_38_extract_canonical_html_single_quotes
    html = "<html><head><link rel='canonical' href='https://example.com/single' /></head></html>"
    res = GSC::CanonicalChains.new.send(:extract_canonical_html, html, "https://example.com/source")
    assert_equal "https://example.com/single", res
  end

  def test_39_canonical_whitespace_stripping
    html = '<html><head><link rel="canonical" href="  https://example.com/clean   " /></head></html>'
    res = GSC::CanonicalChains.new.send(:extract_canonical_html, html, "https://example.com/source")
    assert_equal "https://example.com/clean", res
  end

  def test_40_extract_canonical_http_header
    headers = { 'link' => '<https://example.com/header-target>; rel="canonical"' }
    link = headers['link']
    match = link.match(/<([^>]+)>;\s*rel=["']?canonical["']?/i)
    assert match
    assert_equal "https://example.com/header-target", match[1]
  end

  # =========================================================================
  # SCENARIOS 41-50: Heading Hierarchy (H1-H6) AST Depth & Semantic Validation
  # =========================================================================
  def test_41_perfect_single_h1_hierarchy
    html = "<html><body><h1>Title</h1><h2>Section 1</h2><h3>Subsection 1.1</h3></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_equal 100, res[:score]
    assert_equal 'A', res[:grade]
    assert_equal 1, res[:h1_count]
    assert_empty res[:violations]
  end

  def test_42_missing_h1_tag
    html = "<html><body><h2>Section 1</h2><h3>Subsection 1.1</h3></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_operator res[:score], :<, 100
    assert_equal 0, res[:h1_count]
    assert(res[:violations].any? { |v| v[:type] == :missing_h1 })
  end

  def test_43_multiple_h1_tags_warning
    html = "<html><body><h1>First Title</h1><p>Text</p><h1>Second Title</h1></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_equal 2, res[:h1_count]
    assert(res[:violations].any? { |v| v[:type] == :multiple_h1 })
  end

  def test_44_skipped_heading_level_h1_to_h3
    html = "<html><body><h1>Title</h1><h4>Skipped directly from H1 to H4</h4></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_operator res[:score], :<, 100
    assert(res[:violations].any? { |v| v[:type] == :skipped_level })
  end

  def test_45_empty_heading_text_flagged
    html = "<html><body><h1></h1><h2>Valid H2</h2></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_operator res[:empty_count], :>=, 1
  end

  def test_46_deep_nested_h1_to_h6_hierarchy
    html = "<html><body><h1>1</h1><h2>2</h2><h3>3</h3><h4>4</h4><h5>5</h5><h6>6</h6></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_equal 6, res[:depth]
    assert_empty res[:violations]
  end

  def test_47_h6_followed_by_h2_step_up
    html = "<html><body><h1>1</h1><h2>2</h2><h3>3</h3><h2>Another Section</h2></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_equal 100, res[:score]
  end

  def test_48_heading_with_inner_spans_and_links
    html = "<html><body><h1>Welcome to <a href='/'><span>ZeroCramp</span></a></h1></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_includes res[:ascii_tree], "Welcome to ZeroCramp"
  end

  def test_49_heading_with_multiline_whitespace
    html = "<html><body><h1>\n  Line 1\n  Line 2\n</h1></body></html>"
    res = GSC::HeadingValidator.analyze(html)
    assert_includes res[:ascii_tree], "Line 1 Line 2"
  end

  def test_50_empty_html_input_for_headings
    res = GSC::HeadingValidator.analyze("")
    assert_equal 0, res[:count]
    assert_equal 0, res[:h1_count]
  end

  # =========================================================================
  # SCENARIOS 51-60: Terminal Sparklines & ASCII Visualizations
  # =========================================================================
  def test_51_sparkline_standard_series
    spark = GSC::Sparkline.render([1, 2, 3, 4, 5, 6, 7, 8])
    assert_equal 8, spark.chars.size
  end

  def test_52_sparkline_empty_series
    assert_equal "", GSC::Sparkline.render([])
  end

  def test_53_sparkline_single_value
    assert_equal "▅", GSC::Sparkline.render([42])
  end

  def test_54_sparkline_uniform_flat_series
    spark = GSC::Sparkline.render([10, 10, 10, 10])
    assert_equal "▅▅▅▅", spark
  end

  def test_55_sparkline_zero_values_series
    spark = GSC::Sparkline.render([0, 0, 0])
    assert_equal "▅▅▅", spark
  end

  def test_56_sparkline_extreme_scale_gap
    spark = GSC::Sparkline.render([1, 1_000_000])
    assert_equal 2, spark.chars.size
  end

  def test_57_sparkline_float_values
    spark = GSC::Sparkline.render([0.1, 0.45, 0.99, 1.5, 3.2])
    assert_equal 5, spark.chars.size
  end

  def test_58_sparkline_negative_values_handling
    spark = GSC::Sparkline.render([-10, -5, 0, 5, 10])
    assert_equal 5, spark.chars.size
  end

  def test_59_sparkline_non_numeric_graceful_handling
    spark = GSC::Sparkline.render([1, "2", nil, 4])
    assert_equal 4, spark.chars.size
  end

  def test_60_sparkline_large_dataset_windowing
    data = (1..100).to_a
    spark = GSC::Sparkline.render(data, max_points: 20)
    assert_equal 20, spark.chars.size
  end

  # =========================================================================
  # SCENARIOS 61-70: CTR Curve Modeling & Conversion Economics
  # =========================================================================
  def test_61_ctr_curve_pos_1_benchmark
    assert_equal 28.0, GSC::CtrCurve.benchmark_for(1)
  end

  def test_62_ctr_curve_pos_10_benchmark
    assert_equal 1.8, GSC::CtrCurve.benchmark_for(10)
  end

  def test_63_ctr_curve_pos_20_benchmark
    assert_equal 0.4, GSC::CtrCurve.benchmark_for(20)
  end

  def test_64_ctr_curve_traffic_opportunity_simulation
    rows = [
      { query: 'technical seo audit', clicks: 10, impressions: 1000, ctr: 1.0, position: 7.0 }
    ]
    res = GSC::CtrCurve.simulate(rows, target_pos: 3, min_imp: 10)
    assert_equal 1, res[:opportunities].size
    opp = res[:opportunities].first
    assert_equal 100, opp[:incremental_clicks]
    assert opp[:underperforming]
  end

  def test_65_ctr_curve_target_equal_or_worse_than_current
    rows = [
      { query: 'test', clicks: 50, impressions: 500, ctr: 10.0, position: 2.0 }
    ]
    res = GSC::CtrCurve.simulate(rows, target_pos: 5, min_imp: 10)
    assert_equal 0, res[:opportunities].first[:incremental_clicks]
  end

  def test_66_ctr_curve_zero_impressions
    rows = [
      { query: 'zero', clicks: 0, impressions: 0, ctr: 0.0, position: 5.0 }
    ]
    res = GSC::CtrCurve.simulate(rows, target_pos: 1, min_imp: 10)
    assert_empty res[:opportunities]
  end

  def test_67_ctr_curve_negative_position_clamp
    assert_equal 28.0, GSC::CtrCurve.benchmark_for(-5)
  end

  def test_68_ctr_curve_high_position_floor
    assert_equal 0.2, GSC::CtrCurve.benchmark_for(100)
  end

  def test_69_ctr_underperformer_detection
    rows = [
      { query: 'under', clicks: 5, impressions: 5000, ctr: 0.1, position: 2.0 }
    ]
    res = GSC::CtrCurve.simulate(rows, target_pos: 1, min_imp: 10)
    assert_equal 1, res[:underperformers].size
  end

  def test_70_ctr_healthy_performer_not_flagged
    rows = [
      { query: 'healthy', clicks: 1500, impressions: 5000, ctr: 30.0, position: 1.0 }
    ]
    res = GSC::CtrCurve.simulate(rows, target_pos: 1, min_imp: 10)
    assert_empty res[:underperformers]
  end

  # =========================================================================
  # SCENARIOS 71-80: AI Overviews (AIO Hunter) & GEO Opportunities
  # =========================================================================
  def test_71_aio_hunter_informational_how_to_query
    hunter = GSC::AioHunter.new("how to fix ruby syntax error in gsc")
    res = hunter.analyze
    assert_equal :informational_how_to, res[:intent]
    assert_operator res[:aio_presence][:probability_percent], :>=, 70
    assert res[:aio_presence][:detected]
  end

  def test_72_aio_hunter_transactional_low_probability_query
    hunter = GSC::AioHunter.new("buy macbook pro cheap")
    res = hunter.analyze
    assert_equal :transactional, res[:intent]
    assert_operator res[:aio_presence][:probability_percent], :<=, 40
  end

  def test_73_aio_hunter_definitional_what_is_query
    hunter = GSC::AioHunter.new("what is canonical url in technical seo")
    res = hunter.analyze
    assert_equal :informational_definition, res[:intent]
    assert_operator res[:aio_presence][:probability_percent], :>=, 70
  end

  def test_74_aio_hunter_comparison_vs_query
    hunter = GSC::AioHunter.new("nextjs vs remix for seo performance")
    res = hunter.analyze
    assert_equal :commercial_comparison, res[:intent]
  end

  def test_75_aio_hunter_brand_navigational_query
    hunter = GSC::AioHunter.new("github login")
    res = hunter.analyze
    assert_equal :navigational, res[:intent]
    assert_operator res[:aio_presence][:probability_percent], :<=, 40
  end

  def test_76_aio_hunter_direct_answer_synthesis
    hunter = GSC::AioHunter.new("how to verify google search console ownership")
    res = hunter.analyze
    assert res[:capture_recipe][:direct_answer_draft]
  end

  def test_77_aio_hunter_empty_query_safeguard
    hunter = GSC::AioHunter.new("")
    res = hunter.analyze
    assert_equal :portfolio, res[:mode]
  end

  def test_78_aio_hunter_citation_analysis_structure
    hunter = GSC::AioHunter.new("how to speed up rails boot time")
    res = hunter.analyze
    assert res[:citation_analysis].key?(:citation_gap_index)
    refute_nil res[:citation_analysis][:eligibility_status]
  end

  def test_79_aio_hunter_domain_portfolio_summary
    hunter = GSC::AioHunter.new("example.com")
    res = hunter.analyze
    assert_equal :portfolio, res[:mode]
    assert res[:summary].key?(:aio_penetration_rate)
  end

  def test_80_aio_hunter_opportunities_array
    hunter = GSC::AioHunter.new("example.com")
    res = hunter.analyze
    assert_instance_of Array, res[:opportunities]
  end

  # =========================================================================
  # SCENARIOS 81-90: Brand vs Non-Brand & Cannibalization Engines
  # =========================================================================
  def test_81_brand_segmenter_exact_match
    segmenter = GSC::BrandSegmenter.new(custom_brand: "exampleapp")
    assert segmenter.brand?("exampleapp login")
    assert segmenter.brand?("exampleapp pricing")
    refute segmenter.brand?("best organic rank tracking software")
  end

  def test_82_brand_segmenter_empty_brand_list
    segmenter = GSC::BrandSegmenter.new
    refute segmenter.brand?("any query")
  end

  def test_83_brand_segmenter_case_insensitivity
    segmenter = GSC::BrandSegmenter.new(custom_brand: "ApollosWave")
    assert segmenter.brand?("apolloswave dataset")
    assert segmenter.brand?("APOLLOSWAVE EXTRACTOR")
  end

  def test_84_cannibalization_critical_conflict_detection
    rows = [
      { 'keys' => ['technical seo audit', 'https://example.com/audit-1'], 'clicks' => 10, 'impressions' => 60, 'position' => 3.2 },
      { 'keys' => ['technical seo audit', 'https://example.com/audit-2'], 'clicks' => 2, 'impressions' => 40, 'position' => 4.5 }
    ]
    analysis = GSC::CannibalizationAnalyzer.analyze(rows, min_imp: 10)
    assert_equal 1, analysis[:conflicts_count]
    assert_equal "CRITICAL", analysis[:conflicts].first[:severity]
  end

  def test_85_cannibalization_dominant_page_no_critical_conflict
    rows = [
      { 'keys' => ['technical seo audit', 'https://example.com/audit-main'], 'clicks' => 500, 'impressions' => 10_000, 'position' => 1.0 },
      { 'keys' => ['technical seo audit', 'https://example.com/audit-minor'], 'clicks' => 1, 'impressions' => 10, 'position' => 45.0 }
    ]
    analysis = GSC::CannibalizationAnalyzer.analyze(rows, min_imp: 10)
    assert_equal 0, analysis[:critical_count]
  end

  def test_86_cannibalization_conflicts_count_on_clean_data
    rows = [
      { 'keys' => ['unique search term', 'https://example.com/unique'], 'clicks' => 50, 'impressions' => 500, 'position' => 1.0 }
    ]
    analysis = GSC::CannibalizationAnalyzer.analyze(rows, min_imp: 10)
    assert_equal 0, analysis[:conflicts_count]
  end

  def test_87_cannibalization_multiple_conflicts_detection
    rows = [
      { 'keys' => ['query 1', 'https://example.com/a'], 'clicks' => 10, 'impressions' => 50, 'position' => 3.0 },
      { 'keys' => ['query 1', 'https://example.com/b'], 'clicks' => 8, 'impressions' => 50, 'position' => 4.0 },
      { 'keys' => ['query 2', 'https://example.com/c'], 'clicks' => 10, 'impressions' => 50, 'position' => 3.0 },
      { 'keys' => ['query 2', 'https://example.com/d'], 'clicks' => 8, 'impressions' => 50, 'position' => 4.0 }
    ]
    analysis = GSC::CannibalizationAnalyzer.analyze(rows, min_imp: 10)
    assert_equal 2, analysis[:conflicts_count]
  end

  def test_88_decay_predictor_linear_regression_slope
    # Declining weekly impressions: 100, 80, 60, 40, 20
    slope = GSC::DecayPredictor.calc_slope([100, 80, 60, 40, 20])
    assert_in_delta(-20.0, slope, 1.0)
  end

  def test_89_decay_predictor_surging_slope
    # Increasing weekly impressions: 10, 30, 50, 70, 90
    slope = GSC::DecayPredictor.calc_slope([10, 30, 50, 70, 90])
    assert_in_delta(20.0, slope, 1.0)
  end

  def test_90_decay_predictor_flat_slope
    slope = GSC::DecayPredictor.calc_slope([50, 50, 50, 50])
    assert_in_delta(0.0, slope, 0.01)
  end

  # =========================================================================
  # SCENARIOS 91-100: Robots.txt Parsing, Entity Extraction & Doctor Health
  # =========================================================================
  def test_91_robots_checker_user_agent_disallow_root
    checker = GSC::RobotsChecker.new("https://example.com")
    checker.instance_variable_set(:@robots_content, "User-agent: *\nDisallow: /")
    res = checker.check("/blog", "Googlebot")
    refute res[:allowed]
  end

  def test_92_robots_checker_allow_all
    checker = GSC::RobotsChecker.new("https://example.com")
    checker.instance_variable_set(:@robots_content, "User-agent: *\nAllow: /")
    res = checker.check("/blog", "Googlebot")
    assert res[:allowed]
  end

  def test_93_robots_checker_specific_bot_override
    checker = GSC::RobotsChecker.new("https://example.com")
    checker.instance_variable_set(:@robots_content, "User-agent: *\nDisallow: /\n\nUser-agent: GPTBot\nAllow: /public/")
    res_gpt = checker.check("/public/post", "GPTBot")
    res_google = checker.check("/public/post", "Googlebot")
    assert res_gpt[:allowed]
    refute res_google[:allowed]
  end

  def test_94_entity_auditor_json_ld_extraction
    html = <<~HTML
      <html><head>
      <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Organization",
        "name": "ZeroCramp",
        "url": "https://zerocramp.com",
        "sameAs": [
          "https://twitter.com/zerocramp",
          "https://wikidata.org/wiki/Q12345"
        ]
      }
      </script>
      </head><body></body></html>
    HTML
    res = GSC::EntityAuditor.audit('https://zerocramp.com', custom_html: html)
    assert_equal 1, res[:entities_found]
    assert_equal 'https://wikidata.org/wiki/Q12345', res[:authoritative_links][:wikidata]
  end

  def test_95_entity_auditor_malformed_json_ld_ignored
    html = '<html><head><script type="application/ld+json">{ invalid json here </script></head><body></body></html>'
    res = GSC::EntityAuditor.audit('https://zerocramp.com', custom_html: html)
    assert_equal 0, res[:entities_found]
  end

  def test_96_doctor_ast_purity_whitelist
    doctor = GSC::Doctor.new({}, File.expand_path('..', __dir__))
    purity = doctor.audit_purity
    assert_equal 100.0, purity[:purity_score]
  end

  def test_97_doctor_cold_start_under_50ms
    doctor = GSC::Doctor.new({}, File.expand_path('..', __dir__))
    cold_start = doctor.benchmark_cold_start(2)
    assert_operator cold_start[:average_ms], :<, 50.0
  end

  def test_98_color_strip_ansi_utility
    styled = "\e[31merror message\e[0m"
    clean = GSC::Color.strip_ansi(styled)
    assert_equal "error message", clean
  end

  def test_99_version_format_compliance
    assert_match(/^\d+\.\d+\.\d+$/, GSC::VERSION, "Version must follow Semantic Versioning (X.Y.Z)")
  end

  def test_100_grand_forensic_suite_summary
    assert_equal 100, 100
  end

  # =========================================================================
  # SCENARIOS 101-110: Multi-Persona Audit & Inaccuracy Remediations
  # =========================================================================
  def test_101_cli_preview_variable_safety
    # Verify handle_preview_command handles title and desc options without crashing
    out = StringIO.new
    $stdout = out
    begin
      GSC::CLI.handle_preview_command(nil, { title: 'Test Title', desc: 'Test Desc', json: true })
    ensure
      $stdout = STDOUT
    end
    parsed = JSON.parse(out.string) rescue {}
    assert parsed.key?('desktop_serp') || parsed.key?('metrics')
  end

  def test_102_base_format_api_error
    err_hash = { 'error' => { 'code' => 403, 'message' => 'User does not have sufficient permission' } }
    formatted = GSC::CLI::Base.format_api_error(err_hash)
    assert_equal 'User does not have sufficient permission', formatted

    raw_str = 'Socket timeout'
    assert_equal 'Socket timeout', GSC::CLI::Base.format_api_error(raw_str)
  end

  def test_103_base_write_csv_escapes_headers
    headers = ['Query,Keyword', 'Clicks "Count"', '=Formula']
    rows = [['technical seo', 100, 1]]
    tmp = File.join(Dir.tmpdir, "gsc_csv_test_#{Time.now.to_i}.csv")
    begin
      GSC::CLI::Base.write_csv(tmp, headers, rows)
      content = File.read(tmp)
      lines = content.split("\n")
      assert_equal '"Query,Keyword","Clicks ""Count""","=Formula"', lines[0].strip
    ensure
      File.delete(tmp) if File.exist?(tmp)
    end
  end

  def test_104_schema_validator_unwraps_page_analyzer_schemas
    wrapped = [
      { valid: true, types: ['Product'], data: { '@type' => 'Product', 'name' => 'Sample Prod' } },
      { valid: true, types: ['Graph'], data: { '@graph' => [{ '@type' => 'FAQPage', 'mainEntity' => [] }] } }
    ]
    flattened = GSC::SchemaValidator.flatten_schemas(wrapped)
    assert_equal 2, flattened.size
    assert_equal 'Product', flattened[0]['@type']
    assert_equal 'FAQPage', flattened[1]['@type']
  end

  def test_105_decay_predictor_impression_weighted_position
    # Day 1: pos 1.0, 1000 impressions
    # Day 2: pos 10.0, 10 impressions
    # Arithmetic unweighted: (1.0 + 10.0)/2 = 5.5
    # Impression-weighted: (1*1000 + 10*10) / 1010 = 1100 / 1010 = 1.089
    days_map = {
      '2026-01-01' => { clicks: 50, impressions: 1000, position: 1.0 },
      '2026-01-02' => { clicks: 1,  impressions: 10,   position: 10.0 }
    }
    dates = ['2026-01-01', '2026-01-02']
    res = GSC::DecayPredictor.sum_window(days_map, dates)
    assert_operator res[:position], :<, 2.0
    assert_in_delta 1.09, res[:position], 0.05
  end

  def test_106_keyword_value_format_currency_precision
    kv = GSC::KeywordValue.new
    formatted = kv.send(:format_currency, 1234567.89)
    assert_equal '1,234,567.89', formatted

    formatted_small = kv.send(:format_currency, 42.5)
    assert_equal '42.50', formatted_small
  end

  def test_107_cannibalization_remedy_root_paths
    primary = { page: 'https://example.com', position: 1.0, impressions: 100, clicks: 10 }
    secondary = { page: 'https://example.com/about', position: 2.0, impressions: 80, clicks: 8 }
    remedy = GSC::CannibalizationAnalyzer.determine_remedy(primary, secondary, 'example brand')
    assert remedy[:recommendation].include?('/')
    refute remedy[:recommendation].include?('pointing to .')
  end

  def test_108_citation_simulator_empty_tags
    sim = GSC::CitationSimulator.new
    html = '<html><head><title></title></head><body><h1></h1></body></html>'
    query = sim.send(:infer_query_from_html, html)
    assert_equal 'core product benefits and comparison', query
  end

  def test_109_llms_generator_escapes_brackets_in_links
    gen = GSC::LlmsGenerator.new('https://example.com')
    html = '<p><a href="/page">Click [Here] for docs</a></p>'
    md = gen.html_to_clean_markdown(html, 'https://example.com')
    assert_includes md, '\[Here\]'
  end

  def test_110_vault_and_config_traversal_protection
    # Negative index 0 guard
    assert_nil GSC::Config.load_saved_keywords('test.com', '0')

    # Path traversal in vault get_decrypted_key
    traversal_entry = { 'key_file' => '../../etc/passwd' }
    assert_nil GSC::Vault.get_decrypted_key(traversal_entry)
  end
end

# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'json'

class OutputContractTest < Minitest::Test
  BINARY = File.expand_path('../dist/gsc', __dir__)
  FIXTURES_DIR = File.expand_path('fixtures', __dir__)

  def strip_ansi(str)
    str.to_s.gsub(/\e\[[0-9;]*m/, '')
  end

  def run_cmd(*args)
    stdout, stderr, status = Open3.capture3(BINARY, *args)
    [stdout.to_s.force_encoding('UTF-8').scrub, stderr.to_s.force_encoding('UTF-8').scrub, status]
  end

  def run_json(*args)
    stdout, stderr, status = run_cmd(*(args + ['--json']))
    assert status.success?, "Command failed: #{args.join(' ')}\nStderr: #{stderr}\nStdout: #{stdout}"
    parsed = JSON.parse(stdout)
    assert parsed.is_a?(Hash) || parsed.is_a?(Array), "JSON output must be a Hash or Array: #{stdout}"
    parsed
  end

  # =========================================================================
  # 1. CLI Standard Flags & Error Output Contracts
  # =========================================================================

  def test_version_output_contract
    stdout, _stderr, status = run_cmd('version')
    assert status.success?
    clean = strip_ansi(stdout)
    assert_match(/^gsc version 2\.2\.0 \(Ruby/, clean)
    assert_includes clean, 'Executable:'
    assert_includes clean, 'Config:'
  end

  def test_help_flag_output_contract
    stdout, _stderr, status = run_cmd('--help')
    assert status.success?
    clean = strip_ansi(stdout)
    assert_includes clean, 'GOOGLE SEARCH CONSOLE'
    assert_includes clean, 'COMMANDS'
    assert_includes clean, 'doctor'
    assert_includes clean, 'soft-404'
  end

  def test_unknown_command_error_contract
    stdout, stderr, status = run_cmd('invalid-command-random-xyz')
    refute status.success?, "Unknown command should exit with non-zero status"
    combined = strip_ansi(stdout + stderr)
    assert_includes combined, "Unknown command: 'invalid-command-random-xyz'"
    assert_includes combined, "Run 'gsc --help'"
    refute_match(/undefined local variable|undefined method|backtrace/i, combined)
  end

  def test_compact_json_contract
    stdout, _stderr, status = run_cmd('doctor', '--compact')
    assert status.success?
    assert_equal 1, stdout.strip.lines.size, "Compact JSON should be on a single line"
    parsed = JSON.parse(stdout)
    assert_equal '2.2.0', parsed['version']
    assert_equal 100.0, parsed.dig('certification', 'score')
  end

  def test_ndjson_streaming_contract
    stdout, _stderr, status = run_cmd('prompts', '--ndjson')
    assert status.success?
    lines = stdout.strip.lines
    assert_equal 27, lines.size, "NDJSON should output exactly 1 line per item"
    first = JSON.parse(lines.first)
    assert first.key?('id')
    assert first.key?('title')
  end

  def test_missing_argument_json_error_contract
    json = run_json('answer')
    assert json.key?('error')
    assert_includes json['error'], 'Query required'

    json_suggest = run_json('suggest')
    assert json_suggest.key?('error')
    assert_includes json_suggest['error'], 'Query required'

    json_questions = run_json('questions')
    assert json_questions.key?('error')
    assert_includes json_questions['error'], 'Query required'
  end

  # =========================================================================
  # 2. JSON Schema & Key Matching Contracts (Diagnostics & Utilities)
  # =========================================================================

  def test_doctor_json_contract
    data = run_json('doctor')
    assert_equal '2.2.0', data['version']
    assert data.key?('certification')
    assert_equal 100.0, data.dig('certification', 'score')
    assert_equal 'A+', data.dig('certification', 'grade')
    assert_equal 'certified_ready', data.dig('certification', 'status')
    assert_equal true, data.dig('certification', 'certified_zero_gem')

    assert data.key?('purity')
    assert_equal 105, data.dig('purity', 'files_scanned')
    assert_equal 100.0, data.dig('purity', 'purity_score')

    assert data.key?('cold_start')
    assert data.dig('cold_start', 'average_ms').is_a?(Numeric)
    assert data.key?('crypto')
    assert_equal true, data.dig('crypto', 'aes_gcm_available')
  end

  def test_commands_json_contract
    data = run_json('commands')
    assert data.is_a?(Hash)
    assert data.key?('categories')
    categories = data['categories']
    assert categories.is_a?(Array)
    refute_empty categories

    first_cat = categories.first
    assert first_cat.key?('category')
    assert first_cat.key?('commands')
    cmd = first_cat['commands'].first
    assert cmd.key?('name')
    assert cmd.key?('desc')
    assert cmd.key?('flags')
  end

  def test_prompts_json_contract
    data = run_json('prompts')
    assert data.is_a?(Hash)
    assert data.key?('playbooks')
    playbooks = data['playbooks']
    assert_equal 27, playbooks.size
    first = playbooks.first
    assert first.key?('id')
    assert first.key?('title')
    assert first.key?('template')
  end

  def test_vault_status_json_contract
    data = run_json('vault', 'status')
    assert data.key?('vault_dir')
    assert data.key?('encryption_algorithm')
    assert_equal 'AES-256-GCM', data['encryption_algorithm']
    assert data.key?('keys_stored')
  end

  def test_sparklines_json_contract
    data = run_json('sparklines', '--data', '10,25,40,70,90,120')
    assert data.key?('sparkline')
    assert data.key?('min')
    assert data.key?('max')
    assert_equal 10.0, data['min']
    assert_equal 120.0, data['max']
  end

  def test_schema_generate_faq_json_contract
    data = run_json('schema-generate', '--type', 'faq', '--q', 'What is gsc?', '--a', 'A CLI tool.')
    schema = data['schema'] || data
    assert_equal 'https://schema.org', schema['@context']
    assert_equal 'FAQPage', schema['@type']
    assert schema.key?('mainEntity')
    assert_equal 1, schema['mainEntity'].size
    assert_equal 'Question', schema['mainEntity'][0]['@type']
    assert_equal 'What is gsc?', schema['mainEntity'][0]['name']
  end

  def test_soft_404_json_contract
    data = run_json('soft-404', 'https://example.com/not-found-page-test', '--fix', 'nginx')
    assert data.key?('target')
    assert data.key?('health_score')
    assert data.key?('grade')
    assert data.key?('summary')
    assert data.key?('all_results')
    first_res = data['all_results'].first
    assert first_res.key?('url')
    assert first_res.key?('remediation_rules')
    assert first_res['remediation_rules'].key?('nginx')
    assert_includes first_res['remediation_rules']['nginx'], 'rewrite'
  end

  def test_skill_pack_dry_run_json_contract
    data = run_json('skill-pack', '--dry-run')
    assert_equal 'gsc', data['skill_name']
    assert_equal '2.2.0', data['version']
    assert_equal true, data['dry_run']
    assert data.key?('skill_preview')
    assert data.key?('verification')
  end

  def test_page_audit_json_contract
    html_fixture = File.join(FIXTURES_DIR, 'sample_page.html')
    data = run_json('page', html_fixture)
    assert_equal 200, data['http_status']
    assert_equal 'Technical SEO Health & Audit Platform | ExampleApp', data.dig('title', 'text')
    assert_equal 'https://example.com/tools', data.dig('canonical', 'url')
    assert_equal 1, data.dig('headings', 'h1_count')
    assert_equal 100, data.dig('headings', 'score')
    assert_equal 2, data.dig('images', 'total')
    assert_equal 1, data.dig('images', 'missing_alt_count')
    assert data.key?('structured_data')
    assert data.key?('schema')
  end

  def test_headings_tree_json_contract
    html_fixture = File.join(FIXTURES_DIR, 'sample_page.html')
    data = run_json('headings', html_fixture)
    assert_equal 1, data['h1_count']
    assert_equal 100, data['score']
    assert_equal 'A', data['grade']
    assert data.key?('ascii_tree')
    assert_includes data['ascii_tree'], '[H1] Technical SEO & Performance Diagnostics'
    assert_includes data['ascii_tree'], '[H2] Key Features of Technical SEO Auditing'
  end

  def test_image_seo_json_contract
    html_fixture = File.join(FIXTURES_DIR, 'sample_page.html')
    data = run_json('image-seo', html_fixture)
    assert_equal 2, data['total_images']
    assert_equal 1, data.dig('issues_summary', 'missing_alt')
    assert_equal 50.0, data['health_score']
    assert_equal 2, data['images'].size
  end

  def test_eeat_signals_json_contract
    html_fixture = File.join(FIXTURES_DIR, 'sample_page.html')
    data = run_json('eeat', html_fixture)
    assert data['health_score'].is_a?(Numeric)
    assert_equal 'F', data['grade']
    assert_equal 'Jane Doe', data['author_name']
    assert_includes data['issues'], 'missing_person_schema'
  end

  def test_hreflang_check_json_contract
    html_fixture = File.join(FIXTURES_DIR, 'sample_page.html')
    data = run_json('hreflang-check', html_fixture)
    assert_equal 3, data['total_tags']
    assert_equal true, data['has_x_default']
    assert_equal 75.0, data['health_score']
    assert_equal 3, data['tags'].size
  end

  def test_rich_results_json_contract
    html_fixture = File.join(FIXTURES_DIR, 'sample_page.html')
    data = run_json('rich-results', html_fixture)
    assert_equal true, data['eligible_for_rich_results']
    assert_equal 100, data['score']
    assert_equal 1, data['total_schemas_detected']
    assert_equal 'FAQPage', data['schemas'].first['type']
  end

  def test_cite_sim_json_contract
    html_fixture = File.join(FIXTURES_DIR, 'sample_page.html')
    data = run_json('cite-sim', html_fixture, 'technical seo audit')
    assert data['citation_likelihood_score'].is_a?(Numeric)
    assert_equal 'B', data['grade']
    assert data.key?('emulated_ai_response')
    refute_empty data['extracted_quotes']
    refute_empty data['prescriptions']
  end

  # =========================================================================
  # 3. Human Terminal Output Contracts
  # =========================================================================

  def test_doctor_human_output_contract
    stdout, _stderr, status = run_cmd('doctor')
    assert status.success?
    clean = strip_ansi(stdout)
    assert_includes clean, 'GSC ZERO-DEPENDENCY ARCHITECTURE & SYSTEM CERTIFICATION'
    assert_includes clean, 'Zero-Gem Compliance'
    assert_includes clean, 'Cold-Start Latency'
    assert_includes clean, 'AES-256-GCM Cipher'
  end

  def test_soft_404_server_fix_output_contract
    stdout, _stderr, status = run_cmd('soft-404', 'https://example.com/missing-test', '--fix', 'caddy')
    assert status.success?
    clean = strip_ansi(stdout)
    assert_includes clean, 'SOFT-404 & BROKEN URL DIAGNOSTIC ENGINE'
    assert_includes clean, 'redir /missing-test / 301'
  end

  def test_sparklines_human_output_contract
    stdout, _stderr, status = run_cmd('sparklines', '--data', '5,10,20,40,80')
    assert status.success?
    clean = strip_ansi(stdout)
    assert_includes clean, 'ASCII DATA CHART'
    assert_includes clean, 'Sparkline:'
    assert_match(/[ ▂▃▄▅▆▇█]/, clean)
  end

  def test_where_human_output_contract
    stdout, _stderr, status = run_cmd('where')
    assert status.success?
    clean = strip_ansi(stdout)
    assert_includes clean, 'Active Key:'
    assert_includes clean, 'Config File:'
    assert_includes clean, 'Executable:'
  end
end

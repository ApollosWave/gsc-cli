# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class CacheManagerTest < Minitest::Test
  def setup
    @tmp_dir = File.expand_path('../tmp/test_cache', __dir__)
    FileUtils.rm_rf(@tmp_dir)
    FileUtils.mkdir_p(@tmp_dir)

    @test_db_path = File.join(@tmp_dir, 'test_cache.db')
    @orig_config_dir = ENV['GSC_CONFIG_DIR']
    ENV['GSC_CONFIG_DIR'] = @tmp_dir

    @manager = GSC::CacheManager.new(@test_db_path)
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
    ENV['GSC_CONFIG_DIR'] = @orig_config_dir
  end

  def test_initialization_and_status
    status = @manager.status
    assert_includes %i[sqlite_gem sqlite_cli json], status[:engine]
    assert_equal 0, status[:total_queries]
    assert_equal 0, status[:total_pages]
    assert_empty status[:domains]
  end

  def test_save_and_query_filtering
    sample_queries = [
      { 'keys' => ['seo tools'], 'clicks' => 150, 'impressions' => 1200, 'ctr' => 0.125, 'position' => 2.4 },
      { 'keys' => ['keyword planner'], 'clicks' => 50, 'impressions' => 600, 'ctr' => 0.083, 'position' => 4.1 },
      { 'keys' => ['rank tracker'], 'clicks' => 5, 'impressions' => 80, 'ctr' => 0.062, 'position' => 9.2 }
    ]

    saved = @manager.save_queries_direct('example.com', sample_queries, 30, '2026-09-01')
    assert_equal 3, saved

    # Query without filters
    all_res = @manager.query(domain: 'example.com')
    assert_equal 3, all_res.size
    assert_equal 'seo tools', all_res.first[:query]

    # Query with search text
    search_res = @manager.query(domain: 'example.com', search: 'planner')
    assert_equal 1, search_res.size
    assert_equal 'keyword planner', search_res.first[:query]

    # Query with min_clicks filter
    filtered_res = @manager.query(domain: 'example.com', min_clicks: 60)
    assert_equal 1, filtered_res.size
    assert_equal 'seo tools', filtered_res.first[:query]

    # Query with sort by position ASC
    pos_sorted = @manager.query(domain: 'example.com', sort: 'position', order: 'ASC')
    assert_equal 2.4, pos_sorted.first[:position]
  end

  def test_save_and_query_pages
    sample_pages = [
      { 'keys' => ['https://example.com/blog'], 'clicks' => 200, 'impressions' => 2500, 'ctr' => 0.08, 'position' => 3.1 },
      { 'keys' => ['https://example.com/pricing'], 'clicks' => 45, 'impressions' => 500, 'ctr' => 0.09, 'position' => 5.2 }
    ]

    saved = @manager.save_pages_direct('example.com', sample_pages, 30, '2026-09-01')
    assert_equal 2, saved

    pages = @manager.pages(domain: 'example.com')
    assert_equal 2, pages.size
    assert_equal 'https://example.com/blog', pages.first[:page]

    # Filter pages by search
    pricing = @manager.pages(domain: 'example.com', search: 'pricing')
    assert_equal 1, pricing.size
    assert_equal 'https://example.com/pricing', pricing.first[:page]
  end

  def test_diff_calculation
    # Snapshot 1 (2026-08-01)
    old_rows = [
      { 'keys' => ['keyword one'], 'clicks' => 10, 'impressions' => 100, 'ctr' => 0.1, 'position' => 5.0 },
      { 'keys' => ['keyword decaying'], 'clicks' => 50, 'impressions' => 500, 'ctr' => 0.1, 'position' => 2.0 },
      { 'keys' => ['keyword dropping'], 'clicks' => 20, 'impressions' => 200, 'ctr' => 0.1, 'position' => 4.0 }
    ]
    @manager.save_queries_direct('example.com', old_rows, 30, '2026-08-01')

    # Snapshot 2 (2026-09-01)
    new_rows = [
      { 'keys' => ['keyword one'], 'clicks' => 35, 'impressions' => 300, 'ctr' => 0.116, 'position' => 2.5 },
      { 'keys' => ['keyword decaying'], 'clicks' => 20, 'impressions' => 300, 'ctr' => 0.066, 'position' => 4.5 },
      { 'keys' => ['keyword brand new'], 'clicks' => 15, 'impressions' => 150, 'ctr' => 0.1, 'position' => 3.0 }
    ]
    @manager.save_queries_direct('example.com', new_rows, 30, '2026-09-01')

    diff = @manager.diff('example.com', '2026-08-01', '2026-09-01')
    assert_equal 'example.com', diff[:domain]
    assert_equal 1, diff[:summary][:winners_count]
    assert_equal 1, diff[:summary][:losers_count]
    assert_equal 1, diff[:summary][:new_queries_count]
    assert_equal 1, diff[:summary][:dropped_queries_count]

    assert_equal 'keyword one', diff[:winners].first[:query]
    assert_equal 25, diff[:winners].first[:click_delta]
    assert_equal 2.5, diff[:winners].first[:pos_delta]

    assert_equal 'keyword decaying', diff[:losers].first[:query]
    assert_equal(-30, diff[:losers].first[:click_delta])

    assert_equal 'keyword brand new', diff[:new_queries].first[:query]
    assert_equal 'keyword dropping', diff[:dropped_queries].first[:query]
  end

  def test_warm_with_mock_api
    mock_api = Object.new
    def mock_api.query_analytics(_domain, dimensions:, **_opts)
      if dimensions == ['query']
        { 'rows' => [{ 'keys' => ['gsc gem'], 'clicks' => 88, 'impressions' => 900, 'ctr' => 0.097, 'position' => 1.8 }] }
      elsif dimensions == ['page']
        { 'rows' => [{ 'keys' => ['https://example.com/'], 'clicks' => 120, 'impressions' => 1100, 'ctr' => 0.109, 'position' => 1.5 }] }
      elsif dimensions == %w[query page]
        { 'rows' => [{ 'keys' => ['gsc gem', 'https://example.com/'], 'clicks' => 88, 'impressions' => 900 }] }
      else
        { 'rows' => [] }
      end
    end

    res = @manager.warm('example.com', mock_api, days: 30, limit: 100)
    assert_equal 'example.com', res[:domain]
    assert_equal 1, res[:queries_saved]
    assert_equal 1, res[:pages_saved]

    status = @manager.status
    assert_equal 1, status[:total_queries]
    assert_equal 1, status[:total_pages]
    assert_includes status[:domains], 'example.com'
  end

  def test_clear_domain_and_all
    sample_queries = [{ 'keys' => ['domain a kw'], 'clicks' => 10, 'impressions' => 100, 'ctr' => 0.1, 'position' => 5.0 }]
    sample_queries_b = [{ 'keys' => ['domain b kw'], 'clicks' => 20, 'impressions' => 200, 'ctr' => 0.1, 'position' => 3.0 }]

    @manager.save_queries_direct('site-a.com', sample_queries, 30, '2026-09-01')
    @manager.save_queries_direct('site-b.com', sample_queries_b, 30, '2026-09-01')

    assert_equal 2, @manager.status[:total_queries]

    # Clear domain a only
    @manager.clear(domain: 'site-a.com')
    assert_equal 1, @manager.status[:total_queries]
    assert_equal 0, @manager.query(domain: 'site-a.com').size
    assert_equal 1, @manager.query(domain: 'site-b.com').size

    # Clear all
    @manager.clear(all: true)
    assert_equal 0, @manager.status[:total_queries]
  end

  def test_json_engine_fallback
    # Explicitly test JSON engine mode
    json_dir = File.join(@tmp_dir, 'json_test')
    FileUtils.mkdir_p(json_dir)
    json_manager = GSC::CacheManager.allocate
    json_manager.instance_variable_set(:@config_dir, json_dir)
    json_manager.instance_variable_set(:@db_path, File.join(json_dir, 'cache.db'))
    json_manager.instance_variable_set(:@json_path, File.join(json_dir, 'cache.json'))
    json_manager.instance_variable_set(:@engine, :json)
    json_manager.send(:init_schema!)

    assert_equal :json, json_manager.status[:engine]

    # Save queries in JSON engine
    json_manager.save_queries_direct('json-domain.com', [
      { 'keys' => ['pure json keyword'], 'clicks' => 42, 'impressions' => 420, 'ctr' => 0.1, 'position' => 1.0 }
    ])

    results = json_manager.query(domain: 'json-domain.com')
    assert_equal 1, results.size
    assert_equal 'pure json keyword', results.first[:query]

    # Status under JSON engine
    st = json_manager.status
    assert_equal 1, st[:total_queries]
    assert_includes st[:domains], 'json-domain.com'

    # Clear under JSON engine
    json_manager.clear(domain: 'json-domain.com')
    assert_equal 0, json_manager.status[:total_queries]
  end
end

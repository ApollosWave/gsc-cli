# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/sitemap_tree'

class SitemapTreeTest < Minitest::Test
  def setup
    @tmp_dir = File.expand_path('../scratch/sitemaps_test', __dir__)
    FileUtils.mkdir_p(@tmp_dir)

    @single_sitemap_path = File.join(@tmp_dir, 'sitemap_single.xml')
    File.write(@single_sitemap_path, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/</loc>
          <lastmod>2026-09-01</lastmod>
          <changefreq>daily</changefreq>
          <priority>1.0</priority>
        </url>
        <url>
          <loc>https://example.com/pricing</loc>
          <lastmod>2026-08-15T12:00:00Z</lastmod>
          <changefreq>weekly</changefreq>
          <priority>0.8</priority>
        </url>
      </urlset>
    XML

    @index_sitemap_path = File.join(@tmp_dir, 'sitemap_index.xml')
    File.write(@index_sitemap_path, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <sitemap>
          <loc>#{@single_sitemap_path}</loc>
          <lastmod>2026-09-01</lastmod>
        </sitemap>
      </sitemapindex>
    XML
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir) if File.exist?(@tmp_dir)
  end

  def test_audits_single_sitemap
    auditor = GSC::SitemapTree.new(@single_sitemap_path)
    report = auditor.audit

    refute report[:is_index]
    assert_equal 1, report[:total_sitemaps]
    assert_equal 2, report[:total_urls]
    assert_equal 100, report[:health_score]
    assert_empty report[:violations]
    assert_includes report[:all_urls], 'https://example.com/'
    assert_includes report[:all_urls], 'https://example.com/pricing'
  end

  def test_audits_sitemap_index_hierarchy
    auditor = GSC::SitemapTree.new(@index_sitemap_path)
    report = auditor.audit

    assert report[:is_index]
    assert_equal 2, report[:total_sitemaps] # 1 index + 1 child
    assert_equal 2, report[:total_urls]
    assert_equal 100, report[:health_score]
  end

  def test_detects_future_timestamp_violation
    bad_path = File.join(@tmp_dir, 'bad_sitemap.xml')
    future_date = (Time.now + (40 * 86400)).strftime('%Y-%m-%d')
    File.write(bad_path, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        <url>
          <loc>https://example.com/future</loc>
          <lastmod>#{future_date}</lastmod>
        </url>
      </urlset>
    XML

    auditor = GSC::SitemapTree.new(bad_path)
    report = auditor.audit

    assert report[:violations].any? { |v| v[:type] == :future_timestamp }
    assert report[:health_score] < 100
  end

  def test_computes_coverage_against_gsc_pages
    auditor = GSC::SitemapTree.new(@single_sitemap_path)
    gsc_pages = [
      { url: 'https://example.com/' },
      { url: 'https://example.com/pricing' },
      { url: 'https://example.com/blog/missing-post' }
    ]

    report = auditor.audit(gsc_pages)
    cov = report[:coverage]

    assert_equal 3, cov[:total_gsc_pages]
    assert_equal 2, cov[:included_in_sitemap]
    assert_equal 1, cov[:missing_from_sitemap]
    assert_in_delta 66.7, cov[:coverage_pct], 0.5
    assert_includes cov[:missing_sample].first, 'missing-post'
  end
end

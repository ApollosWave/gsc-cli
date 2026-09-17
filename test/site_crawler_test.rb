# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class SiteCrawlerTest < Minitest::Test
  def test_crawler_initialization
    crawler = GSC::SiteCrawler.new("https://example.com/sitemap.xml", limit: 5)
    assert_equal "https://example.com/sitemap.xml", crawler.target
    assert_equal 5, crawler.options[:limit]
  end

  def test_aggregate_summary_structure
    crawler = GSC::SiteCrawler.new("https://example.com/sitemap.xml")
    summary = crawler.aggregate_summary
    assert_equal 0, summary[:total_pages]
    assert_equal 0, summary[:broken_links_count]
    assert_equal 0, summary[:missing_alts_count]
  end

  def test_concurrent_run_preserves_order_and_aggregates
    crawler = GSC::SiteCrawler.new("https://example.com/sitemap.xml", concurrency: 4)

    # Stub discover_urls
    test_urls = (1..8).map { |i| "https://example.com/page-#{i}" }
    crawler.define_singleton_method(:discover_urls) { |_| test_urls }

    # Stub PageAnalyzer
    original_analyzer = GSC::PageAnalyzer
    stub_analyzer = Class.new do
      attr_reader :url
      def initialize(url)
        @url = url
      end
      def fetch_and_analyze(options = {})
        sleep(0.01) # Simulate network latency
        {
          url: @url,
          status: 200,
          h1: ["Heading for #{@url}"],
          title: "Title for #{@url}",
          broken_links: [],
          missing_alts: [],
          heading_issues: [],
          title_issues: [],
          canonical_issues: []
        }
      end
    end

    GSC.send(:remove_const, :PageAnalyzer)
    GSC.const_set(:PageAnalyzer, stub_analyzer)

    progress_events = []
    summary = crawler.run do |url, current, total|
      progress_events << [url, current, total]
    end

    # Restore original analyzer
    GSC.send(:remove_const, :PageAnalyzer)
    GSC.const_set(:PageAnalyzer, original_analyzer)

    assert_equal 8, summary[:total_pages]
    assert_equal 8, crawler.results.size
    # Order should be preserved exactly 1 through 8
    (1..8).each do |i|
      assert_equal "https://example.com/page-#{i}", crawler.results[i - 1][:url]
    end
    assert_equal 8, progress_events.size
  end
end

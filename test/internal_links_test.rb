# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'

class InternalLinksTest < Minitest::Test
  def test_initialization_defaults
    il = GSC::InternalLinks.new('example.com', limit: 30, concurrency: 4)
    assert_equal 'https://example.com', il.base_url
    assert_equal 4, il.concurrency
  end

  def test_concurrency_bounds
    il_low = GSC::InternalLinks.new('https://example.com', concurrency: 0)
    assert_equal 1, il_low.concurrency

    il_high = GSC::InternalLinks.new('https://example.com', concurrency: 50)
    assert_equal 20, il_high.concurrency
  end

  def test_calculate_depths_bfs
    il = GSC::InternalLinks.new('https://example.com')
    root = 'https://example.com'
    p1 = 'https://example.com/about'
    p2 = 'https://example.com/about/team'
    p3 = 'https://example.com/about/team/john'

    il.instance_variable_get(:@out_links)[root] << p1
    il.instance_variable_get(:@out_links)[p1] << p2
    il.instance_variable_get(:@out_links)[p2] << p3

    depths = il.send(:calculate_depths, root)
    assert_equal 0, depths[root]
    assert_equal 1, depths[p1]
    assert_equal 2, depths[p2]
    assert_equal 3, depths[p3]
  end

  def test_orphan_rescue_suggestions
    il = GSC::InternalLinks.new('https://example.com')
    orphan_url = 'https://example.com/blog/advanced-seo-guide'
    hubs = ['https://example.com/blog', 'https://example.com/features']
    root = 'https://example.com'

    rescues = il.send(:generate_rescue_suggestions, orphan_url, hubs, root)
    assert_equal 2, rescues.size
    assert_equal 'https://example.com/blog', rescues.first[:source_url]
    assert_includes rescues.first[:recommended_anchor], 'Advanced Seo Guide'
    assert_includes rescues.first[:action], 'Add in-content link'
  end

  def test_audit_with_provided_sitemap_urls
    il = GSC::InternalLinks.new('https://example.com', limit: 5)
    
    # Mock crawl_single_page to simulate page links
    il.define_singleton_method(:crawl_single_page) do |url|
      # simulate root linking to /about, but /orphan has 0 incoming links
      if url == 'https://example.com'
        @mutex.synchronize do
          @graph['https://example.com/about'] << 'https://example.com'
          @out_links['https://example.com'] << 'https://example.com/about'
        end
      end
    end

    result = il.audit(['https://example.com', 'https://example.com/about', 'https://example.com/orphan'])
    
    assert_equal 'https://example.com', result[:base_url]
    assert_equal 3, result[:total_pages]
    assert_includes result[:orphans], 'https://example.com/orphan'
    refute_includes result[:orphans], 'https://example.com/about'
    assert_equal 1, result[:orphan_details].size
    assert_equal 'https://example.com/orphan', result[:orphan_details].first[:url]
    assert result[:health_score] >= 0 && result[:health_score] <= 100
  end
end

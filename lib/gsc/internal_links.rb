# encoding: utf-8
# frozen_string_literal: true

require 'uri'
require 'set'
require 'thread'
require 'time'

module GSC
  class InternalLinks
    attr_reader :base_url, :pages, :graph, :orphans, :depths, :concurrency

    def initialize(base_url, limit: 50, concurrency: 5)
      @base_url = base_url.to_s.strip
      @base_url = "https://#{@base_url}" unless @base_url =~ %r{^https?://}
      @base_uri = URI.parse(@base_url)
      @limit = limit.to_i > 0 ? limit.to_i : 50
      @concurrency = [[concurrency.to_i, 1].max, 20].min
      @graph = Hash.new { |h, k| h[k] = Set.new }      # target_url => Set of source_urls
      @out_links = Hash.new { |h, k| h[k] = Set.new }  # source_url => Set of target_urls
      @page_titles = {}                                # url => String
      @page_anchors = Hash.new { |h, k| h[k] = {} }    # target_url => { source_url => anchor_text }
      @all_discovered = Set.new
      @mutex = Mutex.new
    end

    def audit(sitemap_urls = nil, &progress_block)
      start_time = Time.now

      urls_to_crawl = if sitemap_urls && !sitemap_urls.empty?
                        sitemap_urls.first(@limit)
                      else
                        discover_urls
                      end

      urls_to_crawl.each do |url|
        @all_discovered << normalize_url(url)
      end

      # Multi-threaded concurrent crawling
      crawl_urls_concurrently(urls_to_crawl, &progress_block)

      crawl_duration = (Time.now - start_time).round(2)

      # Calculate click depths via BFS from root
      normalized_root = normalize_url(@base_url)
      depths = calculate_depths(normalized_root)

      # Top hub pages (highest out-links and in-links)
      top_hubs = top_linked_pages(10)
      hub_urls = top_hubs.map { |h| h[:url] }.reject { |u| u == normalized_root }

      # Calculate Orphans and Weak Pages
      orphans = []
      orphan_details = []
      weak_pages = []
      deep_pages = []

      @all_discovered.each do |url|
        next if url == normalized_root

        in_degree = @graph[url].size
        depth = depths[url]

        if depth && depth >= 4
          deep_pages << { url: url, depth: depth, in_degree: in_degree }
        end

        if in_degree == 0
          orphans << url
          orphan_details << {
            url: url,
            depth: depth || 'Unreachable via internal links (∞)',
            suggested_rescues: generate_rescue_suggestions(url, hub_urls, normalized_root)
          }
        elsif in_degree == 1
          source = @graph[url].first
          anchor = @page_anchors.dig(url, source) || 'View page'
          weak_pages << {
            url: url,
            source: source,
            anchor: anchor,
            depth: depth,
            suggested_rescues: generate_rescue_suggestions(url, hub_urls, normalized_root)
          }
        end
      end

      # Link Equity Health Score (0–100)
      health_score = [100 - (orphans.size * 12) - (weak_pages.size * 3) - (deep_pages.size * 4), 0].max
      health_grade = case health_score
                     when 90..100 then 'A'
                     when 80..89  then 'B'
                     when 70..79  then 'C'
                     when 60..69  then 'D'
                     else              'F'
                     end

      # Depth distribution
      depth_dist = Hash.new(0)
      depths.each_value { |d| depth_dist[d] += 1 }

      {
        base_url: @base_url,
        total_pages: @all_discovered.size,
        crawl_duration_s: crawl_duration,
        health_score: health_score,
        health_grade: health_grade,
        orphans: orphans,
        orphan_details: orphan_details,
        weak_pages: weak_pages,
        deep_pages: deep_pages,
        top_linked: top_hubs,
        depths: depths,
        depth_distribution: depth_dist.sort.to_h
      }
    end

    private

    def crawl_urls_concurrently(urls, &_block)
      queue = Queue.new
      urls.each { |u| queue << u }

      workers = (1..@concurrency).map do
        Thread.new do
          while !queue.empty? && (url = queue.pop(true) rescue nil)
            crawl_single_page(url)
          end
        end
      end

      workers.each(&:join)
    end

    def crawl_single_page(url)
      pa = GSC::PageAnalyzer.new(url)
      pa.load_content!
      dom = pa.analyze_dom
      return unless dom

      norm_source = normalize_url(url)
      title = dom.dig(:title, :text).to_s.strip
      links = dom.dig(:links, :all) || []

      @mutex.synchronize do
        @page_titles[norm_source] = title unless title.empty?
      end

      links.each do |link_obj|
        href = link_obj[:href]
        target_url = resolve_internal_url(href)
        next unless target_url

        norm_target = normalize_url(target_url)
        next if norm_target == norm_source

        anchor = link_obj[:anchor].to_s.strip

        @mutex.synchronize do
          @graph[norm_target] << norm_source
          @out_links[norm_source] << norm_target
          @page_anchors[norm_target][norm_source] = anchor unless anchor.empty?
        end
      end
    rescue StandardError
      # resilient worker execution
    end

    def discover_urls
      urls = GSC::SitemapLoader.resolve_urls(@base_url, @base_url, quiet: true)
      urls.empty? ? [@base_url] : urls.first(@limit)
    rescue StandardError
      [@base_url]
    end

    def resolve_internal_url(href)
      return nil if href.nil? || href.strip.empty?
      return nil if href =~ /^(mailto|tel|javascript|#):/i

      uri = URI.join(@base_url, href) rescue nil
      return nil unless uri && uri.scheme =~ /^https?$/i
      return nil unless uri.host.downcase == @base_uri.host.downcase

      uri.fragment = nil
      uri.to_s
    end

    def normalize_url(url)
      u = url.to_s.strip.sub(%r{/$}, '')
      u.empty? ? @base_url : u
    end

    def calculate_depths(root_url)
      depths = { root_url => 0 }
      queue = [root_url]

      until queue.empty?
        curr = queue.shift
        curr_depth = depths[curr]

        (@out_links[curr] || []).each do |neighbor|
          next if depths.key?(neighbor)

          depths[neighbor] = curr_depth + 1
          queue << neighbor
        end
      end

      depths
    end

    def top_linked_pages(limit)
      @graph.map do |url, sources|
        {
          url: url,
          title: @page_titles[url] || '',
          incoming_count: sources.size,
          outgoing_count: (@out_links[url] || []).size
        }
      end.sort_by { |item| -item[:incoming_count] }.first(limit)
    end

    def generate_rescue_suggestions(orphan_url, hub_urls, root_url)
      # Extract keyword tokens from slug
      path = URI.parse(orphan_url).path.to_s rescue ''
      slug = path.split('/').reject(&:empty?).last || ''
      keyword = slug.gsub(/[-_]+/, ' ').strip
      keyword_title = keyword.split.map(&:capitalize).join(' ')

      # Pick 2 best rescue sources: 1 high-equity hub, 1 root/pillar
      sources = []
      if !hub_urls.empty?
        # Pick first hub that isn't the orphan itself
        hub_source = hub_urls.find { |h| h != orphan_url }
        sources << hub_source if hub_source
      end
      sources << root_url unless sources.include?(root_url)

      sources.first(2).map do |src|
        {
          source_url: src,
          recommended_anchor: keyword.empty? ? 'Explore this guide' : keyword_title,
          action: "Add in-content link from #{src} pointing to #{orphan_url} with anchor \"#{keyword.empty? ? 'Learn more' : keyword_title}\""
        }
      end
    end
  end
end

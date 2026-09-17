# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'zlib'
require 'stringio'
require 'time'
require_relative 'config' if File.exist?(File.expand_path('config.rb', __dir__))
require_relative 'color' if File.exist?(File.expand_path('color.rb', __dir__))
require_relative 'sitemap_loader' if File.exist?(File.expand_path('sitemap_loader.rb', __dir__))

module GSC
  class TitleOptimizer
    DESKTOP_MAX_PX  = 580.0
    MOBILE_MAX_PX   = 540.0
    OPTIMAL_MIN_PX  = 380.0
    OPTIMAL_MAX_PX  = 560.0
    MIN_CHARS       = 35
    MAX_CHARS       = 65

    SEPARATORS = [' | ', ' - ', ' — ', ' – ', ' • ', ' : ', ' » '].freeze

    attr_reader :target, :options, :results, :brand_token

    def initialize(target = nil, options = {})
      raw = target.to_s.strip
      raw = Config.default_domain.to_s.strip if raw.empty?
      @target = raw
      @options = options
      @results = []
      @brand_token = extract_brand_token(@target)
    end

    def audit(&progress_block)
      urls = discover_target_urls(@target)
      limit = (@options[:limit] || 25).to_i
      urls = urls.first(limit) if limit > 0

      total = urls.size
      concurrency = (@options[:concurrency] || 5).to_i
      concurrency = 1 if concurrency < 1
      concurrency = [concurrency, 20].min
      concurrency = [concurrency, total].min if total > 0

      if concurrency <= 1 || total <= 1
        urls.each_with_index do |url, idx|
          progress_block.call(url, idx + 1, total) if block_given?
          @results << audit_page(url)
        end
      else
        queue = Queue.new
        urls.each_with_index { |url, idx| queue << [url, idx] }

        indexed_results = []
        mutex = Mutex.new
        completed = 0

        workers = Array.new(concurrency) do
          Thread.new do
            loop do
              item = begin
                       queue.pop(true)
                     rescue ThreadError
                       nil
                     end
              break unless item

              url, original_idx = item
              page_data = audit_page(url)

              mutex.synchronize do
                indexed_results << [original_idx, page_data]
                completed += 1
                progress_block.call(url, completed, total) if block_given?
              end
            end
          end
        end

        workers.each(&:join)
        @results = indexed_results.sort_by { |idx, _| idx }.map { |_, data| data }
      end

      calculate_site_summary
    end

    def self.estimate_pixel_width(str)
      width = 0.0
      str.to_s.each_char do |ch|
        width += case ch
                 when /[WM]/ then 13.5
                 when /[wm]/ then 12.0
                 when /[ABCDEFGHKNOPQRSTUVXYZ]/ then 10.5
                 when /[fijlt1I\|\ \.\:\;\!\,\'\`\-\/]/ then 4.5
                 when /[abcdeghknopqrsuvxyz]/ then 8.5
                 when /[\@\&\%\©\®\#\$\*\+\=\<\>]/ then 12.0
                 when /[0-9]/ then 9.0
                 else 8.5
                 end
      end
      width.round(1)
    end

    def self.truncate_to_pixel_width(str, limit_px = DESKTOP_MAX_PX)
      return '' if str.nil? || str.empty?
      return str if estimate_pixel_width(str) <= limit_px

      ellipsis = '...'
      target_limit = limit_px - estimate_pixel_width(ellipsis)
      current = ''

      str.each_char do |ch|
        break if estimate_pixel_width(current + ch) > target_limit
        current += ch
      end

      current.strip + ellipsis
    end

    private

    def discover_target_urls(input)
      normalized = input.start_with?('http://', 'https://') ? input : "https://#{input}"
      uri = URI.parse(normalized)

      # If input has a specific path that is not root and not sitemap, treat as single page
      if !uri.path.empty? && uri.path != '/' && !uri.path.include?('sitemap') && !input.end_with?('.xml')
        return [normalized]
      end

      # 1. Try sitemap first
      sitemap_candidates = [
        input.end_with?('.xml') ? input : nil,
        "#{uri.scheme}://#{uri.host}:#{uri.port}/sitemap.xml",
        "#{uri.scheme}://#{uri.host}:#{uri.port}/sitemap_products_1.xml"
      ].compact

      sitemap_candidates.each do |candidate|
        begin
          urls = SitemapLoader.load_urls(candidate)
          return urls if urls.any?
        rescue StandardError
          # continue to next candidate
        end
      end

      # 2. Fallback: Crawl homepage and extract internal links
      crawl_homepage_links(normalized)
    rescue StandardError
      [input.start_with?('http') ? input : "https://#{input}"]
    end

    def crawl_homepage_links(root_url)
      uri = URI.parse(root_url)
      html = fetch_html(root_url)
      return [root_url] if html.empty?

      found = [root_url]
      html.scan(/<a\s+[^>]*href=["']([^"']+)["']/i).flatten.each do |href|
        href = href.split('#').first.to_s.strip
        next if href.empty? || href.start_with?('javascript:', 'mailto:', 'tel:')

        resolved = begin
                     URI.join(root_url, href).to_s
                   rescue StandardError
                     nil
                   end
        next unless resolved

        res_uri = URI.parse(resolved) rescue nil
        next unless res_uri && res_uri.host == uri.host && res_uri.scheme =~ /^https?$/

        clean_url = "#{res_uri.scheme}://#{res_uri.host}#{res_uri.path}"
        clean_url = clean_url.chomp('/') unless res_uri.path == '/'
        found << clean_url unless found.include?(clean_url)
      end

      found.uniq
    end

    def audit_page(url)
      html = fetch_html(url)
      title_match = html.match(/<title[^>]*>(.*?)<\/title>/im)
      raw_title = title_match ? decode_html_entities(title_match[1].to_s.strip.gsub(/\s+/, ' ')) : ''

      h1_match = html.match(/<h1[^>]*>(.*?)<\/h1>/im)
      h1_text = h1_match ? decode_html_entities(h1_match[1].to_s.gsub(/<[^>]+>/, '').strip.gsub(/\s+/, ' ')) : ''

      meta_match = html.match(/<meta\s+[^>]*name=["']description["'][^>]*content=["']([^"']*)["']/im) ||
                   html.match(/<meta\s+[^>]*content=["']([^"']*)["'][^>]*name=["']description["']/im)
      meta_desc = meta_match ? decode_html_entities(meta_match[1].to_s.strip.gsub(/\s+/, ' ')) : ''

      chars = raw_title.size
      px_width = self.class.estimate_pixel_width(raw_title)

      status, hazard = evaluate_title_status(raw_title, chars, px_width)
      separator = detect_separator(raw_title)
      has_brand = contains_brand?(raw_title)

      rewrites = (status != :optimal) ? synthesize_rewrites(url, raw_title, h1_text, px_width) : []

      {
        url: url,
        title: raw_title,
        h1: h1_text,
        meta_desc: meta_desc,
        char_count: chars,
        pixel_width: px_width,
        status: status, # :optimal, :desktop_overflow, :critical_overflow, :too_short, :missing
        truncation_hazard: hazard,
        desktop_preview: self.class.truncate_to_pixel_width(raw_title, DESKTOP_MAX_PX),
        separator_detected: separator,
        has_brand_name: has_brand,
        suggested_rewrites: rewrites
      }
    end

    def evaluate_title_status(title, chars, px)
      return [:missing, 'CRITICAL: Missing Title Tag'] if title.empty?
      return [:critical_overflow, 'SEVERE: Truncates on both Desktop and Mobile (>630px)'] if px > 630.0 || chars > 70
      return [:desktop_overflow, 'MODERATE: Truncates on Desktop SERP (>580px)'] if px > DESKTOP_MAX_PX
      return [:too_short, 'SUBOPTIMAL: Too short (<35 chars, wasting SERP real estate)'] if chars < MIN_CHARS || px < 350.0

      [:optimal, 'NONE: Fits cleanly in desktop and mobile SERPs']
    end

    def detect_separator(title)
      SEPARATORS.find { |sep| title.include?(sep) }&.strip
    end

    def contains_brand?(title)
      return false if @brand_token.empty?
      title.downcase.include?(@brand_token.downcase)
    end

    def synthesize_rewrites(url, original_title, h1_text, current_px)
      uri = URI.parse(url) rescue nil
      slug_words = uri ? uri.path.split('/').last.to_s.tr('-_', ' ').split : []
      core_topic = if !h1_text.empty? && h1_text.size < 45
                     h1_text
                   elsif slug_words.any?
                     slug_words.map(&:capitalize).join(' ')
                   else
                     original_title.split(/[\-\|\—\•\:]/).first.to_s.strip
                   end

      core_topic = core_topic.sub(/^(The|A|An)\s+/i, '').strip
      brand = @brand_token.capitalize

      rewrites = []

      # Variation 1: Primary Search Keyword + Brand (Clean standard format)
      v1_raw = "#{core_topic} | #{brand}"
      if self.class.estimate_pixel_width(v1_raw) > DESKTOP_MAX_PX
        v1_raw = "#{core_topic.split.first(4).join(' ')} | #{brand}"
      end
      v1_px = self.class.estimate_pixel_width(v1_raw)
      rewrites << {
        type: 'Primary Hook + Clean Brand',
        title: v1_raw,
        char_count: v1_raw.size,
        pixel_width: v1_px,
        fits_serp: v1_px <= DESKTOP_MAX_PX
      }

      # Variation 2: Action / Value-Driven Hook
      verbs = ['The Official', 'Boost', 'Scale', 'Automate', 'Ultimate']
      chosen_verb = verbs[(core_topic.length + brand.length) % verbs.size]
      v2_raw = "#{chosen_verb} #{core_topic} - #{brand}"
      if self.class.estimate_pixel_width(v2_raw) > DESKTOP_MAX_PX
        v2_raw = "#{chosen_verb} #{core_topic.split.first(3).join(' ')} - #{brand}"
      end
      v2_px = self.class.estimate_pixel_width(v2_raw)
      rewrites << {
        type: 'Action / Benefit-Driven Hook',
        title: v2_raw,
        char_count: v2_raw.size,
        pixel_width: v2_px,
        fits_serp: v2_px <= DESKTOP_MAX_PX
      }

      # Variation 3: Compact Exact-Intent Match (Fluff stripped)
      v3_clean = core_topic.gsub(/\b(official|best|new|202[0-9]|review|app)\b/i, '').strip.gsub(/\s+/, ' ')
      v3_raw = brand.to_s.strip.empty? ? "#{v3_clean} – Official Overview" : "#{v3_clean} | #{brand}"
      if self.class.estimate_pixel_width(v3_raw) > DESKTOP_MAX_PX
        v3_raw = "#{v3_clean.split.first(4).join(' ')} | #{brand}"
      end
      v3_px = self.class.estimate_pixel_width(v3_raw)
      rewrites << {
        type: 'Compact Exact-Intent Match',
        title: v3_raw,
        char_count: v3_raw.size,
        pixel_width: v3_px,
        fits_serp: v3_px <= DESKTOP_MAX_PX
      }

      rewrites
    end

    def calculate_site_summary
      total = @results.size
      return empty_summary if total.zero?

      optimal_count  = @results.count { |r| r[:status] == :optimal }
      desk_overflow  = @results.count { |r| r[:status] == :desktop_overflow }
      crit_overflow  = @results.count { |r| r[:status] == :critical_overflow }
      short_count    = @results.count { |r| r[:status] == :too_short }
      missing_count  = @results.count { |r| r[:status] == :missing }

      optimal_pct = ((optimal_count.to_f / total) * 100).round(1)

      # Score calculation (0 - 100)
      raw_score = 100.0
      raw_score -= (desk_overflow.to_f / total) * 30.0
      raw_score -= (crit_overflow.to_f / total) * 60.0
      raw_score -= (short_count.to_f / total) * 15.0
      raw_score -= (missing_count.to_f / total) * 100.0
      score = [[0, raw_score.round].max, 100].min

      grade = case score
              when 90..100 then 'A'
              when 75..89  then 'B'
              when 60..74  then 'C'
              when 40..59  then 'D'
              else 'F'
              end

      verdict = case grade
                when 'A' then 'EXCELLENT: Over 90% of titles fit Google SERP pixel constraints'
                when 'B' then 'GOOD: Minor title overflow on desktop SERPs'
                when 'C' then 'MODERATE: Noticeable title truncation across multiple landing pages'
                when 'D' then 'POOR: Frequent SERP ellipsis (...) truncation harming click-through rates'
                else 'CRITICAL: Widespread title overflow or missing title tags'
                end

      {
        target: @target,
        timestamp: Time.now.utc.iso8601,
        total_pages: total,
        health_score: score,
        grade: grade,
        verdict: verdict,
        counts: {
          optimal: optimal_count,
          desktop_overflow: desk_overflow,
          critical_overflow: crit_overflow,
          too_short: short_count,
          missing: missing_count
        },
        percentages: {
          optimal_pct: optimal_pct,
          overflow_pct: (((desk_overflow + crit_overflow).to_f / total) * 100).round(1)
        },
        pages: @results
      }
    end

    def empty_summary
      {
        target: @target,
        timestamp: Time.now.utc.iso8601,
        total_pages: 0,
        health_score: 0,
        grade: 'F',
        verdict: 'No pages found or audited',
        counts: { optimal: 0, desktop_overflow: 0, critical_overflow: 0, too_short: 0, missing: 0 },
        percentages: { optimal_pct: 0.0, overflow_pct: 0.0 },
        pages: []
      }
    end

    def extract_brand_token(url_or_domain)
      clean = url_or_domain.sub(%r{^https?://}, '').split('/').first.to_s.downcase
      clean.sub(/\.(com|co|io|net|org|app|dev|ai|store)$/, '').split('.').last.to_s
    end

    def fetch_html(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 5
      http.read_timeout = 8

      path = uri.request_uri.empty? ? '/' : uri.request_uri
      req = Net::HTTP::Get.new(path)
      req['User-Agent'] = "Mozilla/5.0 (compatible; GSC-TitleOptimizer/#{GSC::VERSION}; +https://apolloswave.com)"
      req['Accept-Encoding'] = 'gzip'

      res = http.request(req)
      return '' unless res.code.to_i >= 200 && res.code.to_i < 400

      raw = res.body || ''
      body_str = if res['content-encoding'] =~ /gzip/i && !raw.empty?
                   begin
                     Zlib::GzipReader.new(StringIO.new(raw)).read
                   rescue StandardError
                     raw
                   end
                 else
                   raw
                 end
      body_str.to_s.dup.force_encoding('UTF-8').scrub
    rescue StandardError
      ''
    end

    def decode_html_entities(str)
      str.to_s
         .gsub('&amp;', '&')
         .gsub('&quot;', '"')
         .gsub('&#39;', "'")
         .gsub('&apos;', "'")
         .gsub('&lt;', '<')
         .gsub('&gt;', '>')
         .gsub('&nbsp;', ' ')
    end
  end
end

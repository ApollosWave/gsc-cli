# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'zlib'
require 'stringio'
require 'time'
require 'date'
require 'cgi'

module GSC
  class SitemapTree
    MAX_URLS_PER_SITEMAP = 50_000
    MAX_BYTES_PER_SITEMAP = 50 * 1024 * 1024 # 50 MB
    STALE_DAYS_THRESHOLD = 180

    attr_reader :root_source, :options, :tree, :all_urls, :violations

    def initialize(root_source, options = {})
      @root_source = root_source.to_s.strip
      @options = options
      @tree = {}
      @all_urls = []
      @violations = []
    end

    def audit(gsc_pages = [])
      content, size_bytes = fetch_raw_content(@root_source)
      is_index = content.include?('<sitemapindex')

      @tree = if is_index
                parse_sitemap_index(@root_source, content, size_bytes)
              else
                parse_single_urlset(@root_source, content, size_bytes)
              end

      # Collect all unique URLs from tree
      @all_urls = collect_urls_from_tree(@tree).uniq

      # Coverage analysis against GSC pages if provided
      coverage = analyze_coverage(gsc_pages, @all_urls)

      # Global compliance health score (0-100)
      health_score = calculate_health_score

      {
        root: @root_source,
        is_index: is_index,
        total_sitemaps: count_sitemaps(@tree),
        total_urls: @all_urls.size,
        total_size_bytes: sum_sizes(@tree),
        tree: @tree,
        all_urls: @all_urls,
        violations: @violations,
        coverage: coverage,
        health_score: health_score
      }
    end

    private

    def parse_sitemap_index(source_url, xml, size_bytes)
      sub_sitemaps = []
      now = Time.now

      # Extract <sitemap> blocks
      xml.scan(/<sitemap\b[^>]*>(.*?)<\/sitemap>/im).each do |match|
        block = match[0]
        loc = block.match(/<loc\b[^>]*>(.*?)<\/loc>/i)&.[](1)&.strip
        next unless loc
        loc = loc.sub(/^<!\[CDATA\[/i, '').sub(/\]\]>$/i, '').strip
        loc = CGI.unescapeHTML(loc)

        lastmod_str = block.match(/<lastmod\b[^>]*>(.*?)<\/lastmod>/i)&.[](1)&.strip
        lastmod_time, lastmod_valid = parse_and_validate_timestamp(lastmod_str, loc)

        # Recursively fetch child sitemap if requested or level 1
        child_node = begin
                       child_content, child_size = fetch_raw_content(loc)
                       if child_content.include?('<sitemapindex')
                         parse_sitemap_index(loc, child_content, child_size)
                       else
                         parse_single_urlset(loc, child_content, child_size)
                       end
                     rescue => e
                       @violations << { type: :fetch_error, sitemap: loc, message: e.message }
                       {
                         url: loc,
                         type: :error,
                         error: e.message,
                         url_count: 0,
                         urls: []
                       }
                     end

        child_node[:declared_lastmod] = lastmod_str
        child_node[:lastmod_time] = lastmod_time
        child_node[:lastmod_valid] = lastmod_valid

        sub_sitemaps << child_node
      end

      {
        url: source_url,
        type: :sitemapindex,
        size_bytes: size_bytes,
        children: sub_sitemaps,
        url_count: sub_sitemaps.sum { |s| s[:url_count] || 0 }
      }
    end

    def parse_single_urlset(source_url, xml, size_bytes)
      urls = []
      now = Time.now
      latest_lastmod = nil

      # Check file size limit (50MB)
      if size_bytes > MAX_BYTES_PER_SITEMAP
        @violations << {
          type: :size_overflow,
          sitemap: source_url,
          size_bytes: size_bytes,
          message: "Exceeds Google 50MB limit (#{format('%.2f', size_bytes / (1024.0 * 1024.0))} MB)"
        }
      end

      xml.scan(/<url\b[^>]*>(.*?)<\/url>/im).each do |match|
        block = match[0]
        loc = block.match(/<loc\b[^>]*>(.*?)<\/loc>/i)&.[](1)&.strip
        next unless loc
        loc = loc.sub(/^<!\[CDATA\[/i, '').sub(/\]\]>$/i, '').strip
        loc = CGI.unescapeHTML(loc)

        lastmod_str = block.match(/<lastmod\b[^>]*>(.*?)<\/lastmod>/i)&.[](1)&.strip
        changefreq = block.match(/<changefreq\b[^>]*>(.*?)<\/changefreq>/i)&.[](1)&.strip
        priority = block.match(/<priority\b[^>]*>(.*?)<\/priority>/i)&.[](1)&.strip

        lastmod_time, lastmod_valid = parse_and_validate_timestamp(lastmod_str, source_url)
        if lastmod_time && (latest_lastmod.nil? || lastmod_time > latest_lastmod)
          latest_lastmod = lastmod_time
        end

        urls << {
          loc: loc,
          lastmod: lastmod_str,
          changefreq: changefreq,
          priority: priority
        }
      end

      # Check URL count limit (50,000)
      if urls.size > MAX_URLS_PER_SITEMAP
        @violations << {
          type: :url_overflow,
          sitemap: source_url,
          count: urls.size,
          message: "Exceeds Google 50,000 URLs per sitemap limit (#{urls.size} URLs)"
        }
      end

      # Check date drift / staleness
      drift_days = latest_lastmod ? ((now - latest_lastmod) / 86400.0).round : nil
      is_stale = drift_days && drift_days > STALE_DAYS_THRESHOLD

      {
        url: source_url,
        type: :urlset,
        size_bytes: size_bytes,
        url_count: urls.size,
        latest_lastmod: latest_lastmod ? latest_lastmod.strftime('%Y-%m-%d') : nil,
        drift_days: drift_days,
        is_stale: is_stale,
        urls: urls
      }
    end

    def parse_and_validate_timestamp(ts_str, sitemap_url)
      return [nil, true] if ts_str.nil? || ts_str.empty?

      # ISO-8601 regex test
      is_iso = ts_str =~ /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?$/
      unless is_iso
        @violations << {
          type: :invalid_timestamp,
          sitemap: sitemap_url,
          timestamp: ts_str,
          message: "Invalid non-ISO-8601 timestamp: '#{ts_str}'"
        }
        return [nil, false]
      end

      t = Time.parse(ts_str) rescue nil
      if t && t > (Time.now + 86400) # Allow 1 day clock drift
        @violations << {
          type: :future_timestamp,
          sitemap: sitemap_url,
          timestamp: ts_str,
          message: "Future timestamp detected: #{ts_str}"
        }
        return [t, false]
      end

      [t, true]
    end

    def collect_urls_from_tree(node)
      if node[:type] == :sitemapindex && node[:children]
        node[:children].flat_map { |c| collect_urls_from_tree(c) }
      elsif node[:type] == :urlset && node[:urls]
        node[:urls].map { |u| u[:loc] }
      else
        []
      end
    end

    def count_sitemaps(node)
      if node[:type] == :sitemapindex && node[:children]
        1 + node[:children].sum { |c| count_sitemaps(c) }
      else
        1
      end
    end

    def sum_sizes(node)
      size = node[:size_bytes] || 0
      if node[:type] == :sitemapindex && node[:children]
        size += node[:children].sum { |c| sum_sizes(c) }
      end
      size
    end

    def analyze_coverage(gsc_pages, sitemap_urls)
      return { status: :no_gsc_data } if gsc_pages.nil? || gsc_pages.empty?

      sitemap_set = sitemap_urls.map { |u| normalize_url(u) }.to_set
      gsc_urls = gsc_pages.map { |p| normalize_url(p[:url] || p['url'] || p) }

      included = gsc_urls.select { |u| sitemap_set.include?(u) }
      missing = gsc_urls.reject { |u| sitemap_set.include?(u) }

      coverage_pct = gsc_urls.any? ? ((included.size.to_f / gsc_urls.size) * 100.0).round(1) : 100.0

      {
        total_gsc_pages: gsc_urls.size,
        included_in_sitemap: included.size,
        missing_from_sitemap: missing.size,
        coverage_pct: coverage_pct,
        missing_sample: missing.first(10)
      }
    end

    def calculate_health_score
      score = 100
      @violations.each do |v|
        case v[:type]
        when :fetch_error then score -= 25
        when :size_overflow, :url_overflow then score -= 20
        when :future_timestamp then score -= 15
        when :invalid_timestamp then score -= 10
        end
      end
      [0, score].max
    end

    def fetch_raw_content(source)
      if source =~ %r{^https?://}
        uri = URI.parse(source)
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = 'Mozilla/5.0 (compatible; GSC-SitemapTree-Auditor/1.0)'
        req['Accept-Encoding'] = 'gzip'

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 8
        http.read_timeout = 15

        res = http.request(req)
        raise "HTTP #{res.code} on #{source}" unless res.is_a?(Net::HTTPSuccess)

        raw = res.body || ''
        decompressed = if (res['content-encoding'] =~ /gzip/i || source.end_with?('.gz')) && !raw.empty?
                         Zlib::GzipReader.new(StringIO.new(raw)).read
                       else
                         raw
                       end
        content = decompressed.to_s.dup.force_encoding('UTF-8').scrub
        [content, content.bytesize]
      else
        raise "Local sitemap file not found: #{source}" unless File.exist?(source)
        content = File.read(source, encoding: 'UTF-8').scrub
        [content, content.bytesize]
      end
    end

    def normalize_url(url)
      u = url.to_s.strip.downcase.chomp('/')
      u.sub(%r{^https?://(www\.)?}, '')
    end
  end
end

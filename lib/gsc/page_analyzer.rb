# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'zlib'
require 'stringio'
require 'json'
require 'time'

module GSC
  class PageAnalyzer
    attr_reader :url, :html, :http_status, :response_time_ms, :headers, :error

    def initialize(url_or_path, html: nil)
      @target = url_or_path
      @is_local_file = File.file?(url_or_path)
      @url = @is_local_file ? "file://#{File.expand_path(url_or_path)}" : url_or_path
      @html = html ? html.to_s.dup.force_encoding('UTF-8').scrub : ''
      @http_status = html ? 200 : 0
      @response_time_ms = 0
      @headers = {}
      @error = nil
    end

    def fetch_and_analyze(check_links: false, gsc_api: nil, active_domain: nil)
      load_content!
      data = analyze_dom

      if check_links && !data[:links][:internal].empty?
        data[:links][:verification] = verify_links(data[:links][:internal].first(20))
      end

      if gsc_api && active_domain
        data[:gsc_performance] = fetch_gsc_metrics(gsc_api, @url, active_domain)
      end

      data
    end

    def load_content!
      return unless @html.empty?

      if @is_local_file
        raw = File.read(@target, encoding: 'UTF-8')
        @html = raw.to_s.dup.force_encoding('UTF-8').scrub
        @http_status = 200
        @response_time_ms = 0
      else
        uri = URI.parse(@target)
        start_t = Time.now
        res = fetch_http(uri)
        @response_time_ms = ((Time.now - start_t) * 1000).round(1)
        @http_status = res.code.to_i
        @headers = res.to_hash

        raw_body = res.body || ''
        decompressed = if res['content-encoding'] =~ /gzip/i && !raw_body.empty?
                         Zlib::GzipReader.new(StringIO.new(raw_body)).read
                       else
                         raw_body
                       end
        @html = decompressed.to_s.dup.force_encoding('UTF-8').scrub
      end
    rescue StandardError => e
      @html = ''
      @http_status = 0
      @error = e.message
    end

    def analyze_dom
      doc = @html.to_s.dup.force_encoding('UTF-8').scrub

      # 1. Basic Title & Meta
      title_raw = extract_tag_content(doc, 'title')
      meta_desc = extract_meta_content(doc, 'name', 'description')
      canonical_url = extract_link_attr(doc, 'canonical', 'href')
      robots_meta = extract_meta_content(doc, 'name', 'robots')

      # 2. Detailed Headings Structure & Hierarchy Depth
      heading_audit = if defined?(HeadingValidator)
                        HeadingValidator.analyze(doc, target_keywords: title_raw)
                      else
                        h_list = extract_headings(doc)
                        h1_found = h_list.select { |h| h[:tag] == 'h1' }
                        {
                          score: h1_found.size == 1 ? 100 : 70,
                          grade: h1_found.size == 1 ? 'A' : 'C',
                          depth: h_list.map { |h| h[:tag][1].to_i }.max || 0,
                          count: h_list.size,
                          counts: h_list.group_by { |h| h[:tag] }.transform_values(&:size),
                          h1_count: h1_found.size,
                          empty_count: 0,
                          headings: h_list,
                          violations: [],
                          ascii_tree: '',
                          color_tree: ''
                        }
                      end
      headings = heading_audit[:headings]
      h1_list = headings.select { |h| h[:tag] == 'h1' && !h[:empty] }

      # 3. Images & Missing Alt Tags
      images_data = extract_images(doc)

      # 4. Links (Internal vs External & Nofollow)
      links_data = extract_links(doc)

      # 5. Schema / JSON-LD Data
      schemas = extract_json_ld(doc)

      # 6. Open Graph & Twitter Cards
      og_data = {
        title: extract_meta_content(doc, 'property', 'og:title'),
        description: extract_meta_content(doc, 'property', 'og:description'),
        image: extract_meta_content(doc, 'property', 'og:image'),
        type: extract_meta_content(doc, 'property', 'og:type'),
        url: extract_meta_content(doc, 'property', 'og:url')
      }
      twitter_data = {
        card: extract_meta_content(doc, 'name', 'twitter:card'),
        title: extract_meta_content(doc, 'name', 'twitter:title'),
        description: extract_meta_content(doc, 'name', 'twitter:description'),
        image: extract_meta_content(doc, 'name', 'twitter:image')
      }

      # 7. Word Count & Content Ratio
      text_content = clean_text(doc)
      word_count = text_content.split(/\s+/).size
      reading_time_mins = (word_count / 200.0).ceil

      # 8. Indexability Diagnostics
      x_robots = @headers['x-robots-tag']&.first
      noindex = (robots_meta.to_s =~ /noindex/i) || (x_robots.to_s =~ /noindex/i)
      nofollow = (robots_meta.to_s =~ /nofollow/i) || (x_robots.to_s =~ /nofollow/i)

      # 9. Pixel Width & Character Limits
      title_pixel_est = estimate_pixel_width(title_raw)

      issues = []
      issues << { level: :error, type: :title, message: "Missing <title> tag" } if title_raw.empty?
      issues << { level: :warn, type: :title, message: "Title too long: > 60 chars (#{title_raw.length}c)" } if title_raw.length > 60
      issues << { level: :warn, type: :title, message: "Title > 568px width (~#{title_pixel_est}px, risks SERP truncation)" } if title_pixel_est > 568.0
      issues << { level: :warn, type: :meta, message: "Missing meta description" } if meta_desc.nil? || meta_desc.empty?
      issues << { level: :warn, type: :meta, message: "Meta description > 155 chars (#{meta_desc.length}c)" } if meta_desc && meta_desc.length > 155
      if heading_audit[:violations] && !heading_audit[:violations].empty?
        heading_audit[:violations].each do |v|
          lvl = case v[:severity]
                when :critical then :error
                when :warning then :warn
                else :info
                end
          issues << { level: lvl, type: :headings, message: v[:message] }
        end
      else
        issues << { level: :error, type: :headings, message: "Missing <h1> tag (0 found)" } if h1_list.empty?
        issues << { level: :warn, type: :headings, message: "Multiple <h1> tags (#{h1_list.size} found)" } if h1_list.size > 1
      end
      issues << { level: :warn, type: :images, message: "#{images_data[:missing_alt_count]} images missing alt tags" } if images_data[:missing_alt_count] > 0
      issues << { level: :critical, type: :indexability, message: "Robots noindex tag detected (Blocking Googlebot)" } if noindex

      {
        url: @url,
        http_status: @http_status,
        response_time_ms: @response_time_ms,
        indexability: {
          status: noindex ? 'NOINDEX' : 'INDEXABLE',
          noindex: !!noindex,
          nofollow: !!nofollow,
          robots_meta: robots_meta,
          x_robots: x_robots
        },
        title: {
          text: title_raw,
          length: title_raw.length,
          pixel_est: title_pixel_est,
          ok: title_raw.length.between?(30, 60) && title_pixel_est <= 568.0
        },
        meta_description: {
          text: meta_desc || '',
          length: meta_desc ? meta_desc.length : 0,
          ok: meta_desc ? meta_desc.length.between?(70, 155) : false
        },
        canonical: {
          url: canonical_url,
          self_referencing: canonical_url ? (canonical_url.chomp('/') == @url.chomp('/')) : false
        },
        headings: {
          count: heading_audit[:count],
          h1_count: heading_audit[:h1_count],
          score: heading_audit[:score],
          grade: heading_audit[:grade],
          depth: heading_audit[:depth],
          counts: heading_audit[:counts],
          empty_count: heading_audit[:empty_count],
          violations: heading_audit[:violations],
          ascii_tree: heading_audit[:ascii_tree],
          color_tree: heading_audit[:color_tree],
          keyword_analysis: heading_audit[:keyword_analysis],
          list: headings
        },
        images: images_data,
        links: links_data,
        schema: schemas,
        structured_data: { schemas: schemas },
        social: { og: og_data, twitter: twitter_data },
        stats: { word_count: word_count, reading_time_mins: reading_time_mins },
        issues: issues
      }
    end

    private

    def fetch_http(uri, limit = 5)
      raise 'Too many HTTP redirects' if limit == 0

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 15

      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 (gsc-cli)'
      req['Accept-Encoding'] = 'gzip'

      res = http.request(req)
      if res.is_a?(Net::HTTPRedirection) && res['location']
        new_loc = URI.join(uri.to_s, res['location'])
        fetch_http(new_loc, limit - 1)
      else
        res
      end
    end

    def extract_tag_content(html, tag)
      match = html.match(%r{<#{tag}[^>]*>(.*?)</#{tag}>}im)
      match ? clean_text(match[1]) : ''
    end

    def extract_meta_content(html, attr_type, attr_name)
      regex = %r{<meta\s+[^>]*#{attr_type}=["']#{Regexp.escape(attr_name)}["'][^>]*content=["'](.*?)["']}im
      m = html.match(regex)
      return clean_text(m[1]) if m

      # Also test reversed attribute order: content="..." name="..."
      regex_rev = %r{<meta\s+[^>]*content=["'](.*?)["'][^>]*#{attr_type}=["']#{Regexp.escape(attr_name)}["']}im
      m2 = html.match(regex_rev)
      m2 ? clean_text(m2[1]) : nil
    end

    def extract_link_attr(html, rel_name, target_attr)
      regex = %r{<link\s+[^>]*rel=["']#{Regexp.escape(rel_name)}["'][^>]*#{target_attr}=["'](.*?)["']}im
      m = html.match(regex)
      return m[1].strip if m

      regex_rev = %r{<link\s+[^>]*#{target_attr}=["'](.*?)["'][^>]*rel=["']#{Regexp.escape(rel_name)}["']}im
      m2 = html.match(regex_rev)
      m2 ? m2[1].strip : nil
    end

    def extract_headings(html)
      headings = []
      html.scan(%r{<(h[1-6])(?:\s+[^>]*)?>(.*?)</\1>}im) do |tag, content|
        text = clean_text(content)
        headings << { tag: tag.downcase, text: text } unless text.empty?
      end
      headings
    end

    def extract_images(html)
      all_imgs = []
      missing_alt = []

      html.scan(/<img\s+([^>]+)>/im) do |attrs_str|
        src = attrs_str[0].match(/src=["'](.*?)["']/i)&.captures&.first
        alt_match = attrs_str[0].match(/alt=(?:["'](.*?)["']|(\S+))/i)
        alt = alt_match ? (alt_match[1] || alt_match[2] || '') : nil

        img_info = { src: src, alt: alt }
        all_imgs << img_info

        if alt.nil? || alt.strip.empty?
          missing_alt << img_info
        end
      end

      {
        total: all_imgs.size,
        missing_alt_count: missing_alt.size,
        missing_alt_images: missing_alt
      }
    end

    def extract_links(doc)
      internal_links = []
      external_links = []
      all_links = []

      base_host = begin
        URI(@url).host.downcase
      rescue StandardError
        ''
      end

      doc.scan(/<a\s+([^>]+)>(.*?)<\/a>/im) do |attrs_str, anchor_inner|
        href = attrs_str.match(/href=["'](.*?)["']/i)&.captures&.first
        next if !href || href.start_with?('#', 'javascript:', 'mailto:', 'tel:')

        rel = attrs_str.match(/rel=["'](.*?)["']/i)&.captures&.first || ''
        nofollow = rel.downcase.include?('nofollow')
        anchor_text = clean_text(anchor_inner)

        link_uri = begin
          URI.join(@url, href)
        rescue StandardError
          nil
        end
        next unless link_uri

        link_item = {
          href: link_uri.to_s,
          raw_href: href,
          anchor: anchor_text,
          nofollow: nofollow
        }
        all_links << link_item

        if link_uri.host.nil? || link_uri.host.downcase == base_host || link_uri.host.downcase.end_with?(".#{base_host}")
          internal_links << link_item
        else
          external_links << link_item
        end
      end

      {
        total: all_links.size,
        internal_count: internal_links.size,
        external_count: external_links.size,
        nofollow_count: all_links.count { |l| l[:nofollow] },
        all: all_links,
        internal: internal_links,
        external: external_links
      }
    end

    def verify_links(link_items)
      verified = []
      link_items.each do |link|
        begin
          uri = URI.parse(link[:href])
          next unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == 'https')
          http.open_timeout = 3
          http.read_timeout = 5
          res = http.request_head(uri.request_uri.empty? ? '/' : uri.request_uri)

          status = res.code.to_i
          # If HEAD not allowed (405), fallback to quick GET
          if status == 405
            res = http.request_get(uri.request_uri.empty? ? '/' : uri.request_uri)
            status = res.code.to_i
          end

          verified << link.merge(status: status, ok: status.between?(200, 399))
        rescue StandardError => e
          verified << link.merge(status: 0, error: e.message, ok: false)
        end
      end
      verified
    end

    def extract_json_ld(doc)
      schemas = []
      doc.scan(%r{<script\s+[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>}im) do |script_body|
        clean_json = script_body[0].strip
        begin
          parsed = JSON.parse(clean_json)
          types = extract_schema_types(parsed)
          schemas << { valid: true, types: types, data: parsed }
        rescue JSON::ParserError => e
          schemas << { valid: false, error: e.message, raw: clean_json }
        end
      end
      schemas
    end

    def extract_schema_types(data)
      types = []
      if data.is_a?(Hash)
        types << data['@type'] if data['@type']
        data.each_value { |v| types.concat(extract_schema_types(v)) }
      elsif data.is_a?(Array)
        data.each { |item| types.concat(extract_schema_types(item)) }
      end
      types.compact.flatten.uniq
    end

    def estimate_pixel_width(str)
      # Proportional font estimation for Arial/Roboto 18px in Google SERP
      width = 0.0
      str.to_s.each_char do |ch|
        width += case ch
                 when /[WMwm]/ then 13.5
                 when /[ABCDEFGHKNOPQRSTUVXYZ]/ then 10.5
                 when /[abcdeghnopqrsuvxyz]/ then 8.5
                 when /[fIjt1l\|\ \.\:\;]/ then 4.5
                 else 9.0
                 end
      end
      width.round(1)
    end

    def clean_text(str)
      str.to_s
         .dup
         .force_encoding('UTF-8')
         .scrub
         .gsub(/<[^>]+>/, ' ')
         .gsub(/&amp;/, '&')
         .gsub(/&lt;/, '<')
         .gsub(/&gt;/, '>')
         .gsub(/&quot;/, '"')
         .gsub(/&#39;/, "'")
         .gsub(/\s+/, ' ')
         .strip
    end

    def fetch_gsc_metrics(api, page_url, domain)
      return nil unless api

      site_url = domain.start_with?('sc-domain:') ? domain : "sc-domain:#{domain}"
      res = api.query_analytics(
        site_url,
        days: 90,
        dimensions: ['query'],
        row_limit: 50,
        filters: [
          {
            dimension: 'page',
            operator: 'equals',
            expression: page_url
          }
        ]
      )
      return nil unless res[:ok]

      rows = res.dig(:data, 'rows') || []
      return nil if rows.empty?

      total_clicks = rows.sum { |r| r['clicks'] }
      total_imp = rows.sum { |r| r['impressions'] }
      avg_ctr = total_imp > 0 ? ((total_clicks.to_f / total_imp) * 100).round(2) : 0.0
      avg_pos = (rows.sum { |r| r['position'] } / rows.size).round(1)

      top_queries = rows.sort_by { |r| -r['impressions'] }.first(5).map do |r|
        { query: r['keys'][0], clicks: r['clicks'], impressions: r['impressions'], position: r['position'].round(1) }
      end

      {
        total_clicks: total_clicks,
        total_impressions: total_imp,
        ctr: avg_ctr,
        avg_position: avg_pos,
        top_queries: top_queries
      }
    rescue StandardError
      nil
    end
  end
end

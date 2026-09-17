# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module GSC
  class ImageSeo
    MODERN_FORMATS = %w[webp avif svg].freeze
    LEGACY_FORMATS = %w[png jpg jpeg gif bmp webp_fallback].freeze

    attr_reader :options, :url, :html

    def initialize(options = {})
      @options = options
    end

    def self.audit(target, options = {})
      new(options).audit(target)
    end

    def audit(target)
      @url, @html = load_content(target)
      images = extract_images(@html, @url)

      # Optionally check file size via HTTP HEAD
      if @options[:check_size]
        audit_image_sizes(images)
      end

      evaluate_health(images)
    end

    private

    def load_content(target)
      target_str = target.to_s.strip
      if target_str.match?(%r{^https?://})
        uri = URI.parse(target_str)
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
        req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 10) do |http|
          http.request(req)
        end
        [target_str, res.body.to_s.dup.force_encoding('UTF-8').scrub]
      elsif File.exist?(target_str)
        [target_str, File.read(target_str, encoding: 'UTF-8')]
      else
        [target_str.start_with?('http') ? target_str : 'local-document', target_str]
      end
    rescue StandardError => e
      [target_str.to_s, "<html><body><!-- Error: #{e.message} --></body></html>"]
    end

    def extract_images(html_str, base_url)
      images = []
      index = 0

      # Match all <img> tags
      html_str.scan(/<img\b([^>]*?)>/im) do |match|
        tag_attrs = match.first
        src = extract_attr(tag_attrs, 'src')
        next if src.nil? || src.empty?

        alt = extract_attr(tag_attrs, 'alt')
        width = extract_attr(tag_attrs, 'width')
        height = extract_attr(tag_attrs, 'height')
        loading = extract_attr(tag_attrs, 'loading')&.downcase
        fetchpriority = extract_attr(tag_attrs, 'fetchpriority')&.downcase
        decoding = extract_attr(tag_attrs, 'decoding')&.downcase
        role = extract_attr(tag_attrs, 'role')&.downcase
        aria_hidden = extract_attr(tag_attrs, 'aria-hidden')&.downcase

        is_decorative = (role == 'presentation' || role == 'none' || aria_hidden == 'true')
        resolved_src = resolve_url(src, base_url)
        ext = extract_extension(resolved_src)

        is_hero = (index == 0)

        issues = []
        issues << :missing_alt if alt.nil? && !is_decorative
        issues << :empty_alt if alt == '' && !is_decorative
        issues << :long_alt if alt && alt.length > 125
        issues << :legacy_format if LEGACY_FORMATS.include?(ext)
        issues << :missing_dimensions if (width.nil? || height.nil?)
        issues << :lcp_lazy_loaded if is_hero && loading == 'lazy'
        issues << :hero_missing_priority if is_hero && fetchpriority != 'high'
        issues << :missing_lazy if !is_hero && loading != 'lazy'

        images << {
          index: index + 1,
          src: resolved_src,
          raw_src: src,
          alt: alt,
          width: width ? width.to_i : nil,
          height: height ? height.to_i : nil,
          format: ext,
          loading: loading,
          fetchpriority: fetchpriority,
          decoding: decoding,
          is_decorative: is_decorative,
          is_hero: is_hero,
          issues: issues,
          issue_count: issues.size,
          picture_tag_snippet: build_picture_snippet(resolved_src, alt, width, height, is_hero),
          nextjs_snippet: build_nextjs_snippet(resolved_src, alt, width, height, is_hero)
        }
        index += 1
      end

      images
    end

    def audit_image_sizes(images)
      images.each do |img|
        next unless img[:src].match?(%r{^https?://})
        begin
          uri = URI.parse(img[:src])
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 4, read_timeout: 4) do |http|
            http.head(uri.request_uri)
          end
          if res['content-length']
            bytes = res['content-length'].to_i
            img[:bytes] = bytes
            img[:size_kb] = (bytes / 1024.0).round(1)
            img[:issues] << :oversized_payload if bytes > 200 * 1024
            img[:issues] << :critical_payload if bytes > 500 * 1024
          end
        rescue StandardError
          img[:bytes] = nil
        end
      end
    end

    def evaluate_health(images)
      total = images.size
      if total.zero?
        return {
          url: @url,
          total_images: 0,
          health_score: 100.0,
          grade: 'A+',
          metrics: { alt_coverage_pct: 100.0, dimension_coverage_pct: 100.0, modern_format_pct: 100.0 },
          issues_summary: {},
          images: []
        }
      end

      valid_alt_count = images.count { |img| !img[:issues].include?(:missing_alt) && !img[:issues].include?(:empty_alt) }
      valid_dims_count = images.count { |img| !img[:issues].include?(:missing_dimensions) }
      modern_format_count = images.count { |img| MODERN_FORMATS.include?(img[:format]) }
      proper_lazy_count = images.count { |img| (!img[:is_hero] && img[:loading] == 'lazy') || (img[:is_hero] && img[:loading] != 'lazy') }

      alt_coverage = ((valid_alt_count.to_f / total) * 100.0).round(1)
      dim_coverage = ((valid_dims_count.to_f / total) * 100.0).round(1)
      format_coverage = ((modern_format_count.to_f / total) * 100.0).round(1)
      lazy_coverage = ((proper_lazy_count.to_f / total) * 100.0).round(1)

      # Deductions
      score = 100.0
      score -= (100.0 - alt_coverage) * 0.35      # Alt text is critical (up to 35 pts)
      score -= (100.0 - dim_coverage) * 0.25      # CLS dimensions (up to 25 pts)
      score -= (100.0 - format_coverage) * 0.25   # Next-gen formats (up to 25 pts)
      score -= (100.0 - lazy_coverage) * 0.15     # Lazy loading & LCP priority (up to 15 pts)

      score = [[score.round(1), 100.0].min, 0.0].max
      grade = compute_grade(score)

      summary = {
        missing_alt: images.count { |i| i[:issues].include?(:missing_alt) },
        empty_alt: images.count { |i| i[:issues].include?(:empty_alt) },
        missing_dimensions: images.count { |i| i[:issues].include?(:missing_dimensions) },
        legacy_format: images.count { |i| i[:issues].include?(:legacy_format) },
        lcp_lazy_loaded: images.count { |i| i[:issues].include?(:lcp_lazy_loaded) },
        hero_missing_priority: images.count { |i| i[:issues].include?(:hero_missing_priority) },
        oversized: images.count { |i| i[:issues].include?(:oversized_payload) }
      }

      prescriptions = generate_prescriptions(summary, images)

      limit = (@options[:limit] || 20).to_i
      displayed = images.first(limit)

      {
        url: @url,
        total_images: total,
        health_score: score,
        grade: grade,
        metrics: {
          alt_coverage_pct: alt_coverage,
          dimension_coverage_pct: dim_coverage,
          modern_format_pct: format_coverage,
          lazy_loading_pct: lazy_coverage
        },
        issues_summary: summary,
        prescriptions: prescriptions,
        images: displayed
      }
    end

    def generate_prescriptions(sum, images)
      recs = []

      if sum[:missing_alt] > 0
        recs << "Add descriptive, keyword-rich alt text to #{sum[:missing_alt]} images missing the alt attribute."
      end

      if sum[:missing_dimensions] > 0
        recs << "Specify explicit width and height attributes on #{sum[:missing_dimensions]} images to eliminate Cumulative Layout Shift (CLS)."
      end

      if sum[:legacy_format] > 0
        recs << "Convert #{sum[:legacy_format]} PNG/JPEG images to modern WebP or AVIF formats for 65–80% byte reduction."
      end

      if sum[:lcp_lazy_loaded] > 0
        recs << "Remove loading=\"lazy\" from the primary above-the-fold hero image to accelerate Largest Contentful Paint (LCP)."
      end

      if sum[:hero_missing_priority] > 0
        recs << "Add fetchpriority=\"high\" to the primary hero image to trigger immediate preloading by the browser."
      end

      recs
    end

    def build_picture_snippet(src, alt, width, height, is_hero)
      base = src.sub(/\.[^.]+$/, '')
      w_attr = width ? " width=\"#{width}\"" : ""
      h_attr = height ? " height=\"#{height}\"" : ""
      loading_attr = is_hero ? " fetchpriority=\"high\"" : " loading=\"lazy\" decoding=\"async\""

      <<~HTML.strip
        <picture>
          <source srcset="#{base}.avif" type="image/avif">
          <source srcset="#{base}.webp" type="image/webp">
          <img src="#{src}" alt="#{alt || 'Descriptive image text'}"#{w_attr}#{h_attr}#{loading_attr}>
        </picture>
      HTML
    end

    def build_nextjs_snippet(src, alt, width, height, is_hero)
      w = width || 800
      h = height || 600
      priority_attr = is_hero ? " priority" : ""

      "<Image src=\"#{src}\" alt=\"#{alt || 'Descriptive image text'}\" width={#{w}} height={#{h}}#{priority_attr} />"
    end

    def compute_grade(score)
      case score
      when 90.0..100.0 then 'A+'
      when 80.0...90.0 then 'A'
      when 70.0...80.0 then 'B'
      when 55.0...70.0 then 'C'
      when 40.0...55.0 then 'D'
      else 'F'
      end
    end

    def extract_attr(tag_str, attr_name)
      if tag_str =~ /\b#{attr_name}\s*=\s*(['"])(.*?)\1/i
        $2.strip
      elsif tag_str =~ /\b#{attr_name}\s*=\s*([^\s>]+)/i
        $1.strip
      else
        nil
      end
    end

    def resolve_url(src, base)
      return src if src.match?(%r{^https?://})
      URI.join(base, src).to_s
    rescue StandardError
      src
    end

    def extract_extension(url_str)
      clean = url_str.split('?').first.split('#').first
      File.extname(clean).sub(/^\./, '').downcase
    end
  end
end

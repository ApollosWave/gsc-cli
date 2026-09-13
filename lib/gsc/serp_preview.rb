# encoding: utf-8
# frozen_string_literal: true

require 'uri'

module GSC
  class SerpPreview
    attr_reader :url, :title, :desc, :data

    DESKTOP_TITLE_PIXEL_LIMIT = 580.0
    MOBILE_TITLE_PIXEL_LIMIT  = 650.0
    DESKTOP_DESC_PIXEL_LIMIT  = 960.0
    MOBILE_DESC_PIXEL_LIMIT   = 680.0

    def initialize(url = nil, title: nil, desc: nil)
      @url = url.to_s.dup.force_encoding('UTF-8').scrub.strip
      @custom_title = title ? title.to_s.dup.force_encoding('UTF-8').scrub : nil
      @custom_desc = desc ? desc.to_s.dup.force_encoding('UTF-8').scrub : nil
    end

    def generate
      if @custom_title || @custom_desc
        generate_custom
      elsif !@url.empty? && @url.start_with?('http://', 'https://')
        generate_from_url
      else
        generate_custom
      end
    end

    def self.estimate_pixel_width(str)
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

    private

    def generate_from_url
      pa = GSC::PageAnalyzer.new(@url)
      @data = pa.fetch_and_analyze

      title = @custom_title || @data.dig(:title, :text) || 'Untitled Page'
      desc = @custom_desc || @data.dig(:meta_description, :text) || 'No meta description found.'
      canonical = @data.dig(:canonical, :url) || @url

      og = @data[:open_graph] || {}
      twitter = @data[:twitter_card] || {}

      build_result(
        url: @url,
        canonical: canonical,
        title: title,
        desc: desc,
        og_title: og['og:title'],
        og_description: og['og:description'],
        og_image: og['og:image'],
        twitter_card: twitter['twitter:card']
      )
    end

    def generate_custom
      url = @url.empty? ? "https://#{Config.default_domain || 'example.com'}/page" : @url
      title = @custom_title || 'Example Page Title — High Growth Operator'
      desc = @custom_desc || 'Discover how to automate your search presence, crawl budgets, and organic rankings with zero dependencies.'

      build_result(
        url: url,
        canonical: url,
        title: title,
        desc: desc
      )
    end

    def build_result(url:, canonical:, title:, desc:, og_title: nil, og_description: nil, og_image: nil, twitter_card: nil)
      t_px = self.class.estimate_pixel_width(title)
      d_px = self.class.estimate_pixel_width(desc)

      title_truncated = t_px > DESKTOP_TITLE_PIXEL_LIMIT
      desc_truncated  = d_px > DESKTOP_DESC_PIXEL_LIMIT

      desktop_title = title_truncated ? truncate_to_pixels(title, DESKTOP_TITLE_PIXEL_LIMIT) : title
      desktop_desc  = desc_truncated  ? truncate_to_pixels(desc, DESKTOP_DESC_PIXEL_LIMIT)  : desc

      {
        url: url,
        canonical: canonical,
        title: title,
        meta_description: desc,
        metrics: {
          title_chars: title.length,
          title_pixel_est: t_px,
          title_desktop_limit: DESKTOP_TITLE_PIXEL_LIMIT,
          title_truncated: title_truncated,
          desc_chars: desc.length,
          desc_pixel_est: d_px,
          desc_desktop_limit: DESKTOP_DESC_PIXEL_LIMIT,
          desc_truncated: desc_truncated
        },
        desktop_serp: {
          breadcrumb: format_breadcrumb(canonical),
          title: desktop_title,
          snippet: desktop_desc
        },
        mobile_serp: {
          breadcrumb: format_breadcrumb(canonical),
          title: t_px > MOBILE_TITLE_PIXEL_LIMIT ? truncate_to_pixels(title, MOBILE_TITLE_PIXEL_LIMIT) : title,
          snippet: d_px > MOBILE_DESC_PIXEL_LIMIT ? truncate_to_pixels(desc, MOBILE_DESC_PIXEL_LIMIT) : desc
        },
        social: {
          og_title: og_title || title,
          og_description: og_description || desc,
          og_image: og_image,
          twitter_card: twitter_card || 'summary_large_image'
        }
      }
    end

    def truncate_to_pixels(str, limit)
      return str if self.class.estimate_pixel_width(str) <= limit

      chars = []
      str.each_char do |c|
        candidate = "#{chars.join}#{c}..."
        break if self.class.estimate_pixel_width(candidate) > limit
        chars << c
      end
      "#{chars.join}..."
    end

    def format_breadcrumb(url_str)
      uri = URI.parse(url_str) rescue nil
      return url_str unless uri && uri.host

      domain = uri.host.sub(/^www\./, '')
      parts = uri.path.split('/').reject(&:empty?)
      if parts.empty?
        "https://#{domain}"
      else
        "https://#{domain} > #{parts.join(' > ')}"
      end
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'zlib'
require 'stringio'
require 'time'
require_relative 'ctr_curve' if File.exist?(File.expand_path('ctr_curve.rb', __dir__))
require_relative 'title_optimizer' if File.exist?(File.expand_path('title_optimizer.rb', __dir__))

module GSC
  class LowCtrRewriter
    DEFAULT_CPC_ESTIMATE = 1.50  # $1.50 baseline CPC equivalent
    MAX_SERP_PX          = 560.0 # Google SERP width target (< 580px limit)
    MIN_CHARS            = 35
    MAX_CHARS            = 60

    attr_reader :rows, :options, :results

    def self.analyze(rows, options = {})
      new(rows, options).analyze
    end

    def initialize(rows, options = {})
      @rows = rows || []
      @options = options
      @cpc_estimate = (options[:cpc] || options[:cpc_estimate] || DEFAULT_CPC_ESTIMATE).to_f
      @min_imp = (options[:min_imp] || options[:min_impressions] || 50).to_i
      @max_pos = (options[:max_pos] || 15.0).to_f
      @brand = (options[:brand_name] || (options[:brand].is_a?(String) ? options[:brand] : nil) || '').to_s.strip
      @results = []
    end

    def analyze
      # 1. Normalize rows into standard query-page records
      records = normalize_rows(@rows)

      # 2. Filter for keywords ranking on page 1-2 (pos <= max_pos) with sufficient impressions
      qualified = records.select do |r|
        r[:position] <= @max_pos && r[:impressions] >= [(@min_imp / 2), 10].max
      end

      # 3. Group by page URL to build page-level clusters
      pages_map = Hash.new { |h, k| h[k] = [] }
      qualified.each { |r| pages_map[r[:page]] << r }

      analyzed_pages = []
      total_portfolio_lost_clicks = 0

      pages_map.each do |page_url, query_records|
        page_analysis = analyze_page_cluster(page_url, query_records)
        next unless page_analysis[:is_leaking]

        analyzed_pages << page_analysis
        total_portfolio_lost_clicks += page_analysis[:lost_clicks]
      end

      # Sort by highest lost clicks (maximum traffic hemorrhage first)
      analyzed_pages.sort_by! { |p| -p[:lost_clicks] }

      limit = (@options[:limit] || 15).to_i
      limited_pages = limit > 0 ? analyzed_pages.first(limit) : analyzed_pages

      total_lost_revenue = (total_portfolio_lost_clicks * @cpc_estimate).round(2)

      {
        total_leaking_pages: analyzed_pages.size,
        total_monthly_lost_clicks: total_portfolio_lost_clicks,
        estimated_monthly_value_lost: total_lost_revenue,
        cpc_used: @cpc_estimate,
        projected_recovery: {
          conservative_25pct: (total_portfolio_lost_clicks * 0.25).round,
          realistic_50pct: (total_portfolio_lost_clicks * 0.50).round,
          full_parity_100pct: total_portfolio_lost_clicks
        },
        pages: limited_pages
      }
    end

    # Public helper to synthesize 3 title hooks for a given query and brand
    def self.generate_title_hooks(primary_query, brand = '', page_url = '')
      new([], brand_name: brand).synthesize_three_hooks(primary_query, brand, page_url)
    end

    # Public helper to synthesize high-converting meta description
    def self.generate_meta_description(primary_query, brand = '')
      new([], brand_name: brand).synthesize_meta_description(primary_query, brand)
    end

    def synthesize_three_hooks(primary_query, brand = '', page_url = '', _current_title = '')
      clean_query = title_case(primary_query.to_s.strip)
      clean_brand = brand.to_s.strip.capitalize
      brand_suffix = clean_brand.empty? ? '' : " | #{clean_brand}"

      year = Time.now.year.to_s

      rewrites = []

      # Hook 1: Authority / Power-Number Hook
      # e.g., "Best [Query] (2026 Tested Guide) | Brand"
      h1_candidate = "#{clean_query} (#{year} Tested Guide)#{brand_suffix}"
      h1_final = enforce_serp_pixel_limit(h1_candidate, clean_query, brand_suffix, "#{clean_query} (#{year})#{brand_suffix}")
      rewrites << build_hook_record('Authority & Power-Number Hook', h1_final, 'Adds proof year and tested authority to capture trust.')

      # Hook 2: Benefit & Outcome Velocity Hook
      # e.g., "How to [Query] Fast: Complete Blueprint | Brand"
      verb_prefix = clean_query.downcase.start_with?('how to') ? '' : 'How to '
      h2_candidate = "#{verb_prefix}#{clean_query} Fast: The Proven Blueprint#{brand_suffix}"
      h2_fallback = "#{verb_prefix}#{clean_query} (Step-by-Step)#{brand_suffix}"
      h2_final = enforce_serp_pixel_limit(h2_candidate, clean_query, brand_suffix, h2_fallback)
      rewrites << build_hook_record('Benefit & Velocity Hook', h2_final, 'Focuses on speed and clear outcome to induce clicks.')

      # Hook 3: Curiosity / Information-Gain Hook
      # e.g., "The Truth About [Query]: What Works Now | Brand"
      h3_candidate = "The Truth About #{clean_query} (#{year} Update)#{brand_suffix}"
      h3_fallback = "#{clean_query} Explained: 5 Proven Secrets#{brand_suffix}"
      h3_final = enforce_serp_pixel_limit(h3_candidate, clean_query, brand_suffix, h3_fallback)
      rewrites << build_hook_record('Curiosity & Information-Gain Hook', h3_final, 'Leverages high curiosity and informational advantage.')

      rewrites
    end

    def synthesize_meta_description(primary_query, brand = '')
      clean_query = title_case(primary_query.to_s.strip)
      brand_name = brand.to_s.strip.empty? ? 'our team' : brand.to_s.strip
      year = Time.now.year.to_s

      # 140 - 155 chars optimal target
      base = "Looking for #{clean_query.downcase}? Discover the #{year} verified guide by #{brand_name}. Proven strategies, exact benchmarks & practical examples inside."
      if base.length > 155
        base = "Discover the #{year} guide to #{clean_query.downcase} by #{brand_name}. Proven strategies, benchmarks and actionable tips. Read now!"
      end
      base
    end

    private

    def normalize_rows(raw_rows)
      raw_rows.map do |r|
        if r.is_a?(Hash) && r.key?('keys') && r['keys'].is_a?(Array)
          q = r['keys'][0].to_s
          p = r['keys'][1].to_s
          imp = (r['impressions'] || 0).to_i
          clk = (r['clicks'] || 0).to_i
          pos = (r['position'] || 100.0).to_f.round(1)
          ctr = (r['ctr'] ? (r['ctr'] * 100.0).round(2) : (imp > 0 ? (clk.to_f / imp * 100.0).round(2) : 0.0))
          { query: q, page: p, impressions: imp, clicks: clk, position: pos, ctr: ctr }
        elsif r.is_a?(Hash)
          q = (r[:query] || r['query']).to_s
          p = (r[:page] || r['page'] || r[:url] || r['url']).to_s
          imp = (r[:impressions] || r['impressions'] || 0).to_i
          clk = (r[:clicks] || r['clicks'] || 0).to_i
          pos = (r[:position] || r['position'] || 100.0).to_f.round(1)
          raw_ctr = r[:ctr] || r['ctr']
          ctr = if raw_ctr && raw_ctr <= 1.0 && raw_ctr > 0.0
                  (raw_ctr * 100.0).round(2)
                elsif raw_ctr
                  raw_ctr.to_f.round(2)
                else
                  imp > 0 ? (clk.to_f / imp * 100.0).round(2) : 0.0
                end
          { query: q, page: p, impressions: imp, clicks: clk, position: pos, ctr: ctr }
        end
      end.compact
    end

    def analyze_page_cluster(page_url, queries)
      total_imp = queries.sum { |q| q[:impressions] }
      total_clicks = queries.sum { |q| q[:clicks] }
      actual_ctr = total_imp > 0 ? ((total_clicks.to_f / total_imp) * 100.0).round(2) : 0.0

      # Weighted average position by impressions
      weighted_pos = if total_imp > 0
                       (queries.sum { |q| q[:position] * q[:impressions] }.to_f / total_imp).round(1)
                     else
                       queries.map { |q| q[:position] }.sum / [queries.size, 1].max
                     end

      # Benchmark expected CTR based on weighted position
      expected_ctr = benchmark_ctr_for(weighted_pos)

      # Sort queries by highest impressions to pinpoint primary search intent
      sorted_queries = queries.sort_by { |q| -q[:impressions] }
      primary_query = sorted_queries.first ? sorted_queries.first[:query] : extract_slug_topic(page_url)
      secondary_queries = sorted_queries.drop(1).first(3).map { |q| q[:query] }

      # Lost Clicks Calculation (Query-by-query sum for precision)
      page_lost_clicks = 0
      queries.each do |q|
        q_exp = benchmark_ctr_for(q[:position])
        if q[:ctr] < (q_exp * 0.70) && (q_exp - q[:ctr]) >= 1.0
          q_lost = [((q[:impressions] * ((q_exp - q[:ctr]) / 100.0))).round, 0].max
          page_lost_clicks += q_lost
        end
      end

      # Fallback to aggregate formula if individual sum was 0 but aggregate is leaking
      ctr_gap = (expected_ctr - actual_ctr).round(2)
      if page_lost_clicks == 0 && actual_ctr < (expected_ctr * 0.65) && ctr_gap >= 1.5 && total_imp >= @min_imp
        page_lost_clicks = [((total_imp * (ctr_gap / 100.0))).round, 1].max
      end

      # A page is leaking if it has lost clicks and meets threshold
      is_leaking = page_lost_clicks >= 5 && total_imp >= @min_imp

      # Determine brand token
      brand = @brand.empty? ? extract_brand_from_url(page_url) : @brand

      # Inspect current live title tag & pixel width if enabled
      current_title_info = fetch_page_title_info(page_url)

      # Synthesize 3 high-converting hook title options
      rewrites = synthesize_three_hooks(primary_query, brand, page_url, current_title_info[:title])

      # Synthesize high-converting meta description
      meta_desc = synthesize_meta_description(primary_query, brand)

      # Revenue hemorrhage
      lost_revenue = (page_lost_clicks * @cpc_estimate).round(2)

      # Severity classification
      severity = if page_lost_clicks >= 80 || (actual_ctr < expected_ctr * 0.35 && total_imp >= 200)
                   :critical
                 elsif page_lost_clicks >= 30 || (actual_ctr < expected_ctr * 0.55)
                   :high
                 else
                   :moderate
                 end

      {
        url: page_url,
        primary_query: primary_query,
        secondary_queries: secondary_queries,
        impressions: total_imp,
        clicks: total_clicks,
        position: weighted_pos,
        actual_ctr: actual_ctr,
        expected_ctr: expected_ctr,
        ctr_gap: ctr_gap,
        lost_clicks: page_lost_clicks,
        lost_revenue: lost_revenue,
        severity: severity,
        is_leaking: is_leaking,
        current_title: current_title_info[:title],
        current_pixel_width: current_title_info[:pixel_width],
        current_char_count: current_title_info[:char_count],
        current_truncated: current_title_info[:truncated],
        current_meta_desc: current_title_info[:meta_desc],
        suggested_rewrites: rewrites,
        suggested_meta: meta_desc,
        code_snippets: {
          html_title: "<title>#{rewrites.first[:title]}</title>",
          html_meta: "<meta name=\"description\" content=\"#{meta_desc}\">",
          nextjs: "export const metadata = {\n  title: \"#{rewrites.first[:title]}\",\n  description: \"#{meta_desc}\"\n};"
        }
      }
    end

    def benchmark_ctr_for(position)
      if defined?(CtrCurve) && CtrCurve.respond_to?(:benchmark_for)
        CtrCurve.benchmark_for(position)
      else
        pos = position.to_f.round
        if pos <= 1
          28.0
        else
          case pos
          when 2   then 15.5
          when 3   then 11.0
          when 4   then 8.0
          when 5   then 6.0
          when 6   then 4.5
          when 7   then 3.5
          when 8   then 2.8
          when 9   then 2.2
          when 10  then 1.8
          when 11..15 then 1.0
          else 0.5
          end
        end
      end
    end


    def build_hook_record(type, title_str, rationale)
      px = pixel_width_of(title_str)
      {
        type: type,
        title: title_str,
        char_count: title_str.size,
        pixel_width: px,
        fits_serp: px <= MAX_SERP_PX,
        rationale: rationale
      }
    end

    def enforce_serp_pixel_limit(candidate, primary_query, brand_suffix, fallback)
      if pixel_width_of(candidate) <= MAX_SERP_PX && candidate.size <= MAX_CHARS
        return candidate
      end

      if pixel_width_of(fallback) <= MAX_SERP_PX && fallback.size <= MAX_CHARS
        return fallback
      end

      # Truncate / compress query gracefully while retaining brand
      condensed_q = primary_query.split.first(4).join(' ')
      condensed = "#{condensed_q} Guide#{brand_suffix}"
      return condensed if pixel_width_of(condensed) <= MAX_SERP_PX

      "#{condensed_q}#{brand_suffix}"
    end

    def pixel_width_of(str)
      if defined?(TitleOptimizer) && TitleOptimizer.respond_to?(:estimate_pixel_width)
        TitleOptimizer.estimate_pixel_width(str)
      else
        (str.to_s.size * 8.5).round(1)
      end
    end

    def title_case(str)
      non_cap = %w[a an the and but or for nor on in at to from by of]
      words = str.to_s.split
      return '' if words.empty?

      words.each_with_index.map do |word, idx|
        if idx == 0 || !non_cap.include?(word.downcase)
          word.capitalize
        else
          word.downcase
        end
      end.join(' ')
    end

    def extract_slug_topic(url)
      uri = URI.parse(url) rescue nil
      return 'Target Page' unless uri

      slug = uri.path.to_s.split('/').last.to_s.sub(/\.[^.]+$/, '').tr('-_', ' ').strip
      slug.empty? ? 'Home Page' : title_case(slug)
    end

    def extract_brand_from_url(url)
      uri = URI.parse(url) rescue nil
      return '' unless uri && uri.host

      parts = uri.host.split('.')
      parts.size >= 2 ? parts[-2].capitalize : parts.first.capitalize
    end

    def fetch_page_title_info(url)
      # In testing or offline environments, provide clean defaults
      return default_title_info(url) unless @options[:fetch_live_titles] && url =~ %r{^https?://}

      uri = URI.parse(url) rescue nil
      return default_title_info(url) unless uri

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 3
      http.read_timeout = 4

      req = Net::HTTP::Get.new(uri.request_uri.empty? ? '/' : uri.request_uri)
      req['User-Agent'] = "Mozilla/5.0 (compatible; GSC-LowCtrRewriter/#{GSC::VERSION}; +https://apolloswave.com)"

      res = http.request(req)
      return default_title_info(url) unless res.code.to_i >= 200 && res.code.to_i < 400

      body = res.body.to_s.dup.force_encoding('UTF-8').scrub
      title_match = body.match(/<title[^>]*>(.*?)<\/title>/im)
      raw_title = title_match ? title_match[1].to_s.gsub(/\s+/, ' ').strip : ''

      meta_match = body.match(/<meta\s+[^>]*name=["']description["'][^>]*content=["']([^"']*)["']/im) ||
                   body.match(/<meta\s+[^>]*content=["']([^"']*)["'][^>]*name=["']description["']/im)
      meta_desc = meta_match ? meta_match[1].to_s.gsub(/\s+/, ' ').strip : ''

      chars = raw_title.size
      px = pixel_width_of(raw_title)

      {
        title: raw_title.empty? ? extract_slug_topic(url) : raw_title,
        char_count: chars,
        pixel_width: px,
        truncated: px > MAX_SERP_PX,
        meta_desc: meta_desc
      }
    rescue StandardError
      default_title_info(url)
    end

    def default_title_info(url)
      topic = extract_slug_topic(url)
      brand = extract_brand_from_url(url)
      synth = "#{topic} | #{brand}"
      px = pixel_width_of(synth)
      {
        title: synth,
        char_count: synth.size,
        pixel_width: px,
        truncated: px > MAX_SERP_PX,
        meta_desc: ''
      }
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'uri'

module GSC
  class ZombiePurger
    DEFAULT_DAYS = 90
    DEFAULT_THRESHOLD = 0
    EST_MONTHLY_CRAWLS_PER_ZOMBIE = 6

    # Common utility/legal URL path fragments that should remain accessible to users but noindexed
    UTILITY_PATHS = %w[
      /privacy /terms /disclaimer /legal /contact /about-us /about
      /account /login /signin /signup /register /cart /checkout
      /order /thank-you /confirmation /search /sitemap
    ].freeze

    # Common taxonomy, archive, or thin content fragments suited for 410 purge
    THIN_PATTERNS = [
      %r{/page/\d+},
      %r{/tag/},
      %r{/tags/},
      %r{/category/},
      %r{/archive/},
      %r{/author/},
      %r{/attachment/},
      %r{\?replytocom=},
      %r{\?amp=1},
      %r{/feed/?$}
    ].freeze

    STOPWORDS = %w[the a an and of to in for with on at by from is are was were this that].freeze

    attr_reader :options, :days, :threshold

    def initialize(options = {})
      @options = options
      @days = (options[:days] || DEFAULT_DAYS).to_i
      @threshold = (options[:threshold] || DEFAULT_THRESHOLD).to_i
    end

    # Convenience class method for auditing inventory against GSC pages
    def self.audit(inventory_urls, gsc_pages, options = {})
      new(options).audit(inventory_urls, gsc_pages)
    end

    # inventory_urls: Array of URL strings
    # gsc_pages: Hash of { clean_url => { impressions:, clicks:, position: } } OR Array of row hashes
    def audit(inventory_urls, gsc_pages)
      urls = normalize_url_list(inventory_urls)
      active_map = normalize_gsc_pages(gsc_pages)

      active_items = []
      zombie_items = []

      # List of all active clean URLs for candidate pillar matching
      active_candidates = active_map.keys

      urls.each do |raw_url|
        clean_key = clean_url_key(raw_url)
        page_stat = active_map[clean_key]
        impressions = page_stat ? (page_stat[:impressions] || 0) : 0
        clicks = page_stat ? (page_stat[:clicks] || 0) : 0
        position = page_stat ? (page_stat[:position] || 0.0) : 0.0

        if impressions > @threshold
          active_items << {
            url: raw_url,
            clean_url: clean_key,
            impressions: impressions,
            clicks: clicks,
            position: position
          }
        else
          # Triage this zombie URL
          triage = classify_zombie(raw_url, active_candidates)
          zombie_items << {
            url: raw_url,
            clean_url: clean_key,
            impressions: impressions,
            clicks: clicks,
            action: triage[:action],
            action_label: format_action_label(triage[:action]),
            target_url: triage[:target_url],
            rationale: triage[:rationale],
            path: uri_path(raw_url)
          }
        end
      end

      total_inventory = urls.size
      zombie_count = zombie_items.size
      active_count = active_items.size

      zombie_ratio = total_inventory > 0 ? ((zombie_count.to_f / total_inventory) * 100.0).round(1) : 0.0
      cedi = zombie_ratio # Crawl Equity Dilution Index (0-100, lower is better)
      health_score = [0.0, (100.0 - cedi)].max.round(1)
      grade = compute_grade(cedi)

      wasted_crawls_monthly = zombie_count * EST_MONTHLY_CRAWLS_PER_ZOMBIE
      wasted_crawls_annually = wasted_crawls_monthly * 12

      action_breakdown = {
        purge_410: zombie_items.count { |z| z[:action] == :purge_410 },
        redirect_301: zombie_items.count { |z| z[:action] == :redirect_301 },
        consolidate: zombie_items.count { |z| z[:action] == :consolidate },
        noindex: zombie_items.count { |z| z[:action] == :noindex }
      }

      # Filter if specific action requested
      filtered_zombies = if @options[:action]
                           target_act = @options[:action].to_s.downcase.sub('301', '').sub('410', '').to_sym
                           zombie_items.select { |z| z[:action].to_s.include?(target_act.to_s) }
                         else
                           zombie_items
                         end

      limit = (@options[:limit] || 25).to_i
      displayed_zombies = filtered_zombies.first(limit)

      {
        total_inventory: total_inventory,
        active_count: active_count,
        zombie_count: zombie_count,
        zombie_percentage: zombie_ratio,
        cedi: cedi,
        health_score: health_score,
        grade: grade,
        days: @days,
        threshold: @threshold,
        wasted_crawls_monthly: wasted_crawls_monthly,
        wasted_crawls_annually: wasted_crawls_annually,
        action_breakdown: action_breakdown,
        zombies: displayed_zombies,
        all_zombies_count: filtered_zombies.size,
        server_rules: {
          nginx: generate_nginx(displayed_zombies),
          htaccess: generate_htaccess(displayed_zombies),
          redirects: generate_redirects(displayed_zombies),
          meta_robots: generate_meta_robots
        }
      }
    end

    # Classifies a single zombie URL into a strategic action
    def classify_zombie(url, active_candidates)
      path = uri_path(url).downcase

      # 1. Check if it's a utility or legal page that should be noindexed
      if UTILITY_PATHS.any? { |up| path.start_with?(up) || path == up }
        return {
          action: :noindex,
          target_url: nil,
          rationale: "Utility/legal page necessary for user experience; noindex to preserve crawl equity."
        }
      end

      # 2. Check for thin taxonomy, pagination, or feed loops
      if THIN_PATTERNS.any? { |pat| path =~ pat }
        return {
          action: :purge_410,
          target_url: nil,
          rationale: "Thin taxonomy/archive/pagination loop; return 410 Gone to immediately drop from Googlebot index."
        }
      end

      # 3. Check for candidate active pillar target to redirect equity
      candidate = find_candidate_target(url, active_candidates)
      if candidate
        return {
          action: :redirect_301,
          target_url: candidate,
          rationale: "Topical slug overlap with active pillar '#{uri_path(candidate)}'; 301 redirect to consolidate equity."
        }
      end

      # 4. Check for dated content or parameter duplicates
      if path.match?(%r{/\d{4}/\d{2}/}) || path.include?('?')
        return {
          action: :consolidate,
          target_url: nil,
          rationale: "Dated archive or parameter URL; consolidate or rewrite into evergreen canonical."
        }
      end

      # 5. Default dead zombie: Purge 410
      {
        action: :purge_410,
        target_url: nil,
        rationale: "Zero impressions over #{@days} days with no active pillar match; return 410 Gone to reclaim crawl budget."
      }
    end

    # Finds an active page with substantial slug keyword overlap
    def find_candidate_target(zombie_url, active_candidates)
      zombie_tokens = extract_slug_tokens(zombie_url)
      return nil if zombie_tokens.empty?

      best_candidate = nil
      best_score = 0.0

      active_candidates.each do |act_url|
        act_tokens = extract_slug_tokens(act_url)
        next if act_tokens.empty?

        common = zombie_tokens & act_tokens
        next if common.empty?

        # Score based on token overlap
        overlap_ratio = common.size.to_f / [zombie_tokens.size, act_tokens.size].max
        if overlap_ratio > best_score && common.size >= 2
          best_score = overlap_ratio
          best_candidate = act_url
        end
      end

      best_score >= 0.4 ? best_candidate : nil
    end

    # Server directive generators
    def generate_nginx(zombies)
      lines = [
        "# ====================================================================",
        "# Nginx Zombie Content Purge Directives (gsc-cli)",
        "# Reclaims Googlebot crawl budget and stops 404 crawl waste",
        "# ===================================================================="
      ]

      zombies.each do |z|
        path = uri_path(z[:url])
        case z[:action]
        when :purge_410
          lines << "location = #{path} { return 410; }"
        when :redirect_301
          target_path = uri_path(z[:target_url] || '/')
          lines << "location = #{path} { return 301 #{target_path}; }"
        end
      end
      lines.join("\n")
    end

    def generate_htaccess(zombies)
      lines = [
        "# ====================================================================",
        "# Apache .htaccess Zombie Content Purge Directives (gsc-cli)",
        "# ===================================================================="
      ]

      zombies.each do |z|
        path = uri_path(z[:url])
        case z[:action]
        when :purge_410
          lines << "RedirectGone #{path}"
        when :redirect_301
          target_path = uri_path(z[:target_url] || '/')
          lines << "Redirect 301 #{path} #{target_path}"
        end
      end
      lines.join("\n")
    end

    def generate_redirects(zombies)
      lines = [
        "# ====================================================================",
        "# Netlify / Cloudflare Pages _redirects Rules (gsc-cli)",
        "# ===================================================================="
      ]

      zombies.each do |z|
        path = uri_path(z[:url])
        case z[:action]
        when :purge_410
          lines << "#{path}   410!"
        when :redirect_301
          target_path = uri_path(z[:target_url] || '/')
          lines << "#{path}   #{target_path}   301"
        end
      end
      lines.join("\n")
    end

    def generate_meta_robots
      '<meta name="robots" content="noindex, follow">'
    end

    private

    def compute_grade(cedi)
      case cedi
      when 0..10.0 then 'A'
      when 10.1..25.0 then 'B'
      when 25.1..45.0 then 'C'
      when 45.1..70.0 then 'D'
      else 'F'
      end
    end

    def format_action_label(action)
      case action
      when :purge_410 then 'PURGE (410 GONE)'
      when :redirect_301 then 'REDIRECT (301)'
      when :consolidate then 'CONSOLIDATE'
      when :noindex then 'NOINDEX'
      else action.to_s.upcase
      end
    end

    def extract_slug_tokens(url)
      path = uri_path(url)
      clean = path.sub(/\.(html?|php|aspx?)$/i, '')
      tokens = clean.split(/[\/\-_]/).map(&:downcase).reject do |t|
        t.empty? || t.match?(/^\d+$/) || STOPWORDS.include?(t)
      end
      tokens.uniq
    end

    def uri_path(url_str)
      return '/' if url_str.nil? || url_str.empty?
      u = URI.parse(url_str)
      u.path.nil? || u.path.empty? ? '/' : u.path
    rescue URI::InvalidURIError
      url_str.sub(%r{^https?://[^/]+}, '')
    end

    def clean_url_key(url_str)
      url_str.to_s.strip.downcase.sub(%r{/$}, '')
    end

    def normalize_url_list(urls)
      Array(urls).map(&:to_s).map(&:strip).reject(&:empty?).uniq
    end

    def normalize_gsc_pages(gsc_pages)
      map = {}
      if gsc_pages.is_a?(Hash)
        gsc_pages.each do |k, v|
          clean_k = clean_url_key(k)
          if v.is_a?(Hash)
            map[clean_k] = {
              clicks: (v[:clicks] || v['clicks'] || 0).to_i,
              impressions: (v[:impressions] || v['impressions'] || 0).to_i,
              position: (v[:position] || v['position'] || 0.0).to_f
            }
          else
            map[clean_k] = { clicks: 0, impressions: v.to_i, position: 0.0 }
          end
        end
      elsif gsc_pages.is_a?(Array)
        gsc_pages.each do |row|
          next unless row.is_a?(Hash)
          keys = row['keys'] || row[:keys]
          next unless keys && keys.first
          clean_k = clean_url_key(keys.first)
          map[clean_k] = {
            clicks: (row['clicks'] || row[:clicks] || 0).to_i,
            impressions: (row['impressions'] || row[:impressions] || 0).to_i,
            position: (row['position'] || row[:position] || 0.0).to_f
          }
        end
      end
      map
    end
  end
end

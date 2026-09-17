# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'set'
require 'time'

module GSC
  class CanonicalChains
    EQUITY_DECAY_PER_HOP = 0.15 # 15% estimated equity loss per redirect hop

    attr_reader :max_hops, :timeout, :user_agent

    def initialize(max_hops: 10, timeout: 8, user_agent: nil)
      @max_hops = max_hops
      @timeout = timeout
      @user_agent = user_agent || 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) gsc-cli/2.1'
    end

    # Analyze a single URL through redirect hops and canonical declarations
    def audit_url(url, gsc_rows: nil)
      start_url = normalize_url(url)
      hops = []
      visited_urls = []
      loop_detected = false
      loop_type = nil
      current_url = start_url

      @max_hops.times do |hop_index|
        if visited_urls.include?(current_url)
          loop_detected = true
          loop_type = :redirect_loop
          hops << {
            hop: hop_index + 1,
            url: current_url,
            status_code: 0,
            duration_ms: 0,
            error: "Redirect loop detected: '#{current_url}' previously visited in chain"
          }
          break
        end

        visited_urls << current_url
        hop_data = fetch_hop(current_url, hop_index + 1)
        hops << hop_data

        break if hop_data[:error]

        # Check for HTTP redirect
        if hop_data[:is_redirect] && hop_data[:redirect_target]
          next_url = hop_data[:redirect_target]
          current_url = next_url
        else
          # Final destination reached, inspect canonical
          break
        end
      end

      final_hop = hops.reject { |h| h[:error] && h[:status_code] == 0 }.last || hops.last || {}
      final_url = final_hop[:url] || current_url
      final_canonical = final_hop[:canonical_url]

      # Check for Canonical Loop: Final page's canonical points back to an earlier hop in the chain
      canonical_loop = false
      if final_canonical && normalize_url(final_canonical) != normalize_url(final_url) && visited_urls.include?(normalize_url(final_canonical))
        canonical_loop = true
        loop_detected = true
        loop_type = :mixed_canonical_loop
      end

      # Canonical target status check: if canonical points to a different URL, check if that canonical itself redirects
      canonical_status = nil
      canonical_redirects = false
      if final_canonical && normalize_url(final_canonical) != normalize_url(final_url)
        canonical_info = check_canonical_target(final_canonical)
        canonical_status = canonical_info[:status_code]
        canonical_redirects = canonical_info[:is_redirect]
      end

      redirect_hops_count = hops.count { |h| h[:is_redirect] }
      total_duration_ms = hops.sum { |h| h[:duration_ms] || 0 }.round(1)

      # Equity calculation
      # Base equity = 1.0 (100%). Each redirect hop loses ~15%. Canonical loops destroy equity completely.
      equity_retention = if canonical_loop || loop_type == :redirect_loop
                           0.0
                         elsif redirect_hops_count == 0
                           1.0
                         else
                           ((1.0 - EQUITY_DECAY_PER_HOP)**redirect_hops_count).round(4)
                         end
      equity_loss_pct = ((1.0 - equity_retention) * 100).round(1)

      # Severity classification
      issues = []
      severity = :healthy

      if loop_detected
        severity = :critical
        issues << {
          code: :loop,
          type: loop_type,
          message: loop_type == :mixed_canonical_loop ?
            "Mixed Canonical Loop: Final URL '#{final_url}' canonicalizes to '#{final_canonical}', which redirects back into chain" :
            "Infinite Redirect Loop detected at '#{current_url}'"
        }
      end

      if redirect_hops_count >= 2
        severity = :warning if severity == :healthy
        issues << {
          code: :redirect_chain,
          message: "Multi-hop redirect chain detected: #{redirect_hops_count} hops (#{hops.map { |h| h[:status_code] }.compact.join(' -> ')})"
        }
      end

      if canonical_redirects
        severity = :critical
        issues << {
          code: :canonical_redirects,
          message: "Target canonical URL '#{final_canonical}' issues a redirect (#{canonical_status}). Google ignores redirecting canonicals."
        }
      end

      if final_canonical.nil? && final_hop[:status_code] == 200
        issues << {
          code: :missing_canonical,
          message: "Final destination '#{final_url}' is missing a rel=\"canonical\" tag"
        }
      end

      # Cross-reference GSC traffic if rows provided
      traffic_at_risk = extract_gsc_traffic(visited_urls + [final_canonical].compact, gsc_rows)

      # Generate server collapse rewrite rules
      server_rules = generate_collapse_rules(start_url, final_canonical || final_url)

      {
        start_url: start_url,
        final_url: final_url,
        canonical_url: final_canonical,
        redirect_hops: redirect_hops_count,
        total_hops: hops.length,
        total_duration_ms: total_duration_ms,
        equity_retention_pct: (equity_retention * 100).round(1),
        equity_loss_pct: equity_loss_pct,
        loop_detected: loop_detected,
        loop_type: loop_type,
        canonical_loop: canonical_loop,
        canonical_status: canonical_status,
        canonical_redirects: canonical_redirects,
        severity: severity,
        issues: issues,
        traffic_at_risk: traffic_at_risk,
        server_rules: server_rules,
        hops: hops
      }
    end

    # Batch audit an array of URLs or top pages
    def audit_batch(urls, gsc_rows: nil, concurrency: 4)
      clean_urls = urls.map { |u| normalize_url(u) }.uniq
      results = []

      # Thread pool for faster batch audits
      queue = Queue.new
      clean_urls.each { |u| queue << u }
      mutex = Mutex.new

      workers = [concurrency, clean_urls.size].min
      workers = 1 if workers < 1

      threads = Array.new(workers) do
        Thread.new do
          until queue.empty?
            url = begin
                    queue.pop(true)
                  rescue ThreadError
                    nil
                  end
            break unless url

            res = audit_url(url, gsc_rows: gsc_rows)
            mutex.synchronize { results << res }
          end
        end
      end
      threads.each(&:join)

      # Summary metrics
      total_audited = results.size
      chains = results.select { |r| r[:redirect_hops] >= 2 }
      loops = results.select { |r| r[:loop_detected] }
      canonical_issues = results.select { |r| r[:canonical_redirects] || r[:canonical_loop] }
      total_equity_lost = results.sum { |r| r[:equity_loss_pct] }
      avg_equity_retention = total_audited > 0 ? (results.sum { |r| r[:equity_retention_pct] } / total_audited).round(1) : 100.0
      total_clicks_at_risk = results.sum { |r| r.dig(:traffic_at_risk, :total_clicks) || 0 }
      total_impressions_at_risk = results.sum { |r| r.dig(:traffic_at_risk, :total_impressions) || 0 }

      {
        total_audited: total_audited,
        redirect_chains_count: chains.size,
        loops_count: loops.size,
        canonical_issues_count: canonical_issues.size,
        avg_equity_retention_pct: avg_equity_retention,
        total_clicks_at_risk: total_clicks_at_risk,
        total_impressions_at_risk: total_impressions_at_risk,
        results: results.sort_by { |r| [r[:loop_detected] ? 0 : 1, -r[:redirect_hops], -r[:equity_loss_pct]] }
      }
    end

    # Generate server redirect collapse rules (Nginx, Apache, Cloudflare, Vercel/Netlify)
    def generate_collapse_rules(from_url, to_url)
      from_uri = URI.parse(from_url) rescue nil
      to_uri = URI.parse(to_url) rescue nil
      return {} unless from_uri && to_uri

      from_path = from_uri.path.empty? ? '/' : from_uri.path
      from_path += "?#{from_uri.query}" if from_uri.query

      to_target = to_url

      nginx_rule = "rewrite ^#{Regexp.escape(from_uri.path)}/?$ #{to_target} permanent;"
      apache_rule = "RewriteRule ^#{from_uri.path.sub(%r{^/}, '')}/?$ #{to_target} [R=301,L]"
      cloudflare_expr = "(http.request.full_uri eq \"#{from_url}\") -> 301 to #{to_target}"
      vercel_netlify = "#{from_path} #{to_target} 301!"

      {
        nginx: nginx_rule,
        apache: apache_rule,
        cloudflare: cloudflare_expr,
        vercel_netlify: vercel_netlify
      }
    end

    private

    def normalize_url(url)
      u = url.to_s.strip
      u = "https://#{u}" unless u =~ %r{^https?://}
      u
    end

    def fetch_hop(url, hop_num)
      uri = URI.parse(url) rescue nil
      return { hop: hop_num, url: url, error: "Invalid URI: #{url}", duration_ms: 0, status_code: 0 } unless uri && uri.host

      start_t = Time.now
      res = nil
      body_content = ''

      begin
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https'), open_timeout: @timeout, read_timeout: @timeout) do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          req['User-Agent'] = @user_agent
          req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
          res = http.request(req)
          body_content = res.body.to_s[0..25_000] if res.body # read first 25KB for head tags
        end
      rescue StandardError => e
        return {
          hop: hop_num,
          url: url,
          status_code: 0,
          duration_ms: ((Time.now - start_t) * 1000).round(1),
          error: e.message
        }
      end

      duration_ms = ((Time.now - start_t) * 1000).round(1)
      status_code = res.code.to_i
      location = res['location']
      redirect_target = nil

      if [301, 302, 303, 307, 308].include?(status_code) && location
        redirect_target = URI.join(url, location).to_s rescue location
      end

      # Extract canonical from header and HTML body
      canonical_header = extract_canonical_header(res['link'])
      canonical_html = extract_canonical_html(body_content, url)
      canonical_url = canonical_header || canonical_html

      {
        hop: hop_num,
        url: url,
        status_code: status_code,
        duration_ms: duration_ms,
        is_redirect: !redirect_target.nil?,
        redirect_target: redirect_target,
        canonical_url: canonical_url,
        canonical_source: canonical_header ? :http_header : (canonical_html ? :html_tag : nil),
        x_robots_tag: res['x-robots-tag'],
        server: res['server'],
        content_type: res['content-type']
      }
    end

    def extract_canonical_header(link_header)
      return nil unless link_header
      if link_header =~ /<([^>]+)>;\s*rel=["']?canonical["']?/i
        $1.strip
      end
    end

    def extract_canonical_html(html, base_url)
      return nil unless html && !html.empty?
      # Case-insensitive scan for <link ... rel="canonical" ... href="..." >
      if html =~ /<link\b[^>]*\brel=["']canonical["'][^>]*>/i
        tag = $&
        if tag =~ /href=["']([^"']+)["']/i
          raw_href = $1.strip
          URI.join(base_url, raw_href).to_s rescue raw_href
        end
      elsif html =~ /<link\b[^>]*\bhref=["']([^"']+)["'][^>]*\brel=["']canonical["'][^>]*>/i
        raw_href = $1.strip
        URI.join(base_url, raw_href).to_s rescue raw_href
      end
    end

    def check_canonical_target(canonical_url)
      uri = URI.parse(canonical_url) rescue nil
      return { status_code: 0, is_redirect: false } unless uri && uri.host

      begin
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https'), open_timeout: 4, read_timeout: 5) do |http|
          req = Net::HTTP::Head.new(uri.request_uri)
          req['User-Agent'] = @user_agent
          res = http.request(req)
          code = res.code.to_i
          return { status_code: code, is_redirect: [301, 302, 303, 307, 308].include?(code) }
        end
      rescue StandardError
        { status_code: 0, is_redirect: false }
      end
    end

    def extract_gsc_traffic(urls, gsc_rows)
      return { total_clicks: 0, total_impressions: 0, queries: [] } unless gsc_rows && gsc_rows.is_a?(Array)

      clean_set = urls.map { |u| normalize_url(u).downcase }.to_set
      matched_clicks = 0
      matched_impressions = 0
      matched_queries = []

      gsc_rows.each do |r|
        keys = r['keys'] || []
        page = keys.find { |k| k =~ %r{^https?://} }
        next unless page && clean_set.include?(normalize_url(page).downcase)

        clicks = (r['clicks'] || 0).to_i
        impressions = (r['impressions'] || 0).to_i
        matched_clicks += clicks
        matched_impressions += impressions
        query = keys.find { |k| k !~ %r{^https?://} }
        matched_queries << { query: query, clicks: clicks, impressions: impressions } if query
      end

      {
        total_clicks: matched_clicks,
        total_impressions: matched_impressions,
        queries: matched_queries.sort_by { |q| -q[:clicks] }.first(5)
      }
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'
require 'time'
require 'thread'

module GSC
  class Soft404Analyzer
    ERROR_TITLE_PATTERNS = [
      /404/i,
      /not\s+found/i,
      /page\s+not\s+found/i,
      /error/i,
      /oops/i,
      /unavailable/i,
      /doesn't\s+exist/i,
      /does\s+not\s+exist/i,
      /empty/i,
      /out\s+of\s+stock/i
    ].freeze

    ERROR_BODY_PATTERNS = [
      /page\s+you\s+are\s+looking\s+for\s+(cannot|can't|could\s+not)\s+be\s+found/i,
      /the\s+page\s+you\s+requested\s+does\s+not\s+exist/i,
      /we\s+couldn't\s+find\s+that\s+page/i,
      /no\s+products?\s+found/i,
      /there\s+are\s+no\s+products/i,
      /this\s+product\s+is\s+unavailable/i,
      /sorry,\s+we\s+couldn't\s+find/i,
      /404\s+-\s+file\s+or\s+directory\s+not\s+found/i,
      /item\s+not\s+available/i
    ].freeze

    attr_reader :target, :options

    def initialize(target = nil, options = {})
      if target.is_a?(Array)
        @urls = target.map(&:to_s).reject(&:empty?)
        @target = ''
      else
        @urls = []
        @target = target.to_s.dup.force_encoding('UTF-8').scrub.strip
      end
      @options = options || {}
    end

    def self.analyze(target = nil, options = {})
      new(target, options).analyze
    end

    def analyze
      urls = resolve_urls_to_audit
      return empty_target_result if urls.empty?

      concurrency = (@options[:concurrency] || 5).to_i
      concurrency = [[concurrency, 1].max, 15].min

      results = audit_urls_concurrently(urls, concurrency)

      diagnose_overall(results)
    end

    private

    def resolve_urls_to_audit
      return @urls if @urls.any?
      return @options[:urls] if @options[:urls].is_a?(Array) && @options[:urls].any?

      if @target.empty?
        []
      elsif File.exist?(@target)
        File.readlines(@target, encoding: 'UTF-8').map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
      elsif @target =~ %r{^https?://}i
        [@target]
      elsif @target =~ /\.(com|org|net|io|app|co|dev|store|edu|gov|xyz|info|biz|me)$/i
        clean_dom = @target.sub(%r{^https?://}i, '').chomp('/')
        ["https://#{clean_dom}/", "https://#{clean_dom}/gsc-verify-nonexistent-404-probe"]
      else
        []
      end
    end

    def empty_target_result
      {
        total_urls_audited: 0,
        health_score: 100.0,
        grade: 'A',
        summary: {
          healthy_count: 0,
          soft_404_count: 0,
          hard_404_count: 0,
          thin_content_count: 0,
          crawl_budget_waste_percent: 0.0
        },
        all_results: [],
        prescriptions: ['Provide a target URL, file of URLs, or domain property to audit for soft-404 errors.']
      }
    end

    def audit_urls_concurrently(urls, concurrency)
      results = []
      mutex = Mutex.new
      queue = Queue.new
      urls.each { |u| queue << u }

      threads = Array.new(concurrency) do
        Thread.new do
          loop do
            url = begin
                    queue.pop(true)
                  rescue ThreadError
                    nil
                  end
            break unless url

            res = audit_single_url(url)
            mutex.synchronize { results << res }
          end
        end
      end

      threads.each(&:join)
      results.sort_by { |r| r[:url] }
    end

    def audit_single_url(url)
      uri = URI.parse(url) rescue nil
      return { url: url, error: 'Invalid URL format', status: :invalid_url } unless uri

      # If offline / mock check for tests or local files
      if @options[:mock_results] && @options[:mock_results][url]
        return @options[:mock_results][url]
      end

      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 5
        http.read_timeout = 5

        req = Net::HTTP::Get.new(uri.request_uri, {
          'User-Agent' => 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
        })

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = http.request(req)
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        status_code = response.code.to_i
        body = response.body.to_s.dup.force_encoding('UTF-8').scrub
        headers = response.each_header.to_h

        evaluate_response(url, status_code, body, headers, ((t1 - t0) * 1000).round(1))
      rescue StandardError => e
        # Real-time network error
        network_error_result(url, e.message)
      end
    end

    def evaluate_response(url, status_code, body, headers, latency_ms)
      body_size = body.bytesize
      text = strip_tags(body)
      word_count = text.split.size

      title = extract_title(body)
      h1 = extract_h1(body)
      meta_robots = headers['x-robots-tag'].to_s

      # Soft-404 heuristics
      is_hard_404 = (status_code == 404 || status_code == 410)
      title_has_error = ERROR_TITLE_PATTERNS.any? { |pat| title =~ pat }
      body_has_error_pattern = ERROR_BODY_PATTERNS.any? { |pat| body =~ pat }
      is_thin_content = word_count < (@options[:threshold] || 100).to_i

      # Google treats 200 OK with error title or error body as soft-404
      is_soft_404 = (status_code == 200) && (title_has_error || body_has_error_pattern || (is_thin_content && word_count < 35))

      # 302 redirecting to homepage is often soft-404
      is_homepage_redirect = (status_code == 301 || status_code == 302) && (headers['location'] == '/' || headers['location'] == url.sub(%r{/[^/]+/?$}, '/'))

      classification = if is_hard_404
                         :hard_404
                       elsif is_soft_404
                         :soft_404
                       elsif is_homepage_redirect
                         :soft_404_redirect
                       elsif is_thin_content
                         :thin_content_warning
                       else
                         :healthy_200
                       end

      suggested_action = case classification
                         when :soft_404
                           "Return HTTP 404/410 or 301 redirect to relevant parent hub"
                         when :hard_404
                           "301 redirect to closely matched category or purge from sitemaps"
                         when :soft_404_redirect
                           "Redirect to exact topic match instead of generic homepage"
                         when :thin_content_warning
                           "Enrich content to >250 words or consolidate into topic hub"
                         else
                           "Optimal — verified healthy"
                         end

      suggested_redirect = suggest_redirect_target(url)

      stack = detect_tech_stack(headers, body)

      {
        url: url,
        status_code: status_code,
        latency_ms: latency_ms,
        body_size_bytes: body_size,
        word_count: word_count,
        title: title,
        h1: h1,
        meta_robots: meta_robots,
        classification: classification,
        is_soft_404: (classification == :soft_404 || classification == :soft_404_redirect),
        suggested_action: suggested_action,
        suggested_redirect: suggested_redirect,
        detected_stack: stack,
        remediation_rules: generate_server_rules(url, suggested_redirect)
      }
    end

    def network_error_result(url, err_msg)
      suggested_redirect = suggest_redirect_target(url)

      {
        url: url,
        status_code: 0,
        latency_ms: 0.0,
        body_size_bytes: 0,
        word_count: 0,
        title: "Connection Failed",
        h1: "Network Error",
        meta_robots: "",
        classification: :unreachable,
        is_soft_404: false,
        suggested_action: "Verify DNS and server network accessibility",
        suggested_redirect: suggested_redirect,
        detected_stack: { framework: 'Universal Web', server: 'Unreachable', default_format: 'nginx' },
        remediation_rules: generate_server_rules(url, suggested_redirect),
        note: "Unreachable: #{err_msg}"
      }
    end

    def diagnose_overall(results)
      total = results.size
      soft_404s = results.select { |r| r[:is_soft_404] }
      hard_404s = results.select { |r| r[:classification] == :hard_404 }
      thin_warnings = results.select { |r| r[:classification] == :thin_content_warning }
      healthy = results.select { |r| r[:classification] == :healthy_200 }
      detected_stack = results.map { |r| r[:detected_stack] }.compact.first

      # Health score calculation (100 minus penalties for soft-404 and broken pages)
      penalties = (soft_404s.size * 25.0) + (hard_404s.size * 15.0) + (thin_warnings.size * 5.0)
      score = [100.0, [0.0, 100.0 - (penalties / [total, 1].max)].max].min.round(1)

      grade = case score
              when 90.0..100.0 then 'A'
              when 80.0...90.0 then 'B'
              when 70.0...80.0 then 'C'
              when 60.0...70.0 then 'D'
              else 'F'
              end

      {
        target: @target,
        timestamp: Time.now.utc.iso8601,
        total_urls_audited: total,
        health_score: score,
        grade: grade,
        detected_stack: detected_stack,
        summary: {
          healthy_count: healthy.size,
          soft_404_count: soft_404s.size,
          hard_404_count: hard_404s.size,
          thin_content_count: thin_warnings.size,
          crawl_budget_waste_percent: total > 0 ? ((soft_404s.size + hard_404s.size) * 100.0 / total).round(1) : 0.0
        },
        soft_404_urls: soft_404s,
        all_results: results
      }
    end

    def suggest_redirect_target(url)
      uri = URI.parse(url) rescue nil
      return '/' unless uri && uri.path

      parts = uri.path.split('/').reject(&:empty?)
      if parts.size > 1
        "/#{parts[0...-1].join('/')}"
      else
        '/'
      end
    end

    def detect_tech_stack(headers = {}, body = '')
      server = (headers['server'] || '').downcase
      powered_by = (headers['x-powered-by'] || '').downcase
      body_str = body.to_s

      if headers['x-sveltekit-page'] || body_str.include?('__sveltekit') || body_str.include?('_app/immutable')
        { framework: 'SvelteKit', server: server.empty? ? 'Node/Edge' : server.capitalize, default_format: 'sveltekit' }
      elsif body_str =~ /class=["'][^"']*astro-[^"']*["']/ || body_str.include?('data-astro-cid') || body_str =~ /<meta[^>]+content=["']Astro/i
        { framework: 'Astro', server: server.empty? ? 'Static/SSR' : server.capitalize, default_format: 'astro' }
      elsif body_str.include?('___gatsby') || body_str.include?('gatsby-script') || body_str.include?('id="___gatsby"')
        { framework: 'Gatsby', server: server.empty? ? 'Static/SSR' : server.capitalize, default_format: 'gatsby' }
      elsif powered_by.include?('next.js') || body_str.include?('__NEXT_DATA__') || body_str.include?('/_next/')
        { framework: 'Next.js', server: server.empty? ? 'Vercel/Node' : server.capitalize, default_format: 'nextjs' }
      elsif body_str.include?('assets.website-files.com') || body_str =~ /<meta[^>]+content=["']Webflow/i || body_str.include?('w-mod-')
        { framework: 'Webflow', server: 'Webflow Hosting', default_format: 'webflow' }
      elsif body_str.include?('cdn.shopify.com') || body_str.include?('Shopify.shop') || headers['x-shopify-stage']
        { framework: 'Shopify', server: 'Shopify Cloud', default_format: 'shopify' }
      elsif body_str.include?('wp-content') || body_str =~ /<meta[^>]+content=["']WordPress/i
        { framework: 'WordPress', server: server.empty? ? 'PHP/Apache' : server.capitalize, default_format: 'htaccess' }
      elsif server.include?('github.com')
        { framework: 'GitHub Pages', server: 'GitHub Pages', default_format: 'github' }
      elsif server.include?('caddy')
        { framework: 'Caddy', server: 'Caddy Server', default_format: 'caddy' }
      elsif server.include?('cloudflare')
        { framework: 'Cloudflare Pages / Workers', server: 'Cloudflare', default_format: 'cloudflare' }
      elsif server.include?('nginx')
        { framework: 'Nginx', server: 'Nginx', default_format: 'nginx' }
      elsif server.include?('apache')
        { framework: 'Apache', server: 'Apache', default_format: 'htaccess' }
      else
        { framework: 'Universal Web', server: server.empty? ? 'HTTP' : server.capitalize, default_format: 'nginx' }
      end
    end

    def generate_server_rules(url, destination)
      uri = URI.parse(url) rescue nil
      path = uri ? uri.path : url
      path = "/#{path}" unless path.start_with?('/')

      escaped_path = Regexp.escape(path).gsub('\-', '-')

      {
        nginx: "rewrite ^#{escaped_path}/?$ #{destination} permanent;",
        caddy: "redir #{path} #{destination} 301",
        htaccess: "Redirect 301 #{path} #{destination}",
        cloudflare: "#{path} #{destination} 301",
        cloudflare_workers: "if (url.pathname === '#{path}') return Response.redirect(new URL('#{destination}', request.url), 301);",
        github_pages: "<meta http-equiv=\"refresh\" content=\"0; url=#{destination}\">\n<link rel=\"canonical\" href=\"#{destination}\">",
        netlify: "#{path} #{destination} 301",
        sveltekit: "if (event.url.pathname === '#{path}') redirect(301, '#{destination}');",
        astro: "'#{path}': '#{destination}',",
        gatsby: "createRedirect({ fromPath: '#{path}', toPath: '#{destination}', isPermanent: true });",
        nextjs: "{ source: '#{path}', destination: '#{destination}', permanent: true },",
        webflow: "Old Path: #{path}  ->  Redirect to Page: #{destination}",
        shopify: "#{path},#{destination}",
        vercel: { "source" => path, "destination" => destination, "permanent" => true }
      }
    end

    def extract_title(html)
      if html =~ %r{<title[^>]*>(.*?)</title>}im
        $1.strip.gsub(/\s+/, ' ')
      else
        ''
      end
    end

    def extract_h1(html)
      if html =~ %r{<h1[^>]*>(.*?)</h1>}im
        $1.strip.gsub(/<[^>]+>/, '').gsub(/\s+/, ' ')
      else
        ''
      end
    end

    def strip_tags(html)
      # Remove script, style tags
      clean = html.gsub(%r{<(script|style)[^>]*>.*?</\1>}im, ' ')
      clean.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
    end
  end
end

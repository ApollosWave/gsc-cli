# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'zlib'
require 'stringio'
require 'openssl'
require 'time'
require_relative 'config' if File.exist?(File.expand_path('config.rb', __dir__))
require_relative 'color' if File.exist?(File.expand_path('color.rb', __dir__))

module GSC
  class FirewallScanner
    AI_BOTS = {
      'GPTBot' => {
        provider: 'OpenAI',
        category: 'search_and_training',
        critical: true,
        default_ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)',
        desc: 'ChatGPT Search & OpenAI foundation model training'
      },
      'ChatGPT-User' => {
        provider: 'OpenAI',
        category: 'user_browsing',
        critical: true,
        default_ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ChatGPT-User/1.0; +https://openai.com/bot)',
        desc: 'Real-time browsing agent for ChatGPT user queries'
      },
      'ClaudeBot' => {
        provider: 'Anthropic',
        category: 'search_and_training',
        critical: true,
        default_ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ClaudeBot/1.0; +claudebot@anthropic.com)',
        desc: 'Claude AI web search & knowledge retrieval'
      },
      'Claude-Web' => {
        provider: 'Anthropic',
        category: 'user_browsing',
        critical: true,
        default_ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Claude-Web/1.0; +claudebot@anthropic.com)',
        desc: 'Real-time browsing agent for Claude.ai sessions'
      },
      'PerplexityBot' => {
        provider: 'Perplexity AI',
        category: 'search',
        critical: true,
        default_ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)',
        desc: 'Perplexity conversational search crawler'
      },
      'Google-Extended' => {
        provider: 'Google',
        category: 'training',
        critical: false,
        default_ua: 'Mozilla/5.0 (compatible; Google-Extended; +https://developers.google.com/search/docs/crawling-indexing/google-extended)',
        desc: 'Gemini and Vertex AI generative training'
      },
      'Applebot-Extended' => {
        provider: 'Apple',
        category: 'training',
        critical: false,
        default_ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15 (Applebot-Extended/0.1)',
        desc: 'Apple Intelligence foundation model training'
      },
      'CCBot' => {
        provider: 'Common Crawl',
        category: 'training',
        critical: false,
        default_ua: 'CCBot/2.0 (https://commoncrawl.org/faq/)',
        desc: 'Open-source web corpus for open LLMs (Llama, Mistral)'
      },
      'Bytespider' => {
        provider: 'ByteDance',
        category: 'search_and_training',
        critical: false,
        default_ua: 'Mozilla/5.0 (compatible; Bytespider; spider-feedback@bytedance.com)',
        desc: 'TikTok & Doubao AI crawling engine'
      },
      'cohere-ai' => {
        provider: 'Cohere',
        category: 'training',
        critical: false,
        default_ua: 'Mozilla/5.0 (compatible; cohere-ai/1.0; +https://cohere.ai/bot)',
        desc: 'Cohere enterprise LLM training crawler'
      },
      'FacebookBot' => {
        provider: 'Meta',
        category: 'training',
        critical: false,
        default_ua: 'Mozilla/5.0 (compatible; FacebookBot/1.0; +https://en-gb.facebook.com/webmasters/crawler)',
        desc: 'Meta Llama web scraping & indexer'
      },
      'Amazonbot' => {
        provider: 'Amazon',
        category: 'search_and_training',
        critical: false,
        default_ua: 'Mozilla/5.0 (compatible; Amazonbot/0.1; +https://developer.amazon.com/support/amazonbot)',
        desc: 'Amazon Alexa & Rufus shopping assistant'
      }
    }.freeze

    PROBE_CLIENTS = [
      {
        id: :browser,
        name: 'Chrome Desktop',
        persona: 'Standard Browser',
        ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
      },
      {
        id: :googlebot,
        name: 'Googlebot Desktop',
        persona: 'Google Search Indexer',
        ua: 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)'
      },
      {
        id: :gptbot,
        name: 'GPTBot',
        persona: 'OpenAI Search/Training',
        ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)'
      },
      {
        id: :claudebot,
        name: 'ClaudeBot',
        persona: 'Anthropic AI Crawler',
        ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ClaudeBot/1.0; +claudebot@anthropic.com)'
      },
      {
        id: :perplexity,
        name: 'PerplexityBot',
        persona: 'Perplexity Search',
        ua: 'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)'
      }
    ].freeze

    attr_reader :url, :uri, :options

    def initialize(url_or_domain = nil, options = {})
      raw = url_or_domain.to_s.strip
      raw = options[:domain] || Config.default_domain || '' if raw.empty?
      raise ArgumentError, 'Target URL or domain required. Example: gsc firewall <domain>' if raw.empty?
      raw = "https://#{raw}" unless raw =~ %r{^https?://}
      @url = raw
      @uri = URI.parse(@url)
      @options = options
    end

    def scan
      # 1. Fetch and parse robots.txt
      robots_data = fetch_and_audit_robots

      # 2. Run live HTTP probes across multiple user agents
      probe_results = run_live_probes

      # 3. Detect edge CDN and WAF infrastructure signatures
      edge_infrastructure = detect_edge_infrastructure(probe_results)

      # 4. Detect inadvertent silent bot blockade
      blockade_diagnosis = analyze_blockade(probe_results, robots_data)

      # 5. Compute AI Bot Accessibility Score (0-100) and grade
      score_data = calculate_score(robots_data, probe_results, blockade_diagnosis)

      # 6. Generate WAF Custom Rules & robots.txt remediation recipes
      recipes = generate_remediation_recipes(edge_infrastructure, robots_data, blockade_diagnosis)

      {
        url: @url,
        host: @uri.host,
        timestamp: Time.now.utc.iso8601,
        score: score_data[:score],
        grade: score_data[:grade],
        verdict: score_data[:verdict],
        score_breakdown: score_data[:breakdown],
        edge_infrastructure: edge_infrastructure,
        blockade_diagnosis: blockade_diagnosis,
        robots_txt: robots_data,
        live_probes: probe_results,
        remediation_recipes: recipes
      }
    end

    private

    def fetch_and_audit_robots
      robots_url = "#{@uri.scheme}://#{@uri.host}:#{@uri.port}/robots.txt"
      content = fetch_raw_robots_txt(robots_url)

      audit_entries = {}
      has_robots = !content.empty?

      AI_BOTS.each do |bot_name, meta|
        parsed = parse_robots_rules(content, bot_name)
        audit_entries[bot_name] = {
          provider: meta[:provider],
          category: meta[:category],
          critical: meta[:critical],
          desc: meta[:desc],
          status: parsed[:status], # :allowed, :restricted, :blocked
          matched_agent: parsed[:matched_agent],
          reason: parsed[:reason],
          matched_rules: parsed[:rules]
        }
      end

      # Also inspect baseline Googlebot
      googlebot_parsed = parse_robots_rules(content, 'Googlebot')
      audit_entries['Googlebot'] = {
        provider: 'Google',
        category: 'search',
        critical: true,
        desc: 'Google web search indexing crawler',
        status: googlebot_parsed[:status],
        matched_agent: googlebot_parsed[:matched_agent],
        reason: googlebot_parsed[:reason],
        matched_rules: googlebot_parsed[:rules]
      }

      {
        url: robots_url,
        present: has_robots,
        byte_size: content.bytesize,
        bots: audit_entries,
        raw_snippet: content.lines.first(15).join
      }
    end

    def fetch_raw_robots_txt(target_url)
      uri = URI.parse(target_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 5
      http.read_timeout = 7

      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = "Mozilla/5.0 (compatible; GSC-BotAuditor/#{GSC::VERSION}; +https://apolloswave.com)"
      req['Accept-Encoding'] = 'gzip'

      res = http.request(req)
      return '' unless res.code == '200'

      raw = res.body || ''
      if res['content-encoding'] =~ /gzip/i && !raw.empty?
        begin
          Zlib::GzipReader.new(StringIO.new(raw)).read
        rescue StandardError
          raw
        end
      else
        raw
      end.to_s.dup.force_encoding('UTF-8').scrub
    rescue StandardError
      ''
    end

    def parse_robots_rules(robots_text, target_bot)
      return { status: :allowed, matched_agent: nil, rules: [], reason: 'No robots.txt found (Default Allow)' } if robots_text.nil? || robots_text.empty?

      target_bot_down = target_bot.downcase
      lines = robots_text.lines.map(&:strip).reject { |l| l.start_with?('#') || l.empty? }

      blocks = []
      current_agents = []
      current_rules = []

      lines.each do |line|
        if line =~ /^user-agent:\s*(.+)$/i
          agent = $1.strip.downcase
          if current_rules.any?
            blocks << { agents: current_agents, rules: current_rules }
            current_agents = [agent]
            current_rules = []
          else
            current_agents << agent
          end
        elsif line =~ /^(allow|disallow):\s*(.*)$/i
          type = $1.downcase.to_sym
          path = $2.strip
          current_rules << { type: type, path: path }
        end
      end
      blocks << { agents: current_agents, rules: current_rules } if current_agents.any?

      # Exact match first, then wildcard '*'
      exact_block = blocks.find { |b| b[:agents].include?(target_bot_down) }
      star_block  = blocks.find { |b| b[:agents].include?('*') }
      chosen_block = exact_block || star_block

      if chosen_block.nil?
        return { status: :allowed, matched_agent: nil, rules: [], reason: 'Allowed (No matching agent directive, implicit allow)' }
      end

      matched_agent = exact_block ? target_bot : '*'
      rules = chosen_block[:rules]

      root_disallow = rules.find { |r| r[:type] == :disallow && (r[:path] == '/' || r[:path] == '/*') }
      root_allow    = rules.find { |r| r[:type] == :allow && (r[:path] == '/' || r[:path] == '/*') }

      if root_disallow && !root_allow
        {
          status: :blocked,
          matched_agent: matched_agent,
          rules: rules,
          reason: "Disallow: #{root_disallow[:path]} blocks root access"
        }
      elsif rules.any? { |r| r[:type] == :disallow && !r[:path].empty? }
        {
          status: :restricted,
          matched_agent: matched_agent,
          rules: rules,
          reason: "Partial restrictions present (#{rules.count { |r| r[:type] == :disallow }} disallow rules)"
        }
      else
        {
          status: :allowed,
          matched_agent: matched_agent,
          rules: rules,
          reason: matched_agent == '*' ? 'Allowed via wildcard (*) rules' : "Explicitly allowed for #{target_bot}"
        }
      end
    end

    def run_live_probes
      results = []

      # Standard suite of probe clients
      clients = PROBE_CLIENTS.dup

      # If custom user agent specified in options
      if @options[:user_agent] && !@options[:user_agent].to_s.strip.empty?
        clients << {
          id: :custom,
          name: 'Custom User-Agent',
          persona: 'CLI User Override',
          ua: @options[:user_agent].to_s.strip
        }
      end

      clients.each do |client|
        probe_res = probe_http(@uri, client[:ua])
        results << client.merge(probe_res)
      end

      results
    end

    def probe_http(target_uri, user_agent, timeout = 6)
      start_t = Time.now
      http = Net::HTTP.new(target_uri.host, target_uri.port)
      http.use_ssl = (target_uri.scheme == 'https')
      http.open_timeout = timeout
      http.read_timeout = timeout

      path = target_uri.request_uri.empty? ? '/' : target_uri.request_uri
      req = Net::HTTP::Get.new(path)
      req['User-Agent'] = user_agent
      req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      req['Accept-Encoding'] = 'gzip'

      res = http.request(req)
      duration_ms = ((Time.now - start_t) * 1000).round(1)

      status = res.code.to_i
      raw_body = res.body || ''
      body_str = if res['content-encoding'] =~ /gzip/i && !raw_body.empty?
                   begin
                     Zlib::GzipReader.new(StringIO.new(raw_body)).read
                   rescue StandardError
                     raw_body
                   end
                 else
                   raw_body
                 end
      body_str = body_str.to_s.dup.force_encoding('UTF-8').scrub

      headers_hash = {}
      res.each_capitalized { |k, v| headers_hash[k.downcase] = v }

      challenges = detect_waf_challenges(status, headers_hash, body_str)

      verdict = if challenges.any?
                  :challenge
                elsif status >= 200 && status < 300
                  :pass
                elsif status >= 300 && status < 400
                  :redirect
                elsif [403, 429, 503].include?(status)
                  :blocked
                else
                  :error
                end

      {
        status: status,
        duration_ms: duration_ms,
        verdict: verdict,
        challenges: challenges,
        headers: headers_hash,
        body_length: body_str.bytesize,
        title: extract_page_title(body_str)
      }
    rescue StandardError => e
      duration_ms = ((Time.now - start_t) * 1000).round(1) rescue 0
      {
        status: 0,
        duration_ms: duration_ms,
        verdict: :error,
        challenges: [],
        headers: {},
        body_length: 0,
        title: '',
        error: e.message
      }
    end

    def detect_waf_challenges(status_code, headers, body)
      indicators = []

      # Cloudflare Turnstile / Managed Challenge
      if headers['cf-mitigated'] == 'challenge' ||
         body.include?('cf-turnstile') ||
         body.include?('challenges.cloudflare.com') ||
         body.include?('Just a moment...') ||
         body.include?('Attention Required! | Cloudflare') ||
         body.include?('cf-challenge-running')
        indicators << 'Cloudflare Managed Challenge (Turnstile/JS Challenge)'
      end

      # Cloudflare 1020 / Super Bot Fight Mode block
      if [403, 503].include?(status_code) && (headers['cf-ray'] || headers['server'].to_s.include?('cloudflare'))
        indicators << 'Cloudflare Super Bot Fight Mode (403/503 Block)'
      end

      # AWS WAF Block
      if headers['x-amzn-waf-action'] == 'block' || body.include?('Request blocked by AWS WAF')
        indicators << 'AWS WAF Automated Block'
      end

      # Akamai Bot Manager
      if status_code == 403 && headers['server'].to_s.include?('akamaighost')
        indicators << 'Akamai Bot Manager Access Denied'
      end

      # DataDome
      if headers['x-datadome'] || body.include?('datadome.js')
        indicators << 'DataDome Anti-Bot Challenge'
      end

      # PerimeterX / HUMAN
      if headers.keys.any? { |k| k.start_with?('x-px-') } || body.include?('captcha.px-cdn.net')
        indicators << 'PerimeterX (HUMAN Security) Challenge'
      end

      # Generic CAPTCHA
      if body.include?('g-recaptcha') || body.include?('hcaptcha.com')
        indicators << 'Interactive CAPTCHA Challenge'
      end

      indicators
    end

    def detect_edge_infrastructure(probe_results)
      # Aggregate headers across all probes
      combined_headers = {}
      probe_results.each do |pr|
        (pr[:headers] || {}).each { |k, v| combined_headers[k] ||= v }
      end

      server = combined_headers['server'].to_s.downcase
      detected = []

      # Cloudflare
      if combined_headers['cf-ray'] || server.include?('cloudflare') || combined_headers['cf-cache-status']
        detected << {
          name: 'Cloudflare',
          role: 'Edge CDN, DDoS & WAF',
          indicators: [
            combined_headers['cf-ray'] ? "cf-ray: #{combined_headers['cf-ray']}" : nil,
            combined_headers['cf-cache-status'] ? "cache: #{combined_headers['cf-cache-status']}" : nil,
            server.include?('cloudflare') ? 'server: cloudflare' : nil
          ].compact
        }
      end

      # Shopify Edge
      if combined_headers['x-shopify-stage'] || combined_headers['x-shopid'] || combined_headers['x-shardid']
        detected << {
          name: 'Shopify Cloudflare Enterprise',
          role: 'E-commerce Edge Platform',
          indicators: ['x-shopify-stage header present']
        }
      end

      # AWS CloudFront / WAF
      if combined_headers['x-amz-cf-id'] || combined_headers['x-amzn-requestid'] || combined_headers['via'].to_s.include?('cloudfront')
        detected << {
          name: 'AWS CloudFront / WAF',
          role: 'Cloud CDN & Security Perimeter',
          indicators: [
            combined_headers['x-amz-cf-id'] ? 'x-amz-cf-id present' : nil,
            combined_headers['x-amzn-waf-action'] ? "WAF action: #{combined_headers['x-amzn-waf-action']}" : nil
          ].compact
        }
      end

      # Fastly
      if combined_headers['x-fastly-request-id'] || combined_headers['x-served-by'].to_s.include?('cache-')
        detected << {
          name: 'Fastly Edge',
          role: 'Edge Cloud CDN',
          indicators: ['x-fastly-request-id present']
        }
      end

      # Akamai
      if server.include?('akamaighost') || combined_headers['x-akamai-transformed']
        detected << {
          name: 'Akamai Edge',
          role: 'Enterprise Bot Management & CDN',
          indicators: ['Akamai Ghost Server identified']
        }
      end

      # Vercel
      if combined_headers['x-vercel-id'] || server.include?('vercel')
        detected << {
          name: 'Vercel Edge Network',
          role: 'Serverless Edge & Middleware',
          indicators: ['x-vercel-id present']
        }
      end

      # DataDome
      if combined_headers['x-datadome']
        detected << {
          name: 'DataDome Bot Protection',
          role: 'AI Bot Mitigation Firewall',
          indicators: ['x-datadome header present']
        }
      end

      detected << { name: 'Standard Web Origin', role: 'Direct Origin Server', indicators: ['Standard HTTP Server'] } if detected.empty?

      detected
    end

    def analyze_blockade(probe_results, robots_data)
      browser_probe = probe_results.find { |p| p[:id] == :browser }
      googlebot_probe = probe_results.find { |p| p[:id] == :googlebot }
      ai_probes = probe_results.reject { |p| [:browser, :googlebot].include?(p[:id]) }

      browser_ok = browser_probe && [200, 301, 302].include?(browser_probe[:status])
      googlebot_ok = googlebot_probe && [200, 301, 302].include?(googlebot_probe[:status])

      blocked_ai_probes = ai_probes.select { |p| p[:verdict] == :blocked || p[:verdict] == :challenge }
      silent_blockade = browser_ok && blocked_ai_probes.any?

      # Check robots.txt disallow conflicts
      robots_blocked_critical = (robots_data[:bots] || {}).select do |bot_name, info|
        info[:critical] && info[:status] == :blocked
      end

      severity = if silent_blockade && blocked_ai_probes.size >= 2
                   :critical
                 elsif silent_blockade || robots_blocked_critical.any?
                   :high
                 elsif ai_probes.any? { |p| p[:verdict] == :challenge }
                   :moderate
                 else
                   :none
                 end

      {
        silent_blockade_detected: silent_blockade,
        severity: severity,
        browser_accessible: browser_ok,
        googlebot_accessible: googlebot_ok,
        blocked_probes: blocked_ai_probes.map { |p| { id: p[:id], name: p[:name], status: p[:status], verdict: p[:verdict], challenges: p[:challenges] } },
        robots_critical_blocked: robots_blocked_critical.keys,
        summary: if silent_blockade
                   "🚨 SILENT BOT BLOCKADE: Standard browsers receive HTTP 200, but AI search crawlers (#{blocked_ai_probes.map { |p| p[:name] }.join(', ')}) are challenged or blocked by edge firewall rules."
                 elsif robots_blocked_critical.any?
                   "⚠️ ROBOTS.TXT BLOCKADE: Critical AI search bots (#{robots_blocked_critical.keys.join(', ')}) are blocked from crawling in /robots.txt."
                 else
                   "✅ OPEN ACCESS: AI search crawlers pass both edge firewall inspection and robots.txt governance."
                 end
      }
    end

    def calculate_score(robots_data, probe_results, blockade)
      # 1. Robots score (0 - 50 pts)
      critical_bots = ['GPTBot', 'ChatGPT-User', 'ClaudeBot', 'PerplexityBot']
      extended_bots = ['Google-Extended', 'Applebot-Extended']

      robots_score = 0
      critical_bots.each do |b|
        status = robots_data.dig(:bots, b, :status)
        robots_score += 10 if status == :allowed
        robots_score += 6  if status == :restricted
      end

      extended_bots.each do |b|
        status = robots_data.dig(:bots, b, :status)
        robots_score += 5 if status == :allowed
        robots_score += 3 if status == :restricted
      end

      # 2. Live probe score (0 - 50 pts)
      probe_score = 0
      probe_results.each do |pr|
        next if pr[:id] == :custom # Don't skew default scoring
        case pr[:verdict]
        when :pass, :redirect
          probe_score += 10
        when :challenge
          probe_score += 3
        end
      end

      # 3. Penalties
      penalty = 0
      penalty += 25 if blockade[:silent_blockade_detected]
      penalty += 15 if blockade[:robots_critical_blocked].any?

      raw_total = robots_score + probe_score - penalty
      final_score = [[0, raw_total].max, 100].min

      grade = case final_score
              when 90..100 then 'A'
              when 75..89  then 'B'
              when 60..74  then 'C'
              when 40..59  then 'D'
              else 'F'
              end

      verdict = case grade
                when 'A' then 'EXCELLENT: Fully Accessible & AI Search Ready'
                when 'B' then 'GOOD: Accessible with minor training crawler restrictions'
                when 'C' then 'MODERATE: Partial WAF challenges or restricted bots detected'
                when 'D' then 'POOR: Key AI search assistants (ChatGPT/Claude/Perplexity) blocked'
                else 'CRITICAL: Severe AI Search Blockade active'
                end

      {
        score: final_score,
        grade: grade,
        verdict: verdict,
        breakdown: {
          robots_governance: { score: robots_score, max: 50 },
          firewall_passthrough: { score: probe_score, max: 50 },
          penalties: penalty
        }
      }
    end

    def generate_remediation_recipes(edge_infra, robots_data, blockade)
      is_cloudflare = edge_infra.any? { |i| i[:name].include?('Cloudflare') }
      is_aws = edge_infra.any? { |i| i[:name].include?('AWS') }

      cf_expression = '(http.user_agent contains "GPTBot" or ' \
                      'http.user_agent contains "ChatGPT-User" or ' \
                      'http.user_agent contains "ClaudeBot" or ' \
                      'http.user_agent contains "Claude-Web" or ' \
                      'http.user_agent contains "PerplexityBot")'

      cf_rule = {
        name: 'Allow Legitimate AI Search Engines & User Browsing',
        filter_expression: cf_expression,
        action: 'Skip',
        skip_features: [
          'WAF Managed Rules',
          'Super Bot Fight Mode (Managed Challenge)',
          'Rate Limiting Rules'
        ],
        dashboard_instructions: [
          '1. Log into Cloudflare Dashboard -> Security -> WAF -> Custom Rules.',
          '2. Click "Create rule" with Name: "Allow Verified AI Search Engines".',
          "3. Set expression to:\n   #{cf_expression}",
          '4. Select Action: "Skip" and check "All remaining custom rules", "Super Bot Fight Mode", and "Managed Rules".',
          '5. Save and Deploy to prevent silent HTTP 403 / Turnstile challenges on AI search bots.'
        ]
      }

      robots_recommendation = <<~ROBOTS
        # ==============================================================================
        # AI Search Engine & Citability Governance (Optimized for ChatGPT, Claude, Perplexity)
        # ==============================================================================

        # Allow Real-Time AI Search Assistants (ChatGPT Search & Retrieval)
        User-agent: GPTBot
        Allow: /

        User-agent: ChatGPT-User
        Allow: /

        # Allow Anthropic Claude Search & Retrieval
        User-agent: ClaudeBot
        Allow: /

        User-agent: Claude-Web
        Allow: /

        # Allow Perplexity Conversational Search
        User-agent: PerplexityBot
        Allow: /

        # (Optional) Restrict model training if proprietary content protection is needed:
        # User-agent: Google-Extended
        # Disallow: /
        # User-agent: CCBot
        # Disallow: /
      ROBOTS

      {
        cloudflare_waf_rule: is_cloudflare || is_aws ? cf_rule : nil,
        recommended_robots_txt: robots_recommendation,
        action_items: [
          blockade[:silent_blockade_detected] ? 'CRITICAL: Create WAF bypass rule for GPTBot and ClaudeBot to stop 403 challenges.' : nil,
          blockade[:robots_critical_blocked].any? ? "ROBOTS: Remove Disallow: / for #{blockade[:robots_critical_blocked].join(', ')}." : nil,
          'MONITOR: Periodically run `gsc firewall <url>` to verify ongoing AI crawler accessibility.'
        ].compact
      }
    end

    def extract_page_title(html_str)
      if html_str =~ /<title[^>]*>(.*?)<\/title>/im
        $1.to_s.strip.gsub(/\s+/, ' ')
      else
        ''
      end
    end
  end
end

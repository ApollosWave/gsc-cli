# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'socket'
require 'time'
require 'date'

module GSC
  class SecurityScanner
    RECOMMENDED_HEADERS = {
      'strict-transport-security' => {
        name: 'Strict-Transport-Security',
        weight: 20,
        desc: 'Enforces HTTPS connections and prevents SSL stripping attacks (HSTS).'
      },
      'content-security-policy' => {
        name: 'Content-Security-Policy',
        weight: 20,
        desc: 'Restricts script, stylesheet, and frame sources to prevent XSS.'
      },
      'x-frame-options' => {
        name: 'X-Frame-Options',
        weight: 15,
        desc: 'Prevents clickjacking by disabling embedding in external iframes.'
      },
      'x-content-type-options' => {
        name: 'X-Content-Type-Options',
        weight: 10,
        desc: 'Prevents MIME-sniffing vulnerabilities (must be "nosniff").'
      },
      'referrer-policy' => {
        name: 'Referrer-Policy',
        weight: 10,
        desc: 'Controls referrer data sent in outgoing links (e.g. strict-origin-when-cross-origin).'
      },
      'permissions-policy' => {
        name: 'Permissions-Policy',
        weight: 10,
        desc: 'Restricts browser hardware features (camera, mic, geolocation, sensors).'
      }
    }.freeze

    LEAK_HEADERS = %w[server x-powered-by x-aspnet-version x-runtime].freeze

    attr_reader :target, :options

    def self.audit(url_or_domain, options = {})
      new(url_or_domain, options).audit
    end

    def initialize(target, options = {})
      raw = target.to_s.strip
      raw = "https://#{raw}" unless raw =~ %r{^https?://}
      @target = raw
      @options = options
    end

    def audit
      uri = URI.parse(@target) rescue nil
      return error_result("Invalid URL target: #{@target}") unless uri && uri.host

      # 1. Fetch live HTTP/HTTPS headers and HTML body
      fetch_result = fetch_page(uri)
      return error_result(fetch_result[:error]) if fetch_result[:error]

      headers = fetch_result[:headers]
      body = fetch_result[:body]
      effective_url = fetch_result[:effective_url]

      # 2. Inspect SSL/TLS certificate
      ssl_info = inspect_ssl(uri)

      # 3. Audit Security Headers
      header_audit = audit_security_headers(headers)

      # 4. Check for Info-Leakage Headers
      leak_audit = audit_leak_headers(headers)

      # 5. Scan for Active & Passive Mixed Content
      mixed_content = scan_mixed_content(body, effective_url)

      # 6. Check HSTS Preload Eligibility
      hsts_preload = evaluate_hsts_preload(headers['strict-transport-security'])

      # 7. Calculate Security Score & Grade
      scoring = calculate_security_score(header_audit, leak_audit, mixed_content, ssl_info)

      # 8. Generate 1-Click Server Directives
      server_rules = generate_server_rules(header_audit[:missing_headers])

      {
        target: @target,
        effective_url: effective_url,
        timestamp: Time.now.utc.iso8601,
        score: scoring[:score],
        grade: scoring[:grade],
        verdict: scoring[:verdict],
        ssl: ssl_info,
        headers: {
          present: header_audit[:present],
          missing: header_audit[:missing],
          leakage: leak_audit
        },
        hsts_preload: hsts_preload,
        mixed_content: mixed_content,
        recommendations: scoring[:recommendations],
        server_rules: server_rules
      }
    end

    private

    def fetch_page(uri, redirect_limit = 5, visited = Set.new)
      return { error: 'Redirect loop or excessive redirects detected' } if redirect_limit <= 0 || visited.include?(uri.to_s)
      visited.add(uri.to_s)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 5
      http.read_timeout = 8

      req = Net::HTTP::Get.new(uri.request_uri.empty? ? '/' : uri.request_uri)
      req['User-Agent'] = "Mozilla/5.0 (compatible; GSC-SecurityScanner/#{GSC::VERSION}; +https://apolloswave.com)"

      res = http.request(req)

      # Handle redirects up to redirect_limit
      if res.is_a?(Net::HTTPRedirection) && res['location']
        redirect_uri = URI.join(uri.to_s, res['location']) rescue nil
        if redirect_uri && redirect_uri.scheme =~ /^https?/
          return fetch_page(redirect_uri, redirect_limit - 1, visited)
        end
      end

      headers_hash = {}
      res.each_header { |k, v| headers_hash[k.downcase] = v }

      {
        headers: headers_hash,
        body: res.body.to_s.dup.force_encoding('UTF-8').scrub,
        effective_url: uri.to_s
      }
    rescue StandardError => e
      { error: "Failed to connect to #{uri}: #{e.message}" }
    end

    def inspect_ssl(uri)
      return { status: :not_https, message: 'URL is served over plain HTTP' } unless uri.scheme == 'https'

      port = uri.port || 443
      tcp_sock = TCPSocket.new(uri.host, port)
      ssl_ctx = OpenSSL::SSL::SSLContext.new
      ssl_sock = OpenSSL::SSL::SSLSocket.new(tcp_sock, ssl_ctx)
      ssl_sock.hostname = uri.host
      ssl_sock.connect

      cert = ssl_sock.peer_cert
      ssl_sock.close
      tcp_sock.close

      return { status: :error, message: 'No certificate presented' } unless cert

      valid_from = cert.not_before
      valid_to = cert.not_after
      days_remaining = [((valid_to - Time.now) / 86400).round, 0].max

      status = if days_remaining <= 0
                 :expired
               elsif days_remaining <= 14
                 :critical_expiry
               elsif days_remaining <= 30
                 :expiring_soon
               else
                 :valid
               end

      issuer = cert.issuer.to_a.map { |part| "#{part[0]}=#{part[1]}" }.join(', ')
      subject = cert.subject.to_a.map { |part| "#{part[0]}=#{part[1]}" }.join(', ')

      # Extract SAN domains
      san_ext = cert.extensions.find { |e| e.oid == 'subjectAltName' }
      sans = san_ext ? san_ext.value.split(',').map(&:strip) : []

      {
        status: status,
        days_remaining: days_remaining,
        valid_from: valid_from.iso8601,
        valid_to: valid_to.iso8601,
        issuer: issuer,
        subject: subject,
        san_count: sans.size,
        sans: sans.first(5),
        is_wildcard: sans.any? { |s| s.start_with?('DNS:*.') }
      }
    rescue StandardError => e
      { status: :error, message: "SSL Handshake Error: #{e.message}" }
    end

    def audit_security_headers(headers)
      present = []
      missing = []
      missing_headers = []

      RECOMMENDED_HEADERS.each do |key, spec|
        val = headers[key]
        if val && !val.strip.empty?
          quality, details = assess_header_quality(key, val)
          present << {
            header: spec[:name],
            value: val,
            quality: quality, # :optimal, :acceptable, :suboptimal
            details: details
          }
        else
          missing << {
            header: spec[:name],
            desc: spec[:desc],
            weight: spec[:weight]
          }
          missing_headers << spec[:name]
        end
      end

      {
        present: present,
        missing: missing,
        missing_headers: missing_headers
      }
    end

    def assess_header_quality(key, value)
      val = value.to_s.strip.downcase
      case key
      when 'strict-transport-security'
        if val.include?('includeSubDomains'.downcase) && val.include?('preload') && val =~ /max-age=(\d+)/ && $1.to_i >= 31536000
          [:optimal, 'Preload ready (1yr+ with subdomains and preload token)']
        elsif val =~ /max-age=(\d+)/ && $1.to_i >= 15552000
          [:acceptable, 'Valid HSTS (6+ months), but missing preload token or subdomains']
        else
          [:suboptimal, 'Short max-age (<6 months) or weak parameters']
        end
      when 'content-security-policy'
        if val.include?("'unsafe-inline'") || val.include?("'unsafe-eval'")
          [:suboptimal, "Contains 'unsafe-inline' or 'unsafe-eval' relaxation"]
        else
          [:optimal, 'Restricted directives without unsafe relaxations']
        end
      when 'x-frame-options'
        if %w[deny sameorigin].include?(val)
          [:optimal, "Configured to #{val.upcase}"]
        else
          [:suboptimal, "Non-standard value: #{value}"]
        end
      when 'x-content-type-options'
        if val == 'nosniff'
          [:optimal, 'nosniff properly configured']
        else
          [:suboptimal, "Expected 'nosniff', got: #{value}"]
        end
      when 'referrer-policy'
        if %w[strict-origin-when-cross-origin no-referrer strict-origin].include?(val)
          [:optimal, "Safe modern policy (#{value})"]
        else
          [:acceptable, "Standard policy (#{value})"]
        end
      when 'permissions-policy'
        [:optimal, 'Restricted feature permissions defined']
      else
        [:optimal, 'Present']
      end
    end

    def audit_leak_headers(headers)
      leaks = []
      LEAK_HEADERS.each do |key|
        val = headers[key]
        if val && !val.strip.empty?
          leaks << { header: key, value: val }
        end
      end
      leaks
    end

    def scan_mixed_content(html, base_url)
      return { active: [], passive: [], total: 0 } if html.to_s.empty?

      active = []
      passive = []

      # Active mixed content (Hard blocked by browsers)
      html.scan(/<(?:script|iframe|embed|object)\b[^>]*?(?:src|data)=["'](http:\/\/[^"']+)["']/i).flatten.each do |src|
        active << { type: 'script_or_frame', url: src }
      end
      html.scan(/<link\b[^>]*?rel=["']stylesheet["'][^>]*?href=["'](http:\/\/[^"']+)["']/i).flatten.each do |href|
        active << { type: 'stylesheet', url: href }
      end
      html.scan(/<link\b[^>]*?href=["'](http:\/\/[^"']+)["'][^>]*?rel=["']stylesheet["']/i).flatten.each do |href|
        active << { type: 'stylesheet', url: href }
      end

      # Passive mixed content (Degrades lock icon / warnings)
      html.scan(/<(?:img|audio|video|source)\b[^>]*?src=["'](http:\/\/[^"']+)["']/i).flatten.each do |src|
        passive << { type: 'media_or_image', url: src }
      end

      active.uniq! { |i| i[:url] }
      passive.uniq! { |i| i[:url] }

      {
        active: active,
        passive: passive,
        total: active.size + passive.size,
        has_critical_active_blocks: active.any?
      }
    end

    def evaluate_hsts_preload(hsts_header)
      return { eligible: false, reasons: ['Strict-Transport-Security header is missing'] } unless hsts_header

      val = hsts_header.to_s.downcase
      reasons = []

      # Check max-age >= 31536000
      if val =~ /max-age=(\d+)/
        age = $1.to_i
        reasons << "max-age is #{age}s (must be at least 31536000s / 1 year)" if age < 31536000
      else
        reasons << 'Missing max-age directive'
      end

      reasons << 'Missing includeSubDomains directive' unless val.include?('includesubdomains')
      reasons << 'Missing preload token' unless val.include?('preload')

      {
        eligible: reasons.empty?,
        current_header: hsts_header,
        reasons: reasons
      }
    end

    def calculate_security_score(headers_audit, leak_audit, mixed_content, ssl_info)
      score = 100
      recommendations = []

      # Headers deductions
      headers_audit[:missing].each do |m|
        score -= m[:weight]
        recommendations << "Add '#{m[:header]}' response header: #{m[:desc]}"
      end

      # Suboptimal headers
      headers_audit[:present].each do |p|
        if p[:quality] == :suboptimal
          score -= 5
          recommendations << "Strengthen '#{p[:header]}': #{p[:details]}"
        end
      end

      # Leaks
      if leak_audit.any?
        score -= 5
        leaks_list = leak_audit.map { |l| l[:header] }.join(', ')
        recommendations << "Hide server fingerprinting headers: #{leaks_list}"
      end

      # Mixed content
      if mixed_content[:active].any?
        score -= [mixed_content[:active].size * 15, 30].min
        recommendations << "CRITICAL: Fix #{mixed_content[:active].size} active mixed content HTTP scripts/frames (browsers actively block these)"
      end

      if mixed_content[:passive].any?
        score -= [mixed_content[:passive].size * 5, 15].min
        recommendations << "Replace #{mixed_content[:passive].size} passive mixed content HTTP images/media with HTTPS URLs"
      end

      # SSL
      if ssl_info[:status] == :expired
        score -= 50
        recommendations << 'CRITICAL: SSL certificate is EXPIRED!'
      elsif ssl_info[:status] == :critical_expiry
        score -= 25
        recommendations << "URGENT: SSL certificate expires in #{ssl_info[:days_remaining]} days. Renew immediately!"
      elsif ssl_info[:status] == :expiring_soon
        score -= 10
        recommendations << "Notice: SSL certificate expires in #{ssl_info[:days_remaining]} days."
      end

      score = [[score, 0].max, 100].min

      grade = case score
              when 95..100 then 'A+'
              when 85..94  then 'A'
              when 70..84  then 'B'
              when 55..69  then 'C'
              when 40..54  then 'D'
              else 'F'
              end

      verdict = case grade
                when 'A+', 'A'
                  'EXCELLENT: Enterprise-grade security headers & clean HTTPS encryption'
                when 'B'
                  'GOOD: Minor security header omissions or mild policy optimizations needed'
                when 'C'
                  'MODERATE: Multiple standard security headers missing; potential clickjacking or MIME risks'
                when 'D'
                  'POOR: Weak security posture; mixed content or critical headers missing'
                else
                  'CRITICAL: Severe vulnerabilities (Active mixed content, expired cert, or missing HSTS)'
                end

      {
        score: score,
        grade: grade,
        verdict: verdict,
        recommendations: recommendations
      }
    end

    def generate_server_rules(missing_headers = [])
      nginx_lines = []
      apache_lines = []
      vercel_lines = []

      nginx_lines << '# Recommended Security Headers (Nginx)'
      apache_lines << '<IfModule mod_headers.c>'
      vercel_lines << '/*'

      if missing_headers.include?('Strict-Transport-Security')
        nginx_lines << 'add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;'
        apache_lines << '  Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"'
        vercel_lines << '  Strict-Transport-Security: max-age=31536000; includeSubDomains; preload'
      end

      if missing_headers.include?('X-Frame-Options')
        nginx_lines << 'add_header X-Frame-Options "SAMEORIGIN" always;'
        apache_lines << '  Header always set X-Frame-Options "SAMEORIGIN"'
        vercel_lines << '  X-Frame-Options: SAMEORIGIN'
      end

      if missing_headers.include?('X-Content-Type-Options')
        nginx_lines << 'add_header X-Content-Type-Options "nosniff" always;'
        apache_lines << '  Header always set X-Content-Type-Options "nosniff"'
        vercel_lines << '  X-Content-Type-Options: nosniff'
      end

      if missing_headers.include?('Referrer-Policy')
        nginx_lines << 'add_header Referrer-Policy "strict-origin-when-cross-origin" always;'
        apache_lines << '  Header always set Referrer-Policy "strict-origin-when-cross-origin"'
        vercel_lines << '  Referrer-Policy: strict-origin-when-cross-origin'
      end

      if missing_headers.include?('Permissions-Policy')
        nginx_lines << 'add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;'
        apache_lines << '  Header always set Permissions-Policy "camera=(), microphone=(), geolocation=()"'
        vercel_lines << '  Permissions-Policy: camera=(), microphone=(), geolocation=()'
      end

      if missing_headers.include?('Content-Security-Policy')
        nginx_lines << 'add_header Content-Security-Policy "default-src \'self\'; script-src \'self\' https:; style-src \'self\' \'unsafe-inline\' https:; img-src \'self\' data: https:;" always;'
        apache_lines << '  Header always set Content-Security-Policy "default-src \'self\'; script-src \'self\' https:; style-src \'self\' \'unsafe-inline\' https:; img-src \'self\' data: https:;"'
        vercel_lines << '  Content-Security-Policy: default-src \'self\'; script-src \'self\' https:; style-src \'self\' \'unsafe-inline\' https:; img-src \'self\' data: https:;'
      end

      nginx_lines << 'server_tokens off;'
      apache_lines << '</IfModule>'

      {
        nginx: nginx_lines.join("\n"),
        apache: apache_lines.join("\n"),
        vercel_netlify: vercel_lines.join("\n")
      }
    end

    def error_result(msg)
      {
        target: @target,
        error: msg,
        score: 0,
        grade: 'F',
        verdict: "Error: #{msg}",
        ssl: { status: :error, message: msg },
        headers: { present: [], missing: [], leakage: [] },
        hsts_preload: { eligible: false, reasons: [msg] },
        mixed_content: { active: [], passive: [], total: 0 },
        recommendations: [msg],
        server_rules: { nginx: '', apache: '', vercel_netlify: '' }
      }
    end
  end
end

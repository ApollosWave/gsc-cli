# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'

module GSC
  class RobotsChecker
    attr_reader :base_url, :robots_content

    def initialize(target_url)
      @target_url = target_url.to_s.strip
      @target_url = "https://#{@target_url}" unless @target_url =~ %r{^https?://}
      @uri = URI.parse(@target_url)
      @robots_url = if (@uri.port == 80 && @uri.scheme == 'http') || (@uri.port == 443 && @uri.scheme == 'https')
                      "#{@uri.scheme}://#{@uri.host}/robots.txt"
                    else
                      "#{@uri.scheme}://#{@uri.host}:#{@uri.port}/robots.txt"
                    end
    end

    def fetch_robots_txt(url = @robots_url, limit = 3)
      return '' if limit <= 0
      uri = URI.parse(url) rescue nil
      return '' unless uri && uri.host

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 4
      http.read_timeout = 6
      req = Net::HTTP::Get.new(uri.request_uri.empty? ? '/robots.txt' : uri.request_uri)
      req['User-Agent'] = 'Mozilla/5.0 (compatible; GSC-SEO-Auditor/2.2)'

      res = http.request(req)
      if res.is_a?(Net::HTTPRedirection) && res['location']
        new_url = URI.join(url, res['location']).to_s rescue nil
        return new_url ? fetch_robots_txt(new_url, limit - 1) : ''
      end

      return '' unless res.code == '200'
      res.body.to_s.force_encoding('UTF-8').scrub
    rescue StandardError
      ''
    end

    def check(path_to_test = nil, user_agent = 'googlebot')
      @robots_content ||= fetch_robots_txt
      path = path_to_test || @uri.path
      path = '/' if path.empty?

      ua = user_agent.to_s.downcase
      rules = parse_rules(ua)

      allowed = true
      matched_rule = nil

      rules.each do |rule|
        pattern = rule[:path]
        regex = Regexp.new('^' + Regexp.escape(pattern).gsub('\*', '.*'))
        if path =~ regex
          allowed = (rule[:type] == :allow)
          matched_rule = rule
        end
      end

      {
        robots_url: @robots_url,
        user_agent: user_agent,
        tested_path: path,
        allowed: allowed,
        matched_rule: matched_rule,
        has_robots_txt: !@robots_content.empty?
      }
    end

    private

    def parse_rules(target_ua)
      groups = Hash.new { |h, k| h[k] = [] }
      current_uas = []
      in_directives = false

      @robots_content.each_line do |line|
        line = line.strip.sub(/#.*$/, '')
        next if line.empty?

        if line =~ /^User-agent:\s*(.+)$/i
          if in_directives
            current_uas = []
            in_directives = false
          end
          current_uas << $1.strip.downcase
        elsif line =~ /^Disallow:\s*(.*)$/i
          in_directives = true
          val = $1.strip
          current_uas.each { |ua| groups[ua] << { type: :disallow, path: val } unless val.empty? }
        elsif line =~ /^Allow:\s*(.*)$/i
          in_directives = true
          val = $1.strip
          current_uas.each { |ua| groups[ua] << { type: :allow, path: val } unless val.empty? }
        end
      end

      # RFC 9309: Specific user-agent match takes absolute precedence over wildcard '*'
      if groups.key?(target_ua) && groups[target_ua].any?
        groups[target_ua]
      elsif groups.key?('*')
        groups['*']
      else
        []
      end
    end
  end
end

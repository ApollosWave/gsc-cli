# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'set'

module GSC
  class NetworkTracer
    attr_reader :start_url, :max_hops

    def initialize(start_url, max_hops: 10)
      @start_url = start_url.to_s.strip
      @start_url = "http://#{@start_url}" unless @start_url =~ %r{^https?://}
      @max_hops = max_hops
    end

    def trace
      current_url = @start_url
      hops = []
      visited = Set.new

      @max_hops.times do |hop_idx|
        break if visited.include?(current_url)
        visited << current_url

        uri = URI.parse(current_url) rescue nil
        break unless uri && uri.host

        start_t = Time.now
        res = nil

        begin
          Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https'), open_timeout: 5, read_timeout: 10) do |http|
            req = Net::HTTP::Get.new(uri.request_uri)
            req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) gsc-cli/2.1'
            res = http.request(req)
          end
        rescue StandardError => e
          hops << {
            hop: hop_idx + 1,
            url: current_url,
            error: e.message
          }
          break
        end

        duration_ms = ((Time.now - start_t) * 1000).round(1)
        status_code = res.code.to_i
        location = res['location']

        hop_info = {
          hop: hop_idx + 1,
          url: current_url,
          status_code: status_code,
          duration_ms: duration_ms,
          x_robots_tag: res['x-robots-tag'],
          canonical_header: res['link'] =~ /rel="canonical"/i ? res['link'] : nil,
          hsts: res['strict-transport-security'],
          content_type: res['content-type'],
          server: res['server']
        }

        hops << hop_info

        if [301, 302, 303, 307, 308].include?(status_code) && location
          next_url = begin
                       URI.join(current_url, location.strip).to_s
                     rescue StandardError
                       nil
                     end
          break unless next_url
          current_url = next_url
        else
          break
        end
      end

      total_time = hops.sum { |h| h[:duration_ms] || 0 }.round(1)
      final_hop = hops.last || {}
      is_redirect_chain = hops.length > 2

      {
        start_url: @start_url,
        final_url: final_hop[:url],
        total_hops: hops.length,
        total_duration_ms: total_time,
        is_redirect_chain: is_redirect_chain,
        hops: hops
      }
    end
  end
end

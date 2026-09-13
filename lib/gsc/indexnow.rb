# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'

module GSC
  class IndexNow
    ENDPOINT = 'https://api.indexnow.org/indexnow'

    def self.generate_key
      OpenSSL::Random.random_bytes(16).unpack1('H*')
    end

    def self.get_or_create_key
      existing = Config.get('indexnow_key') || ENV['INDEXNOW_KEY']
      return existing if existing && !existing.strip.empty?

      new_key = generate_key
      Config.set('indexnow_key', new_key)
      new_key
    end

    def self.set_key(key)
      clean = key.to_s.strip
      Config.set('indexnow_key', clean)
      clean
    end

    def self.submit(urls, key: nil, host: nil)
      urls = Array(urls).map(&:to_s).map(&:strip).reject(&:empty?)
      raise 'No URLs provided for IndexNow submission' if urls.empty?

      first_uri = URI.parse(urls.first) rescue nil
      detected_host = host || (first_uri ? first_uri.host : Config.default_domain)
      raise 'Could not determine host for IndexNow submission. Please provide full URLs (e.g. https://example.com/page)' unless detected_host

      detected_host = detected_host.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')

      active_key = key || get_or_create_key

      payload = {
        host: detected_host,
        key: active_key,
        keyLocation: "https://#{detected_host}/#{active_key}.txt",
        urlList: urls
      }

      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 20

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json; charset=utf-8'
      req['User-Agent'] = 'gsc-cli IndexNow/1.0'
      req.body = JSON.generate(payload)

      res = http.request(req)

      status_msg = case res.code.to_i
                   when 200 then 'OK (URLs submitted successfully)'
                   when 202 then 'Accepted (Key pending verification)'
                   when 400 then 'Bad Request (Invalid JSON or URL format)'
                   when 403 then "Forbidden (Key invalid or https://#{detected_host}/#{active_key}.txt missing)"
                   when 422 then 'Unprocessable Entity (URLs do not match host)'
                   when 429 then 'Too Many Requests'
                   else "HTTP #{res.code}"
                   end

      {
        success: [200, 202].include?(res.code.to_i),
        http_code: res.code.to_i,
        message: status_msg,
        host: detected_host,
        key: active_key,
        key_location: "https://#{detected_host}/#{active_key}.txt",
        submitted_urls: urls.size,
        urls: urls
      }
    end

    def self.submit_sitemap(sitemap_path_or_url, key: nil, limit: nil)
      urls = SitemapLoader.resolve_urls(sitemap_path_or_url, quiet: true)
      raise "No URLs found in sitemap: #{sitemap_path_or_url}" if urls.empty?

      urls = urls.first(limit) if limit && limit.positive?
      submit(urls, key: key)
    end
  end
end

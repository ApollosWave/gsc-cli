# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'zlib'
require 'stringio'

module GSC
  class Client
    def initialize(token:)
      @token = token
    end

    def get(url)
      uri = URI(url)
      req = Net::HTTP::Get.new(uri)
      prepare_headers(req)
      execute(uri, req)
    end

    def post(url, body)
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      prepare_headers(req)
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(body)
      execute(uri, req)
    end

    def put(url)
      uri = URI(url)
      req = Net::HTTP::Put.new(uri)
      prepare_headers(req)
      execute(uri, req)
    end

    private

    def prepare_headers(req)
      req['Authorization'] = "Bearer #{@token}"
      req['Accept-Encoding'] = 'gzip'
      ver = defined?(GSC::VERSION) ? GSC::VERSION : '1.0.0'
      req['User-Agent'] = "gsc-cli/#{ver} (gzip)"
    end

    def execute(uri, req)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(req)

      # Transparent gzip decompression
      raw_body = response.body
      body_str = if response['content-encoding'] =~ /gzip/i && raw_body && !raw_body.empty?
                   begin
                     Zlib::GzipReader.new(StringIO.new(raw_body)).read
                   rescue Zlib::GzipFile::Error, Zlib::Error
                     raw_body
                   end
                 else
                   raw_body
                 end

      body_str = body_str.to_s.dup.force_encoding('UTF-8').scrub if body_str

      body = if body_str && !body_str.strip.empty?
               begin
                 parsed = JSON.parse(body_str)
                 parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : { 'value' => parsed }
               rescue JSON::ParserError, Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
                 { 'error' => { 'message' => body_str }, 'raw' => body_str }
               end
             else
               {}
             end

      {
        ok: response.is_a?(Net::HTTPSuccess),
        status: response.code.to_i,
        data: body,
        compressed: (response['content-encoding'] =~ /gzip/i ? true : false)
      }
    rescue StandardError => e
      {
        ok: false,
        status: 0,
        data: { 'error' => { 'message' => e.message } }
      }
    end
  end
end

# frozen_string_literal: true

require_relative 'test_helper'
require 'zlib'
require 'stringio'

class ClientTest < Minitest::Test
  class FakeHTTP
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def initialize(response)
      @response = response
    end

    def request(_req)
      @response
    end
  end

  def setup
    @client = GSC::Client.new(token: 'test_token')
  end

  def with_stubbed_http(fake_http)
    Net::HTTP.singleton_class.alias_method :orig_new, :new
    Net::HTTP.define_singleton_method(:new) { |*| fake_http }
    yield
  ensure
    Net::HTTP.singleton_class.alias_method :new, :orig_new
    Net::HTTP.singleton_class.remove_method :orig_new
  end

  def gzip_string(str)
    sio = StringIO.new
    gz = Zlib::GzipWriter.new(sio)
    gz.write(str)
    gz.close
    sio.string
  end

  def test_gzipped_utf8_json_decompression_and_parsing
    payload = {
      'rows' => [
        {
          'keys' => ["seel’s checkout friction — is it “worth it”? 🚀"],
          'clicks' => 5,
          'impressions' => 120,
          'ctr' => 0.0416,
          'position' => 3.2
        },
        {
          'keys' => ['café résumé Überprüfung 日本語'],
          'clicks' => 2,
          'impressions' => 50,
          'ctr' => 0.04,
          'position' => 1.5
        }
      ]
    }
    json_str = JSON.generate(payload)
    gzipped_body = gzip_string(json_str)

    # Mock HTTP response
    mock_response = Net::HTTPOK.new('1.1', '200', 'OK')
    mock_response['content-encoding'] = 'gzip'
    allow_body_read(mock_response, gzipped_body)
    fake_http = FakeHTTP.new(mock_response)

    with_stubbed_http(fake_http) do
      res = @client.get('https://searchconsole.googleapis.com/test')
      assert res[:ok]
      assert_equal 200, res[:status]
      assert res[:compressed]

      # Critical: Verify data is a Hash and .dig works without raising "String does not have #dig method"
      assert_kind_of Hash, res[:data]
      rows = res.dig(:data, 'rows')
      refute_nil rows
      assert_equal 2, rows.size
      assert_equal "seel’s checkout friction — is it “worth it”? 🚀", rows.first['keys'].first
      assert_equal 'café résumé Überprüfung 日本語', rows.last['keys'].first
    end
  end

  def test_empty_response_returns_empty_hash_safely
    mock_response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow_body_read(mock_response, '')
    fake_http = FakeHTTP.new(mock_response)

    with_stubbed_http(fake_http) do
      res = @client.get('https://searchconsole.googleapis.com/test')
      assert res[:ok]
      assert_kind_of Hash, res[:data]
      assert_nil res.dig(:data, 'rows')
    end
  end

  def test_html_error_response_wrapped_in_hash_so_dig_never_crashes
    html_error = '<html><body>502 Bad Gateway</body></html>'
    mock_response = Net::HTTPBadGateway.new('1.1', '502', 'Bad Gateway')
    allow_body_read(mock_response, html_error)
    fake_http = FakeHTTP.new(mock_response)

    with_stubbed_http(fake_http) do
      res = @client.get('https://searchconsole.googleapis.com/test')
      refute res[:ok]
      assert_equal 502, res[:status]
      assert_kind_of Hash, res[:data]

      # Critical: Calling .dig on error responses must return the error message gracefully, never throw
      assert_equal html_error, res.dig(:data, 'error', 'message')
      assert_nil res.dig(:data, 'rows')
    end
  end

  def test_corrupted_gzip_payload_graceful_fallback
    corrupt_body = "not actually gzipped \x00\x01\x02"
    mock_response = Net::HTTPOK.new('1.1', '200', 'OK')
    mock_response['content-encoding'] = 'gzip'
    allow_body_read(mock_response, corrupt_body)
    fake_http = FakeHTTP.new(mock_response)

    with_stubbed_http(fake_http) do
      res = @client.get('https://searchconsole.googleapis.com/test')
      assert res[:ok]
      assert_kind_of Hash, res[:data]
      assert_nil res.dig(:data, 'rows')
    end
  end

  private

  def allow_body_read(response, body_string)
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, body_string)
  end
end

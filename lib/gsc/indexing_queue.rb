# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'date'
require 'time'

module GSC
  class IndexingQueue
    QUEUE_FILE = File.join(Config::CONFIG_DIR, 'indexing_queue.json')
    DAILY_LIMIT = 200

    attr_reader :state

    def initialize(file_path = QUEUE_FILE)
      @file_path = file_path
      @state = load_state
    end

    def add_urls(urls)
      normalized = Array(urls).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      # Only keep valid http(s) URLs
      valid_urls = normalized.select { |u| u.start_with?('http://', 'https://') }

      existing_pending = @state['pending'] || []
      new_urls = valid_urls - existing_pending

      @state['pending'] = existing_pending + new_urls
      save_state
      new_urls.size
    end

    def status
      check_quota_reset!
      used = @state['daily_quota_used'] || 0
      remaining = [DAILY_LIMIT - used, 0].max

      {
        pending_count: (@state['pending'] || []).size,
        submitted_count: (@state['submitted'] || []).size,
        failed_count: (@state['failed'] || []).size,
        daily_quota_limit: DAILY_LIMIT,
        daily_quota_used: used,
        daily_quota_remaining: remaining,
        last_reset_date: @state['last_reset_date']
      }
    end

    def clear(scope = :all)
      if scope == :pending
        @state['pending'] = []
      else
        @state['pending'] = []
        @state['submitted'] = []
        @state['failed'] = []
      end
      save_state
    end

    def process_batch(api, batch_size: 50, dry_run: false, delay_sec: 0.15)
      check_quota_reset!
      used = @state['daily_quota_used'] || 0
      remaining_quota = [DAILY_LIMIT - used, 0].max

      if remaining_quota <= 0 && !dry_run
        return {
          status: :quota_exhausted,
          message: "Daily quota of #{DAILY_LIMIT} requests reached for today (#{@state['last_reset_date']}). Next reset at 00:00 UTC.",
          processed: 0,
          remaining_in_queue: (@state['pending'] || []).size
        }
      end

      to_process_count = [batch_size.to_i, remaining_quota].min
      urls = (@state['pending'] || []).shift(to_process_count)

      if urls.empty?
        return {
          status: :queue_empty,
          message: 'Indexing queue is empty. Use `gsc index-batch add <url|sitemap>` to enqueue URLs.',
          processed: 0,
          remaining_in_queue: 0
        }
      end

      results = []
      successful = 0
      failed = 0

      urls.each_with_index do |url, idx|
        if dry_run
          results << { url: url, status: 'DRY_RUN', ok: true }
          successful += 1
          next
        end

        res = api.publish_url(url, 'URL_UPDATED')
        if res[:ok]
          successful += 1
          @state['submitted'] ||= []
          @state['submitted'] << {
            url: url,
            status: res[:status],
            submitted_at: Time.now.utc.iso8601
          }
          @state['daily_quota_used'] = (@state['daily_quota_used'] || 0) + 1
          results << { url: url, status: 'SUCCESS', http_code: res[:status], ok: true }
        else
          failed += 1
          @state['failed'] ||= []
          @state['failed'] << {
            url: url,
            error: res[:data],
            failed_at: Time.now.utc.iso8601
          }
          results << { url: url, status: 'FAILED', error: res[:data], ok: false }
        end

        sleep(delay_sec) if delay_sec > 0 && idx < urls.size - 1
      end

      # In dry_run, restore pending list so URLs aren't lost
      if dry_run
        @state['pending'] = urls + (@state['pending'] || [])
      else
        save_state
      end

      {
        status: :success,
        processed: urls.size,
        successful: successful,
        failed: failed,
        dry_run: dry_run,
        remaining_in_queue: (@state['pending'] || []).size,
        daily_quota_remaining: dry_run ? remaining_quota : [DAILY_LIMIT - @state['daily_quota_used'], 0].max,
        results: results
      }
    end

    private

    def check_quota_reset!
      today = Date.today.to_s
      if @state['last_reset_date'] != today
        @state['last_reset_date'] = today
        @state['daily_quota_used'] = 0
        save_state
      end
    end

    def load_state
      return default_state unless File.exist?(@file_path)

      data = JSON.parse(File.read(@file_path))
      data.is_a?(Hash) ? data : default_state
    rescue StandardError
      default_state
    end

    def save_state
      FileUtils.mkdir_p(File.dirname(@file_path))
      File.write(@file_path, JSON.pretty_generate(@state))
    rescue StandardError => e
      # Silently handle disk write errors
    end

    def default_state
      {
        'daily_quota_limit' => DAILY_LIMIT,
        'daily_quota_used' => 0,
        'last_reset_date' => Date.today.to_s,
        'pending' => [],
        'submitted' => [],
        'failed' => []
      }
    end
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/gsc/config'
require_relative '../lib/gsc/indexing_queue'

class IndexingQueueTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('gsc_test_queue')
    @queue_file = File.join(@tmpdir, 'queue.json')
    @queue = GSC::IndexingQueue.new(@queue_file)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if File.exist?(@tmpdir)
  end

  def test_initial_queue_state
    st = @queue.status
    assert_equal 0, st[:pending_count]
    assert_equal 0, st[:daily_quota_used]
    assert_equal 200, st[:daily_quota_remaining]
  end

  def test_add_urls_filters_and_deduplicates
    urls = [
      'https://example.com/page-1',
      'https://example.com/page-2',
      'not-a-valid-url',
      'https://example.com/page-1' # Duplicate
    ]

    added = @queue.add_urls(urls)
    assert_equal 2, added

    st = @queue.status
    assert_equal 2, st[:pending_count]
  end

  def test_process_batch_dry_run_preserves_queue
    @queue.add_urls(['https://example.com/p1', 'https://example.com/p2'])
    fake_api = Object.new

    result = @queue.process_batch(fake_api, batch_size: 10, dry_run: true)
    assert_equal :success, result[:status]
    assert_equal 2, result[:processed]
    assert_equal 2, result[:successful]
    assert result[:dry_run]

    # In dry run, pending URLs are preserved
    assert_equal 2, @queue.status[:pending_count]
  end

  def test_process_batch_live_tracks_quota_and_state
    @queue.add_urls(['https://example.com/success', 'https://example.com/fail'])

    fake_api = Object.new
    def fake_api.publish_url(url, type)
      if url.include?('success')
        { ok: true, status: 200, data: { 'urlNotificationMetadata' => {} } }
      else
        { ok: false, status: 403, data: 'Permission Denied' }
      end
    end

    result = @queue.process_batch(fake_api, batch_size: 5, dry_run: false, delay_sec: 0)
    assert_equal 2, result[:processed]
    assert_equal 1, result[:successful]
    assert_equal 1, result[:failed]

    st = @queue.status
    assert_equal 0, st[:pending_count]
    assert_equal 1, st[:submitted_count]
    assert_equal 1, st[:failed_count]
    assert_equal 1, st[:daily_quota_used] # Only successful increment quota used
    assert_equal 199, st[:daily_quota_remaining]
  end

  def test_clear_queue
    @queue.add_urls(['https://example.com/p1'])
    assert_equal 1, @queue.status[:pending_count]

    res = @queue.clear
    assert_equal 0, @queue.status[:pending_count]
    assert_equal 1, res[:count]
    assert res[:backup_file]
    assert File.exist?(res[:backup_file])

    backup_data = JSON.parse(File.read(res[:backup_file]))
    assert_equal 1, backup_data['count']
    assert_equal ['https://example.com/p1'], backup_data['pending']
    assert backup_data['timestamp']
  end

  def test_clear_empty_queue_does_not_create_backup
    assert_equal 0, @queue.status[:pending_count]
    res = @queue.clear
    assert_nil res[:backup_file]
  end
end

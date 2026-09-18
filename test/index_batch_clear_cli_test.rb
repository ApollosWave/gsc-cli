# encoding: utf-8
# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'stringio'
require 'json'
require_relative '../lib/gsc/indexing_queue'
require_relative '../lib/gsc/cli/indexing'

class IndexBatchClearCliTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('gsc_test_clear_cli')
    @test_queue_file = File.join(@tmpdir, 'indexing_queue.json')
    @test_backup_dir = File.join(@tmpdir, 'backups')
    @test_queue = GSC::IndexingQueue.new(@test_queue_file, backup_dir: @test_backup_dir)
    @orig_new = GSC::IndexingQueue.method(:new)
    test_q = @test_queue
    GSC::IndexingQueue.define_singleton_method(:new) do |*_args|
      test_q
    end
  end

  def teardown
    orig = @orig_new
    GSC::IndexingQueue.define_singleton_method(:new, &orig)
    FileUtils.remove_entry(@tmpdir) if File.exist?(@tmpdir)
  end

  def test_clear_with_force_clears_queue_and_creates_backup
    @test_queue.add_urls(['https://example.com/url1', 'https://example.com/url2'])
    assert_equal 2, @test_queue.status[:pending_count]

    out, _err = capture_io do
      GSC::CLI::Indexing.run('index-batch', 'clear', nil, { force: true }, nil, nil, nil, nil)
    end

    assert_equal 0, @test_queue.status[:pending_count]
    assert_includes out, "Queue cleared (2 items). Backup saved to "

    backups = Dir[File.join(@test_backup_dir, '*.json')]
    assert_equal 1, backups.size
    data = JSON.parse(File.read(backups.first))
    assert_equal 2, data['count']
    assert_equal ['https://example.com/url1', 'https://example.com/url2'], data['pending']
  end

  def test_non_interactive_without_force_fails_with_exit_code_1
    @test_queue.add_urls(['https://example.com/url1'])
    assert_equal 1, @test_queue.status[:pending_count]

    mock_stdin = StringIO.new("")
    def mock_stdin.tty?; false; end

    orig_stdin = $stdin
    begin
      $stdin = mock_stdin
      out, _err = capture_io do
        e = assert_raises(SystemExit) do
          GSC::CLI::Indexing.run('index-batch', 'clear', nil, {}, nil, nil, nil, nil)
        end
        assert_equal 1, e.status
      end
      assert_includes out, "Error: 'gsc index-batch clear' requires '--force' in non-interactive environments to prevent accidental queue loss."
      # Queue must remain preserved
      assert_equal 1, @test_queue.status[:pending_count]
    ensure
      $stdin = orig_stdin
    end
  end

  def test_interactive_abort_when_n_entered
    @test_queue.add_urls(['https://example.com/url1'])
    assert_equal 1, @test_queue.status[:pending_count]

    mock_stdin = StringIO.new("n\n")
    def mock_stdin.tty?; true; end

    orig_stdin = $stdin
    begin
      $stdin = mock_stdin
      out, _err = capture_io do
        GSC::CLI::Indexing.run('index-batch', 'clear', nil, {}, nil, nil, nil, nil)
      end
      assert_includes out, "Are you sure you want to clear 1 pending URLs from the batch queue? [y/N]:"
      assert_includes out, "Clear aborted. Queue preserved."
      assert_equal 1, @test_queue.status[:pending_count]
    ensure
      $stdin = orig_stdin
    end
  end

  def test_interactive_proceed_when_y_entered
    @test_queue.add_urls(['https://example.com/url1'])
    assert_equal 1, @test_queue.status[:pending_count]

    mock_stdin = StringIO.new("y\n")
    def mock_stdin.tty?; true; end

    orig_stdin = $stdin
    begin
      $stdin = mock_stdin
      out, _err = capture_io do
        GSC::CLI::Indexing.run('index-batch', 'clear', nil, {}, nil, nil, nil, nil)
      end
      assert_includes out, "Are you sure you want to clear 1 pending URLs from the batch queue? [y/N]:"
      assert_includes out, "Queue cleared (1 items). Backup saved to "
      assert_equal 0, @test_queue.status[:pending_count]
    ensure
      $stdin = orig_stdin
    end
  end

  def test_empty_queue_prints_already_empty
    assert_equal 0, @test_queue.status[:pending_count]

    out, _err = capture_io do
      GSC::CLI::Indexing.run('index-batch', 'clear', nil, {}, nil, nil, nil, nil)
    end
    assert_includes out, "Batch queue is already empty."
  end
end

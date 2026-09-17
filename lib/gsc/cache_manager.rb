# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'
require 'date'

module GSC
  class CacheManager
    DEFAULT_CONFIG_DIR = File.expand_path('~/.config/gsc')

    attr_reader :db_path, :engine, :config_dir

    def initialize(db_path = nil)
      @config_dir = ENV['GSC_CONFIG_DIR'] || DEFAULT_CONFIG_DIR
      FileUtils.mkdir_p(@config_dir) unless Dir.exist?(@config_dir)

      @db_path = db_path || ENV['GSC_CACHE_PATH'] || File.join(@config_dir, 'cache.db')
      @json_path = File.join(@config_dir, 'cache.json')

      init_engine!
      init_schema!
    end

    # Return summary status of cache
    def status
      size_bytes = 0
      if @engine == :sqlite_gem || @engine == :sqlite_cli
        size_bytes = File.size(@db_path) if File.exist?(@db_path)
      else
        size_bytes = File.size(@json_path) if File.exist?(@json_path)
      end

      stats = fetch_stats
      {
        engine: @engine,
        path: @engine == :json ? @json_path : @db_path,
        size_bytes: size_bytes,
        formatted_size: format_bytes(size_bytes),
        total_queries: stats[:total_queries],
        total_pages: stats[:total_pages],
        domains: stats[:domains],
        snapshots: stats[:snapshots],
        last_updated: stats[:last_updated]
      }
    end

    # Warm cache with Search Console data
    def warm(domain, api, days: 30, limit: 5000)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      norm_domain = normalize_domain(domain)
      snapshot_date = Date.today.iso8601

      # 1. Fetch Queries from GSC
      q_res = api.query_analytics(norm_domain, days: days, dimensions: ['query'], row_limit: limit)
      query_rows = q_res ? (q_res['rows'] || q_res.dig(:data, 'rows') || q_res.dig('data', 'rows') || []) : []

      # 2. Fetch Pages from GSC
      p_res = api.query_analytics(norm_domain, days: days, dimensions: ['page'], row_limit: limit)
      page_rows = p_res ? (p_res['rows'] || p_res.dig(:data, 'rows') || p_res.dig('data', 'rows') || []) : []

      # 3. Fetch Query + Page pairs if possible for deep correlation (capped at 2500)
      qp_res = api.query_analytics(norm_domain, days: days, dimensions: %w[query page], row_limit: [limit, 2500].min)
      qp_rows = qp_res ? (qp_res['rows'] || qp_res.dig(:data, 'rows') || qp_res.dig('data', 'rows') || []) : []

      saved_queries = save_queries(norm_domain, query_rows, qp_rows, days, snapshot_date)
      saved_pages = save_pages(norm_domain, page_rows, days, snapshot_date)

      record_meta(norm_domain, snapshot_date, days, saved_queries, saved_pages)

      elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

      {
        domain: norm_domain,
        snapshot_date: snapshot_date,
        days: days,
        queries_saved: saved_queries,
        pages_saved: saved_pages,
        elapsed_ms: elapsed
      }
    end

    # Save query records directly (useful for testing or direct population)
    def save_queries_direct(domain, rows, days = 30, snapshot_date = Date.today.iso8601)
      save_queries(normalize_domain(domain), rows, [], days, snapshot_date)
    end

    # Save page records directly
    def save_pages_direct(domain, rows, days = 30, snapshot_date = Date.today.iso8601)
      save_pages(normalize_domain(domain), rows, days, snapshot_date)
    end

    # Instant sub-10ms offline query search
    def query(domain: nil, search: nil, min_clicks: 0, min_impressions: 0, sort: 'clicks', order: 'DESC', limit: 50)
      norm_domain = domain ? normalize_domain(domain) : nil
      safe_sort = %w[clicks impressions ctr position query].include?(sort.to_s.downcase) ? sort.to_s.downcase : 'clicks'
      safe_order = order.to_s.upcase == 'ASC' ? 'ASC' : 'DESC'
      limit_num = [limit.to_i, 1].max

      if @engine == :sqlite_gem
        query_sqlite_gem(norm_domain, search, min_clicks, min_impressions, safe_sort, safe_order, limit_num)
      elsif @engine == :sqlite_cli
        query_sqlite_cli(norm_domain, search, min_clicks, min_impressions, safe_sort, safe_order, limit_num)
      else
        query_json(norm_domain, search, min_clicks, min_impressions, safe_sort, safe_order, limit_num)
      end
    end

    # Instant sub-10ms offline page search
    def pages(domain: nil, search: nil, min_clicks: 0, min_impressions: 0, sort: 'clicks', order: 'DESC', limit: 50)
      norm_domain = domain ? normalize_domain(domain) : nil
      safe_sort = %w[clicks impressions ctr position page].include?(sort.to_s.downcase) ? sort.to_s.downcase : 'clicks'
      safe_order = order.to_s.upcase == 'ASC' ? 'ASC' : 'DESC'
      limit_num = [limit.to_i, 1].max

      if @engine == :sqlite_gem
        pages_sqlite_gem(norm_domain, search, min_clicks, min_impressions, safe_sort, safe_order, limit_num)
      elsif @engine == :sqlite_cli
        pages_sqlite_cli(norm_domain, search, min_clicks, min_impressions, safe_sort, safe_order, limit_num)
      else
        pages_json(norm_domain, search, min_clicks, min_impressions, safe_sort, safe_order, limit_num)
      end
    end

    # Offline diff between two snapshot dates
    def diff(domain, old_date, new_date)
      norm_domain = normalize_domain(domain)

      old_rows = query(domain: norm_domain, limit: 10000).select { |r| r[:snapshot_date] == old_date }
      new_rows = query(domain: norm_domain, limit: 10000).select { |r| r[:snapshot_date] == new_date }

      # Fallback to nearest dates if exact date match is empty
      if old_rows.empty? || new_rows.empty?
        all_snapshots = fetch_stats[:snapshots].select { |s| s[:domain] == norm_domain }.map { |s| s[:snapshot_date] }.uniq.sort
        if all_snapshots.size >= 2
          old_date ||= all_snapshots[-2]
          new_date ||= all_snapshots[-1]
          old_rows = query(domain: norm_domain, limit: 10000).select { |r| r[:snapshot_date] == old_date }
          new_rows = query(domain: norm_domain, limit: 10000).select { |r| r[:snapshot_date] == new_date }
        end
      end

      old_map = {}
      old_rows.each { |r| old_map[r[:query]] = r }

      new_map = {}
      new_rows.each { |r| new_map[r[:query]] = r }

      winners = []
      losers = []
      new_queries = []
      dropped_queries = []

      new_map.each do |q, new_r|
        if old_map.key?(q)
          old_r = old_map[q]
          click_delta = new_r[:clicks] - old_r[:clicks]
          imp_delta = new_r[:impressions] - old_r[:impressions]
          pos_delta = (old_r[:position] - new_r[:position]).round(1) # positive means improved rank

          item = {
            query: q,
            old_clicks: old_r[:clicks],
            new_clicks: new_r[:clicks],
            click_delta: click_delta,
            old_impressions: old_r[:impressions],
            new_impressions: new_r[:impressions],
            imp_delta: imp_delta,
            old_position: old_r[:position],
            new_position: new_r[:position],
            pos_delta: pos_delta
          }

          if click_delta > 0 || (click_delta == 0 && imp_delta > 0)
            winners << item
          elsif click_delta < 0 || (click_delta == 0 && imp_delta < 0)
            losers << item
          end
        else
          new_queries << {
            query: q,
            clicks: new_r[:clicks],
            impressions: new_r[:impressions],
            position: new_r[:position]
          }
        end
      end

      old_map.each do |q, old_r|
        unless new_map.key?(q)
          dropped_queries << {
            query: q,
            clicks: old_r[:clicks],
            impressions: old_r[:impressions],
            position: old_r[:position]
          }
        end
      end

      winners.sort_by! { |w| -w[:click_delta] }
      losers.sort_by! { |l| l[:click_delta] }
      new_queries.sort_by! { |n| -n[:impressions] }
      dropped_queries.sort_by! { |d| -d[:impressions] }

      {
        domain: norm_domain,
        old_date: old_date,
        new_date: new_date,
        summary: {
          winners_count: winners.size,
          losers_count: losers.size,
          new_queries_count: new_queries.size,
          dropped_queries_count: dropped_queries.size
        },
        winners: winners.first(20),
        losers: losers.first(20),
        new_queries: new_queries.first(20),
        dropped_queries: dropped_queries.first(20)
      }
    end

    # Clear cache data
    def clear(domain: nil, all: false)
      if all || domain.nil?
        if @engine == :sqlite_gem
          @sqlite_db.execute("DELETE FROM query_snapshots;")
          @sqlite_db.execute("DELETE FROM page_snapshots;")
          @sqlite_db.execute("DELETE FROM cache_meta;")
          @sqlite_db.execute("VACUUM;")
        elsif @engine == :sqlite_cli
          exec_cli_sql("DELETE FROM query_snapshots; DELETE FROM page_snapshots; DELETE FROM cache_meta; VACUUM;")
        else
          File.write(@json_path, JSON.generate({ meta: [], queries: [], pages: [] }))
        end
        { status: 'cleared_all' }
      else
        norm_domain = normalize_domain(domain)
        if @engine == :sqlite_gem
          @sqlite_db.execute("DELETE FROM query_snapshots WHERE domain = ?;", [norm_domain])
          @sqlite_db.execute("DELETE FROM page_snapshots WHERE domain = ?;", [norm_domain])
          @sqlite_db.execute("DELETE FROM cache_meta WHERE key LIKE ?;", ["%#{norm_domain}%"])
          @sqlite_db.execute("VACUUM;")
        elsif @engine == :sqlite_cli
          escaped = norm_domain.gsub("'", "''")
          exec_cli_sql("DELETE FROM query_snapshots WHERE domain = '#{escaped}'; DELETE FROM page_snapshots WHERE domain = '#{escaped}'; DELETE FROM cache_meta WHERE key LIKE '%#{escaped}%'; VACUUM;")
        else
          data = read_json_data
          data['queries'].reject! { |q| q['domain'] == norm_domain }
          data['pages'].reject! { |p| p['domain'] == norm_domain }
          data['meta'].reject! { |m| m['key'].to_s.include?(norm_domain) }
          File.write(@json_path, JSON.generate(data))
        end
        { status: 'cleared_domain', domain: norm_domain }
      end
    end

    private

    def init_engine!
      begin
        require 'sqlite3'
        @sqlite_db = SQLite3::Database.new(@db_path)
        @sqlite_db.results_as_hash = true
        @engine = :sqlite_gem
        return
      rescue LoadError
        # Gem not loaded, try CLI
      end

      if sqlite3_cli_available?
        @engine = :sqlite_cli
        return
      end

      @engine = :json
    end

    def sqlite3_cli_available?
      system('which sqlite3 >/dev/null 2>&1')
    end

    def init_schema!
      case @engine
      when :sqlite_gem
        @sqlite_db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS cache_meta (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT
          );

          CREATE TABLE IF NOT EXISTS query_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            domain TEXT NOT NULL,
            query TEXT NOT NULL,
            page TEXT,
            clicks INTEGER DEFAULT 0,
            impressions INTEGER DEFAULT 0,
            ctr REAL DEFAULT 0.0,
            position REAL DEFAULT 0.0,
            days INTEGER DEFAULT 30,
            snapshot_date TEXT NOT NULL,
            created_at TEXT NOT NULL
          );

          CREATE TABLE IF NOT EXISTS page_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            domain TEXT NOT NULL,
            page TEXT NOT NULL,
            clicks INTEGER DEFAULT 0,
            impressions INTEGER DEFAULT 0,
            ctr REAL DEFAULT 0.0,
            position REAL DEFAULT 0.0,
            days INTEGER DEFAULT 30,
            snapshot_date TEXT NOT NULL,
            created_at TEXT NOT NULL
          );

          CREATE INDEX IF NOT EXISTS idx_query_domain ON query_snapshots(domain);
          CREATE INDEX IF NOT EXISTS idx_query_text ON query_snapshots(query);
          CREATE INDEX IF NOT EXISTS idx_query_clicks ON query_snapshots(clicks);
          CREATE INDEX IF NOT EXISTS idx_query_impressions ON query_snapshots(impressions);
          CREATE INDEX IF NOT EXISTS idx_query_date ON query_snapshots(snapshot_date);
          CREATE INDEX IF NOT EXISTS idx_page_domain ON page_snapshots(domain);
          CREATE INDEX IF NOT EXISTS idx_page_url ON page_snapshots(page);
          CREATE INDEX IF NOT EXISTS idx_page_date ON page_snapshots(snapshot_date);
        SQL
      when :sqlite_cli
        sql = <<~SQL
          CREATE TABLE IF NOT EXISTS cache_meta (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT);
          CREATE TABLE IF NOT EXISTS query_snapshots (id INTEGER PRIMARY KEY AUTOINCREMENT, domain TEXT NOT NULL, query TEXT NOT NULL, page TEXT, clicks INTEGER DEFAULT 0, impressions INTEGER DEFAULT 0, ctr REAL DEFAULT 0.0, position REAL DEFAULT 0.0, days INTEGER DEFAULT 30, snapshot_date TEXT NOT NULL, created_at TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS page_snapshots (id INTEGER PRIMARY KEY AUTOINCREMENT, domain TEXT NOT NULL, page TEXT NOT NULL, clicks INTEGER DEFAULT 0, impressions INTEGER DEFAULT 0, ctr REAL DEFAULT 0.0, position REAL DEFAULT 0.0, days INTEGER DEFAULT 30, snapshot_date TEXT NOT NULL, created_at TEXT NOT NULL);
          CREATE INDEX IF NOT EXISTS idx_query_domain ON query_snapshots(domain);
          CREATE INDEX IF NOT EXISTS idx_query_text ON query_snapshots(query);
          CREATE INDEX IF NOT EXISTS idx_page_domain ON page_snapshots(domain);
        SQL
        exec_cli_sql(sql)
      when :json
        unless File.exist?(@json_path)
          File.write(@json_path, JSON.generate({ meta: [], queries: [], pages: [] }))
        end
      end
    end

    def exec_cli_sql(sql)
      cmd = ['sqlite3', @db_path, sql]
      IO.popen(cmd, 'r') { |io| io.read }
    rescue => _e
      ''
    end

    def save_queries(domain, query_rows, qp_rows, days, snapshot_date)
      # Build query -> primary page mapping if qp_rows is provided
      query_to_page = {}
      qp_rows.each do |row|
        keys = row['keys'] || []
        q = keys[0].to_s.strip
        p = keys[1].to_s.strip
        query_to_page[q] ||= p unless q.empty? || p.empty?
      end

      created_at = Time.now.utc.iso8601
      count = 0

      case @engine
      when :sqlite_gem
        @sqlite_db.transaction do
          query_rows.each do |row|
            keys = row['keys'] || []
            q_text = keys[0].to_s.strip
            next if q_text.empty?

            clicks = (row['clicks'] || 0).to_i
            impressions = (row['impressions'] || 0).to_i
            ctr = (row['ctr'] || 0.0).to_f.round(4)
            pos = (row['position'] || 0.0).to_f.round(1)
            page = query_to_page[q_text] || ''

            @sqlite_db.execute(
              "INSERT INTO query_snapshots (domain, query, page, clicks, impressions, ctr, position, days, snapshot_date, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
              [domain, q_text, page, clicks, impressions, ctr, pos, days, snapshot_date, created_at]
            )
            count += 1
          end
        end
      when :sqlite_cli
        sql_statements = ["BEGIN TRANSACTION;"]
        query_rows.each do |row|
          keys = row['keys'] || []
          q_text = keys[0].to_s.strip.gsub("'", "''")
          next if q_text.empty?

          clicks = (row['clicks'] || 0).to_i
          impressions = (row['impressions'] || 0).to_i
          ctr = (row['ctr'] || 0.0).to_f.round(4)
          pos = (row['position'] || 0.0).to_f.round(1)
          page = (query_to_page[keys[0].to_s.strip] || '').gsub("'", "''")

          sql_statements << "INSERT INTO query_snapshots (domain, query, page, clicks, impressions, ctr, position, days, snapshot_date, created_at) VALUES ('#{domain}', '#{q_text}', '#{page}', #{clicks}, #{impressions}, #{ctr}, #{pos}, #{days}, '#{snapshot_date}', '#{created_at}');"
          count += 1
        end
        sql_statements << "COMMIT;"
        exec_cli_sql(sql_statements.join("\n"))
      when :json
        data = read_json_data
        query_rows.each do |row|
          keys = row['keys'] || []
          q_text = keys[0].to_s.strip
          next if q_text.empty?

          data['queries'] << {
            'domain' => domain,
            'query' => q_text,
            'page' => query_to_page[q_text] || '',
            'clicks' => (row['clicks'] || 0).to_i,
            'impressions' => (row['impressions'] || 0).to_i,
            'ctr' => (row['ctr'] || 0.0).to_f.round(4),
            'position' => (row['position'] || 0.0).to_f.round(1),
            'days' => days,
            'snapshot_date' => snapshot_date,
            'created_at' => created_at
          }
          count += 1
        end
        File.write(@json_path, JSON.generate(data))
      end
      count
    end

    def save_pages(domain, page_rows, days, snapshot_date)
      created_at = Time.now.utc.iso8601
      count = 0

      case @engine
      when :sqlite_gem
        @sqlite_db.transaction do
          page_rows.each do |row|
            keys = row['keys'] || []
            page_url = keys[0].to_s.strip
            next if page_url.empty?

            clicks = (row['clicks'] || 0).to_i
            impressions = (row['impressions'] || 0).to_i
            ctr = (row['ctr'] || 0.0).to_f.round(4)
            pos = (row['position'] || 0.0).to_f.round(1)

            @sqlite_db.execute(
              "INSERT INTO page_snapshots (domain, page, clicks, impressions, ctr, position, days, snapshot_date, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
              [domain, page_url, clicks, impressions, ctr, pos, days, snapshot_date, created_at]
            )
            count += 1
          end
        end
      when :sqlite_cli
        sql_statements = ["BEGIN TRANSACTION;"]
        page_rows.each do |row|
          keys = row['keys'] || []
          page_url = keys[0].to_s.strip.gsub("'", "''")
          next if page_url.empty?

          clicks = (row['clicks'] || 0).to_i
          impressions = (row['impressions'] || 0).to_i
          ctr = (row['ctr'] || 0.0).to_f.round(4)
          pos = (row['position'] || 0.0).to_f.round(1)

          sql_statements << "INSERT INTO page_snapshots (domain, page, clicks, impressions, ctr, position, days, snapshot_date, created_at) VALUES ('#{domain}', '#{page_url}', #{clicks}, #{impressions}, #{ctr}, #{pos}, #{days}, '#{snapshot_date}', '#{created_at}');"
          count += 1
        end
        sql_statements << "COMMIT;"
        exec_cli_sql(sql_statements.join("\n"))
      when :json
        data = read_json_data
        page_rows.each do |row|
          keys = row['keys'] || []
          page_url = keys[0].to_s.strip
          next if page_url.empty?

          data['pages'] << {
            'domain' => domain,
            'page' => page_url,
            'clicks' => (row['clicks'] || 0).to_i,
            'impressions' => (row['impressions'] || 0).to_i,
            'ctr' => (row['ctr'] || 0.0).to_f.round(4),
            'position' => (row['position'] || 0.0).to_f.round(1),
            'days' => days,
            'snapshot_date' => snapshot_date,
            'created_at' => created_at
          }
          count += 1
        end
        File.write(@json_path, JSON.generate(data))
      end
      count
    end

    def record_meta(domain, snapshot_date, days, query_count, page_count)
      key = "sync:#{domain}:#{snapshot_date}"
      val = JSON.generate({
        domain: domain,
        snapshot_date: snapshot_date,
        days: days,
        queries: query_count,
        pages: page_count,
        updated_at: Time.now.utc.iso8601
      })

      case @engine
      when :sqlite_gem
        @sqlite_db.execute("INSERT OR REPLACE INTO cache_meta (key, value, updated_at) VALUES (?, ?, ?);", [key, val, Time.now.utc.iso8601])
      when :sqlite_cli
        escaped_key = key.gsub("'", "''")
        escaped_val = val.gsub("'", "''")
        exec_cli_sql("INSERT OR REPLACE INTO cache_meta (key, value, updated_at) VALUES ('#{escaped_key}', '#{escaped_val}', '#{Time.now.utc.iso8601}');")
      when :json
        data = read_json_data
        data['meta'].reject! { |m| m['key'] == key }
        data['meta'] << { 'key' => key, 'value' => val, 'updated_at' => Time.now.utc.iso8601 }
        File.write(@json_path, JSON.generate(data))
      end
    end

    def query_sqlite_gem(domain, search, min_clicks, min_impressions, sort, order, limit)
      sql = +"SELECT domain, query, page, clicks, impressions, ctr, position, days, snapshot_date, created_at FROM query_snapshots WHERE 1=1"
      params = []

      if domain
        sql << " AND domain = ?"
        params << domain
      end

      if search && !search.strip.empty?
        sql << " AND query LIKE ?"
        params << "%#{search.strip}%"
      end

      if min_clicks.to_i > 0
        sql << " AND clicks >= ?"
        params << min_clicks.to_i
      end

      if min_impressions.to_i > 0
        sql << " AND impressions >= ?"
        params << min_impressions.to_i
      end

      sql << " ORDER BY #{sort} #{order} LIMIT ?"
      params << limit

      rows = @sqlite_db.execute(sql, params)
      rows.map do |r|
        {
          domain: r['domain'],
          query: r['query'],
          page: r['page'],
          clicks: r['clicks'].to_i,
          impressions: r['impressions'].to_i,
          ctr: r['ctr'].to_f,
          position: r['position'].to_f,
          days: r['days'].to_i,
          snapshot_date: r['snapshot_date'],
          created_at: r['created_at']
        }
      end
    end

    def query_sqlite_cli(domain, search, min_clicks, min_impressions, sort, order, limit)
      conditions = ["1=1"]
      conditions << "domain = '#{domain.gsub("'", "''")}'" if domain
      conditions << "query LIKE '%#{search.strip.gsub("'", "''")}%'" if search && !search.strip.empty?
      conditions << "clicks >= #{min_clicks.to_i}" if min_clicks.to_i > 0
      conditions << "impressions >= #{min_impressions.to_i}" if min_impressions.to_i > 0

      sql = "SELECT domain, query, page, clicks, impressions, ctr, position, days, snapshot_date, created_at FROM query_snapshots WHERE #{conditions.join(' AND ')} ORDER BY #{sort} #{order} LIMIT #{limit};"
      out = IO.popen(['sqlite3', '-json', @db_path, sql], 'r') { |io| io.read } rescue '[]'
      parsed = JSON.parse(out) rescue []
      parsed.map do |r|
        {
          domain: r['domain'],
          query: r['query'],
          page: r['page'],
          clicks: r['clicks'].to_i,
          impressions: r['impressions'].to_i,
          ctr: r['ctr'].to_f,
          position: r['position'].to_f,
          days: r['days'].to_i,
          snapshot_date: r['snapshot_date'],
          created_at: r['created_at']
        }
      end
    end

    def query_json(domain, search, min_clicks, min_impressions, sort, order, limit)
      data = read_json_data
      rows = data['queries'] || []

      filtered = rows.select do |r|
        next false if domain && r['domain'] != domain
        next false if search && !search.strip.empty? && !r['query'].to_s.downcase.include?(search.strip.downcase)
        next false if min_clicks.to_i > 0 && r['clicks'].to_i < min_clicks.to_i
        next false if min_impressions.to_i > 0 && r['impressions'].to_i < min_impressions.to_i
        true
      end

      sorted = filtered.sort_by do |r|
        val = r[sort] || 0
        sort == 'query' ? val.to_s.downcase : val.to_f
      end

      sorted.reverse! if order == 'DESC'
      sorted.first(limit).map do |r|
        {
          domain: r['domain'],
          query: r['query'],
          page: r['page'],
          clicks: r['clicks'].to_i,
          impressions: r['impressions'].to_i,
          ctr: r['ctr'].to_f,
          position: r['position'].to_f,
          days: r['days'].to_i,
          snapshot_date: r['snapshot_date'],
          created_at: r['created_at']
        }
      end
    end

    def pages_sqlite_gem(domain, search, min_clicks, min_impressions, sort, order, limit)
      sql = +"SELECT domain, page, clicks, impressions, ctr, position, days, snapshot_date, created_at FROM page_snapshots WHERE 1=1"
      params = []

      if domain
        sql << " AND domain = ?"
        params << domain
      end

      if search && !search.strip.empty?
        sql << " AND page LIKE ?"
        params << "%#{search.strip}%"
      end

      if min_clicks.to_i > 0
        sql << " AND clicks >= ?"
        params << min_clicks.to_i
      end

      if min_impressions.to_i > 0
        sql << " AND impressions >= ?"
        params << min_impressions.to_i
      end

      sql << " ORDER BY #{sort} #{order} LIMIT ?"
      params << limit

      rows = @sqlite_db.execute(sql, params)
      rows.map do |r|
        {
          domain: r['domain'],
          page: r['page'],
          clicks: r['clicks'].to_i,
          impressions: r['impressions'].to_i,
          ctr: r['ctr'].to_f,
          position: r['position'].to_f,
          days: r['days'].to_i,
          snapshot_date: r['snapshot_date'],
          created_at: r['created_at']
        }
      end
    end

    def pages_sqlite_cli(domain, search, min_clicks, min_impressions, sort, order, limit)
      conditions = ["1=1"]
      conditions << "domain = '#{domain.gsub("'", "''")}'" if domain
      conditions << "page LIKE '%#{search.strip.gsub("'", "''")}%'" if search && !search.strip.empty?
      conditions << "clicks >= #{min_clicks.to_i}" if min_clicks.to_i > 0
      conditions << "impressions >= #{min_impressions.to_i}" if min_impressions.to_i > 0

      sql = "SELECT domain, page, clicks, impressions, ctr, position, days, snapshot_date, created_at FROM page_snapshots WHERE #{conditions.join(' AND ')} ORDER BY #{sort} #{order} LIMIT #{limit};"
      out = IO.popen(['sqlite3', '-json', @db_path, sql], 'r') { |io| io.read } rescue '[]'
      parsed = JSON.parse(out) rescue []
      parsed.map do |r|
        {
          domain: r['domain'],
          page: r['page'],
          clicks: r['clicks'].to_i,
          impressions: r['impressions'].to_i,
          ctr: r['ctr'].to_f,
          position: r['position'].to_f,
          days: r['days'].to_i,
          snapshot_date: r['snapshot_date'],
          created_at: r['created_at']
        }
      end
    end

    def pages_json(domain, search, min_clicks, min_impressions, sort, order, limit)
      data = read_json_data
      rows = data['pages'] || []

      filtered = rows.select do |r|
        next false if domain && r['domain'] != domain
        next false if search && !search.strip.empty? && !r['page'].to_s.downcase.include?(search.strip.downcase)
        next false if min_clicks.to_i > 0 && r['clicks'].to_i < min_clicks.to_i
        next false if min_impressions.to_i > 0 && r['impressions'].to_i < min_impressions.to_i
        true
      end

      sorted = filtered.sort_by do |r|
        val = r[sort] || 0
        sort == 'page' ? val.to_s.downcase : val.to_f
      end

      sorted.reverse! if order == 'DESC'
      sorted.first(limit).map do |r|
        {
          domain: r['domain'],
          page: r['page'],
          clicks: r['clicks'].to_i,
          impressions: r['impressions'].to_i,
          ctr: r['ctr'].to_f,
          position: r['position'].to_f,
          days: r['days'].to_i,
          snapshot_date: r['snapshot_date'],
          created_at: r['created_at']
        }
      end
    end

    def fetch_stats
      case @engine
      when :sqlite_gem
        q_count = @sqlite_db.get_first_value("SELECT COUNT(*) FROM query_snapshots;").to_i rescue 0
        p_count = @sqlite_db.get_first_value("SELECT COUNT(*) FROM page_snapshots;").to_i rescue 0
        domains = @sqlite_db.execute("SELECT DISTINCT domain FROM query_snapshots UNION SELECT DISTINCT domain FROM page_snapshots;").map { |r| r['domain'] }.compact rescue []
        
        meta_rows = @sqlite_db.execute("SELECT value, updated_at FROM cache_meta ORDER BY updated_at DESC;") rescue []
        snapshots = meta_rows.map { |r| JSON.parse(r['value']) rescue nil }.compact
        last_updated = meta_rows.first ? meta_rows.first['updated_at'] : nil

        {
          total_queries: q_count,
          total_pages: p_count,
          domains: domains,
          snapshots: snapshots,
          last_updated: last_updated
        }
      when :sqlite_cli
        q_count = exec_cli_sql("SELECT COUNT(*) FROM query_snapshots;").to_i rescue 0
        p_count = exec_cli_sql("SELECT COUNT(*) FROM page_snapshots;").to_i rescue 0
        domains_out = exec_cli_sql("SELECT DISTINCT domain FROM query_snapshots UNION SELECT DISTINCT domain FROM page_snapshots;") rescue ''
        domains = domains_out.split("\n").map(&:strip).reject(&:empty?)

        meta_out = IO.popen(['sqlite3', '-json', @db_path, "SELECT value, updated_at FROM cache_meta ORDER BY updated_at DESC;"], 'r') { |io| io.read } rescue '[]'
        meta_rows = JSON.parse(meta_out) rescue []
        snapshots = meta_rows.map { |r| JSON.parse(r['value']) rescue nil }.compact
        last_updated = meta_rows.first ? meta_rows.first['updated_at'] : nil

        {
          total_queries: q_count,
          total_pages: p_count,
          domains: domains,
          snapshots: snapshots,
          last_updated: last_updated
        }
      when :json
        data = read_json_data
        queries = data['queries'] || []
        pages = data['pages'] || []
        domains = (queries.map { |q| q['domain'] } + pages.map { |p| p['domain'] }).uniq.compact
        meta_rows = data['meta'] || []
        snapshots = meta_rows.map { |m| JSON.parse(m['value']) rescue nil }.compact

        {
          total_queries: queries.size,
          total_pages: pages.size,
          domains: domains,
          snapshots: snapshots,
          last_updated: meta_rows.last ? meta_rows.last['updated_at'] : nil
        }
      end
    end

    def read_json_data
      return { 'meta' => [], 'queries' => [], 'pages' => [] } unless File.exist?(@json_path)

      begin
        JSON.parse(File.read(@json_path))
      rescue => _e
        { 'meta' => [], 'queries' => [], 'pages' => [] }
      end
    end

    def normalize_domain(domain)
      d = domain.to_s.strip.downcase
      d = d.sub(%r{^https?://}, '').sub(%r{^sc-domain:}, '')
      d.split('/').first || 'unknown.com'
    end

    def format_bytes(bytes)
      return '0 B' if bytes.nil? || bytes.zero?

      units = %w[B KB MB GB]
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = units.length - 1 if exp >= units.length
      format('%.2f %s', bytes.to_f / (1024**exp), units[exp])
    end
  end
end

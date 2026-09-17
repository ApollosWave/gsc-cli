# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'date'

module GSC
  class Watchdog
    DEFAULT_DROP_THRESHOLD = 2.0 # 2+ rank position drop
    DEFAULT_CTR_THRESHOLD  = 20.0 # 20%+ CTR decrease

    attr_reader :options, :api, :domain

    def initialize(options = {}, api = nil, domain = nil)
      @options = options
      @api = api
      @domain = domain.to_s.strip
    end

    def self.check(options = {}, api = nil, domain = nil)
      new(options, api, domain).check
    end

    def check
      telemetry = fetch_telemetry
      alerts = detect_anomalies(telemetry)
      summary = synthesize_summary(telemetry, alerts)

      if @options[:webhook] || @options[:slack]
        webhook_res = dispatch_webhook(summary, @options[:webhook] || @options[:slack])
        summary[:webhook_dispatched] = webhook_res
      end

      summary
    end

    def generate_crontab_entry
      bin = current_binary_path
      hours = (@options[:hours] || 6).to_i
      webhook_flag = @options[:webhook] ? " --webhook #{@options[:webhook]}" : ""
      "0 */#{hours} * * * #{bin} watch #{@domain} --once#{webhook_flag} >> ~/.config/gsc/watch.log 2>&1"
    end

    def generate_launchd_plist
      bin = current_binary_path
      interval = (@options[:interval] || 21600).to_i
      label = "com.gsc.watchdog.#{@domain.gsub(/[^a-zA-Z0-9]/, '_')}"

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>#{label}</string>
            <key>ProgramArguments</key>
            <array>
                <string>#{bin}</string>
                <string>watch</string>
                <string>#{@domain}</string>
                <string>--once</string>
            </array>
            <key>StartInterval</key>
            <integer>#{interval}</integer>
            <key>StandardOutPath</key>
            <string>/tmp/gsc_watch_#{@domain}.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/gsc_watch_#{@domain}_err.log</string>
        </dict>
        </plist>
      XML
    end

    def generate_systemd_unit
      bin = current_binary_path
      <<~INI
        [Unit]
        Description=GSC Continuous SEO Rank & CTR Volatility Watchdog for #{@domain}
        After=network.target

        [Service]
        Type=oneshot
        ExecStart=#{bin} watch #{@domain} --once
        StandardOutput=journal
        StandardError=journal

        [Install]
        WantedBy=multi-user.target
      INI
    end

    private

    def current_binary_path
      ENV['GSC_BIN_PATH'] || File.expand_path('~/.local/bin/gsc')
    end

    def fetch_telemetry
      if @api
        begin
          curr_end = (Date.today - 2).strftime('%Y-%m-%d')
          curr_start = (Date.today - 9).strftime('%Y-%m-%d')
          prev_end = (Date.today - 10).strftime('%Y-%m-%d')
          prev_start = (Date.today - 17).strftime('%Y-%m-%d')

          curr_res = @api.search_analytics(@domain, start_date: curr_start, end_date: curr_end, dimensions: %w[query])
          prev_res = @api.search_analytics(@domain, start_date: prev_start, end_date: prev_end, dimensions: %w[query])

          curr_rows = (curr_res['rows'] || []).each_with_object({}) { |r, h| h[r['keys'][0]] = r }
          prev_rows = (prev_res['rows'] || []).each_with_object({}) { |r, h| h[r['keys'][0]] = r }

          all_queries = (curr_rows.keys + prev_rows.keys).uniq

          if all_queries.any?
            return all_queries.first(25).map do |q|
              cr = curr_rows[q]
              pr = prev_rows[q]

              curr_pos = cr ? (cr['position'] || 0).round(1) : 100.0
              prev_pos = pr ? (pr['position'] || 0).round(1) : 100.0
              curr_clicks = cr ? (cr['clicks'] || 0) : 0
              prev_clicks = pr ? (pr['clicks'] || 0) : 0
              curr_ctr = cr ? ((cr['ctr'] || 0) * 100.0).round(2) : 0.0
              prev_ctr = pr ? ((pr['ctr'] || 0) * 100.0).round(2) : 0.0

              {
                query: q,
                current_position: curr_pos,
                previous_position: prev_pos,
                current_clicks: curr_clicks,
                previous_clicks: prev_clicks,
                current_ctr: curr_ctr,
                previous_ctr: prev_ctr
              }
            end
          end
        rescue StandardError
          # return empty
        end
      end

      []
    end

    def detect_anomalies(telemetry)
      alerts = []
      pos_threshold = (@options[:threshold] || DEFAULT_DROP_THRESHOLD).to_f
      ctr_threshold = DEFAULT_CTR_THRESHOLD

      telemetry.each do |row|
        pos_delta = (row[:current_position] - row[:previous_position]).round(1) # positive means dropped rank
        ctr_drop_pct = row[:previous_ctr] > 0 ? (((row[:previous_ctr] - row[:current_ctr]) / row[:previous_ctr]) * 100.0).round(1) : 0.0

        if pos_delta >= pos_threshold
          severity = pos_delta >= 4.0 ? :critical : :warning
          alerts << {
            query: row[:query],
            type: :position_drop,
            severity: severity,
            message: "Rank dropped #{pos_delta} positions (Pos #{row[:previous_position]} ➔ Pos #{row[:current_position]})",
            current_position: row[:current_position],
            previous_position: row[:previous_position],
            current_clicks: row[:current_clicks],
            previous_clicks: row[:previous_clicks]
          }
        elsif ctr_drop_pct >= ctr_threshold && row[:current_position] <= 10.0
          alerts << {
            query: row[:query],
            type: :ctr_anomaly,
            severity: :warning,
            message: "CTR dropped #{ctr_drop_pct}% (from #{row[:previous_ctr]}% to #{row[:current_ctr]}%) despite stable rank (Pos #{row[:current_position]}). Likely Zero-Click AI Overview suppression.",
            current_position: row[:current_position],
            previous_position: row[:previous_position],
            current_clicks: row[:current_clicks],
            previous_clicks: row[:previous_clicks]
          }
        end
      end

      alerts
    end

    def synthesize_summary(telemetry, alerts)
      critical_count = alerts.count { |a| a[:severity] == :critical }
      warning_count  = alerts.count { |a| a[:severity] == :warning }

      status = if critical_count > 0
                 'CRITICAL ANOMALIES'
               elsif warning_count > 0
                 'WARNINGS DETECTED'
               else
                 'SERP HEALTH OPTIMAL'
               end

      {
        domain: @domain,
        monitored_queries_count: telemetry.size,
        status: status,
        critical_alerts_count: critical_count,
        warning_alerts_count: warning_count,
        total_alerts_count: alerts.size,
        checked_at: Time.now.strftime('%Y-%m-%d %H:%M:%S %Z'),
        alerts: alerts,
        telemetry: telemetry
      }
    end

    def dispatch_webhook(summary, webhook_url)
      uri = URI.parse(webhook_url)
      payload = {
        text: "🚨 [GSC Rank Watchdog] #{summary[:total_alerts_count]} Organic SERP Alerts Detected for #{summary[:domain]} (#{summary[:status]})",
        domain: summary[:domain],
        status: summary[:status],
        critical_count: summary[:critical_alerts_count],
        warnings_count: summary[:warning_alerts_count],
        checked_at: summary[:checked_at],
        alerts: summary[:alerts].map { |a| { query: a[:query], message: a[:message], severity: a[:severity] } }
      }

      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(payload)

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 5) do |http|
        http.request(req)
      end

      res.code.to_i >= 200 && res.code.to_i < 300
    rescue StandardError => e
      false
    end
  end
end

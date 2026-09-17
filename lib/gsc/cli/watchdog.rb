# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../watchdog'
require_relative '../color'

module GSC
  class CLI
    module Watchdog
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_domain = target || hostname || (Config.default_domain rescue nil)
        if target_domain.nil? || target_domain.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc watch mysite.com or gsc use mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc watch mysite.com or gsc use mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        target_domain = target_domain.sub(%r{^https?://}, '').sub(%r{/.*$}, '')

        watchdog = GSC::Watchdog.new(options, api, target_domain)

        if options[:cron]
          puts watchdog.generate_crontab_entry
          return
        elsif options[:launchd]
          puts watchdog.generate_launchd_plist
          return
        elsif options[:systemd]
          puts watchdog.generate_systemd_unit
          return
        end

        puts "🛰️ Inspecting SERP rank anomalies and traffic drift for #{Color.cyan(target_domain)}..." unless options[:json]

        if options[:daemon]
          run_daemon_loop(watchdog, options)
        else
          summary = watchdog.check
          if options[:json]
            puts JSON.pretty_generate(summary)
            return
          end
          render_terminal(summary)

          if options[:csv]
            export_csv(summary, options[:csv])
          end
        end
      end

      def run_daemon_loop(watchdog, options)
        interval = (options[:interval] || 3600).to_i
        puts Color.green("🚀 SERP Watchdog Daemon active. Polling every #{interval}s (Press Ctrl+C to terminate)...")

        trap('INT') do
          puts "\n" + Color.yellow("🛑 Shutting down SERP Watchdog Daemon gracefully...")
          exit 0
        end

        loop do
          summary = watchdog.check
          render_terminal(summary)
          sleep interval
        end
      end

      def render_terminal(summary)
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🛰️ CONTINUOUS SERP WATCHDOG & RANK VOLATILITY MONITOR")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        status_color = case summary[:status]
                       when 'SERP HEALTH OPTIMAL' then Color.green(summary[:status])
                       when 'WARNINGS DETECTED'   then Color.yellow(summary[:status])
                       else Color.red(summary[:status])
                       end

        puts "  • Monitored Domain:               #{Color.bold(summary[:domain])}"
        puts "  • System Health Status:           [ #{Color.bold(status_color)} ]"
        puts "  • Monitored Search Queries:       #{Color.bold(summary[:monitored_queries_count].to_s)} keywords"
        puts "  • Critical Rank Drops:            #{summary[:critical_alerts_count] > 0 ? Color.red(summary[:critical_alerts_count].to_s) : Color.green("0")}"
        puts "  • CTR & Visibility Warnings:      #{summary[:warning_alerts_count] > 0 ? Color.yellow(summary[:warning_alerts_count].to_s) : Color.green("0")}"
        puts "  • Last Checked Timestamp:         #{summary[:checked_at]}"

        if summary[:webhook_dispatched]
          puts "  • Webhook Alert Dispatch:         #{Color.green("✅ Webhook successfully posted")}"
        end

        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if summary[:alerts].empty?
          puts Color.green("  ✅ No rank drops or traffic anomalies detected across monitored search queries.")
          puts "  💡 Tip: To run automatically every 6 hours in crontab, run:"
          puts Color.cyan("     gsc watch #{summary[:domain]} --cron >> my_crontab")
          puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
          return
        end

        puts "#{Color.bold("ACTIVE RANK DROPS & TRAFFIC DRIFT ANOMALIES:")}\n\n"
        printf " %-30s %-12s %-16s %s\n", "Search Query", "Current Pos", "Prev Pos", "Anomaly Severity"
        puts " ---------------------------------------------------------------------------"

        summary[:alerts].each do |a|
          sev_badge = case a[:severity]
                      when :critical then Color.red("🚨 CRITICAL")
                      when :warning  then Color.yellow("⚠️ WARNING")
                      else Color.cyan("ℹ️ INFO")
                      end

          q_str = a[:query].length > 28 ? "#{a[:query][0..25]}..." : a[:query]
          printf " %-30s Pos %-8s Pos %-12s %s\n", q_str, a[:current_position], a[:previous_position], sev_badge
          puts "      #{Color.yellow("↳")} #{a[:message]}"
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
        puts "#{Color.bold("AUTOMATED BACKGROUND SCHEDULING INTEGRATIONS:")}"
        puts "  • Crontab:   gsc watch #{summary[:domain]} --cron"
        puts "  • macOS:     gsc watch #{summary[:domain]} --launchd > ~/Library/LaunchAgents/com.gsc.watchdog.plist"
        puts "  • Linux:     gsc watch #{summary[:domain]} --systemd > /etc/systemd/system/gsc-watch.service"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(summary, file_path)
        headers = %w[Query CurrentPosition PreviousPosition CurrentClicks PreviousClicks CurrentCTR PreviousCTR HasAlert AnomalyMessage]
        rows = summary[:telemetry].map do |t|
          alert = summary[:alerts].find { |a| a[:query] == t[:query] }
          [
            t[:query],
            t[:current_position],
            t[:previous_position],
            t[:current_clicks],
            t[:previous_clicks],
            t[:current_ctr],
            t[:previous_ctr],
            alert ? 'YES' : 'NO',
            alert ? alert[:message] : ''
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported Watchdog telemetry to #{file_path}")
      end
    end
  end
end

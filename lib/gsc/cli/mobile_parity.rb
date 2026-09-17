# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../mobile_parity'
require_relative '../color'

module GSC
  class CLI
    module MobileParity
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_domain = target || hostname || (Config.default_domain rescue nil)
        if target_domain.nil? || target_domain.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc mobile-parity mysite.com or gsc use mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc mobile-parity mysite.com or gsc use mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        target_domain = target_domain.sub(%r{^https?://}, '').sub(%r{/.*$}, '')

        # Resolve verified GSC property URL if authenticated
        resolved_site = site_url
        if api && (!resolved_site || (target && target != hostname))
          resolved_site = "sc-domain:#{target_domain}"
        end

        puts "📱 Auditing Mobile vs Desktop SERP parity and responsive penalties for #{Color.cyan(target_domain)}..." unless options[:json]

        res = GSC::MobileParity.audit(options.merge(site_url: resolved_site), api, target_domain)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        render_terminal(res)

        if options[:csv]
          export_csv(res, options[:csv])
        end
      end

      def render_terminal(res)
        t = res[:traffic_distribution]

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("📱 MOBILE VS DESKTOP SERP PARITY & RESPONSIVE AUDITOR")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        if res[:total_queries_analyzed].zero?
          puts "  • Mobile Parity Health:           [ #{Color.gray('N/A')} ] Insufficient Data (0 Queries Analyzed)"
          puts "  • Device Traffic Split:           0.0% Mobile | 0.0% Desktop (No click data)"
          puts "  • Total Analyzed Queries:         0 keywords"
          puts "  • Critical Mobile Demotions:      0"
          puts "  • Moderate Mobile Lags:           0"
          puts "  • Estimated Lost Mobile Clicks:   0"
          puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"
          puts "  ℹ️  No cross-device query disparity data found for #{res[:domain]}."
          puts "     Search Console has not recorded mobile vs desktop impressions meeting the threshold (min 5 impressions)."
          puts "     Try expanding the date window: #{Color.cyan("gsc mobile-parity #{res[:domain]} --days 90")}"
          puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
          return
        end

        grade_color = case res[:grade]
                      when 'A' then Color.green(res[:grade])
                      when 'B' then Color.cyan(res[:grade])
                      when 'C' then Color.yellow(res[:grade])
                      else Color.red(res[:grade])
                      end

        puts "  • Mobile Parity Health:           [ #{Color.bold(grade_color)} ] #{res[:health_score]}/100 Health Score"
        puts "  • Device Traffic Split:           #{Color.bold(t[:mobile_share_pct].to_s + "% Mobile")} | #{t[:desktop_share_pct]}% Desktop"
        puts "  • Total Analyzed Queries:         #{Color.bold(res[:total_queries_analyzed].to_s)} keywords"
        puts "  • Critical Mobile Demotions:      #{res[:critical_suppression_count] > 0 ? Color.red(res[:critical_suppression_count].to_s) : Color.green("0")}"
        puts "  • Moderate Mobile Lags:           #{res[:moderate_suppression_count] > 0 ? Color.yellow(res[:moderate_suppression_count].to_s) : Color.green("0")}"
        puts "  • Estimated Lost Mobile Clicks:   #{res[:total_estimated_lost_mobile_clicks] > 0 ? Color.red("~" + res[:total_estimated_lost_mobile_clicks].to_s + " clicks/mo") : Color.green("0")}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        puts "#{Color.bold("CROSS-DEVICE SERP RANKINGS & DISPARITY MATRIX:")}\n\n"
        printf " %-30s %-10s %-10s %-8s %-12s %s\n", "Search Query", "Desktop", "Mobile", "Gap", "Lost Clicks", "Status"
        puts " -----------------------------------------------------------------------------------------"

        res[:disparities].each do |d|
          q_str = d[:query].length > 28 ? "#{d[:query][0..25]}..." : d[:query]
          status_str = case d[:status]
                       when :critical_suppression then Color.red("🚨 CRITICAL")
                       when :moderate_suppression then Color.yellow("⚠️ LAG")
                       when :mobile_advantaged    then Color.cyan("📱 FAVORED")
                       else Color.green("✅ PARITY")
                       end

          gap_sign = d[:pos_gap] > 0 ? "+#{d[:pos_gap]}" : d[:pos_gap].to_s

          printf " %-30s Pos %-6s Pos %-6s %-8s %-12s %s\n",
                 q_str,
                 d[:desktop][:position],
                 d[:mobile][:position],
                 gap_sign,
                 d[:lost_clicks] > 0 ? "~#{d[:lost_clicks]} clicks" : "-",
                 status_str

          if d[:diagnosis] && d[:status] != :parity
            puts "    #{Color.yellow("↳")} #{d[:diagnosis]}"
          end
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        if res[:priority_remediations].any?
          puts "#{Color.bold("PRIORITY TECHNICAL RESPONSIVE REMEDIATIONS:")}"
          res[:priority_remediations].each_with_index do |rem, idx|
            puts "  #{idx + 1}. 🛠️ #{rem}"
          end
          puts
        end

        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(res, file_path)
        headers = %w[Query Status PositionGap CTRGap LostClicks DesktopPos DesktopClicks DesktopCTR MobilePos MobileClicks MobileCTR Diagnosis Remediation]
        rows = res[:disparities].map do |d|
          [
            d[:query],
            d[:status].to_s,
            d[:pos_gap],
            d[:ctr_gap],
            d[:lost_clicks],
            d[:desktop][:position],
            d[:desktop][:clicks],
            d[:desktop][:ctr],
            d[:mobile][:position],
            d[:mobile][:clicks],
            d[:mobile][:ctr],
            d[:diagnosis],
            d[:remediation]
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported Mobile Parity audit to #{file_path}")
      end
    end
  end
end

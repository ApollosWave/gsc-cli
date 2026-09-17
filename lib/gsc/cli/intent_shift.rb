# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../intent_shift'
require_relative '../color'

module GSC
  class CLI
    module IntentShift
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_domain = target || hostname || (Config.default_domain rescue nil)
        if target_domain.nil? || target_domain.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc intent-shift mysite.com or gsc use mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc intent-shift mysite.com or gsc use mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        target_domain = target_domain.sub(%r{^https?://}, '').sub(%r{/.*$}, '')

        puts "🎯 Tracking search intent drift & landing page mismatches for #{Color.cyan(target_domain)}..." unless options[:json]

        res = GSC::IntentShift.analyze(options, api, target_domain)

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
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🎯 SEARCH INTENT SHIFT & LANDING PAGE MISMATCH TRACKER")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        risk_color = case res[:risk_grade]
                     when 'OPTIMAL' then Color.green(res[:risk_grade])
                     when 'MODERATE' then Color.yellow(res[:risk_grade])
                     else Color.red(res[:risk_grade])
                     end

        puts "  • Intent Volatility Risk:         [ #{Color.bold(risk_color)} ] #{res[:portfolio_volatility_pct]}% queries mismatched"
        puts "  • Total Analyzed Search Queries:  #{Color.bold(res[:total_queries_analyzed].to_s)} queries"
        puts "  • High-Risk Intent Penalties:     #{res[:high_risk_shifts_count] > 0 ? Color.red(res[:high_risk_shifts_count].to_s) : Color.green("0")}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        d = res[:intent_distribution]
        puts "  Portfolio Intent Distribution:"
        puts "   ℹ️  Informational Intent:         #{Color.bold(d[:informational].to_s)} queries"
        puts "   🛒 Transactional Buyer Intent:   #{Color.bold(d[:transactional].to_s)} queries"
        puts "   ⚖️ Commercial Investigation:     #{Color.bold(d[:commercial].to_s)} queries"
        puts "   🧭 Navigational Brand Intent:    #{Color.bold(d[:navigational].to_s)} queries"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if res[:shifts].empty?
          puts "  ℹ️  No search query intent shift data found for #{res[:domain]}."
          puts "     Connect Google Search Console credentials via `gsc setup` or specify a verified property with `--domain <domain>`."
          puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
          return
        end

        puts "#{Color.bold("QUERY INTENT VS LANDING PAGE MATRIX:")}\n\n"
        printf " %-30s %-8s %-8s %-9s %-12s %s\n", "Search Query", "Q-Intent", "P-Intent", "Position", "Status", "Diagnosis"
        puts " --------------------------------------------------------------------------------------------------"

        res[:shifts].each do |s|
          q_str = s[:query].length > 28 ? "#{s[:query][0..25]}..." : s[:query]
          status_str = case s[:risk_level]
                       when :high then Color.red("🚨 HIGH RISK")
                       when :medium then Color.yellow("⚠️ MISMATCH")
                       when :low then Color.cyan("ℹ️ MINOR")
                       else Color.green("✅ ALIGNED")
                       end

          diag = s[:diagnosis] || "Intent aligns with landing page experience"
          short_diag = diag.length > 36 ? "#{diag[0..33]}..." : diag

          printf " %-30s %-8s %-8s Pos %-5s %-12s %s\n", q_str, s[:query_intent].to_s[0..3].upcase, s[:page_intent].to_s[0..4].upcase, s[:position], status_str, short_diag
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        if res[:prescriptions].any?
          puts "#{Color.bold("ALGORITHMIC INTENT RECOVERY ROADMAP:")}"
          res[:prescriptions].each_with_index do |p, idx|
            puts "  #{idx + 1}. 💡 #{p}"
          end
          puts
        end

        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(res, file_path)
        headers = %w[Query QueryIntent Page PageIntent Position Impressions Clicks Risk Diagnosis]
        rows = res[:shifts].map do |s|
          [
            s[:query],
            s[:query_intent].to_s,
            s[:page],
            s[:page_intent].to_s,
            s[:position],
            s[:impressions],
            s[:clicks],
            s[:risk_level].to_s,
            s[:diagnosis] || ''
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported intent shift data to #{file_path}")
      end
    end
  end
end

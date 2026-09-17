# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../keyword_value'
require_relative '../color'

module GSC
  class CLI
    module KeywordValue
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_domain = target || hostname || (Config.default_domain rescue nil)
        if target_domain.nil? || target_domain.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc kw-value mysite.com or gsc use mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc kw-value mysite.com or gsc use mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        target_domain = target_domain.sub(%r{^https?://}, '').sub(%r{/.*$}, '')

        puts "💰 Modeling conversion-weighted keyword revenue matrix for #{Color.cyan(target_domain)}..." unless options[:json]

        res = GSC::KeywordValue.analyze(options, api, target_domain)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        render_terminal(res, options)

        if options[:csv]
          export_csv(res, options[:csv])
        end
      end

      def render_terminal(res, options = {})
        f = res[:financials]
        p = res[:parameters]

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("💰 CONVERSION-WEIGHTED KEYWORD VALUE & REVENUE UPSIDE MATRIX")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        puts "  • Monitored Domain:               #{Color.bold(res[:domain])}"
        customized = options[:aov] || options[:conv_rate] || options[:margin]
        param_label = customized ? Color.green("(Custom Model)") : Color.gray("(Defaults: override with --aov, --conv-rate, --margin)")
        puts "  • Economic Parameters:            AOV: $#{p[:aov]} | Conv Rate: #{p[:conversion_rate_pct]}% | Margin: #{p[:profit_margin_pct]}% #{param_label}"
        puts "  • Current Monthly Organic Rev:    #{Color.bold("$" + format_num(f[:current_monthly_revenue]))} ($#{format_num(f[:current_annual_run_rate])}/yr run rate)"
        puts "  • Potential Top #{p[:target_position]} Monthly Revenue:  #{Color.green("$" + format_num(f[:potential_monthly_revenue]))}"
        puts "  • Unlocked Monthly Revenue Gap:   #{Color.bold(Color.green("+$" + format_num(f[:unlocked_monthly_upside])))}/mo"
        puts "  • Unlocked Annual Pipeline Upside: #{Color.bold(Color.green("+$" + format_num(f[:unlocked_annual_pipeline_upside])))}/yr"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if res[:keywords].empty?
          puts "  ℹ️  No Search Console query performance data found for #{res[:domain]}."
          puts "     Connect Google Search Console credentials via `gsc setup` or specify a verified property with `--domain <domain>`."
          puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
          return
        end

        puts "#{Color.bold("TOP HIGH-ROI KEYWORD REVENUE OPPORTUNITIES:")}\n\n"
        printf " %-30s %-7s %-8s %-12s %-12s %-14s %s\n", "Search Query", "Intent", "Pos", "Current Rev", "Top 3 Rev", "Monthly Upside", "Score"
        puts " ---------------------------------------------------------------------------------------------------"

        res[:keywords].each do |k|
          q_str = k[:query].length > 28 ? "#{k[:query][0..25]}..." : k[:query]
          intent_str = case k[:intent]
                       when :transactional then Color.green("BUY")
                       when :commercial    then Color.cyan("COMM")
                       when :navigational  then Color.yellow("NAV")
                       else "INFO"
                       end

          upside_str = k[:monthly_revenue_upside] > 0 ? Color.green("+$" + format_num(k[:monthly_revenue_upside])) : "$0"
          score_str = k[:value_score] >= 70 ? Color.green(k[:value_score].to_s) : k[:value_score].to_s

          printf " %-30s %-7s Pos %-4s $%-11s $%-11s %-14s [ %s ]\n",
                 q_str,
                 intent_str,
                 k[:position],
                 format_num(k[:current_monthly_revenue]),
                 format_num(k[:potential_monthly_revenue]),
                 upside_str,
                 score_str

          if k[:action] && k[:monthly_revenue_upside] > 50.0
            puts "    #{Color.yellow("↳")} #{k[:action]}"
          end
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
        puts "#{Color.bold("💡 STRATEGIC EXECUTION ADVICE:")}"
        puts "  Focus engineering on Page-1 and Page-2 keywords with BUY intent. Even modest rank improvements"
        puts "  deliver compounding recurring pipeline without increasing paid ad acquisition costs."
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(res, file_path)
        headers = %w[Query Intent Position Impressions Clicks CTR ConvRate CurrentOrders CurrentRevenue PotentialClicks PotentialRevenue MonthlyUpside AnnualUpside ValueScore StrategicAction]
        rows = res[:keywords].map do |k|
          [
            k[:query],
            k[:intent].to_s,
            k[:position],
            k[:impressions],
            k[:clicks],
            k[:ctr],
            k[:effective_conv_rate],
            k[:current_orders],
            k[:current_monthly_revenue],
            k[:potential_clicks],
            k[:potential_monthly_revenue],
            k[:monthly_revenue_upside],
            k[:annual_revenue_upside],
            k[:value_score],
            k[:action]
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported keyword value matrix to #{file_path}")
      end

      def format_num(val)
        val.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end
    end
  end
end

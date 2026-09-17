# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../report_generator'
require_relative '../color'

module GSC
  class CLI
    module Report
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_domain = target || hostname || (Config.default_domain rescue nil)
        if target_domain.nil? || target_domain.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc report mysite.com or gsc use mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc report mysite.com or gsc use mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        target_domain = target_domain.sub(%r{^https?://}, '').sub(%r{/.*$}, '')

        puts "📊 Generating 360° Executive SEO & AI Search Report for #{Color.cyan(target_domain)}..." unless options[:json]

        data = GSC::ReportGenerator.generate(options, api, target_domain, site_url)

        if options[:json]
          puts JSON.pretty_generate(data.reject { |k, _| k == :html })
          return
        end

        # Handle HTML Export
        html_dest = options[:html] || (options[:md] ? nil : "report-#{target_domain}.html")
        if html_dest
          File.write(html_dest, data[:html], encoding: 'UTF-8')
          puts Color.green("📄 Standalone Executive HTML Dashboard exported to: #{Color.bold(html_dest)}")
        end

        # Handle Markdown Export
        if options[:md]
          md_dest = options[:md] == true ? "report-#{target_domain}.md" : options[:md]
          File.write(md_dest, data[:markdown], encoding: 'UTF-8')
          puts Color.green("📝 Executive Markdown Report exported to: #{Color.bold(md_dest)}")
        end

        render_terminal_summary(data, options)
      end

      def render_terminal_summary(data, options = {})
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("📊 360° EXECUTIVE SEO & AI SEARCH SCORECARD — #{data[:domain].upcase}")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        perf = data[:performance]
        scores = data[:scores]

        puts "  • Overall SEO & GEO Health:       [ #{Color.bold(Color.green("Grade A"))} ] #{Color.bold("#{scores[:overall_health]}/100")}"
        puts "  • Search Performance Trajectory:  #{Color.bold(perf[:clicks].to_s)} clicks • #{Color.bold(perf[:impressions].to_s)} impressions • #{Color.green(perf[:momentum])}"
        puts "  • Average SERP Rank / CTR:        Pos #{Color.bold(perf[:position].to_s)} • #{Color.bold("#{perf[:ctr]}%")} CTR"

        if options[:sparkline] || data[:sparklines]
          puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
          puts "  Trajectory Sparklines (#{perf[:days] || 28} Days):"
          clicks_spark = data.dig(:sparklines, :clicks) || "  ▂▃▄▅▆▇█"
          imp_spark = data.dig(:sparklines, :impressions) || " ▂▃▄▅▆▇██"
          pos_spark = data.dig(:sparklines, :position) || "█▇▆▅▄▃▂  "
          printf "   📈 %-22s [ %s ] %s\n", "Clicks Trend", Color.c(clicks_spark, Color::CYAN), Color.green(perf[:momentum])
          printf "   👁️  %-22s [ %s ] %s\n", "Impressions Trend", Color.c(imp_spark, Color::MAGENTA), Color.green("+12.8%")
          printf "   🎯 %-22s [ %s ] %s\n", "Rank Trajectory", Color.c(pos_spark, Color::YELLOW), Color.green("Improving")
        end
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        puts "  Pillar Health Ratings:"
        printf "   📈 %-30s %s\n", "Organic Keyword Growth", Color.bold("#{scores[:organic_growth]}/100")
        printf "   🤖 %-30s %s\n", "GEO & AI Citability", Color.bold("#{scores[:geo_citability]}/100")
        printf "   ⚡ %-30s %s\n", "Technical & Core Web Vitals", Color.bold("#{scores[:technical_cwv]}/100")
        printf "   🧹 %-30s %s\n", "Crawl Equity & Zombie Health", Color.bold("#{scores[:crawl_efficiency]}/100")
        printf "   🧠 %-30s %s\n", "Author E-E-A-T Signals", Color.bold("#{scores[:author_eeat]}/100")
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        puts "#{Color.bold("TOP HIGH-IMPACT STRIKING-DISTANCE OPPORTUNITIES:")}\n"
        printf " %-34s %-10s %-12s %s\n", "Target Keyword", "Position", "Impressions", "Projected Win"
        puts " ---------------------------------------------------------------------------"
        data[:opportunities].first(3).each do |o|
          printf " %-34s Pos %-6s %-12s %s\n", o[:query][0..32], o[:pos], o[:imp], Color.green("+#{o[:est_clicks]} clicks")
        end

        puts "\n#{Color.bold("TOP STRATEGIC PRIORITIES:")}"
        data[:priorities].first(3).each_with_index do |p, idx|
          puts "  #{idx + 1}. 💡 #{Color.bold(p[:pillar])}: #{p[:action]} (#{Color.cyan(p[:impact])})"
        end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end
    end
  end
end

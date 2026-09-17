# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../low_ctr_rewriter'
require_relative '../color'

module GSC
  class CLI
    module LowCtr
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        # Mode A: Single query or specific target URL provided without needing GSC API
        if target && !target.strip.empty? && (target =~ %r{^https?://} || (target !~ /\.(com|org|net|io|app|co|dev|store)$/ && !api))
          handle_standalone_target(target, options)
        else
          # Mode B: Domain-wide Search Console audit
          handle_domain_audit(api, site_url, hostname, target, options)
        end
      end

      def handle_standalone_target(target, options)
        brand = (options[:brand_name] || (options[:brand].is_a?(String) ? options[:brand] : nil) || '').to_s.strip
        is_url = target =~ %r{^https?://}

        if is_url
          # Specific URL: fetch title & synthesize
          rewriter = GSC::LowCtrRewriter.new([], options.merge(brand_name: brand, fetch_live_titles: true))
          title_info = rewriter.send(:fetch_page_title_info, target)
          primary_query = rewriter.send(:extract_slug_topic, target)
          brand = rewriter.send(:extract_brand_from_url, target) if brand.empty?
          hooks = rewriter.synthesize_three_hooks(primary_query, brand, target, title_info[:title])
          meta = rewriter.synthesize_meta_description(primary_query, brand)

          data = {
            url: target,
            primary_query: primary_query,
            current_title: title_info[:title],
            current_pixel_width: title_info[:pixel_width],
            current_char_count: title_info[:char_count],
            truncated: title_info[:truncated],
            suggested_rewrites: hooks,
            suggested_meta: meta,
            html_title: "<title>#{hooks.first[:title]}</title>",
            html_meta: "<meta name=\"description\" content=\"#{meta}\">"
          }
        else
          # Keyword phrase
          brand = 'Brand' if brand.empty?
          hooks = GSC::LowCtrRewriter.generate_title_hooks(target, brand)
          meta = GSC::LowCtrRewriter.generate_meta_description(target, brand)

          data = {
            query: target,
            brand: brand,
            suggested_rewrites: hooks,
            suggested_meta: meta,
            html_title: "<title>#{hooks.first[:title]}</title>",
            html_meta: "<meta name=\"description\" content=\"#{meta}\">"
          }
        end

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts "\n" + Color.cyan("=" * 80)
        puts Color.bold("  LOW-CTR HIGH-IMPRESSION TITLE REWRITER")
        puts Color.cyan("=" * 80)
        if is_url
          puts Color.gray("  Target URL:    ") + Color.bold(target)
          puts Color.gray("  Detected Query:") + Color.yellow(" \"#{data[:primary_query]}\"")
          puts Color.gray("  Current Title: ") + Color.dim("#{data[:current_title]} (#{data[:current_char_count]} chars / #{data[:current_pixel_width]}px)")
          if data[:truncated]
            puts Color.red("  ⚠️ Current title exceeds 560px and is TRUNCATED on Google SERP!")
          end
        else
          puts Color.gray("  Target Query:  ") + Color.bold("\"#{target}\"")
          puts Color.gray("  Brand Token:   ") + Color.yellow(brand)
        end
        puts Color.cyan("-" * 80)

        puts "\n" + Color.bold("🏷️  3 HIGH-CONVERTING HOOK TITLE REWRITES (Guaranteed < 560px SERP Safe):")
        data[:suggested_rewrites].each_with_index do |hook, idx|
          fit_badge = hook[:fits_serp] ? Color.green("✓ SERP Safe (#{hook[:pixel_width]}px)") : Color.red("Over limit")
          puts "\n  #{idx + 1}. #{Color.bold(hook[:type])}:"
          puts "     #{Color.c(hook[:title], Color::YELLOW, Color::BOLD)}"
          puts "     #{Color.gray("Width: #{hook[:char_count]} chars / #{hook[:pixel_width]}px | [#{fit_badge}]")}"
          puts "     #{Color.dim("↳ #{hook[:rationale]}")}"
        end

        puts "\n" + Color.bold("📝 HIGH-CTR META DESCRIPTION (140–155 chars):")
        puts "   #{Color.white(data[:suggested_meta])}"

        puts "\n" + Color.bold("💻 1-CLICK HTML SNIPPET:")
        puts "   #{Color.dim(data[:html_title])}"
        puts "   #{Color.dim(data[:html_meta])}"
        puts "\n" + Color.cyan("=" * 80) + "\n"
      end

      def handle_domain_audit(api, site_url, hostname, target, options)
        domain = target || hostname || (site_url ? site_url.sub(%r{^https?://}, '').sub(%r{/$}, '') : 'Current Domain')
        days = (options[:days] || 28).to_i
        min_imp = (options[:min_imp] || options[:min_impressions] || 50).to_i
        cpc = (options[:cpc] || 1.50).to_f

        puts Color.cyan("⚡ Scanning GSC Performance data for #{Color.bold(domain)} (Past #{days} days, Min #{min_imp} imp)...") unless options[:json]

        rows = []
        if api && site_url
          begin
            res = api.query_analytics(
              site_url,
              days: days,
              dimensions: %w[query page],
              row_limit: 5000
            )
            rows = res.dig(:data, 'rows') || [] if res[:ok]
          rescue StandardError => e
            puts Color.yellow("⚠️ Note: Live Search Console query returned an error: #{e.message}") unless options[:json]
          end
        end

        analysis = GSC::LowCtrRewriter.analyze(rows, options.merge(min_imp: min_imp, cpc: cpc))

        if options[:json]
          puts JSON.pretty_generate(analysis)
          return
        end

        if analysis[:pages].empty?
          puts "\n" + Color.green("✅ No severe CTR underperformers found! Your ranking pages meet or exceed SERP benchmarks.")
          puts Color.gray("💡 Tip: Lower --min-imp (e.g. gsc low-ctr --min-imp 20) or adjust --days 90 to scan deeper.")
          return
        end

        puts "\n" + Color.cyan("╔" + "═" * 78 + "╗")
        puts Color.cyan("║") + Color.bold("   📉 LOW-CTR HIGH-IMPRESSION TITLE REWRITER (TRAFFIC LEAK RECOVERY)         ") + Color.cyan("║")
        puts Color.cyan("╚" + "═" * 78 + "╝")
        puts Color.gray("  Domain:             ") + Color.bold(domain)
        puts Color.gray("  Leaking Pages:      ") + Color.c(analysis[:total_leaking_pages].to_s, Color::YELLOW, Color::BOLD) + Color.gray(" pages ranking on Page 1-2 with low CTR")
        puts Color.gray("  Monthly Lost Clicks:") + Color.c("-#{analysis[:total_monthly_lost_clicks]} clicks/month", Color::RED, Color::BOLD) + Color.gray(" leaking due to unclickable titles")
        puts Color.gray("  Monthly Value Lost: ") + Color.c("-$#{analysis[:estimated_monthly_value_lost]} / month", Color::RED, Color::BOLD) + Color.gray(" (@ $#{cpc} CPC estimate)")
        rec = analysis[:projected_recovery]
        puts Color.gray("  Projected Recovery: ") + Color.c("+#{rec[:realistic_50pct]} clicks/mo (50% fix)", Color::GREEN, Color::BOLD) + Color.gray(" | ") + Color.c("+#{rec[:full_parity_100pct]} clicks/mo (100% parity)", Color::GREEN, Color::BOLD)
        puts Color.cyan("─" * 80)

        analysis[:pages].each_with_index do |p, idx|
          sev_badge = case p[:severity]
                      when :critical then Color.c(" [CRITICAL LEAK] ", Color::RED, Color::BOLD)
                      when :high     then Color.c(" [HIGH LEAK] ", Color::YELLOW, Color::BOLD)
                      else                Color.cyan(" [MODERATE] ")
                      end

          path = p[:url].sub(%r{^https?://[^/]+}, '')
          path = '/' if path.empty?

          puts "\n#{Color.bold("#{idx + 1}. #{path}")} #{sev_badge}"
          puts "   #{Color.gray("Full URL:")} #{p[:url]}"
          puts "   #{Color.gray("Primary Intent:")} #{Color.c("\"#{p[:primary_query]}\"", Color::YELLOW, Color::BOLD)}"
          if p[:secondary_queries].any?
            puts "   #{Color.gray("Also Ranking for:")} #{Color.dim(p[:secondary_queries].join(', '))}"
          end
          puts "   #{Color.gray("Metrics:")} Pos #{Color.bold(p[:position].to_s)} | #{p[:impressions]} imp | #{p[:clicks]} clicks | #{Color.red("Actual CTR: #{p[:actual_ctr]}%")} vs #{Color.green("Expected: #{p[:expected_ctr]}%")}"
          puts "   #{Color.gray("Hemorrhage:")} #{Color.c("-#{p[:lost_clicks]} lost clicks/mo", Color::RED, Color::BOLD)} (~$#{p[:lost_revenue]}/mo lost)"

          curr_trunc = p[:current_truncated] ? Color.red(" (⚠️ Truncated in Google SERP >560px)") : Color.green(" (Fits SERP)")
          puts "   #{Color.gray("Current Title:")} #{Color.dim(p[:current_title].to_s)}#{curr_trunc}"

          puts "\n   #{Color.bold("🏷️  Suggested 3 Hook Title Rewrites (SERP Safe < 560px):")}"
          p[:suggested_rewrites].each do |h|
            puts "      • [#{h[:type]}]: #{Color.c(h[:title], Color::YELLOW, Color::BOLD)} #{Color.gray("(#{h[:pixel_width]}px)")}"
          end

          puts "   #{Color.bold("📝 Suggested Meta Hook:")}"
          puts "      #{Color.white(p[:suggested_meta])}"

          puts "   #{Color.bold("💻 HTML Snippet:")}"
          puts "      #{Color.dim(p[:code_snippets][:html_title])}"
          puts Color.cyan("   " + "·" * 74)
        end

        if options[:csv]
          csv_rows = analysis[:pages].map do |p|
            [
              p[:url],
              p[:primary_query],
              p[:position],
              p[:impressions],
              p[:clicks],
              p[:actual_ctr],
              p[:expected_ctr],
              p[:lost_clicks],
              p[:lost_revenue],
              p[:suggested_rewrites][0]&.dig(:title),
              p[:suggested_rewrites][1]&.dig(:title),
              p[:suggested_rewrites][2]&.dig(:title),
              p[:suggested_meta]
            ]
          end
          headers = %w[URL PrimaryQuery Position Impressions Clicks ActualCTR ExpectedCTR LostClicks LostRevenueUSD HookTitle1 HookTitle2 HookTitle3 MetaDescription]
          Base.write_csv(options[:csv], headers, csv_rows)
          puts Color.cyan("\n📁 Exported #{analysis[:pages].size} title rewrites to #{options[:csv]}")
        end

        puts "\n💡 #{Color.bold("Execution Tip:")} Update title tags for the top 3 critical leaking pages first. Google typically re-indexes and reflects new CTR within 48 to 72 hours!\n\n"
      end
    end
  end
end

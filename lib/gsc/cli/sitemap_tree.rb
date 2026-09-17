# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../sitemap_tree'
require_relative '../color'

module GSC
  class CLI
    module SitemapTree
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_sitemap = target || options[:sitemap]

        # Auto-detection if target is not specified
        if target_sitemap.nil? || target_sitemap.empty?
          local_candidates = [
            'public/sitemap.xml',
            'public/sitemap_index.xml',
            'dist/sitemap.xml',
            'sitemap.xml',
            'sitemap_index.xml'
          ]
          found_local = local_candidates.find { |f| File.exist?(f) }
          if found_local
            target_sitemap = found_local
          elsif site_url || hostname
            origin = site_url ? site_url.sub(/^sc-domain:/, 'https://').chomp('/') : "https://#{hostname}"
            target_sitemap = "#{origin}/sitemap.xml"
          elsif Config.default_domain
            target_sitemap = "https://#{Config.default_domain}/sitemap.xml"
          else
            if options[:json]
              puts JSON.pretty_generate({ error: 'Target sitemap XML URL or file required. Example: gsc sitemap-tree https://mysite.com/sitemap.xml' })
            else
              puts Color.c("❌ Error: Target sitemap XML URL or file required.", Color::RED, Color::BOLD)
              puts "Example: gsc sitemap-tree https://mysite.com/sitemap.xml"
              puts "         gsc sitemap-tree ./sitemap.xml"
            end
            return
          end
        end

        gsc_pages = []
        if api && site_url
          gsc_res = api.query_analytics(site_url, days: options[:days] || 28, dimensions: ['page'], row_limit: 250) rescue { ok: false }
          if gsc_res[:ok]
            gsc_pages = (gsc_res.dig(:data, 'rows') || []).map { |r| { url: r['keys'][0], clicks: r['clicks'], imp: r['impressions'] } }
          end
        end

        auditor = GSC::SitemapTree.new(target_sitemap, options)
        report = auditor.audit(gsc_pages)

        if options[:json]
          puts JSON.pretty_generate(report)
          return
        end

        render_sitemap_tree(report, options)

        if options[:csv]
          csv_rows = report[:all_urls].map do |u|
            [u, report[:root]]
          end
          Base.write_csv(options[:csv], %w[URL SitemapSource], csv_rows)
          puts Color.cyan("📁 Exported #{report[:all_urls].size} sitemap URLs to #{options[:csv]}")
        end
      end

      def render_sitemap_tree(report, options)
        puts "\n" + Color.cyan("╔" + "═" * 78 + "╗")
        puts Color.cyan("║") + Color.bold("   🗺️  SITEMAP INDEX HIERARCHY & SPECIFICATION COMPLIANCE AUDITOR              ") + Color.cyan("║")
        puts Color.cyan("╚" + "═" * 78 + "╝")
        puts Color.gray("  Root Sitemap:     ") + Color.bold(report[:root].to_s)
        puts Color.gray("  Structure:        ") + (report[:is_index] ? Color.cyan("Sitemap Index (Multi-file hierarchy)") : Color.dim("Single Urlset"))
        puts Color.gray("  Total Sitemaps:   ") + Color.bold(report[:total_sitemaps].to_s)
        puts Color.gray("  Total URLs:       ") + Color.bold(report[:total_urls].to_s)

        # Health Score
        score_color = report[:health_score] >= 85 ? Color::GREEN : (report[:health_score] >= 60 ? Color::YELLOW : Color::RED)
        puts Color.gray("  Compliance Score: ") + Color.c("#{report[:health_score]}/100", score_color, Color::BOLD)
        puts Color.cyan("─" * 80)

        # Violations
        if report[:violations].any?
          puts "\n" + Color.bold("🚨 SITEMAP PROTOCOL VIOLATIONS:")
          report[:violations].each do |v|
            puts "   ✗ [#{v[:type].to_s.upcase}] #{v[:sitemap]}: #{Color.red(v[:message])}"
          end
        else
          puts "\n" + Color.green("✓ Zero protocol violations! Conforms to Google 50,000 URLs & 50MB limits.")
        end

        # GSC Coverage
        cov = report[:coverage]
        if cov && cov[:total_gsc_pages] && cov[:total_gsc_pages] > 0
          cov_color = cov[:coverage_pct] >= 90.0 ? Color::GREEN : Color::YELLOW
          puts "\n" + Color.bold("📈 GOOGLE SEARCH CONSOLE SITEMAP COVERAGE:")
          puts "   • Coverage Ratio:       " + Color.c("#{cov[:coverage_pct]}%", cov_color, Color::BOLD) + " (#{cov[:included_in_sitemap]}/#{cov[:total_gsc_pages]} ranking pages listed)"
          if cov[:missing_from_sitemap] > 0
            puts "   • Missing From Sitemap: " + Color.yellow("#{cov[:missing_from_sitemap]} pages") + Color.gray(" (ranking in GSC but omitted from sitemap)")
            cov[:missing_sample].first(3).each do |m|
              puts "      ↳ " + Color.dim(m)
            end
          end
        end

        # Visual ASCII Tree
        puts "\n" + Color.bold("🌳 SITEMAP ARCHITECTURE TREE:")
        print_tree_node(report[:tree], "", true)
        puts Color.cyan("═" * 80) + "\n"
      end

      def print_tree_node(node, prefix, is_last)
        branch = is_last ? "└── " : "├── "
        icon = node[:type] == :sitemapindex ? "📁 " : "📄 "

        lastmod_label = if node[:latest_lastmod]
                          node[:is_stale] ? Color.yellow("[Stale: #{node[:latest_lastmod]}]") : Color.gray("[Updated: #{node[:latest_lastmod]}]")
                        else
                          Color.gray("[No lastmod]")
                        end

        count_label = Color.bold("#{node[:url_count] || 0} URLs")
        size_kb = ((node[:size_bytes] || 0) / 1024.0).round(1)
        size_label = Color.dim("(#{size_kb} KB)")

        puts "#{prefix}#{branch}#{icon}#{Color.bold(node[:url])} #{count_label} #{size_label} #{lastmod_label}"

        if node[:children] && node[:children].any?
          new_prefix = prefix + (is_last ? "    " : "│   ")
          node[:children].each_with_index do |child, idx|
            child_is_last = (idx == node[:children].size - 1)
            print_tree_node(child, new_prefix, child_is_last)
          end
        end
      end
    end
  end
end

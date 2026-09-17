# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'uri'
require_relative 'base'
require_relative '../zombie_purger'
require_relative '../sitemap_loader'
require_relative '../color'

module GSC
  class CLI
    module ZombiePurger
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil, https_origin = nil)
        target_inv = target || options[:inventory] || options[:sitemap]
        urls = resolve_inventory(target_inv, https_origin, options)
        if urls.empty?
          msg = "No URLs found to audit. Please specify a sitemap or URL inventory file: gsc zombies <sitemap.xml|urls.txt>"
          if options[:json]
            puts JSON.pretty_generate({ error: msg })
          else
            puts Color.red("❌ Error: #{msg}")
          end
          return
        end

        puts "🔍 Auditing #{Color.cyan(urls.size.to_s)} URLs against Search Console performance..." unless options[:json] || options[:format]

        gsc_data = fetch_gsc_pages(api, site_url, options)

        result = GSC::ZombiePurger.audit(urls, gsc_data, options)

        # Handle explicit rule format exports
        if options[:format]
          handle_format_export(result, options)
          return
        end

        if options[:json]
          puts JSON.pretty_generate(result)
          return
        end

        render_terminal(result)

        if options[:csv]
          export_csv(result, options[:csv])
        end
      end

      def resolve_inventory(target, https_origin, options)
        # 1. If target is a file that exists on local disk
        if target && File.exist?(target)
          if target.downcase.end_with?('.xml') || target.downcase.end_with?('.gz')
            return SitemapLoader.resolve_urls(target, https_origin)
          else
            return File.readlines(target).map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
          end
        end

        # 2. If target is a remote sitemap URL
        if target && target.match?(%r{^https?://})
          return SitemapLoader.resolve_urls(target, https_origin)
        end

        # 3. If target is a local path relative to current working directory
        if target && (target.include?('/') || target.include?('.'))
          expanded = File.expand_path(target)
          if File.exist?(expanded)
            return target.end_with?('.xml') ? SitemapLoader.resolve_urls(expanded, https_origin) : File.readlines(expanded).map(&:strip).reject(&:empty?)
          end
        end

        # 4. Auto-detect public/sitemap.xml or sitemap.xml
        %w[public/sitemap.xml sitemap.xml public/sitemaps.xml].each do |candidate|
          if File.exist?(candidate)
            puts "📄 Auto-detected local sitemap: #{Color.cyan(candidate)}" unless options[:json] || options[:format]
            return SitemapLoader.resolve_urls(candidate, https_origin)
          end
        end

        # 5. If origin is present, attempt fetching https_origin/sitemap.xml
        if https_origin
          remote_sitemap = "#{https_origin.sub(%r{/$}, '')}/sitemap.xml"
          remote_urls = SitemapLoader.resolve_urls(remote_sitemap, https_origin)
          return remote_urls if remote_urls.any?
        end

        []
      end

      def fetch_gsc_pages(api, site_url, options)
        return [] unless api && site_url

        days = (options[:days] || 90).to_i
        res = api.query_analytics(site_url, days: days, dimensions: ['page'], row_limit: 5000)
        if res[:ok]
          res.dig(:data, 'rows') || []
        else
          puts Color.yellow("⚠️ Search Analytics notice: #{res[:data]} (operating on zero-baseline)") unless options[:json] || options[:format]
          []
        end
      rescue StandardError => e
        puts Color.yellow("⚠️ Could not fetch GSC live rows (#{e.message}); using local baseline") unless options[:json] || options[:format]
        []
      end

      def handle_format_export(result, options)
        case options[:format].to_s.downcase
        when 'nginx'
          puts result.dig(:server_rules, :nginx)
        when 'htaccess', 'apache'
          puts result.dig(:server_rules, :htaccess)
        when 'redirects', 'netlify', 'cloudflare', '_redirects'
          puts result.dig(:server_rules, :redirects)
        when 'meta', 'robots'
          puts result.dig(:server_rules, :meta_robots)
        else
          puts Color.red("Unknown format '#{options[:format]}'. Choose: nginx, htaccess, redirects, meta")
        end
      end

      def render_terminal(res)
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🧟 ZOMBIE CONTENT PURGE & CRAWL BUDGET OPTIMIZER")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        grade_color = case res[:grade]
                      when 'A' then Color.green(res[:grade])
                      when 'B' then Color.cyan(res[:grade])
                      when 'C' then Color.yellow(res[:grade])
                      else Color.red(res[:grade])
                      end

        puts "  • Crawl Efficiency Grade:             [ #{Color.bold(grade_color)} ] (Health Score: #{res[:health_score]}/100)"
        puts "  • Crawl Equity Dilution Index (CEDI): #{Color.bold("#{res[:cedi]}%")} (#{res[:zombie_count]} of #{res[:total_inventory]} URLs)"
        puts "  • Active Impressions Window:          #{res[:days]} Days (Threshold: <= #{res[:threshold]} impressions)"
        puts "  • Estimated Googlebot Crawl Waste:     #{Color.red(res[:wasted_crawls_monthly].to_s)} crawls/mo (~#{res[:wasted_crawls_annually]} /year)"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        brk = res[:action_breakdown]
        puts "  Triage Recommendations:"
        puts "   🗑️  Purge 410 (Dead / Thin):         #{Color.bold(brk[:purge_410].to_s)} URLs (Immediate drop from Google index)"
        puts "   🔀 Redirect 301 (Pillar Transfer):   #{Color.bold(brk[:redirect_301].to_s)} URLs (Consolidate topic authority)"
        puts "   📦 Consolidate / Rewrite:            #{Color.bold(brk[:consolidate].to_s)} URLs (Merge into evergreen canonical)"
        puts "   🛡️  Noindex (Utility / Legal):        #{Color.bold(brk[:noindex].to_s)} URLs (Preserve user access, stop crawl waste)"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"

        if res[:zombies].empty?
          puts Color.green("🎉 Zero zombie pages detected! All inventory URLs are actively receiving search impressions.\n")
          return
        end

        puts "#{Color.bold("PRIORITIZED ZOMBIE PAGES TO PURGE / REDIRECT:")}\n\n"
        printf " %-36s %-16s %s\n", "URL Path", "Action", "Prescription / Target"
        puts " ---------------------------------------------------------------------------------------"

        res[:zombies].each do |z|
          short_path = z[:path].length > 34 ? "#{z[:path][0..31]}..." : z[:path]

          action_badge = case z[:action]
                         when :purge_410 then Color.red("[PURGE 410]")
                         when :redirect_301 then Color.yellow("[REDIRECT 301]")
                         when :noindex then Color.cyan("[NOINDEX]")
                         else Color.gray("[CONSOLIDATE]")
                         end

          target_info = if z[:action] == :redirect_301 && z[:target_url]
                          t_path = URI.parse(z[:target_url]).path rescue z[:target_url]
                          "-> #{t_path}"
                        else
                          z[:rationale]
                        end
          short_target = target_info.length > 55 ? "#{target_info[0..52]}..." : target_info

          printf " %-36s %-25s %s\n", short_path, action_badge, short_target
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
        puts "💡 #{Color.bold("1-Click Server Purge Exports:")}"
        puts "   • Generate Nginx configuration:       #{Color.cyan("gsc zombies --format nginx")}"
        puts "   • Generate Apache .htaccess rules:    #{Color.cyan("gsc zombies --format htaccess")}"
        puts "   • Generate Netlify/Cloudflare rules:  #{Color.cyan("gsc zombies --format redirects")}"
        puts "   • Export full CSV audit report:       #{Color.cyan("gsc zombies --csv zombies.csv")}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"
      end

      def export_csv(res, file_path)
        headers = %w[URL Path Action ActionLabel Impressions TargetURL Rationale]
        rows = res[:zombies].map do |z|
          [
            z[:url],
            z[:path],
            z[:action].to_s,
            z[:action_label],
            z[:impressions],
            z[:target_url] || '',
            z[:rationale]
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported #{rows.size} zombie audit records to #{file_path}")
      end
    end
  end
end

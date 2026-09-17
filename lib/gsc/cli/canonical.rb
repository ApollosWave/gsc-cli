# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../canonical_chains'

module GSC
  class CLI
    module Canonical
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || options[:url]

        if target_url && target_url =~ %r{^https?://}
          # Single URL audit
          handle_single_url_audit(target_url, options, api, site_url)
        else
          # Batch audit domain
          domain = target_url || hostname || (options[:domain] rescue nil) || (site_url ? site_url.sub(%r{^https?://}, '').sub(%r{/$}, '') : nil)
          handle_batch_domain_audit(domain, options, api, site_url)
        end
      end

      def handle_single_url_audit(target, options, api = nil, site_url = nil)
        unless options[:json]
          puts "\n" + Color.cyan("=" * 80)
          puts Color.bold("  CANONICAL LOOP & REDIRECT CHAIN BREAKER")
          puts Color.cyan("=" * 80)
          puts Color.gray("  Auditing URL: ") + Color.bold(target)
          puts ""
        end

        # Fetch GSC rows if authenticated domain matches
        gsc_rows = nil
        if api && site_url
          begin
            res = api.query_analytics(
              site_url: site_url,
              start_date: (Date.today - 28).to_s,
              end_date: Date.today.to_s,
              dimensions: ['page', 'query'],
              row_limit: 1000
            )
            gsc_rows = res.dig(:data, 'rows') || res['rows']
          rescue StandardError
            # Non-fatal if GSC offline
          end
        end

        breaker = GSC::CanonicalChains.new
        result = breaker.audit_url(target, gsc_rows: gsc_rows)

        if options[:json]
          puts JSON.pretty_generate(result)
          return
        end

        render_canonical_audit(result)
      end

      def handle_batch_domain_audit(domain, options, api = nil, site_url = nil)
        domain = domain || (Config.default_domain rescue nil)
        if domain.nil? || domain.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc canonical-chains mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc canonical-chains mysite.com", Color::RED, Color::BOLD)
          end
          return
        end

        unless options[:json]
          puts "\n" + Color.cyan("=" * 80)
          puts Color.bold("  PORTFOLIO CANONICAL & REDIRECT CHAIN AUDIT: ") + Color.yellow(domain)
          puts Color.cyan("=" * 80)
        end

        limit = (options[:limit] || 20).to_i
        concurrency = (options[:concurrency] || 4).to_i

        urls = []
        rows = []
        if api && site_url
          print Color.gray("  Fetching top #{limit} pages from GSC... ")
          begin
            res = api.query_analytics(
              site_url: site_url,
              start_date: (Date.today - 28).to_s,
              end_date: Date.today.to_s,
              dimensions: ['page'],
              row_limit: limit
            )
            rows = res.dig(:data, 'rows') || res['rows'] || []
            urls = rows.map { |r| (r['keys'] || []).first }.compact
            puts Color.green("✓ (#{rows.size} pages)")
          rescue StandardError => e
            puts Color.yellow("(GSC query failed: #{e.message})")
          end
        end

        if urls.empty?
          urls = [
            "https://#{domain}/",
            "http://#{domain}/",
            "https://#{domain}"
          ]
        end

        puts Color.gray("  Tracing redirect graphs & canonical targets (concurrency: #{concurrency})...\n")

        breaker = GSC::CanonicalChains.new
        batch_summary = breaker.audit_batch(urls, gsc_rows: rows, concurrency: concurrency)

        if options[:json]
          puts JSON.pretty_generate(batch_summary)
          return
        end

        render_batch_summary(batch_summary, domain)
      end

      def render_canonical_audit(r)
        status_badge = case r[:severity]
                       when :critical then Color.red(" CRITICAL DEFECT ")
                       when :warning  then Color.yellow(" WARNING ")
                       else Color.green(" HEALTHY ")
                       end

        puts "  Status:           #{status_badge}"
        puts "  Redirect Hops:    " + (r[:redirect_hops] > 0 ? Color.yellow(r[:redirect_hops].to_s) : Color.green("0"))
        puts "  Equity Retained:  " + (r[:equity_retention_pct] < 75 ? Color.red("#{r[:equity_retention_pct]}%") : Color.green("#{r[:equity_retention_pct]}%")) + Color.gray(" (Loss: #{r[:equity_loss_pct]}%)")
        puts "  Total Latency:    " + Color.cyan("#{r[:total_duration_ms]}ms")

        if r.dig(:traffic_at_risk, :total_clicks) && r[:traffic_at_risk][:total_clicks] > 0
          puts "  Traffic at Risk:  " + Color.red("#{r[:traffic_at_risk][:total_clicks]} clicks / #{r[:traffic_at_risk][:total_impressions]} imps (last 28d)")
        end

        # Hops graph
        puts "\n" + Color.bold("  REDIRECT & CANONICAL GRAPH:")
        puts "  " + Color.gray("-" * 76)
        r[:hops].each do |h|
          code_str = case h[:status_code]
                     when 200 then Color.green("200 OK")
                     when 301 then Color.yellow("301 Perm")
                     when 302 then Color.yellow("302 Temp")
                     when 307, 308 then Color.yellow("#{h[:status_code]} Redir")
                     else Color.red("#{h[:status_code]} Err")
                     end
          puts "  [Hop #{h[:hop]}] #{code_str} (#{h[:duration_ms]}ms) -> #{Color.cyan(h[:url])}"
          if h[:canonical_url]
            puts "         ↳ #{Color.magenta("Canonical:")} #{h[:canonical_url]} (#{h[:canonical_source]})"
          end
          if h[:error]
            puts "         ↳ #{Color.red("ERROR:")} #{h[:error]}"
          end
        end
        puts "  " + Color.gray("-" * 76)

        # Issues
        if r[:issues].any?
          puts "\n" + Color.bold("  IDENTIFIED ISSUES:")
          r[:issues].each do |iss|
            prefix = iss[:code] == :loop || iss[:code] == :canonical_redirects ? Color.red("  ✖ ") : Color.yellow("  ⚠ ")
            puts "#{prefix}#{iss[:message]}"
          end
        end

        # Server Collapse Rules
        if r[:redirect_hops] >= 1 || r[:canonical_loop]
          puts "\n" + Color.bold("  1-CLICK SERVER COLLAPSE RULES (Bypass All Intermediate Hops):")
          puts "  " + Color.gray("-" * 76)
          puts Color.yellow("  [Nginx]")
          puts "  " + Color.cyan(r[:server_rules][:nginx].to_s)
          puts Color.yellow("\n  [Apache .htaccess]")
          puts "  " + Color.cyan(r[:server_rules][:apache].to_s)
          puts Color.yellow("\n  [Cloudflare Redirect Expression]")
          puts "  " + Color.cyan(r[:server_rules][:cloudflare].to_s)
          puts Color.yellow("\n  [Vercel / Netlify _redirects]")
          puts "  " + Color.cyan(r[:server_rules][:vercel_netlify].to_s)
          puts "  " + Color.gray("-" * 76)
        end
        puts ""
      end

      def render_batch_summary(bs, domain)
        puts "\n  Total Pages Audited:    " + Color.bold(bs[:total_audited].to_s)
        puts "  Redirect Chains (>=2):  " + (bs[:redirect_chains_count] > 0 ? Color.red(bs[:redirect_chains_count].to_s) : Color.green("0"))
        puts "  Canonical / Dir Loops:  " + (bs[:loops_count] > 0 ? Color.red(bs[:loops_count].to_s) : Color.green("0"))
        puts "  Average Equity Preserved: " + (bs[:avg_equity_retention_pct] < 85 ? Color.yellow("#{bs[:avg_equity_retention_pct]}%") : Color.green("#{bs[:avg_equity_retention_pct]}%"))
        if bs[:total_clicks_at_risk] > 0
          puts "  Total GSC Clicks at Risk: " + Color.red("#{bs[:total_clicks_at_risk]} clicks")
        end

        puts "\n" + Color.bold("  TOP CHAIN & CANONICAL RISKS:")
        puts "  " + Color.gray("-" * 76)
        printf "  %-40s %-8s %-12s %-12s\n", "URL", "Hops", "Equity Ret.", "Status"
        puts "  " + Color.gray("-" * 76)

        bs[:results].first(15).each do |r|
          status_str = if r[:loop_detected]
                         Color.red("LOOP")
                       elsif r[:redirect_hops] >= 2
                         Color.yellow("CHAIN")
                       elsif r[:redirect_hops] == 1
                         Color.cyan("REDIRECT")
                       else
                         Color.green("DIRECT")
                       end
          short_url = r[:start_url].gsub(%r{^https?://(www\.)?}, '')[0..38]
          printf "  %-40s %-8s %-12s %-12s\n",
                 short_url,
                 r[:redirect_hops],
                 "#{r[:equity_retention_pct]}%",
                 status_str
        end
        puts "  " + Color.gray("-" * 76)
        puts Color.gray("\n  Tip: Run `gsc canonical-chains <url>` on any flagged URL to copy direct Nginx/Cloudflare collapse rules.\n")
      end
    end
  end
end

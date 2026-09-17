# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../soft_404_analyzer'
require_relative '../color'

module GSC
  class CLI
    module Soft404
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || (extra && extra.first) || hostname || Config.default_domain
        if target_url.nil? || target_url.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or domain required. Example: gsc soft-404 https://mydomain.com/page' })
          else
            puts Color.c("❌ Error: Target URL or domain required.", Color::RED, Color::BOLD)
            puts "Example: gsc soft-404 https://mydomain.com/page"
            puts "         gsc soft-404 mydomain.com"
          end
          return
        end

        puts "🔍 Auditing URLs for Soft-404 errors, thin content & HTTP status code mismatches..." unless options[:json]

        res = GSC::Soft404Analyzer.analyze(target_url, options)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        if options[:csv]
          export_csv(res)
          return
        end

        render_terminal(res, options, extra)
      end

      def render_terminal(res, options, extra = [])
        sum = res[:summary]

        grade_color = case res[:grade]
                      when 'A' then Color.green("#{res[:health_score]}/100 (Grade #{res[:grade]})")
                      when 'B', 'C' then Color.yellow("#{res[:health_score]}/100 (Grade #{res[:grade]})")
                      else Color.red("#{res[:health_score]}/100 (Grade #{res[:grade]})")
                      end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🚫 SOFT-404 & BROKEN URL DIAGNOSTIC ENGINE")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        puts "  • Soft-404 Health Score:     [ #{Color.bold(grade_color)} ]"
        puts "  • Crawl Budget Waste:        #{Color.bold(Color.red("#{sum[:crawl_budget_waste_percent]}%"))} of crawled pages"
        puts "  • URLs Audited:              #{Color.bold(res[:total_urls_audited].to_s)} total"
        puts "  • Verified Healthy (200 OK): #{Color.green(sum[:healthy_count].to_s)}"
        puts "  • Soft-404 Errors Flagged:   #{Color.bold(Color.red(sum[:soft_404_count].to_s))}"
        puts "  • Hard 404/410 Broken:       #{Color.yellow(sum[:hard_404_count].to_s)}"
        puts "  • Thin Content Warnings:     #{Color.cyan(sum[:thin_content_count].to_s)}"
        if res[:detected_stack] && res[:detected_stack][:framework] != 'Universal Web'
          puts "  • Detected Environment:      #{Color.bold(Color.cyan("#{res[:detected_stack][:framework]} (#{res[:detected_stack][:server]})"))}"
        end
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        puts format("%-45s | %-5s | %-18s | %-6s | %-16s", "URL", "HTTP", "Classification", "Words", "Suggested Target")
        puts "#{Color.bold("─" * 105)}"

        res[:all_results].each do |item|
          u_trunc = item[:url].length > 43 ? "#{item[:url][0..40]}..." : item[:url]
          code_s = item[:status_code].to_s

          class_badge = case item[:classification]
                        when :healthy_200 then Color.green("HEALTHY")
                        when :soft_404 then Color.red("🚨 SOFT-404")
                        when :soft_404_redirect then Color.red("⚠️ REDIRECT-404")
                        when :hard_404 then Color.yellow("HARD 404")
                        when :thin_content_warning then Color.cyan("THIN CONTENT")
                        else item[:classification].to_s.upcase
                        end

          puts format("%-45s | %-5s | %-27s | %-6d | %-16s",
                      u_trunc, code_s, class_badge, item[:word_count], item[:suggested_redirect])
        end

        fix_urls = res[:all_results].select { |r| r[:is_soft_404] || r[:classification] == :hard_404 || r[:classification] == :soft_404_redirect }

        if fix_urls.any? || options[:fix]
          puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
          puts "#{Color.bold("1-CLICK SERVER REWRITE RULES FOR 404 & REDIRECT RECOVERY:")}"

          if fix_urls.empty?
            puts "  (All audited URLs are verified healthy 200 OK. No redirect rules required.)"
          else
            fix_param = options[:fix].is_a?(String) ? options[:fix] : nil
            valid_fmts = %w[
              nginx caddy htaccess apache nextjs next vercel sveltekit svelte astro
              webflow shopify cloudflare cloudflare-pages pages cf-workers workers worker
              netlify _redirects github github-pages gh-pages gatsby all
            ]
            extra_fmt = (extra && extra.first.to_s) if valid_fmts.include?(extra&.first.to_s.downcase)

            fmt = (options[:format] || fix_param || extra_fmt || 'nginx').to_s.downcase

            case fmt
            when 'caddy'
              puts "  # Caddy (Caddyfile) 301 Redirect Rules:"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:caddy]}") }
            when 'sveltekit', 'svelte'
              puts "  // SvelteKit hooks.server.ts (or +page.server.ts):"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:sveltekit]}") }
            when 'astro'
              puts "  // Astro (astro.config.mjs) redirects map:"
              puts "  redirects: {"
              fix_urls.first(10).each { |s| puts Color.cyan("    #{s[:remediation_rules][:astro]}") }
              puts "  }"
            when 'gatsby'
              puts "  // Gatsby (gatsby-node.js -> createPages):"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:gatsby]}") }
            when 'cloudflare', 'cloudflare-pages', 'pages', 'netlify', '_redirects'
              puts "  # Cloudflare Pages / Netlify _redirects file:"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:cloudflare]}") }
            when 'cloudflare-workers', 'workers', 'worker', 'cf-workers'
              puts "  // Cloudflare Workers (worker.js / ts):"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:cloudflare_workers]}") }
            when 'github', 'github-pages', 'gh-pages'
              puts "  <!-- GitHub Pages / Static HTML Redirect: -->"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:github_pages]}") }
            when 'webflow'
              puts "  # Webflow 301 Redirects (Project Settings -> Publishing -> 301 Redirects):"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:webflow]}") }
            when 'shopify'
              puts "  # Shopify URL Redirects (Import CSV via Online Store -> Navigation):"
              puts "  Redirect from,Redirect to"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:shopify]}") }
            when 'nextjs', 'next'
              puts "  // Next.js (next.config.js) redirects array:"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:nextjs]}") }
            when 'vercel'
              puts "  // vercel.json redirects array:"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{JSON.generate(s[:remediation_rules][:vercel])},") }
            when 'htaccess', 'apache', 'wordpress'
              puts "  # Apache / WordPress .htaccess 301 Redirect Rules:"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:htaccess]}") }
            when 'all'
              puts "  # --- Nginx ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:nginx]}") }
              puts "\n  # --- Caddy ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:caddy]}") }
              puts "\n  # --- Cloudflare Pages / Netlify (_redirects) ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:cloudflare]}") }
              puts "\n  // --- Cloudflare Workers ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:cloudflare_workers]}") }
              puts "\n  // --- SvelteKit (hooks.server.ts) ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:sveltekit]}") }
              puts "\n  // --- Next.js (next.config.js) ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:nextjs]}") }
              puts "\n  // --- Astro (astro.config.mjs) ---"
              fix_urls.first(2).each { |s| puts Color.cyan("    #{s[:remediation_rules][:astro]}") }
              puts "\n  // --- Gatsby (gatsby-node.js) ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:gatsby]}") }
              puts "\n  <!-- --- GitHub Pages HTML Redirect --- -->"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:github_pages]}") }
              puts "\n  # --- Webflow (Site Settings 301) ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:webflow]}") }
              puts "\n  # --- Shopify CSV ---"
              fix_urls.first(2).each { |s| puts Color.cyan("  #{s[:remediation_rules][:shopify]}") }
            else
              puts "  # Nginx 301 Permanent Redirect Rules:"
              fix_urls.first(10).each { |s| puts Color.cyan("  #{s[:remediation_rules][:nginx]}") }
            end

            puts "\n💡 #{Color.gray("Tip: Generate for any stack: --fix caddy | --fix sveltekit | --fix astro | --fix cloudflare | --fix workers | --fix github | --fix gatsby | --fix webflow | --fix shopify | --fix nextjs | --fix all")}"
          end
        end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(res)
        require 'csv'
        puts "url,status_code,classification,word_count,suggested_redirect,suggested_action"
        res[:all_results].each do |item|
          puts [
            item[:url],
            item[:status_code],
            item[:classification],
            item[:word_count],
            item[:suggested_redirect],
            item[:suggested_action]
          ].to_csv
        end
      end
    end
  end
end

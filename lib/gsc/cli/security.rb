# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../security_scanner'
require_relative '../color'

module GSC
  class CLI
    module Security
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || options[:url] || hostname || (site_url ? site_url.sub(/^sc-domain:/, '') : nil) || (Config.default_domain rescue nil)
        unless target_url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or domain required. Example: gsc security https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or domain required. Example: gsc security https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        target_url = "https://#{target_url}" unless target_url =~ %r{^https?://}

        scanner = GSC::SecurityScanner.new(target_url, options)
        result = scanner.audit

        if options[:json]
          puts JSON.pretty_generate(result)
          return
        end

        render_security_audit(result, options)
      end

      def render_security_audit(data, options)
        puts "\n" + Color.cyan("╔" + "═" * 78 + "╗")
        puts Color.cyan("║") + Color.bold("   🔒 SECURITY HEADERS & HTTPS MIXED CONTENT AUDITOR                          ") + Color.cyan("║")
        puts Color.cyan("╚" + "═" * 78 + "╝")
        puts Color.gray("  Target URL:       ") + Color.bold(data[:target])
        puts Color.gray("  Effective URL:    ") + Color.dim(data[:effective_url].to_s)

        # Score & Grade
        grade_color = case data[:grade]
                      when 'A+', 'A' then Color::GREEN
                      when 'B'      then Color::CYAN
                      when 'C'      then Color::YELLOW
                      else               Color::RED
                      end

        puts Color.gray("  Security Posture: ") + Color.c("#{data[:score]}/100 [Grade #{data[:grade]}]", grade_color, Color::BOLD)
        puts Color.gray("  Verdict:          ") + Color.c(data[:verdict].to_s, grade_color)
        puts Color.cyan("─" * 80)

        # 1. SSL/TLS Certificate
        ssl = data[:ssl] || {}
        puts "\n" + Color.bold("🔐 SSL/TLS CERTIFICATE STATUS:")
        if ssl[:status] == :valid
          puts "   • Status:        " + Color.green(Color.bold("VALID & SECURE")) + Color.gray(" (#{ssl[:days_remaining]} days remaining)")
          puts "   • Valid Period:  #{ssl[:valid_from][0..9]} → #{ssl[:valid_to][0..9]}"
          puts "   • Issuer:        #{ssl[:issuer]}"
          puts "   • Subject / SAN: #{ssl[:subject]} (#{ssl[:san_count]} alternate names)"
        elsif ssl[:status] == :not_https
          puts "   • Status:        " + Color.red(Color.bold("NOT SERVED OVER HTTPS"))
        else
          puts "   • Status:        " + Color.red(Color.bold("WARNING: #{ssl[:message] || ssl[:status]}"))
        end

        # 2. HSTS Preload Eligibility
        hsts = data[:hsts_preload] || {}
        puts "\n" + Color.bold("🚀 HSTS PRELOAD STATUS (Google Chrome Preload List):")
        if hsts[:eligible]
          puts "   • Eligibility:   " + Color.green(Color.bold("✓ ELIGIBLE FOR HSTS PRELOAD"))
          puts "   • Header:        " + Color.dim(hsts[:current_header].to_s)
        else
          puts "   • Eligibility:   " + Color.yellow(Color.bold("NOT CURRENTLY ELIGIBLE"))
          (hsts[:reasons] || []).each do |reason|
            puts "     ↳ " + Color.gray(reason)
          end
        end

        # 3. Security Headers Audit Table
        headers = data[:headers] || {}
        puts "\n" + Color.bold("🛡️  ENTERPRISE SECURITY HEADERS:")

        (headers[:present] || []).each do |p|
          q_badge = case p[:quality]
                    when :optimal then Color.green("[OPTIMAL]")
                    when :acceptable then Color.cyan("[ACCEPTABLE]")
                    else Color.yellow("[SUBOPTIMAL]")
                    end
          puts "   ✓ #{Color.bold(p[:header].ljust(27))} #{q_badge} #{Color.dim(p[:details])}"
        end

        (headers[:missing] || []).each do |m|
          puts "   ✗ #{Color.red(Color.bold(m[:header].ljust(27)))} #{Color.red("[MISSING -#{m[:weight]}pts]")} #{Color.gray(m[:desc])}"
        end

        # 4. Leakage Headers
        leaks = headers[:leakage] || []
        if leaks.any?
          puts "\n" + Color.bold("⚠️  SERVER FINGERPRINTING & LEAKAGE HEADERS:")
          leaks.each do |l|
            puts "   • #{Color.yellow(l[:header])}: #{Color.dim(l[:value])} #{Color.gray("(Reveals server version to attackers)")}"
          end
        end

        # 5. Mixed Content
        mixed = data[:mixed_content] || {}
        puts "\n" + Color.bold("⚡ HTTPS MIXED CONTENT STATUS:")
        if mixed[:total] == 0
          puts "   " + Color.green("✓ Zero mixed content detected! All scripts, frames, and media are securely loaded over HTTPS.")
        else
          if mixed[:active].any?
            puts "   🚨 " + Color.red(Color.bold("ACTIVE MIXED CONTENT (#{mixed[:active].size} items - HARD BLOCKED BY BROWSERS):"))
            mixed[:active].first(5).each do |item|
              puts "      • #{item[:type]}: #{Color.yellow(item[:url])}"
            end
          end
          if mixed[:passive].any?
            puts "   ⚠️  " + Color.yellow(Color.bold("PASSIVE MIXED CONTENT (#{mixed[:passive].size} images/media - DEGRADES PADLOCK):"))
            mixed[:passive].first(5).each do |item|
              puts "      • #{item[:type]}: #{Color.dim(item[:url])}"
            end
          end
        end

        # 6. Recommendations
        recs = data[:recommendations] || []
        if recs.any?
          puts "\n" + Color.bold("📋 ACTIONABLE SECURITY RECOMMENDATIONS:")
          recs.each_with_index do |rec, idx|
            puts "   #{idx + 1}. #{rec}"
          end
        end

        # 7. 1-Click Server Directives
        rules = data[:server_rules] || {}
        if rules[:nginx] && !rules[:nginx].empty?
          puts "\n" + Color.cyan("─" * 80)
          puts Color.bold("💻 1-CLICK SERVER FIX RULES (Nginx):")
          puts Color.dim(rules[:nginx])
          puts "\n" + Color.bold("💻 1-CLICK SERVER FIX RULES (Apache .htaccess):")
          puts Color.dim(rules[:apache])
          puts "\n" + Color.bold("💻 1-CLICK SERVER FIX RULES (Vercel / Netlify _headers):")
          puts Color.dim(rules[:vercel_netlify])
        end
        puts Color.cyan("=" * 80) + "\n"
      end
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../doctor'
require_relative '../color'

module GSC
  class CLI
    module Doctor
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        puts "🩺 Running zero-dependency architecture & system certification..." unless options[:json]

        res = GSC::Doctor.diagnose(options)

        if options[:json]
          puts JSON.pretty_generate(res)
          if options[:strict] && (!res[:certification][:certified_zero_gem] || res[:certification][:score] < 100.0)
            exit 1
          end
          return
        end

        render_terminal(res, options)

        if options[:strict] && (!res[:certification][:certified_zero_gem] || res[:certification][:score] < 100.0)
          puts "\n#{Color.red("✖ STRICT AUDIT FAILED: Architecture certification score is #{res[:certification][:score]}/100.")}"
          exit 1
        end
      end

      def render_terminal(res, options)
        cert = res[:certification]
        purity = res[:purity]
        cold = res[:cold_start]
        crypto = res[:crypto]
        env = res[:environment]

        grade_color = case cert[:grade]
                      when 'A+', 'A' then Color.green("#{cert[:score]}/100 (Grade #{cert[:grade]} - #{cert[:status].to_s.upcase})")
                      when 'B', 'C'  then Color.yellow("#{cert[:score]}/100 (Grade #{cert[:grade]} - #{cert[:status].to_s.upcase})")
                      else Color.red("#{cert[:score]}/100 (Grade #{cert[:grade]} - #{cert[:status].to_s.upcase})")
                      end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🩺 GSC ZERO-DEPENDENCY ARCHITECTURE & SYSTEM CERTIFICATION")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        puts "  • Certification Score:   [ #{Color.bold(grade_color)} ]"
        puts "  • Runtime Environment:   #{Color.bold(res[:ruby_version])}"
        puts "  • Zero-Gem Compliance:   #{cert[:certified_zero_gem] ? Color.green("✅ 100% PURE RUBY STDLIB CERTIFIED") : Color.red("❌ DISALLOWED GEMS FOUND")}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        # 1. Codebase Purity Card
        puts "#{Color.bold("1. CODEBASE PURITY & DEPENDENCY AUDIT:")}"
        puts "  • Ruby Files Scanned:    #{Color.cyan(purity[:files_scanned].to_s)} files in lib/ and bin/"
        puts "  • Third-Party Gem Count: #{purity[:unapproved_requires].empty? ? Color.green("0 gems (100% Zero-Gem Purity)") : Color.red("#{purity[:unapproved_requires].size} external gems detected!")}"
        puts "  • Stdlib Packages Used:  #{purity[:stdlib_packages].join(', ')}"
        if purity[:optional_accelerators].any?
          puts "  • Optional Accelerators: #{Color.yellow(purity[:optional_accelerators].join(', '))} (Dynamic load with graceful fallback)"
        end
        if purity[:unapproved_requires].any?
          puts "  • #{Color.red("Disallowed Requires:")}"
          purity[:unapproved_requires].each do |gem_name, occurrences|
            occurrences.each do |occ|
              puts "    ✖ #{Color.red(gem_name)} in #{occ[:file]}:#{occ[:line]}"
            end
          end
        end

        # 2. Cold-Start Performance Card
        puts "\n#{Color.bold("2. COLD-START EXECUTION PERFORMANCE:")}"
        cold_badge = cold[:average_ms] < 50.0 ? Color.green("⚡ INSTANT (#{cold[:average_ms]}ms)") : Color.cyan("#{cold[:average_ms]}ms")
        puts "  • Cold-Start Latency:    [ #{Color.bold(cold_badge)} ] (Target: < #{cold[:target_ms]}ms)"
        puts "  • Bootstrap Benchmark:   Iterations: #{cold[:iterations]} | Samples: #{cold[:measurements_ms].join('ms, ')}ms"

        # 3. Cryptographic Suite Card
        puts "\n#{Color.bold("3. CRYPTOGRAPHIC & TLS 1.3 CAPABILITIES:")}"
        puts "  • OpenSSL Version:       #{crypto[:openssl_version]}"
        puts "  • AES-256-GCM Cipher:    #{crypto[:aes_gcm_available] ? Color.green("✅ Operational (Round-trip verified)") : Color.red("❌ Unavailable")}"
        puts "  • PBKDF2 Key Derivation: #{crypto[:pbkdf2_available] ? Color.green("✅ Operational (SHA256 PBKDF2)") : Color.red("❌ Unavailable")}"
        puts "  • TLS Handshake Context: #{crypto[:tls_context_ready] ? Color.green("✅ Operational (TLS 1.2 & 1.3)") : Color.red("❌ Unavailable")}"
        puts "  • System CA Cert Store:  #{crypto[:ca_cert_store_valid] ? Color.green("✅ Operational") : Color.yellow("⚠️ Default store notice")}"

        # 4. Security & Permissions Card
        puts "\n#{Color.bold("4. ENVIRONMENT & CREDENTIAL ISOLATION:")}"
        puts "  • Config Directory:      #{env[:config_dir]} (#{env[:config_dir_exists] ? Color.green("Found") : Color.yellow("Not yet created")})"
        puts "  • Directory Permissions: #{env[:permissions_secure] ? Color.green("✅ Secure (Strict POSIX 0700/0600)") : Color.yellow("⚠️ Loose permissions detected")}"
        if env[:permissions_fixed].any?
          puts "  • #{Color.green("Repaired Permissions:")}"
          env[:permissions_fixed].each do |fix|
            puts "    ✔ #{fix}"
          end
        end
        puts "  • GSC Credentials:       #{env[:credentials_configured] ? Color.green("✅ Configured") : Color.yellow("⚠️ Not configured (Run `gsc connect`)")}"
        if env[:active_domain]
          puts "  • Active Domain Link:    #{Color.cyan(env[:active_domain])}"
        end

        # 5. System Helpers Card
        puts "\n#{Color.bold("5. SYSTEM CLI HELPERS & IPC STATUS:")}"
        env[:system_helpers].each do |tool, info|
          status_str = info[:available] ? Color.green("✅ Available (#{info[:path]})") : Color.yellow("⚠️ Not in PATH (Optional)")
          puts "  • #{tool.ljust(11)}: #{status_str}"
        end

        # Remediations
        if res[:remediations].any?
          puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
          puts "#{Color.bold("RECOMMENDED REMEDIATIONS:")}"
          res[:remediations].each do |rem|
            puts "  👉 #{Color.yellow(rem)}"
          end
        end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        if cert[:score] >= 95.0
          puts "#{Color.green(Color.bold("✔ SYSTEM FULLY CERTIFIED: Zero dependencies, sub-100ms cold start, secure."))}"
        else
          puts "#{Color.yellow("Notice: Address non-optimal items above to reach 100/100 certification.")}"
        end
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end
    end
  end
end

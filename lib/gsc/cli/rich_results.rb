# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'cgi'
require 'uri'
require_relative 'base'
require_relative '../rich_results'
require_relative '../color'

module GSC
  class CLI
    module RichResults
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || (site_url ? site_url.sub(/^sc-domain:/, 'https://') : nil) || (extra && extra.first) || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        if target_url && target_url !~ %r{^https?://} && !File.exist?(target_url) && target_url =~ /\.[a-z]{2,}/i
          target_url = "https://#{target_url}"
        end

        unless target_url
          if File.exist?('public/index.html')
            target_url = 'public/index.html'
          elsif File.exist?('index.html')
            target_url = 'index.html'
          else
            if options[:json]
              puts JSON.pretty_generate({ error: 'Target URL or HTML file required. Example: gsc rich-results https://mysite.com' })
            else
              puts Color.c("❌ Error: Target URL or HTML file required.", Color::RED, Color::BOLD)
              puts "Example: gsc rich-results https://mysite.com"
              puts "         gsc rich-results ./index.html"
            end
            return
          end
        end

        rich_test_url = target_url =~ %r{^https?://} ? "https://search.google.com/test/rich-results?url=#{CGI.escape(target_url)}" : "https://search.google.com/test/rich-results"

        puts "🔍 Validating schema markup against Google Rich Results API rules for #{Color.cyan(target_url)}..." unless options[:json]

        res = GSC::RichResults.audit(target_url, options)

        if options[:json]
          res[:google_rich_results_test_url] = rich_test_url
          puts JSON.pretty_generate(res)
          return
        end

        render_terminal(res, options, rich_test_url)

        if options[:csv]
          export_csv(res, options[:csv])
        end
      end

      def render_terminal(res, options, rich_test_url = "https://search.google.com/test/rich-results")
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🌟 GOOGLE RICH RESULTS & SCHEMA VALIDATION SUITE")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        grade_color = case res[:grade]
                      when 'A+', 'A' then Color.green(res[:grade])
                      when 'B'      then Color.cyan(res[:grade])
                      when 'C'      then Color.yellow(res[:grade])
                      else Color.red(res[:grade])
                      end

        puts "  • Google Rich Results Eligibility: [ #{Color.bold(grade_color)} ] #{res[:score]}/100 Score"
        puts "  • Total Schemas Detected:          #{Color.bold(res[:total_schemas_detected].to_s)}"
        puts "  • Critical Google Violations:      #{res[:critical_errors_count] > 0 ? Color.red(res[:critical_errors_count].to_s) : Color.green("0")}"
        puts "  • Recommended Field Warnings:      #{res[:warnings_count] > 0 ? Color.yellow(res[:warnings_count].to_s) : Color.green("0")}"

        if res[:duplicate_types]&.any?
          puts "  • ⚠️ Duplicate Schemas Detected:    #{Color.yellow(res[:duplicate_types].join(', '))} (Consolidate into single tag)"
        end

        if res[:eligible_features].any?
          puts "  • Eligible SERP Enhancements:      #{Color.green(res[:eligible_features].join(', '))}"
        else
          puts "  • Eligible SERP Enhancements:      #{Color.red("None (Disqualified by critical schema errors)")}"
        end

        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if res[:schemas].empty?
          puts Color.yellow("  ⚠️ No JSON-LD structured data blocks detected on this page.")
          puts "  💡 Recommendation: Add Schema.org JSON-LD (Product, Article, FAQ, LocalBusiness) to capture Google Rich Snippets."
          puts "  Run `gsc schema-generate --type faq` to create valid JSON-LD markup."
          puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
          puts "#{Color.bold("🌐 OFFICIAL GOOGLE RICH RESULTS TEST TOOL:")}"
          puts "   #{Color.cyan(rich_test_url)}"
          if options[:open]
            puts Color.green("\n🚀 Opening Google Rich Results Test in your browser...")
            Base.open_in_browser(rich_test_url)
          else
            puts Color.gray("   💡 Pass '--open' (or '-o') to launch this test directly in your browser.")
          end
          puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
          return
        end

        puts "#{Color.bold("DETECTED SCHEMA STRUCTURE & GOOGLE COMPLIANCE:")}\n\n"
        printf " %-4s %-22s %-32s %s\n", "#", "Schema Type", "Google Rich Feature", "Status"
        puts " ---------------------------------------------------------------------------"

        res[:schemas].each do |s|
          status_str = if s[:eligible]
                         Color.green("✅ ELIGIBLE")
                       elsif s[:errors].any?
                         Color.red("❌ DISQUALIFIED")
                       else
                         Color.yellow("⚠️ WARNINGS")
                       end

          printf " %-4s %-22s %-32s %s\n", s[:index], s[:type], s[:feature][0..30], status_str

          s[:errors].each do |err|
            puts "      #{Color.red("❌ Critical Error:")} #{err}"
          end

          s[:warnings].each do |warn|
            puts "      #{Color.yellow("⚠️ Warning:")} #{warn}"
          end
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        # Show Patches if available
        patches = res[:schemas].map { |s| s[:patch] }.compact
        if patches.any?
          puts "#{Color.bold("1-CLICK GOOGLE-COMPLIANT JSON-LD FIX:")}\n"
          puts Color.cyan("<script type=\"application/ld+json\">")
          puts Color.cyan(JSON.pretty_generate(patches.size == 1 ? patches.first : { '@context' => 'https://schema.org', '@graph' => patches }))
          puts Color.cyan("</script>")
          puts
        end

        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
        puts "#{Color.bold("🌐 OFFICIAL GOOGLE RICH RESULTS TEST TOOL:")}"
        puts "   #{Color.cyan(rich_test_url)}"
        if options[:open]
          puts Color.green("\n🚀 Opening Google Rich Results Test in your browser...")
          Base.open_in_browser(rich_test_url)
        else
          puts Color.gray("   💡 Tip: Pass '--open' (or '-o') to launch this live test directly in your browser.")
        end

        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(res, file_path)
        headers = %w[Index SchemaType Feature Eligible ErrorsCount WarningsCount ErrorsList WarningsList]
        rows = res[:schemas].map do |s|
          [
            s[:index],
            s[:type],
            s[:feature],
            s[:eligible] ? 'YES' : 'NO',
            s[:errors].size,
            s[:warnings].size,
            s[:errors].join('; '),
            s[:warnings].join('; ')
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported Rich Results validation data to #{file_path}")
      end
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'cgi'
require 'uri'
require_relative 'base'
require_relative '../schema_generator'
require_relative '../color'

module GSC
  class CLI
    module SchemaGenerate
      module_function

      def run(command, target, extra, options)
        generator = GSC::SchemaGenerator.new(options)
        target_str = target.to_s.strip
        if target_str !~ %r{^https?://} && target_str =~ /\.[a-z]{2,}/i
          target_str = "https://#{target_str}"
        end

        result = if target_str =~ %r{^https?://}
                   generator.extract_from_url(target_str, options[:type])
                 elsif options[:type]
                   type = options[:type]
                   params = {
                     name: options[:name] || options[:headline] || target,
                     headline: options[:headline] || options[:name] || target,
                     price: options[:price],
                     currency: options[:currency] || 'USD',
                     brand: options[:brand_name] || (options[:brand].is_a?(String) ? options[:brand] : nil) || 'Brand',
                     rating: options[:rating],
                     reviews: options[:reviews],
                     author: options[:author],
                     q: options[:q],
                     a: options[:a],
                     url: options[:url] || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
                   }
                   generator.generate(type, params)
                 elsif target && !target.empty?
                   # Inferred from text target as an article headline
                   generator.generate('article', {
                     headline: target,
                     url: options[:url] || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
                   })
                 else
                   if options[:json]
                     puts JSON.pretty_generate({ error: 'Target URL or schema type required. Example: gsc schema-generate https://example.com/product' })
                   else
                     puts Color.c("❌ Error: Target URL or schema type required.", Color::RED, Color::BOLD)
                     puts "   Live Crawl Example:  gsc schema-generate https://example.com/product"
                     puts "   Type Direct Example: gsc schema-generate --type faq --q \"Question?\" --a \"Answer\""
                     puts "   Supported Types:     product, software, faq, howto, article, breadcrumb, course, job, event, localbusiness, video, recipe, organization"
                   end
                   return
                 end

        target_page_url = target_str =~ %r{^https?://} ? target_str : (options[:url] || (Config.default_domain ? "https://#{Config.default_domain}" : nil))
        rich_test_url = target_page_url ? "https://search.google.com/test/rich-results?url=#{CGI.escape(target_page_url)}" : "https://search.google.com/test/rich-results"

        if options[:json]
          result[:google_rich_results_test_url] = rich_test_url
          puts JSON.pretty_generate(result)
          return
        end

        render_schema_output(result, options, target_page_url, rich_test_url)
      end

      def render_schema_output(result, options, target_url, rich_test_url = "https://search.google.com/test/rich-results")
        schema = result[:schema]
        val = result[:validation]
        snippets = result[:snippets]

        puts "\n" + Color.cyan("╔" + "═" * 78 + "╗")
        puts Color.cyan("║") + Color.bold("   ✨ STRUCTURED DATA RICH SNIPPET GENERATOR".ljust(78)) + Color.cyan("║")
        puts Color.cyan("╚" + "═" * 78 + "╝")

        puts "\n" + Color.bold("🎯 GENERATION SUMMARY:")
        puts "   🌐 Source URL:  #{Color.cyan(target_url || 'User provided parameters')}"
        puts "   🏷️  Target Type: #{Color.yellow(schema['@type'].to_s)}"

        val_badge = if val[:valid]
                      Color.green("✓ VALID FOR GOOGLE RICH RESULTS (Score: #{val[:score]}/100)")
                    else
                      Color.red("✗ VALIDATION ERRORS DETECTED (Score: #{val[:score]}/100)")
                    end
        puts "   🛡️  Validation:  #{val_badge}"

        if val[:errors]&.any?
          puts Color.red("   ⚠️  Critical Google Violations: #{val[:errors].join(', ')}")
        end
        if val[:warnings]&.any?
          puts Color.yellow("   ℹ️  Recommended Enhancements: #{val[:warnings].join(', ')}")
        end

        # Duplicate & Existing Schema Analysis
        existing = result[:existing_analysis]
        if existing
          if existing[:duplicate_detected]
            puts "\n" + Color.c("⚠️  DUPLICATE PREVENTION ALERT:", Color::YELLOW, Color::BOLD)
            puts "   This page already contains a `<script type=\"application/ld+json\">` for " + Color.bold(existing[:matching_type].to_s) + "."
            puts "   " + Color.red("✗ Do NOT add this as a second duplicate tag.") + " Duplicate entity schemas confuse Googlebot and risk rich result disqualification."
            puts "   " + Color.green("✓ Recommended Action: Replace or update your existing #{existing[:matching_type]} schema with the snippet below.")
          elsif existing[:existing_count] > 0
            puts "\n" + Color.c("ℹ️  EXISTING STRUCTURED DATA DETECTED:", Color::CYAN, Color::BOLD)
            puts "   Page already has #{existing[:existing_count]} schema(s): " + Color.cyan(existing[:existing_types].join(', '))
            puts "   " + Color.green("✓ Adding #{schema['@type']} will complement your existing markup without conflict.")
          else
            puts "\n" + Color.c("✅ NO EXISTING SCHEMA DETECTED:", Color::GREEN, Color::BOLD)
            puts "   Page has no existing JSON-LD markup. Adding this snippet will establish rich snippet eligibility."
          end
        end

        # Code Snippets
        format_choice = (options[:format] || 'html').to_s.downcase

        puts "\n" + Color.bold("📋 1-CLICK COPY-PASTE SNIPPET (#{format_choice.upcase}):")
        case format_choice
        when 'nextjs', 'react'
          puts Color.cyan(snippets[:nextjs])
        when 'shopify', 'liquid'
          puts Color.cyan(snippets[:shopify])
        when 'raw', 'json'
          puts Color.dim(snippets[:raw_json])
        else
          puts Color.green(snippets[:html])
        end

        puts "\n" + Color.bold("💡 DEPLOYMENT GUIDANCE:")
        if existing&.dig(:duplicate_detected)
          puts Color.yellow("   ⚠️ REPLACE your existing #{existing[:matching_type]} <script> tag rather than adding a second one.")
        else
          puts Color.gray("   Paste this `<script>` directly into your page's `<head>` or body.")
        end
        puts Color.gray("   Test live in Google's Rich Results Tool: #{rich_test_url}")
        if options[:open]
          puts Color.green("   🚀 Opening Google Rich Results Test in your browser...")
          Base.open_in_browser(rich_test_url)
        else
          puts Color.gray("   Tip: Pass '--open' (or '-o') to launch this test directly in your browser.")
        end
        puts Color.gray("   Live GSC Verification: Run 'gsc inspect #{target_url || '<url>'}' for real Googlebot rich results crawl data.")
        puts Color.cyan("═" * 80) + "\n"
      end
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../hreflang_validator'
require_relative '../color'

module GSC
  class CLI
    module Hreflang
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || (hostname ? "https://#{hostname}" : nil)
        unless target_url
          if File.exist?('public/index.html')
            target_url = 'public/index.html'
          elsif File.exist?('index.html')
            target_url = 'index.html'
          else
            msg = "Please provide a target URL or HTML file: gsc hreflang-check <url|file>"
            if options[:json]
              puts JSON.pretty_generate({ error: msg })
            else
              puts Color.red("❌ Error: #{msg}")
            end
            return
          end
        end

        puts "🌐 Auditing international hreflang tags & bidirectional reciprocity for #{Color.cyan(target_url)}..." unless options[:json]

        res = GSC::HreflangValidator.audit(target_url, options)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        render_terminal(res)

        if options[:csv]
          export_csv(res, options[:csv])
        end
      end

      def render_terminal(res)
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🌐 INTERNATIONAL HREFLANG RECIPROCITY & ISO CODE AUDITOR")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        score = res[:health_score]
        grade_color = case res[:grade]
                      when 'A+', 'A' then Color.green(res[:grade])
                      when 'B' then Color.cyan(res[:grade])
                      when 'C' then Color.yellow(res[:grade])
                      else Color.red(res[:grade])
                      end

        puts "  • Hreflang Health Score:          [ #{Color.bold(grade_color)} ] #{Color.bold("#{score}/100")}"
        puts "  • Total Alternate Links Found:    #{Color.bold(res[:total_tags].to_s)} declarations"
        puts "  • Target URL / Source:            #{res[:url]}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        self_badge = res[:self_reference] ? Color.green("✅ Present") : Color.red("❌ Missing (Self-reference is required)")
        x_badge = res[:has_x_default] ? Color.green("✅ Present") : Color.yellow("⚠️ Missing (Recommended fallback)")

        puts "  Core International Specifications:"
        puts "   🔁 Self-Referencing Tag:         #{self_badge}"
        puts "   🌍 x-default Global Fallback:    #{x_badge}"
        puts "   ⇄ Confirmed Reciprocal Links:   #{Color.bold(res[:reciprocal_count].to_s)}"
        puts "   ⇥ Unreciprocated Return Links:   #{res[:unreciprocated_count] > 0 ? Color.red(res[:unreciprocated_count].to_s) : Color.green("0")}"
        puts "   ⚠️ Invalid Language/Region Codes: #{res[:invalid_code_count] > 0 ? Color.red(res[:invalid_code_count].to_s) : Color.green("0")}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if res[:tags].empty?
          puts Color.yellow("⚠️ No hreflang alternate tags discovered in target document or response headers.")
          puts "  Add <link rel=\"alternate\" hreflang=\"...\" href=\"...\" /> tags to designate localized variants.\n"
          return
        end

        puts "#{Color.bold("HREFLANG CLUSTER DECLARATIONS:")}\n\n"
        printf " %-12s %-40s %-16s %s\n", "Hreflang", "Destination URL", "Status", "Issues / Notes"
        puts " ---------------------------------------------------------------------------------------"

        res[:tags].each do |tag|
          dest = tag[:href].length > 38 ? "#{tag[:href][0..35]}..." : tag[:href]

          status_str = case tag[:status]
                       when :self_referential then Color.cyan("🔁 Self-Ref")
                       when :confirmed then Color.green("⇄ Confirmed")
                       when :missing_return then Color.red("⇥ No Return")
                       when :http_error then Color.red("❌ HTTP Error")
                       when :unreachable then Color.gray("⚠️ Unreachable")
                       else Color.gray("— Pending")
                       end

          issue_notes = if tag[:correction]
                          Color.yellow("Fix: #{tag[:correction]}")
                        elsif tag[:issues].empty?
                          Color.green("Valid Code")
                        else
                          tag[:issues].map { |i| format_issue(i) }.join(', ')
                        end

          printf " %-12s %-40s %-16s %s\n", tag[:hreflang], dest, status_str, issue_notes
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        if res[:prescriptions].any?
          puts "#{Color.bold("PRIORITIZED INTERNATIONAL SEO PRESCRIPTIONS:")}"
          res[:prescriptions].each_with_index do |p, idx|
            puts "  #{idx + 1}. 💡 #{p}"
          end
          puts
        end

        if res[:cluster_snippets][:html] && !res[:cluster_snippets][:html].empty?
          puts "#{Color.bold("1-CLICK STANDARDIZED HTML CLUSTER CODE:")}"
          puts "```html"
          puts res[:cluster_snippets][:html]
          puts "```\n"

          puts "#{Color.bold("1-CLICK GOOGLE XML SITEMAP <XHTML:LINK> CODE:")}"
          puts "```xml"
          puts res[:cluster_snippets][:sitemap_xml]
          puts "```\n"
        end

        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def format_issue(issue)
        case issue
        when :invalid_language then Color.red("Invalid Language")
        when :invalid_region then Color.red("Invalid Region")
        when :common_mistake then Color.yellow("Common Code Error")
        when :uppercase_language then Color.yellow("Uppercase Lang (Use Lowercase)")
        when :missing_reciprocal_tag then Color.red("Missing Return Tag")
        when :invalid_script then Color.red("Invalid Script")
        when :lowercase_region then Color.yellow("Lowercase Region (Use Uppercase)")
        else issue.to_s
        end
      end

      def export_csv(res, file_path)
        headers = %w[Hreflang Destination Status Source Issues]
        rows = res[:tags].map do |t|
          [
            t[:hreflang],
            t[:href],
            t[:status].to_s,
            t[:source].to_s,
            t[:issues].join('|')
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported hreflang audit to #{file_path}")
      end
    end
  end
end

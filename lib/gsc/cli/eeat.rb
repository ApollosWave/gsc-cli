# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../eeat_auditor'
require_relative '../color'

module GSC
  class CLI
    module Eeat
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || (hostname ? "https://#{hostname}" : nil)
        unless target_url
          if File.exist?('public/index.html')
            target_url = 'public/index.html'
          elsif File.exist?('index.html')
            target_url = 'index.html'
          else
            msg = "Please provide a target URL or HTML file: gsc eeat <url|file>"
            if options[:json]
              puts JSON.pretty_generate({ error: msg })
            else
              puts Color.red("❌ Error: #{msg}")
            end
            return
          end
        end

        puts "🧠 Auditing E-E-A-T author credentials & trust signals for #{Color.cyan(target_url)}..." unless options[:json]

        res = GSC::EeatAuditor.audit(target_url, options)

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
        puts "#{Color.bold("🧠 AUTHOR E-E-A-T & CREDENTIAL SIGNAL AUDITOR (Google Helpful Content)")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        score = res[:health_score]
        grade_color = case res[:grade]
                      when 'A+', 'A' then Color.green(res[:grade])
                      when 'B' then Color.cyan(res[:grade])
                      when 'C' then Color.yellow(res[:grade])
                      else Color.red(res[:grade])
                      end

        puts "  • E-E-A-T Trust Score:            [ #{Color.bold(grade_color)} ] #{Color.bold("#{score}/100")}"
        puts "  • Target URL / Source:            #{res[:url]}"
        puts "  • Author Name:                    #{res[:author_name] ? Color.bold(res[:author_name]) : Color.red("Not Detected")}"
        puts "  • Verified Credentials:           #{res[:credentials].any? ? Color.green(res[:credentials].join(', ')) : Color.yellow("None Detected")}"
        puts "  • Editorial Reviewer:             #{res[:reviewer_name] ? Color.green(res[:reviewer_name]) : Color.gray("None")}"
        puts "  • Publication / Modified Dates:   #{res[:date_published] || 'N/A'} / #{res[:date_modified] || 'N/A'}"
        puts "  • Authoritative Citations:        #{Color.bold(res[:citations_count].to_s)} (.gov, .edu, DOI, studies)"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        puts "  Audited Signal Components:"
        format_signal("Author Byline & Name", !res[:author_name].nil?)
        format_signal("Structured Schema (Person)", !res[:issues].include?(:missing_person_schema))
        format_signal("Professional Credentials", res[:credentials].any?)
        format_signal("Social Proof (LinkedIn/Wiki)", !res[:issues].include?(:missing_social_proof))
        format_signal("Editorial Review / Fact-Check", !res[:reviewer_name].nil?)
        format_signal("Freshness Timestamps", !res[:issues].include?(:missing_dates) && !res[:issues].include?(:missing_date_modified))
        format_signal("Authoritative Citations", res[:citations_count] > 0)
        format_signal("Editorial Transparency Policy", !res[:issues].include?(:missing_editorial_disclosure))
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if res[:prescriptions].any?
          puts "#{Color.bold("PRIORITIZED E-E-A-T RECOVERY PRESCRIPTIONS:")}"
          res[:prescriptions].each_with_index do |p, idx|
            puts "  #{idx + 1}. 💡 #{p}"
          end
          puts
        end

        if res[:schema_fix_snippet]
          puts "#{Color.bold("1-CLICK SCHEMA.ORG JSON-LD CREDENTIAL FIX:")}"
          puts "```json"
          puts res[:schema_fix_snippet]
          puts "```\n"
        end

        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def format_signal(label, status)
        badge = status ? Color.green("✅ VERIFIED") : Color.red("❌ MISSING ")
        printf "   %-32s %s\n", label, badge
      end

      def export_csv(res, file_path)
        headers = %w[URL Score Grade Author Credentials Reviewer Published Modified Citations Issues]
        rows = [
          [
            res[:url],
            res[:health_score],
            res[:grade],
            res[:author_name] || '',
            res[:credentials].join(';'),
            res[:reviewer_name] || '',
            res[:date_published] || '',
            res[:date_modified] || '',
            res[:citations_count],
            res[:issues].join('|')
          ]
        ]
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported E-E-A-T audit to #{file_path}")
      end
    end
  end
end

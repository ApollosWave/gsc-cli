# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../image_seo'
require_relative '../color'

module GSC
  class CLI
    module ImageSeo
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || (hostname ? "https://#{hostname}" : nil)
        unless target_url
          if File.exist?('public/index.html')
            target_url = 'public/index.html'
          elsif File.exist?('index.html')
            target_url = 'index.html'
          else
            msg = "Please provide a target URL or HTML file: gsc image-seo <url|file>"
            if options[:json]
              puts JSON.pretty_generate({ error: msg })
            else
              puts Color.red("❌ Error: #{msg}")
            end
            return
          end
        end

        puts "🖼️ Auditing image SEO, dimensions & next-gen formats for #{Color.cyan(target_url)}..." unless options[:json]

        res = GSC::ImageSeo.audit(target_url, options)

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
        puts "#{Color.bold("🖼️ IMAGE SEO & NEXT-GEN FORMAT AUDITOR (WebP • AVIF • CLS • Alt)")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        score = res[:health_score]
        grade_color = case res[:grade]
                      when 'A+', 'A' then Color.green(res[:grade])
                      when 'B' then Color.cyan(res[:grade])
                      when 'C' then Color.yellow(res[:grade])
                      else Color.red(res[:grade])
                      end

        puts "  • Image SEO Health Score:         [ #{Color.bold(grade_color)} ] #{Color.bold("#{score}/100")}"
        puts "  • Total Images Discovered:        #{Color.bold(res[:total_images].to_s)} images"
        puts "  • Target URL / Source:            #{res[:url]}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        m = res[:metrics]
        puts "  Image Compliance Dimensions:"
        puts "   🏷️  Alt Attribute Coverage:        #{Color.bold("#{m[:alt_coverage_pct]}%")}"
        puts "   📐 Explicit Width & Height (CLS): #{Color.bold("#{m[:dimension_coverage_pct]}%")}"
        puts "   ⚡ Next-Gen Formats (WebP/AVIF):  #{Color.bold("#{m[:modern_format_pct]}%")}"
        puts "   ⏳ Proper Lazy-Loading / LCP:     #{Color.bold("#{m[:lazy_loading_pct]}%")}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if res[:images].empty?
          puts Color.green("🎉 No image tags found on target page.")
          return
        end

        puts "#{Color.bold("IMAGE ASSET AUDIT BREAKDOWN (First #{res[:images].size} of #{res[:total_images]} images):")}\n\n"
        printf " %-4s %-32s %-8s %-12s %-10s %s\n", "#", "Source File", "Format", "Dimensions", "Alt Status", "Issues"
        puts " ---------------------------------------------------------------------------------------"

        res[:images].each do |img|
          filename = File.basename(img[:src].split('?').first)
          short_file = filename.length > 30 ? "#{filename[0..27]}..." : filename

          dim_str = (img[:width] && img[:height]) ? "#{img[:width]}x#{img[:height]}" : Color.red("MISSING")

          alt_status = if img[:alt].nil?
                         Color.red("MISSING")
                       elsif img[:alt].empty?
                         img[:is_decorative] ? Color.gray("DECORATIVE") : Color.yellow("EMPTY")
                       else
                         Color.green("OK")
                       end

          issues_summary = if img[:issues].empty?
                             Color.green("✅ Clean")
                           else
                             img[:issues].map { |i| format_issue(i) }.join(', ')
                           end

          printf " %-4s %-32s %-8s %-12s %-10s %s\n", img[:index], short_file, img[:format].upcase, dim_str, alt_status, issues_summary
        end

        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        if res[:prescriptions].any?
          puts "#{Color.bold("PRIORITIZED IMAGE SEO PRESCRIPTIONS:")}"
          res[:prescriptions].each_with_index do |p, idx|
            puts "  #{idx + 1}. 💡 #{p}"
          end
          puts
        end

        # Code Snippet Preview for the first flagged image
        sample_img = res[:images].find { |i| i[:issues].any? } || res[:images].first
        if sample_img
          puts "#{Color.bold("1-CLICK MODERN <PICTURE> CODE FIX (For #{File.basename(sample_img[:src])}):")}"
          puts "```html"
          puts sample_img[:picture_tag_snippet]
          puts "```\n"
        end

        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def format_issue(issue)
        case issue
        when :missing_alt then Color.red("Missing Alt")
        when :empty_alt then Color.yellow("Empty Alt")
        when :missing_dimensions then Color.red("No Width/Height (CLS)")
        when :legacy_format then Color.yellow("Legacy Format")
        when :lcp_lazy_loaded then Color.red("Hero Lazy Loaded (LCP Risk)")
        when :hero_missing_priority then Color.yellow("Hero Needs Priority")
        when :missing_lazy then Color.gray("Needs Lazy")
        when :oversized_payload then Color.red("Oversized >200KB")
        else issue.to_s
        end
      end

      def export_csv(res, file_path)
        headers = %w[Index Source Format Width Height Alt Loading Hero Issues]
        rows = res[:images].map do |img|
          [
            img[:index],
            img[:src],
            img[:format],
            img[:width] || '',
            img[:height] || '',
            img[:alt] || '',
            img[:loading] || '',
            img[:is_hero] ? 'YES' : 'NO',
            img[:issues].join('|')
          ]
        end
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Successfully exported image audit to #{file_path}")
      end
    end
  end
end

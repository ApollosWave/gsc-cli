# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../citation_simulator'
require_relative '../color'

module GSC
  class CLI
    module CitationSimulator
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_url = target || (hostname ? "https://#{hostname}" : nil)
        unless target_url
          msg = "Please provide a URL or HTML file: gsc cite-sim <url|file> [query]"
          if options[:json]
            puts JSON.pretty_generate({ error: msg })
          else
            puts Color.red("❌ Error: #{msg}")
          end
          return
        end

        # Resolve query from extra arguments or options
        query_str = if extra && !extra.to_s.strip.empty?
                      extra.is_a?(Array) ? extra.join(' ').strip : extra.to_s.strip
                    elsif options[:query]
                      options[:query].to_s.strip
                    elsif options[:keyword]
                      options[:keyword].to_s.strip
                    elsif api && site_url
                      fetch_top_gsc_query(api, site_url)
                    else
                      nil
                    end

        puts "🤖 Simulating AI search citation for #{Color.cyan(target_url)}..." unless options[:json]

        sim_opts = options.dup
        sim_opts[:model] = options[:model] if options[:model]

        res = GSC::CitationSimulator.simulate(target_url, query_str, sim_opts)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        render_terminal(res)

        if options[:csv]
          export_csv(res, options[:csv])
        end
      end

      def fetch_top_gsc_query(api, site_url)
        res = api.query_analytics(site_url, days: 30, dimensions: ['query'], row_limit: 1)
        if res[:ok] && res.dig(:data, 'rows')&.first
          res[:data]['rows'].first['keys'].first
        else
          nil
        end
      rescue StandardError
        nil
      end

      def render_terminal(res)
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🤖 AI SEARCH CITATION SIMULATOR (ChatGPT • Perplexity • Claude • AIO)")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        score = res[:citation_likelihood_score]
        grade_color = case res[:grade]
                      when 'A+', 'A' then Color.green(res[:grade])
                      when 'B' then Color.cyan(res[:grade])
                      when 'C' then Color.yellow(res[:grade])
                      else Color.red(res[:grade])
                      end

        status_color = score >= 70 ? Color.green(res[:status]) : (score >= 45 ? Color.yellow(res[:status]) : Color.red(res[:status]))

        puts "  • Citation Likelihood Score:      [ #{Color.bold(grade_color)} ] #{Color.bold("#{score}/100")} (#{status_color})"
        puts "  • Target Search Query:            #{Color.bold("\"#{res[:target_query]}\"")}"
        puts "  • Evaluated Model Profile:        #{Color.cyan(res[:model_profile].upcase)}"
        puts "  • Content Source:                 #{res[:url]}"
        if res[:http_status] && res[:http_status] >= 400
          puts Color.red("  ⚠️  HTTP STATUS #{res[:http_status]} (PAGE NOT FOUND / ERROR):")
          puts Color.yellow("     Target URL returned HTTP #{res[:http_status]}. The analysis below evaluated the server's 404 error page.")
        end
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"

        sig = res[:signals]
        puts "  Citability Signals Detected:"
        puts "   📊 Facts / Numerical Data:       #{Color.bold(sig[:facts_detected].to_s)} facts found in core passage"
        puts "   🏷️  Schema.org JSON-LD:            #{sig[:has_schema] ? Color.green("YES") : Color.yellow("MISSING")}"
        puts "   ✍️  Author E-E-A-T Byline:        #{sig[:has_author] ? Color.green("YES") : Color.yellow("MISSING")}"
        puts "   📅 Verified Published Date:       #{sig[:has_published_date] ? Color.green("YES") : Color.yellow("MISSING")}"
        puts "   📑 Comparative Data Table:        #{sig[:has_comparative_table] ? Color.green("YES") : Color.gray("NO")}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        puts "#{Color.bold("EMULATED AI SEARCH SYNTHESIZED RESPONSE:")}"
        puts "┌──────────────────────────────────────────────────────────────────────────┐"
        res[:emulated_ai_response].each_line do |line|
          puts "│ #{line.strip.ljust(72)} │"
        end
        puts "└──────────────────────────────────────────────────────────────────────────┘\n"

        if res[:extracted_quotes].any?
          puts "#{Color.bold("EXTRACTED VERIFIABLE CITATION QUOTES:")}"
          res[:extracted_quotes].each_with_index do |q, idx|
            puts "  [#{idx + 1}] #{Color.green("\"#{q}\"")}"
          end
          puts
        end

        top_c = res[:top_cited_chunk]
        puts "#{Color.bold("TOP CITED CONTENT CHUNK (Section: \"#{top_c[:heading]}\"):")}"
        puts "  • Word Count: #{top_c[:word_count]} words | Fact Density: #{top_c[:fact_density]}% | Relevance: #{top_c[:relevance_score]}/100"
        short_text = top_c[:text].length > 180 ? "#{top_c[:text][0..177]}..." : top_c[:text]
        puts "  • Preview: #{Color.gray(short_text)}\n\n"

        puts "#{Color.bold("ACTIONABLE INFORMATION-GAIN PRESCRIPTIONS (TO REACH 100/100):")}"
        res[:prescriptions].each_with_index do |p, idx|
          puts "  #{idx + 1}. 💡 #{p}"
        end

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(res, file_path)
        headers = %w[URL Query Model CLS Grade Status FactsCount Quotes Prescriptions]
        rows = [
          [
            res[:url],
            res[:target_query],
            res[:model_profile],
            res[:citation_likelihood_score],
            res[:grade],
            res[:status],
            res.dig(:signals, :facts_detected),
            res[:extracted_quotes].join(' | '),
            res[:prescriptions].join(' | ')
          ]
        ]
        Base.write_csv(file_path, headers, rows)
        puts Color.cyan("📁 Exported citation simulation to #{file_path}")
      end
    end
  end
end

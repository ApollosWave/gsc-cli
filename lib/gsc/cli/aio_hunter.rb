# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../aio_hunter'
require_relative '../color'

module GSC
  class CLI
    module AioHunter
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        query_or_domain = target || (extra && extra.first)

        puts "🔍 Hunting Google AI Overview (AIO) opportunities and citation sources..." unless options[:json]

        res = GSC::AioHunter.analyze(query_or_domain, options, api, site_url)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        if options[:csv]
          export_csv(res)
          return
        end

        if res[:mode] == :query
          render_query_terminal(res)
        else
          render_portfolio_terminal(res)
        end
      end

      def render_query_terminal(res)
        q = res[:query]
        aio = res[:aio_presence]
        cit = res[:citation_analysis]
        rec = res[:capture_recipe]

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🤖 GOOGLE AI OVERVIEW (AIO) OPPORTUNITY & CITATION HUNTER")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        puts "  • Search Query:          #{Color.bold(Color.cyan("\"#{q}\""))}"
        puts "  • Evaluated Domain:      #{Color.bold(res[:target_domain])}" if res[:target_domain]
        puts "  • Query Intent:          #{Color.bold(res[:intent].to_s.upcase.tr('_', ' '))}"

        prob_color = aio[:probability_percent] >= 75 ? Color.red("#{aio[:probability_percent]}% - #{aio[:status]}") : Color.yellow("#{aio[:probability_percent]}% - #{aio[:status]}")
        puts "  • AIO SERP Probability:  [ #{Color.bold(prob_color)} ]"
        puts "  • Organic CTR Drag:      #{Color.red("-#{aio[:ctr_suppression_estimate]} suppression")} of blue links"

        if cit[:domain_evaluated]
          cited_str = cit[:top_3_prime_candidate] ? Color.green("✅ PRIME CITATION CANDIDATE (Ranks Pos #{cit[:ranking_position]})") : Color.yellow("⚠️ #{cit[:eligibility_status]} (Citation Gap: #{cit[:citation_gap_index]}%)")
        else
          cited_str = Color.yellow("ℹ️ Unspecified Domain (Pass --domain <domain> to evaluate GSC rank)")
        end
        puts "  • Domain Citation State: #{Color.bold(cited_str)}"
        puts "  • AIO Opportunity Score: #{Color.bold(Color.green("#{res[:opportunity_score]} / 100"))}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        # Citation Criteria
        puts "#{Color.bold("GOOGLE GEMINI AIO CITATION & GROUNDING CRITERIA:")}"
        puts "  • Grounding Model:       Google Gemini prioritizes citations from Top 3 organic ranking URLs"
        puts "  • Direct Answer Match:   Requires 35–50 word direct definition answering \"#{q}\""
        puts "  • Structured Schema:     #{Color.yellow(rec[:recommended_schema])}"
        puts "  • Required Structure:    #{rec[:content_elements].first}"

        # Capture Playbook
        puts "\n#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
        puts "#{Color.bold("ACTIONABLE AIO CITATION CAPTURE PLAYBOOK:")}"
        puts "  • Strategy:            #{Color.bold(rec[:strategy])}"
        puts "  • Recommended Heading: #{Color.cyan(rec[:recommended_heading])}"
        puts "  • Recommended Schema:  #{Color.yellow(rec[:recommended_schema])}"
        puts "  • Required Elements:   #{rec[:content_elements].join(' | ')}"
        puts "\n  #{Color.bold("Ready-to-Paste Direct Answer Snippet:")}"
        puts Color.green("  \"#{rec[:direct_answer_draft]}\"")
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def render_portfolio_terminal(res)
        sum = res[:summary]

        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🤖 GOOGLE AI OVERVIEW (AIO) PORTFOLIO RADAR: #{res[:domain].upcase}")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        puts "  • Total Queries Audited:    #{Color.bold(res[:total_queries_audited].to_s)} keywords"
        puts "  • AIO SERP Penetration:     #{Color.bold(Color.yellow("#{sum[:aio_penetration_rate]}%"))} (#{sum[:aio_triggering_queries]} queries triggering AIO)"
        puts "  • Top 3 Prime Candidates:   #{Color.bold(Color.green(sum[:currently_cited_count].to_s))}"
        puts "  • High-Threat Uncited:      #{Color.bold(Color.red("#{sum[:high_threat_uncited_count]} keywords"))} (Click hemorrhaging to AIO)"
        puts "  • AIO Vulnerability Index:  #{Color.bold(Color.red("#{sum[:portfolio_aio_vulnerability_index]}%"))}"
        if res[:opportunities].empty?
          puts "  ℹ️  No Search Console query data found for #{res[:domain]}."
          puts "     Connect Google Search Console credentials via `gsc setup` to audit your portfolio,"
          puts "     or analyze a specific keyword with `gsc aio \"<query>\"`."
          puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
          return
        end

        puts format("%-32s | %-6s | %-6s | %-8s | %-7s | %-8s | %-24s",
                    "Query", "Imp", "Pos", "AIO Prob", "Top 3?", "Opp Score", "Recommended Fix")
        puts "#{Color.bold("─" * 105)}"

        res[:opportunities].each do |item|
          q_trunc = item[:query].length > 30 ? "#{item[:query][0..27]}..." : item[:query]
          prob_s = "#{item[:aio_probability]}%"
          cited_s = item[:top_3_prime] ? Color.green("YES") : Color.gray("NO")
          opp_s = "#{item[:opportunity_score]}/100"

          puts format("%-32s | %-6d | %-6.1f | %-8s | %-16s | %-9s | %-24s",
                      q_trunc, item[:impressions], item[:position], prob_s, cited_s, opp_s, item[:recipe_summary])
        end

        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end

      def export_csv(res)
        require 'csv'

        if res[:mode] == :query
          puts "query,intent,aio_probability,domain_cited,opportunity_score,strategy"
          puts [
            res[:query],
            res[:intent],
            res[:aio_presence][:probability_percent],
            res[:citation_analysis][:domain_cited],
            res[:opportunity_score],
            res[:capture_recipe][:strategy]
          ].to_csv
        else
          puts "query,impressions,clicks,position,ctr,intent,aio_probability,domain_cited,opportunity_score,recipe"
          res[:opportunities].each do |item|
            puts [
              item[:query],
              item[:impressions],
              item[:clicks],
              item[:position],
              item[:ctr],
              item[:intent],
              item[:aio_probability],
              item[:domain_cited],
              item[:opportunity_score],
              item[:recipe_summary]
            ].to_csv
          end
        end
      end
    end
  end
end

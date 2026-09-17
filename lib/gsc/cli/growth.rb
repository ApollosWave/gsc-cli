# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../striking_playbook' if File.exist?(File.expand_path('../striking_playbook.rb', __dir__))
require_relative '../answer_synthesizer' if File.exist?(File.expand_path('../answer_synthesizer.rb', __dir__))
require_relative '../serp_feature_detector' if File.exist?(File.expand_path('../serp_feature_detector.rb', __dir__))
require_relative '../serp_preview' if File.exist?(File.expand_path('../serp_preview.rb', __dir__))
require_relative '../cannibalization_analyzer' if File.exist?(File.expand_path('../cannibalization_analyzer.rb', __dir__))
require_relative '../questions_harvester' if File.exist?(File.expand_path('../questions_harvester.rb', __dir__))
require_relative '../sitemap_loader' if File.exist?(File.expand_path('../sitemap_loader.rb', __dir__))
require_relative 'low_ctr' if File.exist?(File.expand_path('low_ctr.rb', __dir__))

module GSC
  class CLI
    module Growth
      module_function

      def run(command, target, extra, options, api, site_url, hostname, https_origin)
        case command
        when 'strike', 'striker', 'striking-playbook'
          handle_strike(api, site_url, options)
        when 'answer', 'direct-answer', 'aeo-snippet', 'info-gain', 'ans'
          handle_answer(target, options)
        when 'serp-features', 'sf', 'serp-live', 'features'
          handle_serp_features(target, options)
        when 'preview', 'serp', 'serp-preview', 'social-preview'
          handle_preview(target, options)
        when 'opportunities', 'striking-distance', 'quick-wins', 'o', 'opp'
          handle_opportunities(api, site_url, options)
        when 'underperformers', 'ctr-underperformers', 'ctr-gaps', 'u'
          handle_underperformers(api, site_url, options)
        when 'low-ctr', 'ctr-rewrite', 'lost-clicks', 'rewrite-titles', 'ctr-fix', 'lowctr', 'lc'
          LowCtr.run(command, target, extra, options, api, site_url, hostname)
        when 'cannibalization', 'conflicts', 'c'
          handle_cannibalization(api, site_url, options)
        when 'questions-harvest', 'harvest-questions', 'qh', 'faq-harvest'
          handle_questions_harvest(target, api, site_url, options)
        when 'zombies', 'bloat', 'z'
          handle_zombies(target, api, site_url, https_origin, options)
        else
          raise "Unknown growth command: #{command}"
        end
      end

      def handle_strike(api, site_url, options)
        puts Base::BANNER unless options[:json] || options[:in_dashboard]
        puts "🎯 Generating Striking-Distance Playbook for: #{Color.c(site_url, Color::CYAN)}...\n" unless options[:json]

        data = StrikingPlaybook.generate(api, site_url, options)

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        if data[:playbooks].empty?
          puts Color.c("ℹ️ No striking-distance opportunities found (Pos #{data[:filters][:min_pos]}–#{data[:filters][:max_pos]}, Min #{data[:filters][:min_imp]} imp).", Color::YELLOW)
          puts "💡 Tip: Lower --min-imp (e.g. gsc strike --min-imp 5) or increase --days 90."
          return
        end

        puts "╔══════════════════════════════════════════════════════════════════════════════╗"
        puts "║           🚀 STRIKING-DISTANCE PLAYBOOK (POSITIONS 7–20 TO TOP 3)            ║"
        puts "╚══════════════════════════════════════════════════════════════════════════════╝"
        puts "📍 Property:          #{Color.c(data[:site_url], Color::CYAN, Color::BOLD)}"
        puts "📈 Projected Gain:    #{Color.c("+#{data[:projected_monthly_clicks]} clicks/mo", Color::GREEN, Color::BOLD)} (Across top #{data[:playbooks].size} targets)"
        puts "🔍 Opportunities:     #{data[:total_opportunities_found]} keywords detected in striking range"
        puts "─" * 80

        data[:playbooks].each_with_index do |p, idx|
          tier_badge = case p[:tier]
                       when :tier_1_expedite
                         Color.c("⚡ [TIER 1: EXPEDITE - BRINK OF TOP 5]", Color::GREEN, Color::BOLD)
                       when :tier_2_strike
                         Color.c("🎯 [TIER 2: HIGH LEVERAGE STRIKE]", Color::CYAN, Color::BOLD)
                       else
                         Color.c("🧗 [TIER 3: FOUNDATION CLIMB]", Color::YELLOW)
                       end

          page_short = p[:page].sub(%r{^https?://[^/]+}, '')
          page_short = '/' if page_short.empty?

          puts "\n#{Color::BOLD}#{idx + 1}. KEYWORD: #{Color.c("\"#{p[:query]}\"", Color::YELLOW, Color::BOLD)} #{tier_badge}#{Color::RESET}"
          puts "   Target Page:       #{Color.c(page_short, Color::CYAN)} (#{p[:page]})"
          puts "   Current Metrics:   Pos #{Color.c(p[:position].to_s, Color::YELLOW, Color::BOLD)} | #{p[:impressions]} imp | #{p[:clicks]} clicks (#{p[:ctr]}% CTR)"
          puts "   Projected Surge:   #{Color.c("+#{p[:projected_gain]} clicks/month", Color::GREEN, Color::BOLD)} upon ranking Top 3"

          puts "\n   #{Color::BOLD}🏷️  Title Tag Rewrites (Pick one):#{Color::RESET}"
          p[:title_rewrites].each do |t|
            puts "      • #{Color.c(t, Color::BOLD)} (#{t.length} chars)"
          end

          puts "\n   #{Color::BOLD}🌲 Heading Injection Recipe:#{Color::RESET}"
          puts "      H2: #{Color.c(p[:heading_recipes][:h2], Color::MAGENTA)}"
          p[:heading_recipes][:h3s].each do |h3|
            puts "      └── H3: #{h3}"
          end

          puts "\n   #{Color::BOLD}🔗 Internal Link Anchors (Deploy 3 links across site):#{Color::RESET}"
          puts "      • Exact Match:   \"#{Color.c(p[:internal_link_anchors][:exact], Color::CYAN)}\""
          puts "      • Partial Match: \"#{p[:internal_link_anchors][:partial]}\""
          puts "      • Branded:       \"#{p[:internal_link_anchors][:branded]}\""

          puts "\n   #{Color::BOLD}❓ High-Information Gain FAQ Snippet (Paste into page):#{Color::RESET}"
          puts "      Q: #{Color.c(p[:faq_snippet][:question], Color::BOLD)}"
          puts "      A: #{p[:faq_snippet][:answer]}"

          puts "\n   #{Color::BOLD}📋 Action Checklist:#{Color::RESET}"
          p[:action_checklist].each do |task|
            puts "      [ ] #{task}"
          end
          puts "\n" + ("─" * 80)
        end

        if options[:csv]
          csv_data = data[:playbooks].map do |p|
            [p[:query], p[:page], p[:position], p[:impressions], p[:clicks], p[:ctr], p[:projected_gain], p[:tier], p[:title_rewrites].first]
          end
          Base.write_csv(options[:csv], %w[Query Page Position Impressions Clicks CTR ProjectedGain Tier RecommendedTitle], csv_data)
          puts Color.c("📁 Exported striking playbook to #{options[:csv]}", Color::CYAN)
        end
      end

      def handle_answer(query, options = {})
        if query.nil? || query.to_s.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Query required. Usage: gsc answer <query> [--brand <name>] [--type <definition|steps|comparison|faq>] [--generate] [--json]' })
          else
            puts Color.c("❌ Error: Query required. Usage: gsc answer <query> [--brand <name>] [--type <definition|steps|comparison|faq>] [--generate] [--json]", Color::RED, Color::BOLD)
          end
          return
        end

        data = GSC::AnswerSynthesizer.synthesize(query, options)

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "🗣️  #{Color::BOLD}DIRECT ANSWER & INFORMATION GAIN SNIPPET (GEO / AEO)#{Color::RESET}"
        puts "🎯 Target Query  : #{Color.c("\"#{data[:query]}\"", Color::YELLOW, Color::BOLD)}"
        puts "🏷️  Intent Type   : [#{Color.c(data[:intent_type].upcase, Color::MAGENTA, Color::BOLD)}]"
        puts "📊 Word Count    : #{data[:word_count]} words (#{Color.c("Optimal: #{data[:target_optimal_range]}", Color::GREEN)})"
        puts "🏆 Citability    : #{Color.c("#{data[:citability_score]}/100", Color::GREEN, Color::BOLD)} (Optimized for Featured Snippets, ChatGPT & Perplexity)"
        puts "─" * 75

        puts "\n#{Color::BOLD}💬 OPTIMIZED DIRECT ANSWER PARAGRAPH:#{Color::RESET}"
        puts "   #{Color.c(data[:direct_answer], Color::BOLD)}"

        puts "\n#{Color::BOLD}📌 STRUCTURED ATTRIBUTES & KEY POINTS:#{Color::RESET}"
        data[:key_points].each do |kp|
          clean_kp = kp.gsub(/\*\*(.*?)\*\*/, "#{Color::BOLD}\\1#{Color::RESET}")
          puts "   • #{clean_kp}"
        end

        puts "\n#{Color::BOLD}📈 INFORMATION GAIN FACTOID:#{Color::RESET}"
        puts "   💡 #{Color.c(data[:information_gain_stat], Color::CYAN)}"

        if options[:generate]
          puts "\n#{Color::BOLD}💻 READY-TO-PASTE HTML SNIPPET:#{Color::RESET}"
          puts Color.c(data[:html_markup], Color::DIM)

          puts "\n#{Color::BOLD}💎 SCHEMA.ORG JSON-LD SCRIPT BLOCK:#{Color::RESET}"
          puts Color.c("<script type=\"application/ld+json\">\n#{JSON.pretty_generate(data[:schema_jsonld])}\n</script>", Color::CYAN)
        else
          puts "\n💡 #{Color.c('Tip: Pass --generate to print copy-paste HTML and Schema.org JSON-LD blocks.', Color::GRAY)}"
        end
        puts "─" * 75 + "\n"
      end

      def handle_serp_features(query, options)
        query_str = query.to_s.sub(/^(query|live):/, '').strip
        if query_str.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Search query required. Example: gsc serp-features "how to speed up rails"' })
          else
            puts Color.c("❌ Error: Search query required. Example: gsc serp-features \"how to speed up rails\"", Color::RED, Color::BOLD)
          end
          return
        end

        detector = GSC::SerpFeatureDetector.new(query_str, options)
        data = detector.detect

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "🔍 #{Color::BOLD}LIVE SERP FEATURE & ZERO-CLICK THREAT DETECTOR:#{Color::RESET} #{Color.c(query_str, Color::CYAN, Color::BOLD)}"
        puts "─" * 80

        zt = data[:zero_click_threat] || {}
        threat_color = case zt[:level]
                       when 'LOW'      then Color::GREEN
                       when 'MODERATE' then Color::YELLOW
                       else                 Color::RED
                       end

        puts "🎯 Search Intent:     #{Color.c(data.dig(:intent, :primary).to_s, Color::BOLD)} (#{data.dig(:intent, :description)})"
        puts "🚨 Zero-Click Threat: #{Color.c("#{zt[:level]} (#{zt[:score]}/100)", threat_color, Color::BOLD)} [Organic CTR Impact: #{zt[:estimated_organic_ctr_suppression]}]"
        puts "─" * 80

        f = data[:features] || {}
        puts "\n#{Color::BOLD}📊 DETECTED SERP REAL ESTATE FEATURES:#{Color::RESET}"

        aio = f[:ai_overview] || {}
        aio_badge = aio[:detected] ? Color.c("ACTIVE (#{aio[:probability_pct]}% prob)", Color::RED, Color::BOLD) : Color.c("Unlikely (#{aio[:probability_pct]}%)", Color::GRAY)
        puts "   • Google AI Overview (Gemini) : [#{aio_badge}]"
        puts "     └─ #{Color.c(aio[:impact], Color::DIM)}" if aio[:detected]

        fs = f[:featured_snippet] || {}
        fs_badge = fs[:detected] ? Color.c("OPPORTUNITY (#{fs[:target_format].capitalize} - #{fs[:probability_pct]}%)", Color::GREEN, Color::BOLD) : Color.c("None", Color::GRAY)
        puts "   • Featured Snippet Box        : [#{fs_badge}]"
        puts "     └─ Target Recipe: #{Color.c(fs[:capture_prescription], Color::CYAN)}" if fs[:detected]

        paa = f[:people_also_ask] || {}
        paa_badge = paa[:detected] ? Color.c("#{paa[:count]} Live Questions Extracted", Color::CYAN, Color::BOLD) : Color.c("None", Color::GRAY)
        puts "   • People Also Ask (PAA)       : [#{paa_badge}]"
        if paa[:detected] && (paa[:questions] || []).any?
          paa[:questions].first(5).each do |q_text|
            puts "     ❓ \"#{Color.c(q_text, Color::YELLOW)}\""
          end
        end

        lp = f[:local_3_pack] || {}
        lp_badge = lp[:detected] ? Color.c("DETECTED (Google Maps 3-Pack)", Color::YELLOW, Color::BOLD) : Color.c("None", Color::GRAY)
        puts "   • Local Maps 3-Pack           : [#{lp_badge}]"

        vc = f[:video_carousel] || {}
        vc_badge = vc[:detected] ? Color.c("DETECTED (Video Carousel)", Color::YELLOW, Color::BOLD) : Color.c("None", Color::GRAY)
        puts "   • Video Carousel / YouTube    : [#{vc_badge}]"

        df = f[:discussions_and_forums] || {}
        df_badge = df[:detected] ? Color.c("DETECTED (Reddit/Quora Modules)", Color::CYAN, Color::BOLD) : Color.c("None", Color::GRAY)
        puts "   • Discussions & Forums        : [#{df_badge}]"

        sp = f[:shopping_pack] || {}
        sp_badge = sp[:detected] ? Color.c("DETECTED (Shopping Product Grid)", Color::YELLOW, Color::BOLD) : Color.c("None", Color::GRAY)
        puts "   • Google Shopping Grid        : [#{sp_badge}]"

        playbook = data[:playbook] || []
        if playbook.any?
          puts "\n#{Color::BOLD}🏆 RICH SNIPPET & CITATION CAPTURE PLAYBOOK:#{Color::RESET}"
          playbook.each_with_index do |p, idx|
            puts "   #{idx + 1}. [#{Color.c(p[:priority], Color::BOLD)}] #{Color.c(p[:target], Color::CYAN)}:"
            puts "      👉 #{p[:action]}"
          end
        end

        serp = data[:serp_sampling] || []
        if serp.any?
          puts "\n#{Color::BOLD}🌐 LIVE SERP SAMPLING (Top Competitor Results):#{Color::RESET}"
          serp.each do |r|
            puts "   #{r[:position]}. #{Color.c(r[:title], Color::BOLD)} [#{Color.c(r[:domain], Color::GRAY)}]"
            puts "      └─ #{Color.c(r[:url], Color::BLUE)}"
          end
        end

        puts "\n" + ("─" * 80) + "\n"
      end

      def handle_preview(target, options)
        is_url = target.to_s.start_with?('http://', 'https://')
        has_title_or_url = is_url || options[:url] || options[:title] || options[:desc] || options[:description] || options[:preview] || (target.to_s =~ /[:|—]/)

        if options[:live] || options[:features] || (!has_title_or_url && !target.to_s.empty?)
          return handle_serp_features(target, options)
        end

        url = options[:url] || (target if is_url)
        title = options[:title] || (target unless is_url)
        desc = options[:desc] || options[:description]
        url ||= "https://#{Config.default_domain}" if Config.default_domain

        if (url.nil? || url.empty?) && (title.nil? || title.to_s.strip.empty?)
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or custom title required. Example: gsc serp-preview https://mysite.com/page' })
          else
            puts Color.c("❌ Error: Target URL or custom title required.", Color::RED, Color::BOLD)
            puts "Example: gsc serp-preview https://mysite.com/page"
            puts "         gsc serp-preview --title \"Page Title\" --desc \"Meta description\""
          end
          return
        end

        sp = GSC::SerpPreview.new(url, title: title, desc: desc)
        data = sp.generate

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        m = data[:metrics] || {}

        puts "🖥️ #{Color::BOLD}GOOGLE SERP PREVIEW (Desktop Viewport):#{Color::RESET}"
        puts "┌─────────────────────────────────────────────────────────────────────────┐"
        puts "│ #{Color.c(data.dig(:desktop_serp, :breadcrumb).to_s.ljust(71), Color::DIM)}│"
        puts "│ #{Color.c(data.dig(:desktop_serp, :title).to_s.ljust(71), Color::BLUE, Color::BOLD)}│"
        puts "│ #{Color.c(data.dig(:desktop_serp, :snippet).to_s[0..70].ljust(71), Color::DIM)}│"
        puts "└─────────────────────────────────────────────────────────────────────────┘"

        t_status = if m[:title_truncated]
                     Color.c("⚠️ TRUNCATED (+#{(m[:title_pixel_est] - m[:title_desktop_limit]).round(1)}px over 580px limit)", Color::YELLOW, Color::BOLD)
                   else
                     Color.c('✅ OPTIMAL (< 580px desktop limit)', Color::GREEN, Color::BOLD)
                   end

        d_status = if m[:desc_truncated]
                     Color.c("⚠️ TRUNCATED (+#{(m[:desc_pixel_est] - m[:desc_desktop_limit]).round(1)}px over 960px limit)", Color::YELLOW, Color::BOLD)
                   else
                     Color.c('✅ OPTIMAL (< 960px desktop limit)', Color::GREEN, Color::BOLD)
                   end

        puts "   • Title Width:       #{m[:title_chars]} chars / ~#{m[:title_pixel_est]}px  [#{t_status}]"
        puts "   • Description Width: #{m[:desc_chars]} chars / ~#{m[:desc_pixel_est]}px  [#{d_status}]"

        puts "\n📱 #{Color::BOLD}GOOGLE SERP PREVIEW (Mobile Viewport):#{Color::RESET}"
        puts "┌─────────────────────────────────────────────────────────────────────────┐"
        puts "│ #{Color.c(data.dig(:mobile_serp, :breadcrumb).to_s.ljust(71), Color::DIM)}│"
        puts "│ #{Color.c(data.dig(:mobile_serp, :title).to_s.ljust(71), Color::BLUE, Color::BOLD)}│"
        puts "│ #{Color.c(data.dig(:mobile_serp, :snippet).to_s[0..70].ljust(71), Color::DIM)}│"
        puts "└─────────────────────────────────────────────────────────────────────────┘"

        soc = data[:social] || {}
        if soc[:og_title] || soc[:og_image]
          puts "\n🌐 #{Color::BOLD}OPEN GRAPH / SOCIAL CARD PREVIEW:#{Color::RESET}"
          puts "   • Title       : #{soc[:og_title]}"
          puts "   • Description : #{soc[:og_description]}"
          puts "   • Card Image  : #{soc[:og_image] || '(No og:image specified)'}"
        end
        puts ""
      end

      def handle_opportunities(api, site_url, options)
        min_pos = options[:min_pos] || 7.0
        max_pos = options[:max_pos] || 20.0
        min_imp = options[:min_imp] || 10
        puts "🎯 Finding striking-distance keyword opportunities for #{Color.c(site_url, Color::CYAN)} (Positions #{min_pos}–#{max_pos}, Min #{min_imp} Imp)...\n" unless options[:json]

        res = api.query_analytics(site_url, days: options[:days], dimensions: %w[query page], row_limit: 2500)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          opportunities = []

          raw_rows.each do |r|
            q = r['keys'][0]
            p = r['keys'][1]
            pos = r['position'].round(1)
            imp = r['impressions']
            clicks = r['clicks']
            ctr = (r['ctr'] * 100).round(2)

            next unless pos >= min_pos && pos <= max_pos
            next unless imp >= min_imp

            target_ctr = 12.0
            potential_clicks = [((imp * (target_ctr / 100.0)) - clicks).round, 1].max
            score = (potential_clicks * (1.0 / [pos - 2.0, 1.0].max) * 10.0).round(1)

            opportunities << {
              query: q,
              page: p,
              position: pos,
              impressions: imp,
              clicks: clicks,
              ctr: ctr,
              potentialGain: potential_clicks,
              opportunityScore: score
            }
          end

          opportunities.sort_by! { |o| -o[:opportunityScore] }
          opportunities = opportunities.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(opportunities)
          elsif opportunities.empty?
            puts Color.c("ℹ️ No striking-distance opportunities found with current filters (Min #{min_imp} imp, Pos #{min_pos}–#{max_pos}).", Color::YELLOW)
            puts "💡 Tip: Try lowering --min-imp (e.g. gsc opportunities --min-imp 3) or increasing --days 90."
          else
            puts "#{Color::BOLD}Pos   | Imp    | Clicks | Est. +Clicks | Target Page & Query#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            opportunities.each do |opp|
              pos_str    = opp[:position].to_s.ljust(5)
              imp_str    = opp[:impressions].to_s.ljust(6)
              clicks_str = opp[:clicks].to_s.ljust(6)
              gain_str   = "+#{opp[:potentialGain]}/mo".ljust(12)
              page_short = opp[:page].sub(%r{^https?://[^/]+}, '')
              page_short = '/' if page_short.empty?

              puts "#{Color.c(pos_str, Color::YELLOW)} | #{imp_str} | #{clicks_str} | #{Color.c(gain_str, Color::GREEN, Color::BOLD)} | #{Color.c(page_short, Color::CYAN)}"
              puts "      |        |        |              | ↳ #{Color::BOLD}\"#{opp[:query]}\"#{Color::RESET}"
            end
            puts "\n#{Color.c("Total Opportunities: #{opportunities.size}", Color::GRAY)}"
            puts "💡 #{Color::BOLD}Optimization Playbook:#{Color::RESET} Add an H2 subheading and 1-2 paragraphs directly targeting these queries on their respective pages to push them onto Page 1.\n\n"

            if options[:csv]
              csv_data = opportunities.map { |o| [o[:query], o[:page], o[:position], o[:impressions], o[:clicks], o[:ctr], o[:potentialGain], o[:opportunityScore]] }
              Base.write_csv(options[:csv], %w[Query Page Position Impressions Clicks CTR PotentialGain Score], csv_data)
              puts Color.c("📁 Exported opportunities to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end
      end

      def handle_underperformers(api, site_url, options)
        min_imp = options[:min_imp] || 15
        puts "⚡ Scanning for CTR Underperformers in Top 10 for #{Color.c(site_url, Color::CYAN)} (Min #{min_imp} Imp)...\n" unless options[:json]

        res = api.query_analytics(site_url, days: options[:days], dimensions: %w[query page], row_limit: 2500)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          underperformers = []

          raw_rows.each do |r|
            q = r['keys'][0]
            p = r['keys'][1]
            pos = r['position'].round(1)
            imp = r['impressions']
            clicks = r['clicks']
            ctr = (r['ctr'] * 100).round(2)

            next unless pos <= 10.0
            next unless imp >= min_imp

            expected = Base.expected_ctr_for(pos)
            gap = expected - ctr
            next unless gap >= 2.0 && ctr < (expected * 0.70)

            lost_clicks = [((imp * (gap / 100.0))).round, 1].max

            underperformers << {
              query: q,
              page: p,
              position: pos,
              impressions: imp,
              clicks: clicks,
              actualCtr: ctr,
              expectedCtr: expected,
              lostClicks: lost_clicks
            }
          end

          underperformers.sort_by! { |u| -u[:lostClicks] }
          underperformers = underperformers.first(options[:limit])

          if options[:json]
            puts JSON.pretty_generate(underperformers)
          elsif underperformers.empty?
            puts Color.c("✅ No significant CTR underperformers detected in Top 10! Your titles are converting well.", Color::GREEN)
          else
            puts "#{Color::BOLD}Pos   | Imp    | CTR    | Expected | Lost Clicks | Query & Page#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            underperformers.each do |item|
              pos_str    = item[:position].to_s.ljust(5)
              imp_str    = item[:impressions].to_s.ljust(6)
              ctr_str    = "#{item[:actualCtr]}%".ljust(6)
              exp_str    = "~#{item[:expectedCtr]}%".ljust(8)
              lost_str   = "~#{item[:lostClicks]} clicks".ljust(11)
              page_short = item[:page].sub(%r{^https?://[^/]+}, '')
              page_short = '/' if page_short.empty?

              puts "#{Color.c(pos_str, Color::GREEN)} | #{imp_str} | #{Color.c(ctr_str, Color::RED)} | #{exp_str} | #{Color.c(lost_str, Color::YELLOW, Color::BOLD)} | #{Color.c(page_short, Color::CYAN)}"
              puts "      |        |        |          |             | ↳ #{Color::BOLD}\"#{item[:query]}\"#{Color::RESET}"
            end
            puts "\n#{Color.c("Total Underperformers: #{underperformers.size}", Color::GRAY)}"
            puts "💡 #{Color::BOLD}Quick Win Playbook:#{Color::RESET} You already have top rankings! Rewrite the <title> tag and meta description with numbers, brackets [2026], or clear benefit hooks to recover lost clicks immediately.\n\n"

            if options[:csv]
              csv_data = underperformers.map { |u| [u[:query], u[:page], u[:position], u[:impressions], u[:clicks], u[:actualCtr], u[:expectedCtr], u[:lostClicks]] }
              Base.write_csv(options[:csv], %w[Query Page Position Impressions Clicks ActualCTR ExpectedCTR LostClicks], csv_data)
              puts Color.c("📁 Exported CTR underperformers to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end
      end

      def handle_cannibalization(api, site_url, options)
        puts "⚔️  Auditing Keyword Cannibalization & URL Conflicts for #{Color.c(site_url, Color::CYAN)} (Past #{options[:days]} days)...\n" unless options[:json]

        res = api.query_analytics(site_url, days: options[:days], dimensions: %w[query page], row_limit: 5000)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          analysis = GSC::CannibalizationAnalyzer.analyze(raw_rows, min_imp: options[:min_imp] || 10)
          conflicts = analysis[:conflicts].first(options[:limit] || 25)

          if options[:json]
            puts JSON.pretty_generate(analysis)
          elsif conflicts.empty?
            puts Color.c("✅ Zero keyword cannibalization detected! Each query has a distinct ranking page.", Color::GREEN)
            puts "   Evaluated #{analysis[:total_queries_evaluated]} distinct queries across #{site_url}."
          else
            puts "Cannibalization Health Score: #{Color.c("#{analysis[:health_score]}/100 [Grade #{analysis[:health_grade]}]", analysis[:health_score] >= 80 ? Color::GREEN : Color::RED, Color::BOLD)}"
            puts "Total Conflicts Detected:     #{Color.c(analysis[:conflicts_count].to_s, Color::YELLOW, Color::BOLD)} (#{analysis[:critical_count]} Critical)"
            puts "Total Diluted Impressions:    #{Color.c(analysis[:total_diluted_impressions].to_s, Color::RED)} search impressions split across competing URLs\n\n"

            conflicts.each_with_index do |conf, i|
              sev_color = case conf[:severity]
                          when 'CRITICAL' then Color::RED
                          when 'HIGH'     then Color::YELLOW
                          else Color::CYAN
                          end
              sev_badge = Color.c("[#{conf[:severity]}]", sev_color, Color::BOLD)
              puts "#{Color::BOLD}#{i + 1}. #{sev_badge} \"#{conf[:query]}\"#{Color::RESET} (Total Imp: #{Color.c(conf[:total_impressions].to_s, Color::CYAN)}, Clicks: #{conf[:total_clicks]})"
              conf[:pages].each do |p|
                share_str = p[:impression_share_str].ljust(6)
                imp_str   = "#{p[:impressions]} imp".ljust(9)
                pos_str   = "Pos #{p[:position]}".ljust(9)
                page_short = p[:page].sub(%r{^https?://[^/]+}, '')
                page_short = '/' if page_short.empty?
                puts "   • #{Color.c(share_str, Color::YELLOW)} | #{imp_str} | #{pos_str} | #{page_short}"
              end
              puts "   👉 #{Color.c("Remedy [#{conf[:remedy][:action]}]:", Color::BOLD)} #{conf[:remedy][:recommendation]}\n\n"
            end

            if options[:csv]
              csv_rows = []
              analysis[:conflicts].each do |c|
                c[:pages].each do |p|
                  csv_rows << [c[:query], c[:severity], c[:total_impressions], c[:remedy][:action], c[:remedy][:recommendation], p[:page], p[:impression_share_str], p[:impressions], p[:clicks], p[:position]]
                end
              end
              Base.write_csv(options[:csv], %w[Query Severity TotalImpressions RemedyAction Recommendation Page ImpressionShare PageImpressions PageClicks Position], csv_rows)
              puts Color.c("📁 Exported cannibalization conflict report to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end
      end

      def handle_questions_harvest(target, api, site_url, options)
        days = options[:days] || 30
        min_imp = options[:min_imp] || 1
        page_filter = options[:page] || target

        puts "❓ Harvesting Question & FAQ Queries for #{Color.c(site_url, Color::CYAN)} (Past #{days} days)...\n" unless options[:json]

        res = api.query_analytics(site_url, days: days, dimensions: %w[query page], row_limit: 5000)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          harvest_data = GSC::QuestionsHarvester.harvest(
            raw_rows,
            min_imp: min_imp,
            filter_page: page_filter,
            brand: options[:brand] || site_url.sub(/^sc-domain:/, '').sub(/\.[a-z]+$/, '').capitalize,
            synthesize: options[:synthesize] || options[:answer]
          )

          if options[:json]
            puts JSON.pretty_generate(harvest_data)
          else
            puts "#{Color::BOLD}❓ SEARCH CONSOLE QUESTION & FAQ HARVEST#{Color::RESET}"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
            puts "  Total Questions Harvested: #{Color.c(harvest_data[:total_questions_harvested].to_s, Color::CYAN, Color::BOLD)}"
            puts "  🎯 High-Opportunity (Pos 4-20): #{Color.c(harvest_data[:high_opportunity_count].to_s, Color::YELLOW, Color::BOLD)} (Prime for FAQ Rich Snippets)"
            puts "  🛡️  SERP Defense (Pos 1-3):     #{Color.c(harvest_data[:defense_count].to_s, Color::GREEN, Color::BOLD)} (Featured Snippet Candidates)"
            puts "  📄 Landing Pages Covered:       #{harvest_data[:pages_covered]}"
            puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"

            limit = options[:limit] || 15
            top_questions = harvest_data[:questions].first(limit)

            if top_questions.empty?
              puts Color.c("No question queries found meeting criteria for this period.\n", Color::YELLOW)
            else
              puts "#{Color::BOLD}Top Harvested Questions:#{Color::RESET}"
              puts " #  | Imp  | Clicks | Pos  | Type   | Question"
              puts "─────────────────────────────────────────────────────────────────────────────"
              top_questions.each_with_index do |q, i|
                num_str = "[#{i + 1}]".ljust(4)
                imp_str = q[:impressions].to_s.ljust(5)
                clk_str = q[:clicks].to_s.ljust(7)
                pos_str = q[:position].to_s.ljust(5)
                type_str = Color.c((q[:type] || 'OTHER').ljust(7), Color::CYAN)

                puts "#{num_str}| #{imp_str}| #{clk_str}| #{pos_str}| #{type_str}| #{Color::BOLD}#{q[:question]}#{Color::RESET}"
                page_short = q[:page].sub(%r{^https?://[^/]+}, '')
                page_short = '/' if page_short.empty?
                puts "    🔗 Target Page: #{Color.c(page_short, Color::GRAY)} (Tier: #{q[:tier]})"
              end
              puts "─────────────────────────────────────────────────────────────────────────────\n"

              if options[:generate] || harvest_data[:recommended_faq_schemas].any?
                first_page, sample_schema = harvest_data[:recommended_faq_schemas].first
                if sample_schema
                  page_short = first_page.sub(%r{^https?://[^/]+}, '')
                  puts "📋 #{Color::BOLD}READY-TO-PASTE FAQPage JSON-LD SCHEMA FOR #{Color.c(page_short, Color::CYAN)}:#{Color::RESET}"
                  puts "<script type=\"application/ld+json\">"
                  puts JSON.pretty_generate(sample_schema)
                  puts "</script>\n"
                end
              end
            end

            puts "💡 #{Color.bold('Want to do more? Supercharge your question & content strategy:')}"
            clean_dom = site_url.sub('sc-domain:', '')
            sample_keyword = top_questions.any? ? top_questions.first[:question].gsub(/[?]/, '').split(/\s+/).last(2).join(' ') : 'search analytics'
            puts "   • 📅 Expand date range (up to 16 months): #{Color.cyan("gsc questions-harvest -d #{clean_dom} --days 480")}"
            puts "   • 🌐 Mine live People Also Ask questions: #{Color.cyan("gsc questions \"#{sample_keyword}\"")}"
            puts "   • ✍️  Synthesize high-ranking answers:    #{Color.cyan("gsc questions-harvest -d #{clean_dom} --days #{days} --synthesize")}"
            puts "   • 🎯 AI Overview Citation Radar:          #{Color.cyan("gsc aio-hunter \"#{sample_keyword}\"")}"
            puts "   • 📄 Filter by specific landing page:     #{Color.cyan("gsc questions-harvest /features/ -d #{clean_dom}")}\n\n"

            if options[:csv]
              csv_rows = harvest_data[:questions].map do |q|
                [q[:question], q[:type], q[:tier], q[:impressions], q[:clicks], q[:ctr], q[:position], q[:opportunity_score], q[:page]]
              end
              Base.write_csv(options[:csv], %w[Question Type Tier Impressions Clicks CTR Position OpportunityScore TargetPage], csv_rows)
              puts Color.c("📁 Exported question queries to #{options[:csv]}", Color::CYAN)
            end
          end
        else
          if options[:json]
            puts JSON.pretty_generate({ error: res[:data] })
          else
            puts Color.c("❌ Search Analytics Error (#{res[:status]}): #{res[:data]}", Color::RED)
          end
        end
      end

      def handle_zombies(target, api, site_url, https_origin, options)
        ZombiePurger.run('zombies', target, nil, options, api, site_url, nil, https_origin)
      end
    end
  end
end

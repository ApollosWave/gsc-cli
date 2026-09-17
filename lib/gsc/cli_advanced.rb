# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'uri'

module GSC
  class CLI
    # 1. Google Suggest
    def self.handle_suggest_command(target, options)
      query = target.to_s.strip
      if query.empty?
        puts Color.c("❌ Error: Query required. Example: gsc suggest \"seo audit\"", Color::RED)
        return
      end

      alphabet = options[:alphabet] || false
      suggest = GSC::GoogleSuggest.new(query, options)
      results = suggest.fetch(alphabet: alphabet, questions: false)

      if options[:json]
        puts JSON.pretty_generate(results)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "💡 #{Color::BOLD}GOOGLE SEARCH SUGGESTIONS:#{Color::RESET} #{Color.c(query, Color::CYAN)}"
      puts "─" * 70

      if alphabet
        results.each do |key, list|
          next if list.empty?
          prefix = (key == 'root') ? "Root" : "+ #{key.upcase}"
          puts "\n#{Color.c(prefix, Color::BOLD, Color::YELLOW)}:"
          list.each do |item|
            puts "   • #{item[:term]}"
          end
        end
      else
        if results.empty?
          puts "   (No search suggestions returned)"
        else
          results.each_with_index do |item, idx|
            puts "   #{Color.c((idx + 1).to_s.rjust(2), Color::DIM)}. #{Color.c(item[:term], Color::BOLD)}"
          end
        end
      end
      puts ""
    end

    # 2. Questions / PAA
    def self.handle_questions_command(target, options)
      query = target.to_s.strip
      if query.empty?
        puts Color.c("❌ Error: Query required. Example: gsc questions \"seo audit\"", Color::RED)
        return
      end

      suggest = GSC::GoogleSuggest.new(query, options)
      results = suggest.fetch(questions: true)

      if options[:json]
        puts JSON.pretty_generate(results)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "❓ #{Color::BOLD}SEARCH INTENT QUESTIONS & FAQs:#{Color::RESET} #{Color.c(query, Color::CYAN)}"
      puts "─" * 70

      total_found = 0
      results.each do |prefix, list|
        next if list.empty?
        puts "\n#{Color.c(prefix.upcase, Color::BOLD, Color::CYAN)}:"
        list.each do |item|
          total_found += 1
          puts "   • #{item[:term]}"
        end
      end

      if total_found.zero?
        puts "   (No question suggestions found for \"#{query}\")"
      end
      puts ""
    end

    # 3. OpenPageRank Domain Authority
    def self.handle_authority_command(target, extra, options)
      domains = [target, extra].flatten.compact.reject { |d| d.to_s.strip.empty? }
      domains << Config.default_domain if domains.empty?
      domains = domains.compact

      if domains.empty?
        puts Color.c("❌ Error: Domain required. Example: gsc authority example.com", Color::RED)
        return
      end

      opr = GSC::OpenPageRank.new
      unless opr.configured?
        puts Color.c("⚠️ OpenPageRank API key not configured.", Color::YELLOW, Color::BOLD)
        puts "   Get a 100% free key (300,000 free queries/month) at: #{Color.c('https://openpagerank.com', Color::CYAN)}"
        puts "   Then run: #{Color.c('gsc config set opr_api_key <YOUR_KEY>', Color::GREEN)}"
        puts "   Or pass:  #{Color.c('OPENPAGERANK_API_KEY=<KEY> gsc authority ...', Color::DIM)}"
        return
      end

      data = opr.check_domains(domains)

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🌐 #{Color::BOLD}OPEN PAGERANK & DOMAIN AUTHORITY (Common Crawl Graph):#{Color::RESET}"
      puts "─" * 75

      if data[:status] == 'error'
        puts Color.c("❌ Error: #{data[:message]}", Color::RED)
        return
      end

      puts "#{'DOMAIN'.ljust(35)} #{'PAGERANK'.ljust(12)} #{'GLOBAL RANK'.ljust(18)} #{'STATUS'}"
      puts "─" * 75

      (data[:records] || []).each do |rec|
        d_name = rec[:domain].to_s.ljust(35)
        pr = sprintf("%.2f / 10", rec[:page_rank_decimal]).ljust(12)
        gr = rec[:rank] ? "##{rec[:rank].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}".ljust(18) : "N/A".ljust(18)
        st = (rec[:status_code] == 200) ? Color.c("200 OK", Color::GREEN) : Color.c(rec[:status_code].to_s, Color::YELLOW)

        puts "#{Color.c(d_name, Color::BOLD)} #{Color.c(pr, Color::CYAN)} #{Color.c(gr, Color::YELLOW)} #{st}"
      end
      puts ""
    end

    # 4. PageSpeed Core Web Vitals
    def self.handle_speed_command(target, options)
      raw = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if raw.nil? || raw.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc speed https://mybrand.com", Color::RED)
        return
      end
      url = raw.to_s.start_with?('http') ? raw : "https://#{raw}"
      strategy = options[:strategy] || 'mobile'

      puts BANNER unless options[:json] || options[:in_dashboard]
      puts "⚡ Measuring Core Web Vitals via Google PageSpeed Insights (#{strategy.upcase}):" unless options[:json]
      puts "   #{Color.c(url, Color::CYAN)}\n" unless options[:json]

      ps = GSC::PageSpeed.new(url, strategy: strategy)
      data = ps.run

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      if data[:error]
        puts Color.c("❌ PageSpeed API Error: #{data[:message]}", Color::RED)
        return
      end

      perf_score = data[:performance_score]
      score_color = perf_score >= 90 ? Color::GREEN : (perf_score >= 50 ? Color::YELLOW : Color::RED)

      puts "╔══════════════════════════════════════════════════════════════╗"
      puts "║ Lighthouse Performance Score: #{Color.c(perf_score.to_s.rjust(3) + ' / 100', score_color, Color::BOLD)}                ║"
      puts "║ Lighthouse SEO Score        : #{Color.c(data[:seo_score].to_s.rjust(3) + ' / 100', Color::GREEN, Color::BOLD)}                ║"
      puts "╚══════════════════════════════════════════════════════════════╝"

      m = data[:metrics] || {}
      puts "\n#{Color::BOLD}🔬 LIGHTHOUSE LAB METRICS (Simulated #{strategy.upcase}):#{Color::RESET}"
      puts "   • LCP (Largest Contentful Paint) : #{Color.c(m[:lcp] || 'N/A', Color::BOLD)}"
      puts "   • FCP (First Contentful Paint)   : #{Color.c(m[:fcp] || 'N/A', Color::BOLD)}"
      puts "   • CLS (Cumulative Layout Shift)  : #{Color.c(m[:cls] || 'N/A', Color::BOLD)}"
      puts "   • TBT (Total Blocking Time)      : #{Color.c(m[:tbt] || 'N/A', Color::BOLD)}"
      puts "   • Speed Index                    : #{Color.c(m[:speed_index] || 'N/A', Color::BOLD)}"

      fd = data[:field_data] || {}
      if fd.any?
        source_label = data[:field_source] == :origin ? "Domain-Wide Origin RUM" : "URL-Level RUM"
        overall = data[:overall_category] || "UNKNOWN"
        overall_col = overall == 'FAST' ? Color::GREEN : (overall == 'AVERAGE' ? Color::YELLOW : Color::RED)
        puts "\n#{Color::BOLD}🌐 CrUX FIELD DATA (28-Day Real User Monitoring - #{source_label}):#{Color::RESET}"
        puts "   • Core Web Vitals Status        : #{Color.c(overall, overall_col, Color::BOLD)}"

        if fd['LARGEST_CONTENTFUL_PAINT_MS']
          val = "#{(fd['LARGEST_CONTENTFUL_PAINT_MS'][:percentile].to_f / 1000).round(2)} s"
          cat = fd['LARGEST_CONTENTFUL_PAINT_MS'][:category]
          col = cat == 'FAST' ? Color::GREEN : (cat == 'AVERAGE' ? Color::YELLOW : Color::RED)
          puts "   • LCP (75th Percentile)         : #{Color.c(val, Color::BOLD)} [#{Color.c(cat, col)}]"
        end

        if fd['INTERACTION_TO_NEXT_PAINT']
          val = "#{fd['INTERACTION_TO_NEXT_PAINT'][:percentile]} ms"
          cat = fd['INTERACTION_TO_NEXT_PAINT'][:category]
          col = cat == 'FAST' ? Color::GREEN : (cat == 'AVERAGE' ? Color::YELLOW : Color::RED)
          puts "   • INP (75th Percentile)         : #{Color.c(val, Color::BOLD)} [#{Color.c(cat, col)}]"
        end

        if fd['CUMULATIVE_LAYOUT_SHIFT_SCORE']
          val = (fd['CUMULATIVE_LAYOUT_SHIFT_SCORE'][:percentile].to_f / 100).round(3).to_s
          cat = fd['CUMULATIVE_LAYOUT_SHIFT_SCORE'][:category]
          col = cat == 'FAST' ? Color::GREEN : (cat == 'AVERAGE' ? Color::YELLOW : Color::RED)
          puts "   • CLS (75th Percentile)         : #{Color.c(val, Color::BOLD)} [#{Color.c(cat, col)}]"
        end

        if fd['FIRST_CONTENTFUL_PAINT_MS']
          val = "#{(fd['FIRST_CONTENTFUL_PAINT_MS'][:percentile].to_f / 1000).round(2)} s"
          cat = fd['FIRST_CONTENTFUL_PAINT_MS'][:category]
          col = cat == 'FAST' ? Color::GREEN : (cat == 'AVERAGE' ? Color::YELLOW : Color::RED)
          puts "   • FCP (75th Percentile)         : #{Color.c(val, Color::BOLD)} [#{Color.c(cat, col)}]"
        end

        if fd['EXPERIMENTAL_TIME_TO_FIRST_BYTE']
          val = "#{fd['EXPERIMENTAL_TIME_TO_FIRST_BYTE'][:percentile]} ms"
          cat = fd['EXPERIMENTAL_TIME_TO_FIRST_BYTE'][:category]
          col = cat == 'FAST' ? Color::GREEN : (cat == 'AVERAGE' ? Color::YELLOW : Color::RED)
          puts "   • TTFB (75th Percentile)        : #{Color.c(val, Color::BOLD)} [#{Color.c(cat, col)}]"
        end
      else
        puts "\n#{Color::BOLD}🌐 CrUX FIELD DATA (28-Day Real User Monitoring):#{Color::RESET}"
        puts "   #{Color.c('ℹ️ Insufficient real-user Chrome visits over the rolling 28-day window for Google CrUX telemetry.', Color::GRAY)}"
        puts "   #{Color.c('   (Google requires a minimum traffic threshold before publishing real-user CrUX field data).', Color::GRAY)}"
      end

      opps = data[:opportunities] || []
      unless opps.empty?
        puts "\n#{Color::BOLD}💡 TOP SPEED OPPORTUNITIES:#{Color::RESET}"
        opps.each do |opp|
          puts "   • #{opp[:title]}: #{Color.c(opp[:display] || "#{opp[:savings_ms]}ms savings", Color::YELLOW)}"
        end
      end
      puts ""
    end

    # 4b. Core Web Vitals & GSC Performance Correlator
    def self.handle_speed_correlate_command(target, options)
      domain = options[:domain] || Config.default_domain
      if (domain.nil? || domain.empty?) && (target.nil? || target.empty?)
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc speed-correlate https://mybrand.com", Color::RED)
        return
      end
      url = target || "https://#{domain}/"
      url = "https://#{url}" unless url =~ %r{^https?://}
      strategy = options[:strategy] || 'mobile'
      days = (options[:days] || 28).to_i

      # Attempt to get GSC API client if authenticated
      api = nil
      sa = GSC::Auth.find_service_account(options[:key], domain)
      if sa && sa[:data]
        token = GSC::Auth.fetch_access_token(sa[:data])
        client = GSC::Client.new(token: token)
        api = GSC::API.new(client)
      end

      correlator = GSC::SpeedCorrelator.new(url, api: api, domain: domain, days: days, strategy: strategy, options: options)
      data = correlator.correlate

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "⚡ #{Color::BOLD}CORE WEB VITALS & SEARCH CONSOLE PERFORMANCE CORRELATOR:#{Color::RESET}"
      puts "   Target URL: #{Color.c(url, Color::CYAN, Color::BOLD)} [Strategy: #{strategy.upcase}]"
      puts "─" * 80

      cwv = data[:core_web_vitals] || {}
      gsc = data[:gsc_performance] || {}
      diag = data[:correlation_diagnosis] || {}
      proj = data[:projections] || {}

      perf_score = cwv[:performance_score] || 0
      score_color = perf_score >= 90 ? Color::GREEN : (perf_score >= 50 ? Color::YELLOW : Color::RED)

      puts "📱 #{Color::BOLD}LIGHTHOUSE PERFORMANCE:#{Color::RESET} #{Color.c("#{perf_score}/100", score_color, Color::BOLD)} [Source: #{cwv[:source]}]"
      puts "   • LCP (Largest Contentful Paint) : #{Color.c(cwv[:lcp_display].to_s, Color::BOLD)} [Status: #{diag[:lcp_status]}]"
      puts "   • CLS (Cumulative Layout Shift)  : #{Color.c(cwv[:cls_display].to_s, Color::BOLD)} [Status: #{diag[:cls_status]}]"
      puts "   • FCP (First Contentful Paint)   : #{Color.c(cwv[:fcp_display].to_s, Color::BOLD)}"
      puts "   • TBT (Total Blocking Time)      : #{Color.c(cwv[:tbt_display].to_s, Color::BOLD)}"

      puts "\n📈 #{Color::BOLD}SEARCH CONSOLE TRACTION (Past #{days} Days):#{Color::RESET}"
      puts "   • Impressions : #{Color.c(gsc[:impressions].to_s, Color::CYAN, Color::BOLD)}"
      puts "   • Clicks      : #{Color.c(gsc[:clicks].to_s, Color::GREEN, Color::BOLD)}"
      puts "   • CTR         : #{Color.c("#{gsc[:ctr]}%", Color::BOLD)}"
      puts "   • Avg Position: #{Color.c(gsc[:position].to_s, Color::BOLD)}"

      puts "\n🧠 #{Color::BOLD}ALGORITHMIC CWV IMPACT DIAGNOSIS:#{Color::RESET}"
      diag_color = diag[:overall_cwv_pass] ? Color::GREEN : Color::YELLOW
      puts "   • CWV Overall Verdict : [#{Color.c(diag[:overall_cwv_pass] ? 'PASSED' : 'NEEDS OPTIMIZATION', diag_color, Color::BOLD)}]"
      puts "   • Algorithmic Drag    : #{Color.c(diag[:algorithmic_status], Color::BOLD)}"

      puts "\n🚀 #{Color::BOLD}PROJECTED SEARCH IMPRESSION & TRAFFIC SURGE (Upon Reaching 'Good' CWV):#{Color::RESET}"
      puts "   • Potential Impression Lift   : #{Color.c("+#{proj[:potential_lift_percentage]}%", Color::GREEN, Color::BOLD)} (+#{proj[:incremental_impressions_gain]} impressions)"
      puts "   • Projected Impressions Target: #{Color.c(proj[:projected_impressions].to_s, Color::CYAN, Color::BOLD)}"
      puts "   • Projected Rank Lift         : #{Color.c(proj[:estimated_position_improvement].to_s, Color::GREEN, Color::BOLD)} (Pos #{proj[:current_position]} -> Pos #{proj[:projected_position]})"
      puts "   • Projected Monthly Click Gain: #{Color.c("+#{proj[:projected_incremental_monthly_clicks]} clicks/mo", Color::GREEN, Color::BOLD)}"

      action_plan = data[:action_plan] || []
      if action_plan.any?
        puts "\n🛠️  #{Color::BOLD}PRIORITIZED ENGINEERING FIXES FOR SPEED & RANKINGS:#{Color::RESET}"
        action_plan.each_with_index do |act, idx|
          puts "   #{idx + 1}. [#{Color.c(act[:priority], Color::BOLD)}] [#{act[:metric]}]: #{act[:recommendation]}"
        end
      end

      opps = cwv[:opportunities] || []
      if opps.any?
        puts "\n💡 #{Color::BOLD}IDENTIFIED BOTTLENECK OPPORTUNITIES:#{Color::RESET}"
        opps.each do |o|
          puts "   • #{o[:title]} (#{Color.c(o[:display] || "#{o[:savings_ms]}ms savings", Color::YELLOW)})"
        end
      end

      puts "\n" + ("─" * 80) + "\n"
    end

    # 5. Page Comparison
    def self.handle_compare_command(target, extra, options)
      url1 = target
      url2 = extra

      if url1.nil? || url2.nil?
        puts Color.c("❌ Error: Two URLs required. Example: gsc compare https://site.com/p1 https://competitor.com/p2", Color::RED)
        return
      end

      comp = GSC::PageComparator.new(url1, url2)
      data = comp.compare

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🥊 #{Color::BOLD}HEAD-TO-HEAD SEO ON-PAGE COMPARISON:#{Color::RESET}"
      puts "   Page 1 (Target):     #{Color.c(url1, Color::CYAN)}"
      puts "   Page 2 (Competitor): #{Color.c(url2, Color::YELLOW)}"
      puts "─" * 80

      c = data[:comparison] || {}

      # Meta Titles
      t1 = c.dig(:meta, :title, :page1) || {}
      t2 = c.dig(:meta, :title, :page2) || {}
      puts "\n#{Color::BOLD}📑 TITLE TAG:#{Color::RESET}"
      puts "   P1: #{t1[:text]} (#{t1[:length]} chars) [#{t1[:optimal] ? Color.c('Optimal', Color::GREEN) : Color.c('Review', Color::YELLOW)}]"
      puts "   P2: #{t2[:text]} (#{t2[:length]} chars) [#{t2[:optimal] ? Color.c('Optimal', Color::GREEN) : Color.c('Review', Color::YELLOW)}]"

      # Headings
      h = c[:headings] || {}
      puts "\n#{Color::BOLD}🏷️ HEADINGS H1 / H2:#{Color::RESET}"
      puts "   P1: #{h.dig(:h1_count, :page1)} H1s | #{h.dig(:h2_count, :page1)} H2s"
      puts "   P2: #{h.dig(:h1_count, :page2)} H1s | #{h.dig(:h2_count, :page2)} H2s"

      # Images
      img = c[:images] || {}
      puts "\n#{Color::BOLD}🖼️ IMAGES & ACCESSIBILITY:#{Color::RESET}"
      puts "   P1: #{img.dig(:total_images, :page1)} images (#{img.dig(:missing_alt, :page1)} missing alt)"
      puts "   P2: #{img.dig(:total_images, :page2)} images (#{img.dig(:missing_alt, :page2)} missing alt)"

      # Links
      l = c[:links] || {}
      puts "\n#{Color::BOLD}🔗 LINK COUNTS:#{Color::RESET}"
      puts "   P1: #{l.dig(:internal, :page1)} internal | #{l.dig(:external, :page1)} external"
      puts "   P2: #{l.dig(:internal, :page2)} internal | #{l.dig(:external, :page2)} external"

      # Schema
      s = c[:structured_data] || {}
      puts "\n#{Color::BOLD}📦 STRUCTURED DATA (JSON-LD):#{Color::RESET}"
      puts "   P1: #{s.dig(:schema_count, :page1)} schemas #{(s.dig(:schema_types, :page1) || []).inspect}"
      puts "   P2: #{s.dig(:schema_count, :page2)} schemas #{(s.dig(:schema_types, :page2) || []).inspect}"

      # Speed
      p_time = c[:performance] || {}
      puts "\n#{Color::BOLD}⚡ RESPONSE TIME:#{Color::RESET}"
      puts "   P1: #{p_time.dig(:response_time_ms, :page1)}ms | P2: #{p_time.dig(:response_time_ms, :page2)}ms"
      puts ""
    end

    # 6. Content Gap
    def self.handle_content_gap_command(target, extra, options)
      url1 = target
      url2 = extra

      if url1.nil? || url2.nil?
        puts Color.c("❌ Error: Two URLs required. Example: gsc content-gap https://mysite.com https://competitor.com", Color::RED)
        return
      end

      gap = GSC::ContentGap.new(url1, url2)
      data = gap.analyze

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🔍 #{Color::BOLD}CONTENT & TOPICAL KEYWORD GAP (SurferSEO Style):#{Color::RESET}"
      puts "   My URL:         #{Color.c(url1, Color::CYAN)} (#{data[:page1][:word_count]} words)"
      puts "   Competitor URL: #{Color.c(url2, Color::YELLOW)} (#{data[:page2][:word_count]} words)"
      puts "─" * 80

      puts "\n#{Color::BOLD}🎯 HIGH-FREQUENCY PHRASES IN COMPETITOR MISSING IN YOUR CONTENT:#{Color::RESET}"
      unigrams = data[:missing_unigrams] || []
      bigrams  = data[:missing_bigrams] || []

      if unigrams.empty? && bigrams.empty?
        puts "   (No major content gap detected! Your page covers competitor terminology well.)"
      else
        puts "\n   #{Color.c('Top Missing 2-Word Keyphrases:', Color::BOLD, Color::YELLOW)}"
        bigrams.first(8).each do |b|
          puts "   • \"#{Color.c(b[:term], Color::BOLD)}\" (Competitor uses #{b[:competitor_count]}x, You: #{b[:your_count]}x)"
        end

        puts "\n   #{Color.c('Top Missing Keywords:', Color::BOLD, Color::CYAN)}"
        unigrams.first(8).each do |u|
          puts "   • \"#{Color.c(u[:term], Color::BOLD)}\" (Competitor uses #{u[:competitor_count]}x, You: #{u[:your_count]}x)"
        end
      end

      headings = data[:missing_headings] || []
      unless headings.empty?
        puts "\n#{Color::BOLD}📑 COMPETITOR HEADINGS / TOPICS YOU OMITTED:#{Color::RESET}"
        headings.each do |h|
          puts "   • #{h}"
        end
      end
      puts ""
    end

    # 7. Internal Links Audit & Orphan Page Rescue Engine
    def self.handle_internal_links_command(target, options)
      raw = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if raw.nil? || raw.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc internal-links https://mybrand.com", Color::RED)
        return
      end
      base_url = raw.to_s.start_with?('http') ? raw : "https://#{raw}"
      conc = options[:concurrency] || 5
      il = GSC::InternalLinks.new(base_url, limit: options[:limit] || 50, concurrency: conc)

      puts BANNER unless options[:json] || options[:in_dashboard]
      puts "🕸️ Auditing Internal Links & Orphan Pages for: #{Color.c(base_url, Color::CYAN)} (#{conc} worker threads)...\n" unless options[:json]

      data = il.audit

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      score_color = case data[:health_score]
                    when 85..100 then Color::GREEN
                    when 70..84  then Color::YELLOW
                    else              Color::RED
                    end

      puts "📍 Domain:            #{Color.c(data[:base_url], Color::CYAN, Color::BOLD)}"
      puts "⚡ Crawl Performance: #{data[:total_pages]} pages mapped in #{data[:crawl_duration_s]}s"
      puts "🏆 Link Equity Score: #{Color.c("#{data[:health_score]}/100 (Grade #{data[:health_grade]})", score_color, Color::BOLD)}"
      puts "🚨 True Orphans:      #{Color.c(data[:orphans].length.to_s, data[:orphans].empty? ? Color::GREEN : Color::RED, Color::BOLD)} (0 incoming internal links)"
      puts "⚠️  Weakly Linked:     #{Color.c(data[:weak_pages].length.to_s, Color::YELLOW, Color::BOLD)} (Only 1 incoming internal link)"
      puts "🧗 Buried Pages:      #{Color.c(data[:deep_pages].length.to_s, data[:deep_pages].empty? ? Color::GREEN : Color::YELLOW, Color::BOLD)} (Click depth >= 4)"
      puts "─" * 80

      orphan_details = data[:orphan_details] || []
      unless orphan_details.empty?
        puts "\n#{Color::BOLD}🚨 ORPHAN PAGE RESCUE PLAYBOOK (#{orphan_details.size} crawl dead-ends):#{Color::RESET}"
        orphan_details.each_with_index do |orp, idx|
          puts "\n   #{Color::BOLD}#{idx + 1}. #{Color.c(orp[:url], Color::RED, Color::BOLD)}#{Color::RESET} [Depth: #{orp[:depth]}]"
          puts "      #{Color::BOLD}Rescue Prescriptions:#{Color::RESET}"
          orp[:suggested_rescues].each do |rec|
            puts "      • #{Color.c(rec[:action], Color::CYAN)}"
          end
        end
      else
        puts "\n#{Color.c('✅ EXCELLENT! No orphan pages detected on site.', Color::GREEN, Color::BOLD)}"
      end

      weak = data[:weak_pages] || []
      unless weak.empty?
        puts "\n#{Color::BOLD}⚠️  WEAKLY LINKED PAGES (Vulnerable to De-indexation):#{Color::RESET}"
        weak.first(5).each do |w|
          puts "   • #{w[:url]} (Linked only from: #{Color.c(w[:source].to_s, Color::GRAY)})"
        end
        puts "   ... and #{weak.size - 5} more weak pages" if weak.size > 5
      end

      deep = data[:deep_pages] || []
      unless deep.empty?
        puts "\n#{Color::BOLD}🧗 BURIED PAGES (Crawl Depth >= 4 clicks):#{Color::RESET}"
        deep.first(5).each do |dp|
          puts "   • #{dp[:url]} (#{Color.c("#{dp[:depth]} clicks deep", Color::YELLOW)})"
        end
      end

      puts "\n#{Color::BOLD}🔝 TOP LINK EQUITY HUBS (High-Authority Internal Sources):#{Color::RESET}"
      (data[:top_linked] || []).first(6).each do |top|
        title_str = top[:title].to_s.empty? ? '' : " — \"#{top[:title][0..35]}...\""
        puts "   • #{Color.c(top[:url], Color::BOLD)}#{title_str} (#{Color.c(top[:incoming_count].to_s, Color::CYAN)} in / #{top[:outgoing_count]} out)"
      end

      if options[:csv]
        csv_data = orphan_details.map do |o|
          [o[:url], o[:depth], o[:suggested_rescues].map { |r| r[:source_url] }.join('; ')]
        end
        write_csv(options[:csv], %w[OrphanURL Depth RecommendedRescueSources], csv_data)
        puts Color.c("\n📁 Exported orphan rescue playbook to #{options[:csv]}", Color::CYAN)
      end

      puts "\n" + ("─" * 80) + "\n"
    end

    # 8. Schema Validator & Generator
    def self.handle_schema_command(target, extra, options)
      if target == 'generate' || target == 'gen'
        schema_type = extra || 'faq'
        tpl = GSC::SchemaValidator.generate_template(schema_type)
        if options[:json]
          puts JSON.pretty_generate(tpl)
        else
          puts Color.c("📋 Generated JSON-LD Schema (#{schema_type}):", Color::GREEN, Color::BOLD)
          puts "<script type=\"application/ld+json\">"
          puts JSON.pretty_generate(tpl)
          puts "</script>"
        end
        return
      end

      raw = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if raw.nil? || raw.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc schema https://mybrand.com", Color::RED)
        return
      end
      url = raw.to_s.start_with?('http') ? raw : "https://#{raw}"
      sv = GSC::SchemaValidator.new(url)
      data = sv.audit

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "📦 #{Color::BOLD}STRUCTURED DATA & RICH SNIPPET VALIDATION:#{Color::RESET} #{Color.c(url, Color::CYAN)}"
      puts "─" * 75

      schemas = data[:schemas] || []
      if schemas.empty?
        puts "   (No JSON-LD structured data schemas found on this page)"
        puts "   Tip: Run `gsc schema generate faq` to create valid JSON-LD schema."
      else
        schemas.each do |sc|
          valid_badge = sc[:valid] ? Color.c("VALID", Color::GREEN, Color::BOLD) : Color.c("INVALID", Color::RED, Color::BOLD)
          puts "\nSchema ##{sc[:index] + 1}: #{Color.c(sc[:type], Color::BOLD)} [#{valid_badge}]"
          (sc[:errors] || []).each { |e| puts "   ❌ Error: #{Color.c(e, Color::RED)}" }
          (sc[:warnings] || []).each { |w| puts "   ⚠️ Warning: #{Color.c(w, Color::YELLOW)}" }
        end
      end
      puts ""
    end

    # 9. LLMS.txt & AI Search
    def self.handle_llms_command(target, extra, options)
      raw = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if raw.nil? || raw.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc llms https://mybrand.com", Color::RED)
        return
      end
      base_url = raw.to_s.start_with?('http') ? raw : "https://#{raw}"
      llms = GSC::LlmsGenerator.new(base_url)

      if extra == 'audit' || options[:audit]
        data = llms.audit_ai_readability(base_url)
        if options[:json]
          puts JSON.pretty_generate(data)
        else
          puts BANNER unless options[:in_dashboard]
          puts "🤖 #{Color::BOLD}AI SEARCH ENGINE / LLM READABILITY AUDIT:#{Color::RESET} #{Color.c(base_url, Color::CYAN)}"
          puts "─" * 70
          puts "AI Citation Readiness Score: #{Color.c(data[:ai_readability_score].to_s + '/100', Color::GREEN, Color::BOLD)} [Grade: #{data[:grade]}]"
          puts "\nFeatures Detected:"
          puts "   • Single H1 Heading : #{data.dig(:features, :h1_count) == 1 ? '✅ Yes' : '❌ No'}"
          puts "   • Tables for Data   : #{data.dig(:features, :has_tables) ? '✅ Yes' : '❌ No'}"
          puts "   • Bullet Lists      : #{data.dig(:features, :has_lists) ? '✅ Yes' : '❌ No'}"
          puts "   • Structured Data   : #{data.dig(:features, :schemas_found)} schemas"
          unless data[:issues].empty?
            puts "\nOptimizations for Perplexity & ChatGPT:"
            data[:issues].each { |iss| puts "   • #{Color.c(iss, Color::YELLOW)}" }
          end
          puts ""
        end
      else
        content = llms.generate_llms_txt
        if options[:save]
          File.write("llms.txt", content)
          puts Color.c("✅ Successfully wrote llms.txt to current directory!", Color::GREEN)
        else
          puts content
        end
      end
    end

    # 10. SERP & Social Preview / Live SERP Feature Detector
    def self.handle_preview_command(target, options)
      is_url = target.to_s.start_with?('http://', 'https://')
      has_title_or_url = is_url || options[:url] || options[:title] || options[:desc] || options[:description] || options[:preview] || (target.to_s =~ /[:|—]/)

      if options[:live] || options[:features] || (!has_title_or_url && !target.to_s.empty?)
        return handle_serp_features_command(target, options)
      end

      url = options[:url] || (target if is_url)
      url ||= (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      title = options[:title] || (!is_url && !target.to_s.empty? ? target.to_s : nil)
      desc = options[:desc] || options[:description]

      if url.nil? && (title.nil? || title.empty?)
        puts Color.c("❌ Error: Target URL or title required for SERP preview. Example: gsc preview https://mybrand.com/page", Color::RED)
        return
      end
      url ||= "https://#{title.to_s.downcase.gsub(/[^a-z0-9]+/, '-')}.local"

      sp = GSC::SerpPreview.new(url, title: title, desc: desc)
      data = sp.generate

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
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

    # 10a. Live SERP Feature Detector & Zero-Click Threat Analysis
    def self.handle_serp_features_command(query, options)
      query_str = query.to_s.sub(/^(query|live):/, '').strip
      query_str = "what is #{Config.default_domain || 'technical seo'}" if query_str.empty?

      detector = GSC::SerpFeatureDetector.new(query_str, options)
      data = detector.detect

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
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

      # AI Overview
      aio = f[:ai_overview] || {}
      aio_badge = aio[:detected] ? Color.c("ACTIVE (#{aio[:probability_pct]}% prob)", Color::RED, Color::BOLD) : Color.c("Unlikely (#{aio[:probability_pct]}%)", Color::GRAY)
      puts "   • Google AI Overview (Gemini) : [#{aio_badge}]"
      puts "     └─ #{Color.c(aio[:impact], Color::DIM)}" if aio[:detected]

      # Featured Snippet
      fs = f[:featured_snippet] || {}
      fs_badge = fs[:detected] ? Color.c("OPPORTUNITY (#{fs[:target_format].capitalize} - #{fs[:probability_pct]}%)", Color::GREEN, Color::BOLD) : Color.c("None", Color::GRAY)
      puts "   • Featured Snippet Box        : [#{fs_badge}]"
      puts "     └─ Target Recipe: #{Color.c(fs[:capture_prescription], Color::CYAN)}" if fs[:detected]

      # People Also Ask
      paa = f[:people_also_ask] || {}
      paa_badge = paa[:detected] ? Color.c("#{paa[:count]} Live Questions Extracted", Color::CYAN, Color::BOLD) : Color.c("None", Color::GRAY)
      puts "   • People Also Ask (PAA)       : [#{paa_badge}]"
      if paa[:detected] && (paa[:questions] || []).any?
        paa[:questions].first(5).each do |q_text|
          puts "     ❓ \"#{Color.c(q_text, Color::YELLOW)}\""
        end
      end

      # Local Pack
      lp = f[:local_3_pack] || {}
      lp_badge = lp[:detected] ? Color.c("DETECTED (Google Maps 3-Pack)", Color::YELLOW, Color::BOLD) : Color.c("None", Color::GRAY)
      puts "   • Local Maps 3-Pack           : [#{lp_badge}]"

      # Video Carousel
      vc = f[:video_carousel] || {}
      vc_badge = vc[:detected] ? Color.c("DETECTED (Video Carousel)", Color::YELLOW, Color::BOLD) : Color.c("None", Color::GRAY)
      puts "   • Video Carousel / YouTube    : [#{vc_badge}]"

      # Discussions & Forums
      df = f[:discussions_and_forums] || {}
      df_badge = df[:detected] ? Color.c("DETECTED (Reddit/Quora Modules)", Color::CYAN, Color::BOLD) : Color.c("None", Color::GRAY)
      puts "   • Discussions & Forums        : [#{df_badge}]"

      # Shopping Pack
      sp = f[:shopping_pack] || {}
      sp_badge = sp[:detected] ? Color.c("DETECTED (Shopping Product Grid)", Color::YELLOW, Color::BOLD) : Color.c("None", Color::GRAY)
      puts "   • Google Shopping Grid        : [#{sp_badge}]"

      # Playbook
      playbook = data[:playbook] || []
      if playbook.any?
        puts "\n#{Color::BOLD}🏆 RICH SNIPPET & CITATION CAPTURE PLAYBOOK:#{Color::RESET}"
        playbook.each_with_index do |p, idx|
          puts "   #{idx + 1}. [#{Color.c(p[:priority], Color::BOLD)}] #{Color.c(p[:target], Color::CYAN)}:"
          puts "      👉 #{p[:action]}"
        end
      end

      # Live SERP Sampling
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

    # 10b. IndexNow Multi-Engine Instant Indexing (Bing, Yandex, Seznam, Naver)
    def self.handle_indexnow_command(target, extra, options)
      if target == 'key' || target == 'connect'
        if extra && !extra.strip.empty?
          key = IndexNow.set_key(extra)
          puts Color.c("✅ Successfully set IndexNow API key to: #{key}", Color::GREEN, Color::BOLD)
        else
          key = IndexNow.get_or_create_key
          host = Config.default_domain || 'yourdomain.com'
          puts "🔑 #{Color::BOLD}INDEXNOW API KEY & HOST SETUP:#{Color::RESET}"
          puts "   • Active Key:          #{Color.c(key, Color::CYAN, Color::BOLD)}"
          puts "   • Host Verification:   #{Color.c("https://#{host}/#{key}.txt", Color::BLUE)}"
          puts "   • Required Content:    #{Color.c(key, Color::BOLD)}"
          puts "\n💡 #{Color.c('Verification Tip:', Color::YELLOW)} Create a plain text file at the root of your web server named '#{key}.txt' with '#{key}' as the content."
        end
        return
      end

      if target == 'sitemap' || target.to_s.end_with?('.xml')
        sitemap_target = (target == 'sitemap') ? extra : target
        handle_indexnow_sitemap_command(sitemap_target, options)
        return
      end

      target_url = target || options[:url]
      unless target_url
        if Config.default_domain
          target_url = "https://#{Config.default_domain}"
        else
          raise 'Please provide a URL to index (e.g. gsc indexnow https://example.com/new-page) or connect a default domain.'
        end
      end

      urls = [target_url]
      urls << extra if extra && extra.start_with?('http')

      key = options[:key] || IndexNow.get_or_create_key
      res = IndexNow.submit(urls, key: key)

      if options[:json]
        puts JSON.pretty_generate(res)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "⚡ #{Color::BOLD}INDEXNOW MULTI-SEARCH ENGINE SUBMISSION:#{Color::RESET}"
      puts "─" * 75
      status_color = res[:success] ? Color::GREEN : Color::RED
      puts "Status          : #{Color.c(res[:message], status_color, Color::BOLD)}"
      puts "Submitted URLs  : #{Color.c(res[:submitted_urls].to_s, Color::CYAN, Color::BOLD)}"
      puts "Host            : #{res[:host]}"
      puts "Key Location    : #{res[:key_location]}"
      puts "Engines Notified: #{Color.c('Microsoft Bing, Yandex, Seznam, Naver', Color::BOLD)}"
      puts "─" * 75

      urls.each_with_index do |u, idx|
        puts "   #{idx + 1}. #{Color.c(u, Color::CYAN)}"
      end

      unless res[:success]
        puts "\n#{Color.c('⚠️ Note:', Color::YELLOW)} Ensure you have created #{res[:key_location]} with content: #{res[:key]}"
      end
      puts ""
    end

    def self.handle_indexnow_sitemap_command(target, options)
      sitemap = target || options[:sitemap] || 'sitemap.xml'
      key = options[:key] || IndexNow.get_or_create_key
      limit = options[:limit] ? options[:limit].to_i : nil

      puts BANNER unless options[:in_dashboard]
      puts "📄 #{Color::BOLD}BATCH INDEXNOW SITEMAP SUBMISSION:#{Color::RESET} #{Color.c(sitemap, Color::CYAN)}"
      puts "─" * 75

      res = IndexNow.submit_sitemap(sitemap, key: key, limit: limit)

      if options[:json]
        puts JSON.pretty_generate(res)
        return
      end

      status_color = res[:success] ? Color::GREEN : Color::RED
      puts "Status          : #{Color.c(res[:message], status_color, Color::BOLD)}"
      puts "URLs Submitted  : #{Color.c(res[:submitted_urls].to_s, Color::GREEN, Color::BOLD)}"
      puts "Host            : #{res[:host]}"
      puts "Engines Notified: #{Color.c('Microsoft Bing, Yandex, Seznam, Naver', Color::BOLD)}"
      puts "─" * 75
      puts "✨ All URLs pushed to IndexNow instant crawl queue."
      puts ""
    end

    # 11. Network & Redirect Tracer
    def self.handle_trace_command(target, options)
      url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if url.nil? || url.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc trace https://mybrand.com", Color::RED)
        return
      end
      nt = GSC::NetworkTracer.new(url)
      data = nt.trace

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🛤️ #{Color::BOLD}REDIRECT CHAIN & HTTP HEADER TRACE:#{Color::RESET} #{Color.c(url, Color::CYAN)}"
      puts "─" * 75
      puts "Total Hops: #{data[:total_hops]} | Duration: #{data[:total_duration_ms]}ms"

      (data[:hops] || []).each do |hop|
        status_c = (hop[:status_code] == 200) ? Color::GREEN : Color::YELLOW
        puts "\nHop ##{hop[:hop]}: #{Color.c(hop[:status_code].to_s, status_c, Color::BOLD)} (#{hop[:duration_ms]}ms)"
        puts "   URL:    #{hop[:url]}"
        puts "   X-Robots-Tag: #{Color.c(hop[:x_robots_tag], Color::RED)}" if hop[:x_robots_tag]
        puts "   Canonical:    #{hop[:canonical_header]}" if hop[:canonical_header]
        puts "   HSTS:         #{hop[:hsts] ? 'Enabled' : 'Disabled'}"
      end
      puts ""
    end

    # 12. Robots.txt Checker
    def self.handle_robots_command(target, extra, options)
      raw = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if raw.nil? || raw.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc robots https://mybrand.com", Color::RED)
        return
      end
      url = raw.to_s.start_with?('http') ? raw : "https://#{raw}"
      path = extra || '/'
      bot = options[:bot] || 'googlebot'

      rc = GSC::RobotsChecker.new(url)
      data = rc.check(path, bot)

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🤖 #{Color::BOLD}ROBOTS.TXT CRAWLER SIMULATOR:#{Color::RESET}"
      puts "   Robots URL : #{data[:robots_url]}"
      puts "   User Agent : #{Color.c(bot, Color::CYAN)}"
      puts "   Test Path  : #{Color.c(path, Color::BOLD)}"
      puts "─" * 70

      status_badge = data[:allowed] ? Color.c("✅ ALLOWED", Color::GREEN, Color::BOLD) : Color.c("❌ BLOCKED (DISALLOW)", Color::RED, Color::BOLD)
      puts "Crawl Verdict : #{status_badge}"
      if data[:matched_rule]
        puts "Matched Rule  : #{data[:matched_rule][:type].to_s.upcase}: #{data[:matched_rule][:path]}"
      end
      puts ""
    end

    # 13. Backlinks & GSC Links Ingestion
    def self.handle_backlinks_command(target, extra, options)
      domain = (target unless target == 'import') || Config.default_domain
      if domain.nil? || domain.empty?
        puts Color.c("❌ Error: Target domain required. Example: gsc backlinks mybrand.com", Color::RED)
        return
      end
      bm = GSC::BacklinksManager.new(domain)

      if target == 'import' || extra == 'import'
        source = (target == 'import') ? extra : target
        content = if source == 'clip' || source == 'clipboard'
                    `pbpaste 2>/dev/null`
                  elsif source && File.exist?(source)
                    File.read(source)
                  else
                    nil
                  end

        if content.nil? || content.strip.empty?
          puts Color.c("❌ Error: No content provided. Usage: gsc backlinks import [file.csv|clip]", Color::RED)
          return
        end

        res = bm.import_csv(content)
        if options[:json]
          puts JSON.pretty_generate(res)
        else
          puts Color.c("✅ Successfully imported GSC backlink export!", Color::GREEN, Color::BOLD)
          puts "   Referring Domains : #{res[:sources_count]}"
          puts "   Target Pages      : #{res[:targets_count]}"
        end
        return
      end

      data = bm.summary

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🔗 #{Color::BOLD}GSC BACKLINK & REFERRING DOMAIN INTELLIGENCE:#{Color::RESET} #{Color.c(domain, Color::CYAN)}"
      puts "─" * 75
      puts "Total Referring Domains : #{Color.c(data[:total_referring_domains].to_s, Color::BOLD)}"
      puts "Total External Links    : #{Color.c(data[:total_external_links].to_s, Color::BOLD)}"
      puts "Last Updated            : #{data[:updated_at] || 'Never (Run `gsc backlinks import` to ingest GSC export)'}"
      puts "─" * 75

      sources = data[:top_referring_domains] || []
      unless sources.empty?
        puts "\n#{Color::BOLD}🌐 TOP REFERRING SITES:#{Color::RESET}"
        sources.each do |s|
          puts "   • #{s['domain'].to_s.ljust(45)} #{Color.c(s['links_count'].to_s.rjust(6) + ' links', Color::CYAN)}"
        end
      end

      targets = data[:top_target_pages] || []
      unless targets.empty?
        puts "\n#{Color::BOLD}🎯 TOP LINKED LANDING PAGES:#{Color::RESET}"
        targets.each do |t|
          puts "   • #{t['target_url'].to_s.ljust(45)} #{Color.c(t['incoming_count'].to_s.rjust(6) + ' links', Color::GREEN)}"
        end
      end
      puts ""
    end

    # 14. Generative Engine Optimization (GEO / AEO) Citability Auditor
    def self.handle_geo_command(target, options)
      raw = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if raw.nil? || raw.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc geo https://mybrand.com", Color::RED)
        return
      end
      url = raw.to_s.start_with?('http') ? raw : "https://#{raw}"
      auditor = GSC::GeoAuditor.new(url)

      puts "🤖 Analyzing Generative Engine Optimization (GEO) & Citability for #{Color.c(url, Color::CYAN)}...\n" unless options[:json]

      data = auditor.audit
      if data[:error]
        if options[:json]
          puts JSON.pretty_generate(data)
        else
          puts Color.c("❌ Error: #{data[:message]}", Color::RED, Color::BOLD)
        end
        return
      end

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🤖 #{Color::BOLD}GENERATIVE ENGINE OPTIMIZATION (GEO / AEO) AUDIT#{Color::RESET}"
      puts "🎯 Target URL : #{Color.c(data[:url], Color::CYAN)}"
      puts "─" * 75

      score_color = case data[:score]
                    when 85..100 then Color::GREEN
                    when 70..84  then Color::CYAN
                    when 50..69  then Color::YELLOW
                    else              Color::RED
                    end

      puts "🏆 #{Color::BOLD}AI CITABILITY SCORE:#{Color::RESET} #{Color.c("#{data[:score]}/100", score_color, Color::BOLD)} — #{data[:grade]}"
      puts "   • AI Bot Access (Robots.txt)   : #{data[:category_scores][:ai_bot_access][:score]}/25"
      puts "   • Direct Question Answers      : #{data[:category_scores][:direct_answers][:score]}/25"
      puts "   • Factual & Data Citability    : #{data[:category_scores][:facts_and_data][:score]}/25"
      puts "   • Entity Schema & Authority    : #{data[:category_scores][:entity_schema][:score]}/25"
      puts "─" * 75

      puts "\n🤖 #{Color::BOLD}AI SEARCH CRAWLER ACCESS (Robots.txt):#{Color::RESET}"
      data[:ai_crawlers][:bots].each do |bot, info|
        badge = info[:allowed] ? Color.c("✅ ALLOWED", Color::GREEN) : Color.c("❌ BLOCKED", Color::RED, Color::BOLD)
        puts "   • #{bot.ljust(20)} [#{info[:provider]}]: #{badge} (#{info[:rule]})"
      end

      puts "\n📝 #{Color::BOLD}DIRECT ANSWER & CITABILITY DENSITY:#{Color::RESET}"
      puts "   • Question Headings Detected   : #{data[:direct_answers][:total_question_headings]}"
      puts "   • Direct Answer Paragraphs     : #{data[:direct_answers][:direct_answer_blocks_found]}"
      puts "   • Optimal Length Answers (30-80w): #{data[:direct_answers][:optimal_answers_count]}"

      samples = data[:direct_answers][:samples] || []
      if samples.any?
        puts "   #{Color::BOLD}Sample Answer Pairs:#{Color::RESET}"
        samples.each do |s|
          puts "     Q: #{Color.c(s[:question], Color::CYAN)}"
          puts "     A: #{s[:answer_preview]} (#{s[:word_count]} words)"
        end
      end

      puts "\n📊 #{Color::BOLD}FACTUAL & INFORMATION GAIN SIGNALS:#{Color::RESET}"
      puts "   • Statistics & Percentages     : #{data[:facts_and_citability][:percentage_mentions]}"
      puts "   • Currency / Pricing Signals   : #{data[:facts_and_citability][:currency_mentions]}"
      puts "   • Structured Bullet Items (<li>): #{data[:facts_and_citability][:bullet_list_items]}"
      puts "   • Comparison Table Rows (<tr>) : #{data[:facts_and_citability][:comparison_table_rows]}"
      puts "   • Recent Year Signals (2024-26): #{data[:facts_and_citability][:recent_year_mentions]}"

      puts "\n🏛️ #{Color::BOLD}ENTITY KNOWLEDGE GRAPH & SCHEMA:#{Color::RESET}"
      puts "   • Schemas Found                : #{data[:entity_knowledge_graph][:schema_count]} (#{data[:entity_knowledge_graph][:schema_types].join(', ')})"
      puts "   • Organization / Brand Schema  : #{data[:entity_knowledge_graph][:has_organization_or_brand] ? Color.c("Yes", Color::GREEN) : Color.c("Missing", Color::YELLOW)}"
      puts "   • FAQ / HowTo Rich Schema      : #{data[:entity_knowledge_graph][:has_faq_or_howto] ? Color.c("Yes", Color::GREEN) : Color.c("None", Color::YELLOW)}"
      puts "   • Wikidata / Wikipedia Linked  : #{data[:entity_knowledge_graph][:wikidata_or_wikipedia_linked] ? Color.c("Yes", Color::GREEN) : Color.c("No", Color::YELLOW)}"
      if data[:entity_knowledge_graph][:same_as_domains].any?
        puts "   • Social Authority Entity Links: #{data[:entity_knowledge_graph][:same_as_domains].join(', ')}"
      end

      recs = data[:recommendations] || []
      if recs.any?
        puts "\n💡 #{Color::BOLD}AI CITABILITY OPTIMIZATION RECOMMENDATIONS:#{Color::RESET}"
        recs.each_with_index do |r, i|
          puts "   #{i + 1}. #{Color.c(r, Color::YELLOW)}"
        end
      end
      puts ""
    end

    # 15. Knowledge Graph Entity & sameAs Disambiguation Auditor
    def self.handle_entity_command(target, options)
      raw = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
      if raw.nil? || raw.empty?
        puts Color.c("❌ Error: Target URL or domain required. Example: gsc entity https://mybrand.com", Color::RED)
        return
      end
      url = raw.to_s.start_with?('http') ? raw : "https://#{raw}"

      puts "🏛️  Auditing Knowledge Graph Entity & sameAs Identity for #{Color.c(url, Color::CYAN)}...\n" unless options[:json]

      data = GSC::EntityAuditor.audit(url)
      if data[:error]
        if options[:json]
          puts JSON.pretty_generate(data)
        else
          puts Color.c("❌ Error: #{data[:error]}", Color::RED, Color::BOLD)
        end
        return
      end

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🏛️  #{Color::BOLD}KNOWLEDGE GRAPH ENTITY & sameAs DISAMBIGUATION AUDIT#{Color::RESET}"
      puts "🎯 Target URL : #{Color.c(data[:url], Color::CYAN)}"
      puts "─" * 75

      score_color = case data[:score]
                    when 85..100 then Color::GREEN
                    when 70..84  then Color::CYAN
                    when 50..69  then Color::YELLOW
                    else              Color::RED
                    end

      puts "🏆 #{Color::BOLD}ENTITY AUTHORITY SCORE:#{Color::RESET} #{Color.c("#{data[:score]}/100", score_color, Color::BOLD)} — Grade #{data[:grade]}"
      puts "📦 Detected Entities : #{data[:entities_found]}"
      puts "─" * 75

      if data[:findings].any?
        puts "\n🔎 #{Color::BOLD}ENTITY SIGNALS DETECTED:#{Color::RESET}"
        data[:findings].each do |f|
          puts "   • #{Color.c(f, Color::GREEN)}"
        end
      end

      if data[:authoritative_links].any?
        puts "\n🌐 #{Color::BOLD}HIGH-AUTHORITY SAMEAS IDENTITY LINKS:#{Color::RESET}"
        data[:authoritative_links].each do |source, link|
          puts "   • #{source.to_s.capitalize.ljust(15)}: #{Color.c(link, Color::CYAN)}"
        end
      end

      if data[:recommendations].any?
        puts "\n💡 #{Color::BOLD}OPTIMIZATION DIRECTIVES:#{Color::RESET}"
        data[:recommendations].each_with_index do |r, i|
          puts "   #{i + 1}. #{Color.c(r, Color::YELLOW)}"
        end
      end

      if options[:generate] || data[:score] < 70
        puts "\n📋 #{Color::BOLD}RECOMMENDED ENHANCED JSON-LD SCHEMA SNIPPET:#{Color::RESET}"
        puts "<!-- Paste inside <head> on your homepage/about page -->"
        puts "<script type=\"application/ld+json\">"
        puts JSON.pretty_generate(data[:recommended_json_ld])
        puts "</script>"
      end
      puts ""
    end

    # 16. Multi-Domain Agency Vault & Key Manager
    def self.handle_vault_command(subcmd, target, extra, options)
      action = subcmd.to_s.downcase
      action = 'list' if action.empty? || action == 'vault'

      case action
      when 'status'
        stat = GSC::Vault.status
        if options[:json]
          puts JSON.pretty_generate(stat)
        else
          puts BANNER unless options[:in_dashboard]
          puts "🔐 #{Color::BOLD}AGENCY CREDENTIAL VAULT SECURITY STATUS#{Color::RESET}"
          puts "─" * 70
          puts "  • Vault Directory:       #{stat[:vault_dir]}"
          puts "  • Encryption Algorithm:  #{Color.c(stat[:encryption_algorithm], Color::GREEN, Color::BOLD)}"
          puts "  • Master Key Present:    #{stat[:master_key_present] ? Color.c('Yes (Stored locally)', Color::GREEN) : Color.c('Generated on demand', Color::YELLOW)}"
          puts "  • Stored Client Keys:    #{Color.c(stat[:keys_stored].to_s, Color::CYAN, Color::BOLD)}"
          puts "  • Domains Mapped:        #{Color.c(stat[:domains_mapped].to_s, Color::CYAN)}"
          puts "  • POSIX 0700 Security:   #{stat[:permissions_secure] ? Color.c('ENFORCED', Color::GREEN) : Color.c('PERMISSIVE', Color::YELLOW)}"
          puts "  • Active Target Domain:  #{Color.c(stat[:active_domain] || 'None', Color::GREEN, Color::BOLD)}"
          puts "─" * 70
          puts "💡 Switch active client anytime: #{Color.c('gsc switch <domain|alias|#>', Color::CYAN)}"
          puts ""
        end

      when 'add', 'import'
        key_path = target
        unless key_path && File.file?(File.expand_path(key_path))
          puts Color.c("❌ Error: Valid service account JSON path required. Example: gsc vault add ./client-key.json --domain client.com", Color::RED)
          return
        end

        domain = options[:domain] || extra
        alias_name = options[:alias]
        ga4_id = options[:property]

        begin
          entry = GSC::Vault.add_key(key_path, domain: domain, alias_name: alias_name, ga4_id: ga4_id)
          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', entry: entry })
          else
            puts Color.c("✅ Successfully encrypted and added key to Agency Vault!", Color::GREEN, Color::BOLD)
            puts "   • Client Email: #{Color.c(entry['client_email'], Color::CYAN)}"
            puts "   • Domain:       #{Color.c(entry['domain'] || 'Not set', Color::GREEN)}"
            puts "   • Alias:        #{Color.c(entry['alias'] || 'Not set', Color::YELLOW)}"
            puts "   • Key Vault:    #{entry['key_file']} (AES-256-GCM Encrypted)"
          end
        rescue StandardError => e
          puts Color.c("❌ Vault Error: #{e.message}", Color::RED)
        end

      when 'remove', 'rm', 'delete'
        target_query = target
        unless target_query
          puts Color.c("❌ Error: Specify domain or alias to remove. Example: gsc vault remove client.com", Color::RED)
          return
        end

        ok = GSC::Vault.remove_entry(target_query)
        if ok
          puts Color.c("✅ Removed #{target_query} from Agency Vault.", Color::GREEN)
        else
          puts Color.c("⚠️ Entry not found in Agency Vault: #{target_query}", Color::YELLOW)
        end

      when 'list', 'ls'
        entries = GSC::Vault.list_entries
        if options[:json]
          puts JSON.pretty_generate({ vault: GSC::Vault.status, entries: entries })
          return
        end

        puts BANNER unless options[:in_dashboard]
        puts "🔐 #{Color::BOLD}AGENCY CREDENTIAL VAULT (AES-256-GCM Secure Store)#{Color::RESET}"
        puts "─" * 75

        if entries.empty?
          puts Color.c("No client keys registered in Agency Vault yet.", Color::YELLOW)
          puts "To add a key: #{Color.c('gsc vault add /path/to/key.json --domain client.com --alias client', Color::CYAN)}"
          puts "─" * 75
          return
        end

        puts "#{Color::BOLD} #  | Domain                       | Alias      | Client Account / Email#{Color::RESET}"
        puts "─" * 75
        entries.each_with_index do |e, i|
          num_str = "[#{i + 1}]".ljust(4)
          dom_str = (e['domain'] || 'unassigned').ljust(28)
          alias_str = (e['alias'] || '-').ljust(10)
          email_str = e['client_email'].to_s
          marker = e['active'] ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""

          puts "#{Color.c(num_str, Color::CYAN)}| #{dom_str} | #{Color.c(alias_str, Color::YELLOW)} | #{email_str}#{marker}"
        end
        puts "─" * 75
        puts "💡 Switch active client anytime: #{Color.c('gsc switch <domain|alias|#>', Color::CYAN)}"
        puts ""
      else
        puts Color.c("Unknown vault action: #{action}. Valid actions: list, add, remove, status", Color::YELLOW)
      end
    end

    # 18. Direct Answer & Information Gain Snippet Synthesizer
    def self.handle_answer_command(query, options = {})
      if query.nil? || query.to_s.strip.empty?
        puts Color.c("❌ Error: Query required. Usage: gsc answer <query> [--brand <name>] [--type <definition|steps|comparison|faq>] [--generate] [--json]", Color::RED, Color::BOLD)
        return
      end

      data = GSC::AnswerSynthesizer.synthesize(query, options)

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
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

    # 19. AI Bot Robots.txt & Cloudflare Firewall Scanner
    def self.handle_firewall_command(target, options = {})
      scanner = GSC::FirewallScanner.new(target, options)
      data = scanner.scan

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts BANNER unless options[:in_dashboard]
      puts "🛡️  #{Color::BOLD}AI BOT ACCESSIBILITY & CLOUDFLARE/WAF FIREWALL AUDITOR#{Color::RESET}"
      puts "🎯 Target URL    : #{Color.c(data[:url], Color::YELLOW, Color::BOLD)}"
      puts "🌐 Hostname      : #{data[:host]}"

      # Edge Infrastructure
      edge_names = data[:edge_infrastructure].map { |i| "#{i[:name]} (#{i[:role]})" }.join(' | ')
      puts "☁️  Edge CDN/WAF  : #{Color.c(edge_names, Color::CYAN)}"

      # Score & Grade
      grade_color = case data[:grade]
                    when 'A' then Color::GREEN
                    when 'B' then Color::CYAN
                    when 'C' then Color::YELLOW
                    when 'D' then Color::RED
                    else Color::RED
                    end

      score_str = "#{data[:score]}/100 [Grade #{data[:grade]}]"
      puts "🏆 AI Access     : #{Color.c(score_str, Color::BOLD, grade_color)} - #{data[:verdict]}"
      puts "─" * 80

      # Section 1: Live HTTP Probes
      puts "\n#{Color::BOLD}📡 LIVE EDGE WAF MULTI-USER-AGENT PROBES (LIVE PASS-THROUGH):#{Color::RESET}"
      puts "#{Color::BOLD}%-18s %-24s %-12s %-10s %-14s %s#{Color::RESET}" % ['Persona', 'Client Name', 'HTTP Status', 'Latency', 'WAF Verdict', 'Challenge / Block']
      puts "─" * 80

      data[:live_probes].each do |probe|
        status_col = case probe[:status]
                     when 200..299 then Color.c("#{probe[:status]} OK", Color::GREEN)
                     when 300..399 then Color.c("#{probe[:status]} REDIR", Color::YELLOW)
                     when 403 then Color.c("403 FORBID", Color::RED, Color::BOLD)
                     when 503 then Color.c("503 UNAVAIL", Color::RED, Color::BOLD)
                     else Color.c(probe[:status].to_s, Color::RED)
                     end

        verdict_col = case probe[:verdict]
                      when :pass then Color.c("PASS", Color::GREEN)
                      when :redirect then Color.c("REDIRECT", Color::YELLOW)
                      when :challenge then Color.c("CHALLENGE", Color::RED, Color::BOLD)
                      when :blocked then Color.c("BLOCKED", Color::RED, Color::BOLD)
                      else Color.c("ERROR", Color::RED)
                      end

        challenges_str = probe[:challenges].empty? ? '-' : probe[:challenges].join(', ')
        challenges_col = probe[:challenges].empty? ? Color.c(challenges_str, Color::GRAY) : Color.c(challenges_str, Color::RED, Color::BOLD)

        puts "%-18s %-24s %-21s %-10s %-23s %s" % [
          probe[:persona],
          probe[:name],
          status_col,
          "#{probe[:duration_ms]}ms",
          verdict_col,
          challenges_col
        ]
      end

      # Section 2: Robots.txt Crawler Governance
      puts "\n#{Color::BOLD}🤖 ROBOTS.TXT AI SEARCH & TRAINING CRAWLER DIRECTIVES:#{Color::RESET}"
      puts "#{Color::BOLD}%-20s %-15s %-12s %-12s %s#{Color::RESET}" % ['Bot User-Agent', 'Provider', 'Role', 'Status', 'Matched Rule / Reason']
      puts "─" * 80

      data[:robots_txt][:bots].each do |bot_name, bot_info|
        status_col = case bot_info[:status]
                     when :allowed then Color.c("ALLOWED", Color::GREEN, Color::BOLD)
                     when :restricted then Color.c("RESTRICTED", Color::YELLOW)
                     when :blocked then Color.c("BLOCKED", Color::RED, Color::BOLD)
                     else Color.c("UNKNOWN", Color::GRAY)
                     end

        category_label = bot_info[:category].to_s.sub('_', ' ').capitalize

        puts "%-20s %-15s %-12s %-21s %s" % [
          bot_name,
          bot_info[:provider],
          category_label,
          status_col,
          Color.c(bot_info[:reason].to_s, Color::GRAY)
        ]
      end

      # Section 3: Blockade Diagnosis
      puts "\n#{Color::BOLD}🔍 SILENT BOT BLOCKADE DIAGNOSIS:#{Color::RESET}"
      diag = data[:blockade_diagnosis]
      if diag[:silent_blockade_detected]
        puts Color.c("   🚨 #{diag[:summary]}", Color::RED, Color::BOLD)
        puts "   ⚠️ Browser pass: #{diag[:browser_accessible]} | Googlebot pass: #{diag[:googlebot_accessible]}"
        puts "   ❌ Blocked AI crawlers: #{diag[:blocked_probes].map { |p| "#{p[:name]} (#{p[:status]})" }.join(', ')}"
      else
        puts Color.c("   #{diag[:summary]}", Color::GREEN)
      end

      # Section 4: Prescriptive WAF & Robots.txt Remediation Recipes
      recipes = data[:remediation_recipes]
      if recipes[:cloudflare_waf_rule]
        puts "\n#{Color::BOLD}🛠️  RECOMMENDED CLOUDFLARE CUSTOM WAF BYPASS RULE:#{Color::RESET}"
        puts "   Rule Name: #{Color.c(recipes[:cloudflare_waf_rule][:name], Color::CYAN, Color::BOLD)}"
        puts "   Expression:\n   #{Color.c(recipes[:cloudflare_waf_rule][:filter_expression], Color::YELLOW)}"
        puts "   Action: #{Color.c('Skip', Color::GREEN, Color::BOLD)} (Skip WAF Managed Rules, Super Bot Fight Mode, Rate Limiting)"
        puts "\n   #{Color::BOLD}Dashboard Deployment Steps:#{Color::RESET}"
        recipes[:cloudflare_waf_rule][:dashboard_instructions].each do |step|
          puts "   #{Color.c(step, Color::GRAY)}"
        end
      end

      if options[:generate] || diag[:silent_blockade_detected] || diag[:robots_critical_blocked].any?
        puts "\n#{Color::BOLD}📄 RECOMMENDED ROBOTS.TXT CONFIGURATION FOR AI SEARCH:#{Color::RESET}"
        puts Color.c(recipes[:recommended_robots_txt], Color::DIM)
      else
        puts "\n💡 #{Color.c('Tip: Pass --generate to display copy-paste robots.txt configuration.', Color::GRAY)}"
      end

      puts "─" * 80 + "\n"
    end

    # 20. Title Tag Length & Pixel Width Batch Optimizer
    def self.handle_titles_command(target, options = {})
      target_site = target.to_s.strip
      target_site = Config.default_domain || '' if target_site.empty?
      if target_site.empty?
        puts Color.c("❌ Error: Target domain or sitemap required. Example: gsc titles mybrand.com", Color::RED)
        return
      end

      optimizer = GSC::TitleOptimizer.new(target_site, options)

      unless options[:json] || options[:csv]
        puts BANNER unless options[:in_dashboard]
        puts "📏 #{Color::BOLD}GOOGLE SERP TITLE LENGTH & PIXEL OVERFLOW AUDITOR#{Color::RESET}"
        puts "🎯 Target: #{Color.c(target_site, Color::YELLOW, Color::BOLD)}"
        print "🔄 Crawling and calculating pixel metrics across pages... "
        $stdout.flush
      end

      data = optimizer.audit do |_url, current, total|
        unless options[:json] || options[:csv]
          print "\r🔄 Crawling and calculating pixel metrics across pages... [#{current}/#{total}]"
          $stdout.flush
        end
      end

      unless options[:json] || options[:csv]
        puts " Done!\n"
      end

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      if options[:csv]
        require 'csv'
        puts "URL,Characters,Pixel_Width,Status,Current_Title,Desktop_Preview,Suggested_Rewrite_1,Suggested_Rewrite_2"
        data[:pages].each do |p|
          r1 = p[:suggested_rewrites][0] ? p[:suggested_rewrites][0][:title].gsub('"', '""') : ''
          r2 = p[:suggested_rewrites][1] ? p[:suggested_rewrites][1][:title].gsub('"', '""') : ''
          title_clean = p[:title].to_s.gsub('"', '""')
          prev_clean = p[:desktop_preview].to_s.gsub('"', '""')
          puts "\"#{p[:url]}\",#{p[:char_count]},#{p[:pixel_width]},#{p[:status]},\"#{title_clean}\",\"#{prev_clean}\",\"#{r1}\",\"#{r2}\""
        end
        return
      end

      # Health Grade & Color
      grade_color = case data[:grade]
                    when 'A' then Color::GREEN
                    when 'B' then Color::CYAN
                    when 'C' then Color::YELLOW
                    when 'D' then Color::RED
                    else Color::RED
                    end

      puts "🏆 Title Health  : #{Color.c("#{data[:health_score]}/100 [Grade #{data[:grade]}]", Color::BOLD, grade_color)} - #{data[:verdict]}"
      puts "📊 Overview      : #{data[:total_pages]} Pages Audited | #{Color.c("#{data[:percentages][:optimal_pct]}% Optimal", Color::GREEN)} | #{Color.c("#{data[:percentages][:overflow_pct]}% Overflowing", Color::YELLOW)}"
      puts "📈 Breakdown     : ✅ #{data[:counts][:optimal]} Optimal | ⚠️ #{data[:counts][:desktop_overflow]} Desktop Overflow | 🚨 #{data[:counts][:critical_overflow]} Critical Overflow | ℹ️ #{data[:counts][:too_short]} Too Short | ❌ #{data[:counts][:missing]} Missing"
      puts "─" * 80

      pages_to_display = options[:overflow_only] ? data[:pages].select { |p| [:desktop_overflow, :critical_overflow].include?(p[:status]) } : data[:pages]

      if pages_to_display.empty?
        puts "\n🎉 #{Color.c('All audited pages have optimal title tags with zero pixel overflow!', Color::GREEN, Color::BOLD)}"
      else
        puts "\n#{Color::BOLD}%-16s %-7s %-10s %s#{Color::RESET}" % ['Status', 'Chars', 'Width', 'URL & Title Tag']
        puts "─" * 80

        pages_to_display.each do |page|
          status_col = case page[:status]
                       when :optimal then Color.c("OPTIMAL", Color::GREEN)
                       when :desktop_overflow then Color.c("DESK OVERFLOW", Color::YELLOW, Color::BOLD)
                       when :critical_overflow then Color.c("CRIT OVERFLOW", Color::RED, Color::BOLD)
                       when :too_short then Color.c("TOO SHORT", Color::CYAN)
                       when :missing then Color.c("MISSING", Color::RED, Color::BOLD)
                       end

          px_str = "#{page[:pixel_width]}px"
          px_col = page[:pixel_width] > 580.0 ? Color.c(px_str, Color::RED, Color::BOLD) : Color.c(px_str, Color::GREEN)

          puts "%-23s %-7s %-18s %s" % [
            status_col,
            "#{page[:char_count]}c",
            px_col,
            Color.c(page[:url], Color::BOLD)
          ]
          puts "   ↳ #{Color.c(page[:title].empty? ? '(No Title Tag)' : page[:title], Color::DIM)}"
        end
      end

      # Section: Title Rewrite Optimization Playbook
      overflowing_pages = data[:pages].reject { |p| p[:suggested_rewrites].empty? }

      if overflowing_pages.any?
        puts "\n\n#{Color::BOLD}📝 TITLE REWRITE & CTR OPTIMIZATION PLAYBOOK (#{overflowing_pages.size} Pages Flagged):#{Color::RESET}"
        puts "─" * 80

        overflowing_pages.first(8).each_with_index do |p, idx|
          puts "\n#{Color.c("[#{idx + 1}]", Color::CYAN, Color::BOLD)} #{Color.c(p[:url], Color::BOLD)}"
          puts "   ❌ Current Title  : #{Color.c("\"#{p[:title]}\"", Color::RED)} (#{p[:pixel_width]}px, #{p[:char_count]} chars)"
          puts "   👀 Desktop SERP   : #{Color.c(p[:desktop_preview], Color::GRAY)}"

          puts "   💡 #{Color::BOLD}Synthesized Non-Truncating Title Rewrites (<560px):#{Color::RESET}"
          p[:suggested_rewrites].each do |rewrite|
            puts "      • [#{Color.c(rewrite[:type], Color::YELLOW)}] #{Color.c(rewrite[:title], Color::GREEN, Color::BOLD)}"
            puts "        ↳ #{rewrite[:pixel_width]}px | #{rewrite[:char_count]} chars | Desktop SERP: #{Color.c('FITS CLEANLY', Color::GREEN)}"
          end
        end

        if overflowing_pages.size > 8
          puts "\n... and #{overflowing_pages.size - 8} more pages flagged. Run with #{Color.c('--csv', Color::CYAN)} or #{Color.c('--json', Color::CYAN)} to export all rewrites."
        end
      end

      puts "\n" + ("─" * 80) + "\n"
    end
  end
end



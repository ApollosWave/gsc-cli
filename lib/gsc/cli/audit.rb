# frozen_string_literal: true

require 'json'
require 'cgi'
require 'uri'
require_relative 'base'
require_relative '../open_pagerank' if File.exist?(File.expand_path('../open_pagerank.rb', __dir__))
require_relative '../pagespeed' if File.exist?(File.expand_path('../pagespeed.rb', __dir__))
require_relative '../speed_correlator' if File.exist?(File.expand_path('../speed_correlator.rb', __dir__))
require_relative '../page_comparator' if File.exist?(File.expand_path('../page_comparator.rb', __dir__))
require_relative '../content_gap' if File.exist?(File.expand_path('../content_gap.rb', __dir__))
require_relative '../internal_links' if File.exist?(File.expand_path('../internal_links.rb', __dir__))
require_relative '../schema_validator' if File.exist?(File.expand_path('../schema_validator.rb', __dir__))
require_relative '../llms_generator' if File.exist?(File.expand_path('../llms_generator.rb', __dir__))
require_relative '../network_tracer' if File.exist?(File.expand_path('../network_tracer.rb', __dir__))
require_relative '../robots_checker' if File.exist?(File.expand_path('../robots_checker.rb', __dir__))
require_relative '../backlinks_manager' if File.exist?(File.expand_path('../backlinks_manager.rb', __dir__))
require_relative '../geo_auditor' if File.exist?(File.expand_path('../geo_auditor.rb', __dir__))
require_relative '../entity_auditor' if File.exist?(File.expand_path('../entity_auditor.rb', __dir__))
require_relative '../firewall_scanner' if File.exist?(File.expand_path('../firewall_scanner.rb', __dir__))
require_relative '../title_optimizer' if File.exist?(File.expand_path('../title_optimizer.rb', __dir__))
require_relative '../page_analyzer' if File.exist?(File.expand_path('../page_analyzer.rb', __dir__))
require_relative '../site_crawler' if File.exist?(File.expand_path('../site_crawler.rb', __dir__))

module GSC
  class CLI
    module Audit
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil, https_origin = nil)
        case command
        when 'authority', 'opr', 'da', 'domain-authority'
          handle_authority(target, extra, options)
        when 'speed', 'vitals', 'pagespeed', 'psi'
          handle_speed(target, options)
        when 'speed-correlate', 'cwv-correlate', 'sc-perf'
          handle_speed_correlate(target, options)
        when 'compare', 'diff-seo', 'vs'
          handle_compare(target, extra, options)
        when 'content-gap', 'gap'
          handle_content_gap(target, extra, options)
        when 'internal-links', 'orphans', 'links-audit'
          handle_internal_links(target, options)
        when 'schema', 'rich-snippets', 'ld-json'
          handle_schema(target, extra, options)
        when 'llms', 'ai-ready'
          handle_llms(target, extra, options, api, site_url)
        when 'trace', 'redirects', 'hops'
          handle_trace(target, options)
        when 'robots', 'robots-txt'
          handle_robots(target, extra, options)
        when 'backlinks', 'links'
          handle_backlinks(target, extra, options)
        when 'geo', 'aeo', 'citability'
          handle_geo(target, options)
        when 'entity', 'kg', 'knowledge-graph'
          handle_entity(target, options)
        when 'firewall', 'ai-bots', 'waf-scan', 'bot-firewall'
          handle_firewall(target, options)
        when 'titles', 'title-opt', 'pixel-titles', 'title-tags'
          handle_titles(target, options)
        when 'headings', 'h1', 'heading-structure'
          handle_headings(target, options)
        when 'page', 'page-audit'
          handle_page(target, site_url, api, options)
        when 'site-audit', 'site-crawl', 'crawl'
          handle_site_crawl(target, site_url, api, options)
        when 'audit', 'a'
          run_comprehensive_audit(api, site_url, hostname, https_origin, options)
        else
          raise "Unknown audit command: #{command}"
        end
      end

      def handle_authority(target, extra, options)
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

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_speed(target, options)
        url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or domain required. Example: gsc speed https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or domain required. Example: gsc speed https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        url = "https://#{url}" unless url =~ %r{^https?://}
        strategy = options[:strategy] || 'mobile'

        puts Base::BANNER unless options[:json] || options[:in_dashboard]
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
          assessment = data[:cwv_assessment] || data[:overall_category] || "UNKNOWN"
          assessment_badge = case assessment
          when 'PASSED', 'FAST'
            Color.c("PASSED (All 3 Metrics Good)", Color::GREEN, Color::BOLD)
          when 'NEEDS IMPROVEMENT', 'AVERAGE'
            Color.c("NEEDS IMPROVEMENT", Color::YELLOW, Color::BOLD)
          when 'POOR', 'SLOW', 'FAILED'
            Color.c("FAILED (Poor Metrics Detected)", Color::RED, Color::BOLD)
          else
            Color.c(assessment, Color::YELLOW, Color::BOLD)
          end
          puts "\n#{Color::BOLD}🌐 CrUX FIELD DATA (28-Day Real User Monitoring - #{source_label}):#{Color::RESET}"
          puts "   • Core Web Vitals Assessment    : #{assessment_badge}"

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

      def handle_speed_correlate(target, options)
        domain = options[:domain] || (target =~ /\.(com|org|net|io|app|co|dev|store)$/i ? target : nil) || Config.default_domain
        url = target || (domain ? "https://#{domain}/" : nil)
        unless url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or domain required. Example: gsc speed-correlate https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or domain required. Example: gsc speed-correlate https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        domain ||= URI.parse(url).host.to_s.sub(/^www\./, '') rescue 'site'
        url = "https://#{url}" unless url =~ %r{^https?://}
        strategy = options[:strategy] || 'mobile'
        days = (options[:days] || 28).to_i

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

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_compare(target, extra, options)
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

        puts Base::BANNER unless options[:in_dashboard]
        puts "🥊 #{Color::BOLD}HEAD-TO-HEAD SEO ON-PAGE COMPARISON:#{Color::RESET}"
        puts "   Page 1 (Target):     #{Color.c(url1, Color::CYAN)}"
        puts "   Page 2 (Competitor): #{Color.c(url2, Color::YELLOW)}"
        puts "─" * 80

        c = data[:comparison] || {}

        t1 = c.dig(:meta, :title, :page1) || {}
        t2 = c.dig(:meta, :title, :page2) || {}
        puts "\n#{Color::BOLD}📑 TITLE TAG:#{Color::RESET}"
        puts "   P1: #{t1[:text]} (#{t1[:length]} chars) [#{t1[:optimal] ? Color.c('Optimal', Color::GREEN) : Color.c('Review', Color::YELLOW)}]"
        puts "   P2: #{t2[:text]} (#{t2[:length]} chars) [#{t2[:optimal] ? Color.c('Optimal', Color::GREEN) : Color.c('Review', Color::YELLOW)}]"

        h = c[:headings] || {}
        puts "\n#{Color::BOLD}🏷️ HEADINGS H1 / H2:#{Color::RESET}"
        puts "   P1: #{h.dig(:h1_count, :page1)} H1s | #{h.dig(:h2_count, :page1)} H2s"
        puts "   P2: #{h.dig(:h1_count, :page2)} H1s | #{h.dig(:h2_count, :page2)} H2s"

        img = c[:images] || {}
        puts "\n#{Color::BOLD}🖼️ IMAGES & ACCESSIBILITY:#{Color::RESET}"
        puts "   P1: #{img.dig(:total_images, :page1)} images (#{img.dig(:missing_alt, :page1)} missing alt)"
        puts "   P2: #{img.dig(:total_images, :page2)} images (#{img.dig(:missing_alt, :page2)} missing alt)"

        l = c[:links] || {}
        puts "\n#{Color::BOLD}🔗 LINK COUNTS:#{Color::RESET}"
        puts "   P1: #{l.dig(:internal, :page1)} internal | #{l.dig(:external, :page1)} external"
        puts "   P2: #{l.dig(:internal, :page2)} internal | #{l.dig(:external, :page2)} external"

        s = c[:structured_data] || {}
        puts "\n#{Color::BOLD}📦 STRUCTURED DATA (JSON-LD):#{Color::RESET}"
        puts "   P1: #{s.dig(:schema_count, :page1)} schemas #{(s.dig(:schema_types, :page1) || []).inspect}"
        puts "   P2: #{s.dig(:schema_count, :page2)} schemas #{(s.dig(:schema_types, :page2) || []).inspect}"

        p_time = c[:performance] || {}
        puts "\n#{Color::BOLD}⚡ RESPONSE TIME:#{Color::RESET}"
        puts "   P1: #{p_time.dig(:response_time_ms, :page1)}ms | P2: #{p_time.dig(:response_time_ms, :page2)}ms"
        puts ""
      end

      def handle_content_gap(target, extra, options)
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

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_internal_links(target, options)
        base_url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless base_url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or domain required. Example: gsc orphans https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or domain required. Example: gsc orphans https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        conc = options[:concurrency] || 5
        il = GSC::InternalLinks.new(base_url, limit: options[:limit] || 50, concurrency: conc)

        puts Base::BANNER unless options[:json] || options[:in_dashboard]
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
          Base.write_csv(options[:csv], %w[OrphanURL Depth RecommendedRescueSources], csv_data)
          puts Color.c("\n📁 Exported orphan rescue playbook to #{options[:csv]}", Color::CYAN)
        end

        puts "\n" + ("─" * 80) + "\n"
      end

      def handle_schema(target, extra, options)
        type_str = target.to_s.downcase
        supported_types = GSC::SchemaValidator::AVAILABLE_TEMPLATES.map { |t| t[:type] }

        if %w[list templates types help].include?(type_str) || (target.nil? && !Config.default_domain)
          render_schema_templates_list(options)
          return
        end

        if target == 'generate' || target == 'gen' || supported_types.include?(type_str)
          schema_type = (target == 'generate' || target == 'gen') ? (extra || 'faq') : target
          tpl = GSC::SchemaValidator.generate_template(schema_type)
          if options[:json]
            puts JSON.pretty_generate(tpl)
          else
            puts Color.c("📋 Generated JSON-LD Schema (#{schema_type}):", Color::GREEN, Color::BOLD)
            puts "<script type=\"application/ld+json\">"
            puts JSON.pretty_generate(tpl)
            puts "</script>"
            puts "\n" + Color.gray("💡 Available templates: ") + Color.cyan(supported_types.join(', '))
            puts Color.gray("   Run `gsc schema list` to view all templates and Google Rich Result features.")
            puts Color.gray("   Tip: Run `gsc schema-gen <url> --type #{schema_type}` to extract and auto-fill from a live page.")
            puts Color.gray("   Test live in Google's Rich Results Tool: https://search.google.com/test/rich-results")
            if options[:open]
              puts Color.green("\n🚀 Opening Google Rich Results Test (Code Tab) in your browser...")
              Base.open_in_browser("https://search.google.com/test/rich-results")
            end
            puts
          end
          return
        end

        url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or schema type required. Example: gsc schema https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or schema type required. Example: gsc schema https://mysite.com", Color::RED, Color::BOLD)
            puts "   Run `gsc schema list` to view all available JSON-LD templates."
          end
          return
        end
        sv = GSC::SchemaValidator.new(url)
        data = sv.audit

        rich_test_url = url =~ %r{^https?://} ? "https://search.google.com/test/rich-results?url=#{CGI.escape(url)}" : "https://search.google.com/test/rich-results"

        if options[:json]
          data[:google_rich_results_test_url] = rich_test_url
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
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

        puts "\n" + Color.bold("🌐 OFFICIAL GOOGLE RICH RESULTS TEST TOOL:")
        puts "   #{Color.cyan(rich_test_url)}"
        if options[:open]
          puts Color.green("\n🚀 Opening Google Rich Results Test in your browser...")
          Base.open_in_browser(rich_test_url)
        end
        puts ""
      end

      def render_schema_templates_list(options)
        templates = GSC::SchemaValidator::AVAILABLE_TEMPLATES
        if options[:json]
          puts JSON.pretty_generate(templates)
          return
        end

        puts "\n" + Color.cyan("╔" + "═" * 78 + "╗")
        puts Color.cyan("║") + Color.bold("   📦 AVAILABLE GOOGLE RICH SNIPPET SCHEMA TEMPLATES                          ") + Color.cyan("║")
        puts Color.cyan("╚" + "═" * 78 + "╝")
        puts "  Generate ready-to-paste JSON-LD structured data or auto-fill from any live URL."
        puts Color.cyan("─" * 80)
        puts sprintf("  %-16s %-45s %s", Color.bold("Schema Type"), Color.bold("Google SERP Feature"), Color.bold("Command Example"))
        puts Color.gray("  " + "─" * 76)

        templates.each do |tpl|
          type_col = Color.cyan(tpl[:type].ljust(14))
          feature_col = tpl[:feature].ljust(43)
          example_col = Color.gray("gsc schema #{tpl[:type]}")
          puts "  #{type_col} #{feature_col} #{example_col}"
        end

        puts Color.cyan("─" * 80)
        puts Color.bold("💡 USAGE & WORKFLOWS:")
        puts "   1. Generate Clean Template:     " + Color.green("gsc schema <type>") + Color.gray(" (e.g. gsc schema product)")
        puts "   2. Auto-Extract from Live URL:  " + Color.green("gsc schema-gen <url> --type <type>")
        puts "   3. Audit Page for Rich Schema:  " + Color.green("gsc schema <url>") + Color.gray(" (or `gsc rich-results <url>`)")
        puts "   4. Live Googlebot Verification: " + Color.green("gsc inspect <url>")
        puts Color.cyan("═" * 80) + "\n"
      end

      def handle_llms(target, extra, options, api = nil, site_url = nil)
        base_url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless base_url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or domain required. Example: gsc llms https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or domain required. Example: gsc llms https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        base_url = "https://#{base_url}" unless base_url =~ %r{^https?://}
        llms = GSC::LlmsGenerator.new(base_url, options)

        if extra == 'audit' || options[:audit]
          data = llms.audit_ai_readability(base_url)
          if options[:json]
            puts JSON.pretty_generate(data)
          else
            puts Base::BANNER unless options[:in_dashboard]
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
        elsif options[:package] || options[:bundle] || extra == 'bundle' || extra == 'package'
          # Fetch GSC search queries for FAQ injection if available
          gsc_rows = nil
          if api && site_url
            res = api.query_analytics(
              site_url: site_url,
              start_date: (Date.today - 28).to_s,
              end_date: Date.today.to_s,
              dimensions: ['page', 'query'],
              row_limit: 1000
            ) rescue nil
            gsc_rows = res.dig(:data, 'rows') || res['rows'] if res
          end

          output_dir = options[:write] || (options[:save] ? '.' : nil)
          bundle = llms.package_agent_bundle(output_dir: output_dir, limit: (options[:limit] || 25).to_i, gsc_rows: gsc_rows)

          if options[:json]
            puts JSON.pretty_generate(bundle)
            return
          end

          puts Base::BANNER unless options[:in_dashboard]
          puts "📦 #{Color::BOLD}AI AGENT MULTI-PAGE KNOWLEDGE PACKAGER (Turn 23):#{Color::RESET} #{Color.c(base_url, Color::CYAN)}"
          puts "─" * 76
          puts "  Base Domain:            #{Color.c(base_url, Color::CYAN)}"
          puts "  Pages Packaged:         #{Color.bold(bundle[:total_pages_packaged].to_s)}"
          puts "  /llms.txt Size:         #{Color.green("#{bundle.dig(:llms_txt, :chars)} chars")} (#{bundle.dig(:llms_txt, :tokens)} tokens)"
          puts "  /llms-full.txt Size:    #{Color.green("#{bundle.dig(:llms_full_txt, :chars)} chars")} (#{bundle.dig(:llms_full_txt, :tokens)} tokens)"
          puts "\n  LLM Context Window Feasibility:"
          puts "   • Claude 3.5 Sonnet (200k) : #{bundle.dig(:context_window_fit, :claude_3_5_sonnet_200k) ? '✅ Fits cleanly' : '⚠️ Exceeds context'}"
          puts "   • GPT-4o / GPT-5 (128k)    : #{bundle.dig(:context_window_fit, :gpt_4o_128k) ? '✅ Fits cleanly' : '⚠️ Exceeds context'}"
          puts "   • Gemini 1.5 Pro (1M)      : #{bundle.dig(:context_window_fit, :gemini_1_5_pro_1m) ? '✅ Fits cleanly' : '⚠️ Exceeds context'}"

          if bundle[:saved_files].any?
            puts "\n  Saved Files:"
            bundle[:saved_files].each do |f|
              puts "   ✓ #{f[:path]} (#{f[:size_bytes]} bytes)"
            end
          else
            puts "\n  Tip: Run with `--write` to export /llms.txt and /llms-full.txt directly to your project root."
          end
          puts "─" * 76
          puts ""
        elsif options[:full] || extra == 'full'
          # Generate /llms-full.txt
          gsc_rows = nil
          if api && site_url
            res = api.query_analytics(
              site_url: site_url,
              start_date: (Date.today - 28).to_s,
              end_date: Date.today.to_s,
              dimensions: ['page', 'query'],
              row_limit: 1000
            ) rescue nil
            gsc_rows = res.dig(:data, 'rows') || res['rows'] if res
          end

          content = llms.generate_llms_full_txt(limit: (options[:limit] || 25).to_i, gsc_rows: gsc_rows)
          if options[:save] || options[:write]
            out_file = options[:write] && options[:write] != '.' ? File.join(options[:write], 'llms-full.txt') : 'llms-full.txt'
            File.write(out_file, content, encoding: 'UTF-8')
            puts Color.c("✅ Successfully wrote #{out_file} (#{content.length} chars, ~#{(content.length/4.0).ceil} tokens)!", Color::GREEN)
          else
            puts content
          end
        else
          content = llms.generate_llms_txt(limit: (options[:limit] || 25).to_i)
          if options[:save] || options[:write]
            out_file = options[:write] && options[:write] != '.' ? File.join(options[:write], 'llms.txt') : 'llms.txt'
            File.write(out_file, content, encoding: 'UTF-8')
            puts Color.c("✅ Successfully wrote #{out_file} to current directory!", Color::GREEN)
          else
            puts content
          end
        end
      end

      def handle_trace(target, options)
        url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL required. Example: gsc trace https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL required. Example: gsc trace https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        nt = GSC::NetworkTracer.new(url)
        data = nt.trace

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_robots(target, extra, options)
        url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or domain required. Example: gsc robots https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or domain required. Example: gsc robots https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        path = extra || '/'
        bot = options[:bot] || 'googlebot'

        rc = GSC::RobotsChecker.new(url)
        data = rc.check(path, bot)

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_backlinks(target, extra, options)
        domain = target || Config.default_domain
        unless domain
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc backlinks mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc backlinks mysite.com", Color::RED, Color::BOLD)
          end
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

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_geo(target, options)
        url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL required. Example: gsc geo https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL required. Example: gsc geo https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
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

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_entity(target, options)
        url = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL required. Example: gsc entity https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL required. Example: gsc entity https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        url = "https://#{url}" unless url =~ %r{^https?://}

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

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_firewall(target, options = {})
        scanner = GSC::FirewallScanner.new(target, options)
        data = scanner.scan

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "🛡️  #{Color::BOLD}AI BOT ACCESSIBILITY & CLOUDFLARE/WAF FIREWALL AUDITOR#{Color::RESET}"
        puts "🎯 Target URL    : #{Color.c(data[:url], Color::YELLOW, Color::BOLD)}"
        puts "🌐 Hostname      : #{data[:host]}"

        edge_names = data[:edge_infrastructure].map { |i| "#{i[:name]} (#{i[:role]})" }.join(' | ')
        puts "☁️  Edge CDN/WAF  : #{Color.c(edge_names, Color::CYAN)}"

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

        puts "\n#{Color::BOLD}🔍 SILENT BOT BLOCKADE DIAGNOSIS:#{Color::RESET}"
        diag = data[:blockade_diagnosis]
        if diag[:silent_blockade_detected]
          puts Color.c("   🚨 #{diag[:summary]}", Color::RED, Color::BOLD)
          puts "   ⚠️ Browser pass: #{diag[:browser_accessible]} | Googlebot pass: #{diag[:googlebot_accessible]}"
          puts "   ❌ Blocked AI crawlers: #{diag[:blocked_probes].map { |p| "#{p[:name]} (#{p[:status]})" }.join(', ')}"
        else
          puts Color.c("   #{diag[:summary]}", Color::GREEN)
        end

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

      def handle_titles(target, options = {})
        target_site = target.to_s.strip
        target_site = Config.default_domain.to_s.strip if target_site.empty?
        if target_site.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target domain required. Example: gsc titles mysite.com' })
          else
            puts Color.c("❌ Error: Target domain required. Example: gsc titles mysite.com", Color::RED, Color::BOLD)
          end
          return
        end

        optimizer = GSC::TitleOptimizer.new(target_site, options)

        unless options[:json] || options[:csv]
          puts Base::BANNER unless options[:in_dashboard]
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

      def handle_headings(target, options = {})
        url_or_path = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url_or_path
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL or file required. Example: gsc headings https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL or file required. Example: gsc headings https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        puts Base::BANNER unless options[:json] || options[:in_dashboard]

        analyzer = PageAnalyzer.new(url_or_path)
        puts "🔍 Validating Heading Hierarchy (H1-H6) for: #{Color.c(url_or_path, Color::CYAN)}...\n" unless options[:json]

        data = analyzer.fetch_and_analyze
        h = data[:headings]

        if options[:json]
          puts JSON.pretty_generate({
            url: data[:url],
            http_status: data[:http_status],
            score: h[:score],
            grade: h[:grade],
            depth: h[:depth],
            total_headings: h[:count],
            h1_count: h[:h1_count],
            counts: h[:counts],
            empty_count: h[:empty_count],
            violations: h[:violations],
            keyword_analysis: h[:keyword_analysis],
            headings: h[:list],
            ascii_tree: h[:ascii_tree]
          })
          return
        end

        status_color = data[:http_status] == 200 ? Color::GREEN : Color::YELLOW
        score_color = (h[:score] || 0) >= 80 ? Color::GREEN : ((h[:score] || 0) >= 60 ? Color::YELLOW : Color::RED)

        puts "📍 URL:              #{Color.c(data[:url], Color::CYAN, Color::BOLD)}"
        puts "⚡ HTTP Status:      #{Color.c(data[:http_status].to_s, status_color, Color::BOLD)} (#{data[:response_time_ms]}ms)"
        puts "🏆 Heading Health:   #{Color.c("#{h[:score]}/100 (Grade #{h[:grade]})", score_color, Color::BOLD)}"
        puts "📊 Total Headings:   #{h[:count]} (Max Depth: H#{h[:depth]})"

        counts_summary = (h[:counts] || {}).select { |_k, v| v > 0 }.map { |k, v| "#{v}x #{k.upcase}" }.join(' | ')
        puts "🔢 Tag Distribution: #{counts_summary.empty? ? 'None' : counts_summary}"
        puts "─" * 80

        puts "\n#{Color::BOLD}🌲 HEADING HIERARCHY TREE:#{Color::RESET}"
        if h[:color_tree] && !h[:color_tree].strip.empty?
          puts h[:color_tree]
        else
          puts "   (No headings found on page)"
        end

        if h[:violations] && !h[:violations].empty?
          puts "\n#{Color::BOLD}⚠️  SEMANTIC HIERARCHY VIOLATIONS (#{h[:violations].size} detected):#{Color::RESET}"
          h[:violations].each_with_index do |v, idx|
            badge = case v[:severity]
                    when :critical then Color.c("[CRITICAL]", Color::RED, Color::BOLD)
                    when :warning then Color.c("[WARNING]", Color::YELLOW, Color::BOLD)
                    else Color.c("[INFO]", Color::GRAY)
                    end
            puts "   #{idx + 1}. #{badge} #{v[:message]}"
          end
        else
          puts "\n#{Color.c('✅ 100% Semantic Heading Structure Compliance (No hierarchy violations found)', Color::GREEN, Color::BOLD)}"
        end

        if options[:keyword] && h[:keyword_analysis]
          ka = h[:keyword_analysis]
          puts "\n#{Color::BOLD}🎯 KEYWORD HEADING RELEVANCE (#{options[:keyword]}):#{Color::RESET}"
          h1_status = ka[:h1_has_keyword] ? Color.c("Found in H1 ✅", Color::GREEN) : Color.c("Missing from H1 ❌", Color::YELLOW)
          puts "   H1 Optimization:  #{h1_status}"
          puts "   H2 Occurrences:   #{ka[:h2_matched_count]} H2 sections contain target keyword"
        end

        puts "\n" + ("─" * 80) + "\n"
      end

      def handle_page(target, site_url, api, options = {})
        url_or_path = target || (Config.default_domain ? "https://#{Config.default_domain}" : nil)
        unless url_or_path
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target URL required. Example: gsc page https://mysite.com' })
          else
            puts Color.c("❌ Error: Target URL required. Example: gsc page https://mysite.com", Color::RED, Color::BOLD)
          end
          return
        end
        puts Base::BANNER unless options[:json] || options[:in_dashboard]

        analyzer = PageAnalyzer.new(url_or_path)
        puts "🔍 Auditing On-Page DOM & GSC Performance for: #{Color.c(url_or_path, Color::CYAN)}...\n" unless options[:json]

        data = analyzer.fetch_and_analyze(
          check_links: options[:check_links] || false,
          gsc_api: api,
          active_domain: site_url
        )

        if options[:json]
          puts JSON.pretty_generate(data)
          return
        end

        status_color = data[:http_status] == 200 ? Color::GREEN : Color::YELLOW
        puts "📍 URL:           #{Color.c(data[:url], Color::CYAN, Color::BOLD)}"
        puts "⚡ HTTP Status:   #{Color.c(data[:http_status].to_s, status_color, Color::BOLD)} (#{data[:response_time_ms]}ms) | Indexability: #{Color.c(data[:indexability][:status], data[:indexability][:status] == 'INDEXABLE' ? Color::GREEN : Color::RED, Color::BOLD)}"
        puts "─" * 80

        title = data[:title]
        t_color = title[:ok] ? Color::GREEN : Color::YELLOW
        puts "\n#{Color::BOLD}📑 ON-PAGE METADATA (Detailed SEO Engine):#{Color::RESET}"
        puts "   Title:         #{Color.c(title[:text].empty? ? '(Missing)' : title[:text], Color::BOLD)} [#{Color.c("#{title[:length]} chars / ~#{title[:pixel_est]}px", t_color)}]"
        meta = data[:meta_description]
        m_color = meta[:ok] ? Color::GREEN : Color::YELLOW
        puts "   Meta Desc:     #{meta[:text].empty? ? Color.c('(Missing)', Color::YELLOW) : meta[:text]} [#{Color.c("#{meta[:length]} chars", m_color)}]"
        canon = data[:canonical]
        canon_str = canon[:url] ? (canon[:self_referencing] ? "#{canon[:url]} (Self-Referencing ✅)" : "#{canon[:url]} (Canonicalised ⚠️)") : '(None)'
        puts "   Canonical:     #{canon_str}"
        puts "   Word Count:    #{data[:stats][:word_count]} words (~#{data[:stats][:reading_time_mins]} min read)"

        h = data[:headings]
        h_badge = h[:h1_count] == 1 ? Color.c("1x H1 ✅", Color::GREEN) : Color.c("#{h[:h1_count]}x H1 ⚠️", Color::RED)
        score_badge = h[:score] ? " | Health Score: #{Color.c("#{h[:score]}/100", (h[:score] >= 80 ? Color::GREEN : Color::YELLOW), Color::BOLD)} (Grade #{h[:grade]})" : ""
        puts "\n#{Color::BOLD}🏷️ HEADINGS HIERARCHY (#{h[:count]} total, #{h_badge}#{score_badge}):#{Color::RESET}"
        if h[:color_tree] && !h[:color_tree].strip.empty?
          puts h[:color_tree]
        else
          h[:list].first(8).each do |heading|
            indent = "   " + ("  " * (heading[:tag][1].to_i - 1))
            tag_badge = Color.c("[#{heading[:tag].upcase}]", Color::MAGENTA)
            puts "#{indent}#{tag_badge} #{heading[:text]}"
          end
          puts "   ... and #{h[:count] - 8} more headings" if h[:count] > 8
        end

        img = data[:images]
        img_color = img[:missing_alt_count] == 0 ? Color::GREEN : Color::YELLOW
        puts "\n#{Color::BOLD}🖼️ IMAGES & LINKS:#{Color::RESET}"
        puts "   Images:        #{img[:total]} total (#{Color.c("#{img[:missing_alt_count]} missing alt tags", img_color)})"
        if img[:missing_alt_count] > 0
          img[:missing_alt_images].first(3).each do |i|
            puts "                  ⚠️ Missing Alt: #{Color.c(i[:src].to_s[0..60], Color::GRAY)}"
          end
        end
        lnk = data[:links]
        puts "   Links:         #{lnk[:total]} total (#{lnk[:internal_count]} Internal, #{lnk[:external_count]} External, #{lnk[:nofollow_count]} Nofollow)"
        if data.dig(:links, :verification)
          broken = data[:links][:verification].reject { |l| l[:ok] }
          if broken.empty?
            puts "   Link Health:   #{Color.c('All verified links OK (HTTP 200) ✅', Color::GREEN)}"
          else
            puts "   Broken Links:  #{Color.c("#{broken.size} dead links found 🔴", Color::RED, Color::BOLD)}"
            broken.each do |b|
              puts "                  ❌ [HTTP #{b[:status]}] #{b[:href]} (Anchor: #{b[:anchor]})"
            end
          end
        elsif !options[:check_links]
          puts "   Link Health:   #{Color.c('(Pass --check-links to test HTTP status of every link)', Color::GRAY)}"
        end

        s_list = data[:schema]
        puts "\n#{Color::BOLD}💎 STRUCTURED DATA (Schema.org JSON-LD):#{Color::RESET}"
        if s_list.empty?
          puts "   #{Color.c('No JSON-LD schema found on this page.', Color::YELLOW)}"
        else
          types = s_list.flat_map { |s| s[:types] }.compact.uniq
          puts "   Detected Schemas: #{Color.c(types.join(', '), Color::GREEN, Color::BOLD)}"
        end

        if data[:gsc]
          g = data[:gsc]
          puts "\n#{Color::BOLD}📊 GOOGLE SEARCH CONSOLE PERFORMANCE (Past 90 Days):#{Color::RESET}"
          puts "   Total Clicks:       #{Color.c(g[:total_clicks].to_s, Color::CYAN, Color::BOLD)}"
          puts "   Total Impressions:  #{Color.c(g[:total_impressions].to_s, Color::CYAN, Color::BOLD)}"
          puts "   Average CTR:        #{Color.c("#{g[:ctr]}%", Color::CYAN, Color::BOLD)}"
          puts "   Average Position:   #{Color.c(g[:avg_position].to_s, Color::CYAN, Color::BOLD)}"
          if g[:top_queries] && !g[:top_queries].empty?
            puts "   Top Ranking Queries:"
            g[:top_queries].each do |q|
              puts "     • #{Color.c(q[:query], Color::YELLOW)} (Pos #{q[:position]}, #{q[:impressions]} imp, #{q[:clicks]} clicks)"
            end
          end
        end

        puts "\n" + ("─" * 80)
        if data[:issues].empty?
          puts Color.c("✅ EXCELLENT! No SEO defects or hierarchy flaws detected.", Color::GREEN, Color::BOLD)
        else
          puts "#{Color::BOLD}⚠️ ACTIONABLE ISSUES FOUND (#{data[:issues].size}):#{Color::RESET}"
          data[:issues].each do |issue|
            badge = issue[:level] == :error || issue[:level] == :critical ? Color.c("[ERROR]", Color::RED, Color::BOLD) : Color.c("[WARN]", Color::YELLOW, Color::BOLD)
            puts "   #{badge} #{issue[:message]}"
          end
        end
        puts ("─" * 80) + "\n"
      end

      def handle_site_crawl(target, site_url, api, options = {})
        sitemap_target = target || (Config.default_domain ? "https://#{Config.default_domain}/sitemap.xml" : nil)
        unless sitemap_target
          if options[:json]
            puts JSON.pretty_generate({ error: 'Target sitemap XML required. Example: gsc crawl https://mysite.com/sitemap.xml' })
          else
            puts Color.c("❌ Error: Target sitemap XML required. Example: gsc crawl https://mysite.com/sitemap.xml", Color::RED, Color::BOLD)
          end
          return
        end
        puts Base::BANNER unless options[:json] || options[:in_dashboard]
        puts "🕷️ Starting Comprehensive Site Audit & Broken Link Crawler..." unless options[:json]
        puts "   Target: #{Color.c(sitemap_target, Color::CYAN)}" unless options[:json]
        conc = options[:concurrency] || 5
        puts "   Concurrency: #{Color.c("#{conc} worker threads", Color::GREEN)}" unless options[:json]
        puts "   Link Verification: #{options[:check_links] ? Color.c('Enabled (testing all links)', Color::GREEN) : Color.c('Disabled (use --check-links to verify)', Color::GRAY)}" unless options[:json]
        puts "" unless options[:json]

        crawler = SiteCrawler.new(sitemap_target, options.merge(gsc_api: api, active_domain: site_url))

        summary = crawler.run do |url, current, total|
          unless options[:json]
            print "\r\e[K⏳ [#{current}/#{total}] Crawling & auditing: #{Color.c(url[0..60], Color::CYAN)}"
            $stdout.flush
          end
        end

        puts "\n" unless options[:json]

        if options[:report]
          report_file = crawler.generate_markdown_report(options[:report])
          puts Color.c("📝 Exported Comprehensive Markdown Audit Report to: #{report_file}\n", Color::GREEN, Color::BOLD) unless options[:json]
        end

        if options[:json]
          puts JSON.pretty_generate({
            summary: summary,
            broken_links: crawler.broken_links,
            missing_alts: crawler.missing_alts,
            heading_issues: crawler.heading_issues,
            title_issues: crawler.title_issues,
            canonical_issues: crawler.canonical_issues,
            results: crawler.results
          })
          return
        end

        puts ("═" * 80)
        puts "#{Color::BOLD}📊 SITE AUDIT SUMMARY REPORT#{Color::RESET}"
        puts ("─" * 80)
        puts "  Pages Audited:           #{Color.c(summary[:total_pages].to_s, Color::BOLD)}"
        puts "  Total Issues Detected:   #{Color.c(summary[:total_issues].to_s, summary[:total_issues] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
        puts "  Broken Links (404/500):  #{Color.c(summary[:broken_links_count].to_s, summary[:broken_links_count] == 0 ? Color::GREEN : Color::RED, Color::BOLD)}"
        puts "  Images Missing Alt:      #{Color.c(summary[:missing_alts_count].to_s, summary[:missing_alts_count] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
        puts "  H1 Heading Flaws:        #{Color.c(summary[:heading_issues_count].to_s, summary[:heading_issues_count] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
        puts "  Title/Meta Flaws:        #{Color.c(summary[:title_meta_issues_count].to_s, summary[:title_meta_issues_count] == 0 ? Color::GREEN : Color::YELLOW, Color::BOLD)}"
        puts ("═" * 80)

        if summary[:broken_links_count] > 0
          puts "\n#{Color::BOLD}🚨 BROKEN LINKS DETECTED:#{Color::RESET}"
          crawler.broken_links.first(10).each do |b|
            puts "  ❌ [HTTP #{b[:status]}] #{b[:href]}"
            puts "     Found on: #{Color.c(b[:source_page], Color::GRAY)}"
          end
        end

        if summary[:missing_alts_count] > 0
          puts "\n#{Color::BOLD}🖼️ TOP IMAGES MISSING ALT ATTRIBUTES:#{Color::RESET}"
          crawler.missing_alts.first(5).each do |img|
            puts "  ⚠️ #{Color.c(img[:src], Color::YELLOW)} (on #{img[:page_url]})"
          end
        end

        puts "\n💡 Run with #{Color.c('--report docs/seo/site_audit.md', Color::CYAN)} to generate full AI-actionable Markdown report." unless options[:report]
        puts ""
      end

      def run_comprehensive_audit(api, site_url, hostname, https_origin, options)
        days = options[:days] || 30
        puts "🔍 Running 360° Comprehensive SEO & Growth Audit for #{Color.c(hostname, Color::CYAN)} (Past #{days} days)...\n" unless options[:json]

        sites_res = api.list_sites
        access_ok = false
        if sites_res[:ok]
          entries = sites_res.dig(:data, 'siteEntry') || []
          access_ok = entries.any? { |s| s['siteUrl'] == site_url || s['siteUrl'].include?(hostname) }
        end

        perf_res = api.query_analytics(site_url, days: days, dimensions: [])
        perf_row = perf_res.dig(:data, 'rows', 0) || { 'clicks' => 0, 'impressions' => 0, 'ctr' => 0, 'position' => 0 }
        total_clicks = perf_row['clicks'] || 0
        total_imp    = perf_row['impressions'] || 0
        avg_ctr      = ((perf_row['ctr'] || 0) * 100).round(2)
        avg_pos      = (perf_row['position'] || 0).round(1)

        home_res = api.inspect_url("#{https_origin}/", site_url)
        idx_res = home_res.dig(:data, 'inspectionResult', 'indexStatusResult') || {}
        verdict          = idx_res['verdict'] || 'UNKNOWN'
        coverage         = idx_res['coverageState'] || 'Unknown'
        google_canonical = idx_res['googleCanonical'] || "#{https_origin}/"
        user_canonical   = idx_res['userCanonical'] || "#{https_origin}/"
        crawled_as       = idx_res['crawlingUserAgent'] || idx_res['crawledAs'] || 'Googlebot Mobile'
        last_crawl_raw   = idx_res['lastCrawlTime']
        last_crawl       = last_crawl_raw ? last_crawl_raw.split('T').first : 'Unknown'
        canonical_match  = google_canonical.chomp('/') == user_canonical.chomp('/') || google_canonical.include?(hostname)

        sm_res = api.list_sitemaps(site_url)
        sitemaps = sm_res[:ok] ? (sm_res.dig(:data, 'sitemap') || []) : []
        sm_errors = sitemaps.sum { |s| (s['errors'] || 0).to_i }
        sm_warnings = sitemaps.sum { |s| (s['warnings'] || 0).to_i }

        qp_res = api.query_analytics(site_url, days: days, dimensions: %w[query page], row_limit: 500)
        qp_rows = qp_res[:ok] ? (qp_res.dig(:data, 'rows') || []) : []

        opportunities = qp_rows.select { |r| r['position'] >= 7.0 && r['position'] <= 20.0 && r['impressions'] >= 5 }
                               .map do |r|
                                 c = r['clicks'] || 0
                                 i = r['impressions'] || 0
                                 pos = r['position'].round(1)
                                 potential_clicks = [((i * 0.12) - c).round, 1].max
                                 score = (potential_clicks * (1.0 / [pos - 2.0, 1.0].max) * 10.0).round(1)
                                 { query: r['keys'][0], page: r['keys'][1], position: pos, impressions: i, clicks: c, potential_gain: potential_clicks, score: score }
                               end.sort_by { |o| -o[:score] }.first(5)

        underperformers = qp_rows.select { |r| r['position'] <= 10.0 && r['impressions'] >= 15 }
                                 .map do |r|
                                   pos_val = r['position'].round(1)
                                   actual = ((r['ctr'] || 0) * 100).round(2)
                                   exp = Base.expected_ctr_for(pos_val)
                                   gap = (exp - actual).round(2)
                                   lost = [((r['impressions'] * (gap / 100.0))).round, 1].max
                                   { query: r['keys'][0], page: r['keys'][1], position: pos_val, impressions: r['impressions'], clicks: r['clicks'], actual_ctr: actual, expected_ctr: exp, gap: gap, lost_clicks: lost }
                                 end.select { |u| u[:gap] >= 2.0 && u[:actual_ctr] < (u[:expected_ctr] * 0.70) }
                                 .sort_by { |u| -u[:lost_clicks] }.first(5)

        by_query = qp_rows.group_by { |r| r['keys'][0] }
        cannibalized = by_query.select { |_q, list| list.map { |r| r['keys'][1] }.uniq.size > 1 }
                               .map do |q, list|
                                 pages = list.map do |r|
                                   { page: r['keys'][1], impressions: r['impressions'], clicks: r['clicks'], position: r['position'].round(1) }
                                 end.sort_by { |p| -p[:impressions] }
                                 total_q_imp = pages.sum { |p| p[:impressions] }
                                 { query: q, total_impressions: total_q_imp, pages: pages }
                               end.sort_by { |c| -c[:total_impressions] }.first(3)

        dev_res = api.query_analytics(site_url, days: days, dimensions: ['device'])
        devices_data = (dev_res[:ok] ? (dev_res.dig(:data, 'rows') || []) : []).map do |r|
          c = r['clicks'] || 0
          i = r['impressions'] || 0
          ctr = ((r['ctr'] || 0) * 100).round(2)
          pos = (r['position'] || 0).round(1)
          share = total_clicks > 0 ? "#{(c.to_f / total_clicks * 100).round(1)}%" : "-"
          { device: r['keys'].first, clicks: c, impressions: i, ctr: ctr, position: pos, share: share }
        end.sort_by { |r| -r[:clicks] }

        desk_dev = devices_data.find { |d| d[:device] == 'DESKTOP' }
        mob_dev  = devices_data.find { |d| d[:device] == 'MOBILE' }
        mobile_deficit = desk_dev && mob_dev && desk_dev[:ctr] >= 1.0 && mob_dev[:ctr] < (desk_dev[:ctr] * 0.6)

        snip_res = api.query_analytics(site_url, days: days, dimensions: ['searchAppearance'], row_limit: 10)
        snippets_data = (snip_res[:ok] ? (snip_res.dig(:data, 'rows') || []) : []).map do |r|
          { type: r['keys'].first, clicks: r['clicks'] || 0, impressions: r['impressions'] || 0, ctr: ((r['ctr'] || 0) * 100).round(2), position: (r['position'] || 0).round(1) }
        end

        ga4_prop = options[:property] || Config.ga4_property_id(hostname)
        ga4_data = nil
        high_bounce_pages = []
        if ga4_prop
          ga4_res = api.query_ga4_report(ga4_prop, days: days, limit: 50, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
          if ga4_res[:ok]
            raw_ga4 = ga4_res.dig(:data, 'rows') || []
            tot_sess = raw_ga4.sum { |r| r.dig('metricValues', 0, 'value').to_i }
            tot_bounce = raw_ga4.sum { |r| r.dig('metricValues', 3, 'value').to_f * r.dig('metricValues', 0, 'value').to_i }
            overall_bounce = tot_sess.positive? ? (tot_bounce / tot_sess * 100.0).round(1) : 0.0
            tot_dur = raw_ga4.sum { |r| r.dig('metricValues', 4, 'value').to_f * r.dig('metricValues', 0, 'value').to_i }
            overall_dur = tot_sess.positive? ? (tot_dur / tot_sess).round : 0

            high_bounce_pages = raw_ga4.map do |r|
              path = r.dig('dimensionValues', 0, 'value')
              sess = r.dig('metricValues', 0, 'value').to_i
              bounce = ((r.dig('metricValues', 3, 'value') || 0).to_f * 100).round(1)
              dur = (r.dig('metricValues', 4, 'value') || 0).to_f.round
              { path: path, sessions: sess, bounce_rate: bounce, duration: Base.format_duration(dur) }
            end.select { |p| p[:sessions] >= 10 && p[:bounce_rate] >= 80.0 }.sort_by { |p| -p[:sessions] }.first(5)

            ga4_data = {
              linked: true,
              property_id: ga4_prop,
              sessions: tot_sess,
              bounce_rate: overall_bounce,
              avg_duration_sec: overall_dur,
              avg_duration: Base.format_duration(overall_dur),
              high_bounce_pages: high_bounce_pages
            }
          end
        end

        score = 100
        score -= 20 if verdict != 'PASS'
        score -= 10 if sitemaps.empty?
        score -= 10 if sm_errors > 0
        score -= 10 unless canonical_match
        score -= 15 if avg_ctr < 0.5
        score -= 10 if avg_ctr >= 0.5 && avg_ctr < 1.0
        score -= 10 if avg_pos > 30.0
        score -= [underperformers.size * 5, 10].min
        score -= [cannibalized.size * 5, 10].min
        score -= 5 if mobile_deficit
        if ga4_data && ga4_data[:sessions] > 0
          score -= 15 if ga4_data[:bounce_rate] > 85.0
          score -= 10 if ga4_data[:bounce_rate] > 75.0 && ga4_data[:bounce_rate] <= 85.0
          score += 5  if ga4_data[:bounce_rate] <= 60.0
        end
        score += 5 unless snippets_data.empty?
        score = [[score, 20].max, 100].min

        grade = case score
                when 88..100 then 'A'
                when 75...88 then 'B'
                when 60...75 then 'C'
                else 'D'
                end

        grade_label = case grade
                      when 'A' then 'EXCELLENT - DOMINATING SERPS'
                      when 'B' then 'GOOD - HIGH-LEVERAGE GROWTH WINS AVAILABLE'
                      when 'C' then 'NEEDS ATTENTION - CLICK BLEED & CONFLICTS DETECTED'
                      else 'CRITICAL - INDEXING, CANNIBALIZATION OR RETENTION FRICTION'
                      end

        action_plan = []

        if cannibalized.any?
          top_c = cannibalized.first
          conflicting_pages = top_c[:pages].map { |p| p[:page].sub(%r{^https?://[^/]+}, '') }
          action_plan << {
            priority: 'high',
            title: "Consolidate Keyword Cannibalization on \"#{top_c[:query]}\"",
            detail: "Search intent is split across #{top_c[:pages].size} competing URLs (#{conflicting_pages.join(', ')}). Consolidate internal links and canonical signals to #{top_c[:pages].first[:page].sub(%r{^https?://[^/]+}, '')} to unify Page 1 ranking power."
          }
        end

        if underperformers.any?
          top_u = underperformers.first
          action_plan << {
            priority: 'high',
            title: "Recover ~#{top_u[:lost_clicks]} Lost Clicks/mo on \"#{top_u[:query]}\"",
            detail: "Currently ranking Pos #{top_u[:position]} on #{top_u[:page].sub(%r{^https?://[^/]+}, '')} with #{top_u[:actual_ctr]}% CTR (expected benchmark ~#{top_u[:expected_ctr]}%). Rewrite `<title>` and meta description with numbers or benefit hooks to double click-through."
          }
        end

        if sm_errors > 0
          err_sm = sitemaps.find { |s| (s['errors'] || 0).to_i > 0 }
          action_plan << {
            priority: 'high',
            title: "Resolve Sitemap Errors in Search Console",
            detail: "Sitemap #{err_sm['path']} has #{err_sm['errors']} errors. Clean up 404s or resubmit current sitemap-index.xml."
          }
        end

        if verdict != 'PASS'
          action_plan << {
            priority: 'high',
            title: "Resolve Homepage Indexation Blocker",
            detail: "Homepage Googlebot verdict is #{verdict} (#{coverage}). Inspect URL in Search Console to resolve indexing eligibility."
          }
        end

        if opportunities.any?
          top_o = opportunities.first
          action_plan << {
            priority: 'medium',
            title: "Push Striking-Distance Keyword \"#{top_o[:query]}\" to Top 3",
            detail: "Currently Pos #{top_o[:position]} with #{top_o[:impressions]} impressions on #{top_o[:page].sub(%r{^https?://[^/]+}, '')}. Add a dedicated H2 section and clear answering copy to unlock ~+#{top_o[:potential_gain]} clicks/mo."
          }
        end

        if high_bounce_pages.any?
          top_hb = high_bounce_pages.first
          action_plan << {
            priority: 'medium',
            title: "Address High Bounce Rate (#{top_hb[:bounce_rate]}%) on #{top_hb[:path]}",
            detail: "Page received #{top_hb[:sessions]} sessions with #{top_hb[:duration]} average time. Audit above-the-fold LCP speed and ensure page content directly satisfies searcher intent."
          }
        end

        if mobile_deficit
          action_plan << {
            priority: 'medium',
            title: "Audit Mobile Viewport & Responsive CTR",
            detail: "Mobile CTR (#{mob_dev[:ctr]}%) is significantly trailing Desktop (#{desk_dev[:ctr]}%). Test page on real devices for mobile layout shift, font readability, or button touch targets."
          }
        end

        if snippets_data.empty?
          action_plan << {
            priority: 'low',
            title: "Implement Structured Data (Schema.org)",
            detail: "No rich snippet enhancements active. Add Product, FAQ, or Organization JSON-LD markup to earn rich SERP real estate."
          }
        else
          snippet_labels = snippets_data.map { |s| Base.format_appearance(s[:type]) }.join(', ')
          action_plan << {
            priority: 'low',
            title: "Maintain Rich Snippets",
            detail: "#{snippet_labels} currently active. Monitor Google Rich Results Test to maintain snippet coverage."
          }
        end

        audit_payload = {
          domain: hostname,
          siteUrl: site_url,
          healthScore: score,
          grade: grade,
          gradeLabel: grade_label,
          days: days,
          totals: {
            clicks: total_clicks,
            impressions: total_imp,
            ctr: avg_ctr,
            position: avg_pos
          },
          technical: {
            homepageVerdict: verdict,
            coverageState: coverage,
            googleCanonical: google_canonical,
            userCanonical: user_canonical,
            canonicalMatch: canonical_match,
            crawledAs: crawled_as,
            lastCrawl: last_crawl,
            sitemapsCount: sitemaps.size,
            sitemapsErrors: sm_errors,
            sitemapsWarnings: sm_warnings,
            sitemaps: sitemaps
          },
          opportunities: opportunities,
          underperformers: underperformers,
          cannibalization: cannibalized,
          devices: devices_data,
          mobileDeficit: mobile_deficit,
          snippets: snippets_data,
          ga4: ga4_data,
          actionPlan: action_plan
        }

        if options[:json]
          puts JSON.pretty_generate(audit_payload)
        else
          print_comprehensive_audit(audit_payload)

          if options[:csv]
            csv_rows = action_plan.map { |a| [a[:priority], a[:title], a[:detail]] }
            Base.write_csv(options[:csv], %w[Priority Title Recommendation], csv_rows)
            puts Color.c("📁 Exported prioritized action plan to #{options[:csv]}\n", Color::CYAN)
          end
        end
      end

      def print_comprehensive_audit(d)
        score = d[:healthScore]
        score_colored = if score >= 80
          Color.c("#{score} / 100", Color::GREEN, Color::BOLD)
        elsif score >= 65
          Color.c("#{score} / 100", Color::YELLOW, Color::BOLD)
        else
          Color.c("#{score} / 100", Color::RED, Color::BOLD)
        end

        puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}"
        puts "#{Color::BOLD}🎯 OVERALL SEO HEALTH SCORE: #{score_colored} #{Color::BOLD}[GRADE #{d[:grade]} - #{d[:gradeLabel]}]#{Color::RESET}"
        puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}"

        idx_status = d[:technical][:homepageVerdict] == 'PASS' ? Color.c('✅ PASS (100% Eligible)', Color::GREEN) : Color.c("⚠️ #{d[:technical][:homepageVerdict]}", Color::YELLOW)
        ctr_status = d[:totals][:ctr] >= 1.5 ? Color.c("✅ #{d[:totals][:ctr]}% CTR (Healthy)", Color::GREEN) : Color.c("⚠️ #{d[:totals][:ctr]}% CTR (Below Benchmark)", Color::YELLOW)
        cann_status = d[:cannibalization].empty? ? Color.c('✅ 0 Conflicts', Color::GREEN) : Color.c("🔴 #{d[:cannibalization].size} Query Conflicts Detected", Color::RED, Color::BOLD)

        bounce_status = if d[:ga4] && d[:ga4][:linked] && d[:ga4][:sessions] > 0
          b = d[:ga4][:bounce_rate]
          b <= 65.0 ? Color.c("✅ #{b}% Bounce Rate (Strong)", Color::GREEN) : (b <= 80.0 ? Color.c("🟡 #{b}% Bounce Rate (Moderate)", Color::YELLOW) : Color.c("🔴 #{b}% Bounce Rate (High)", Color::RED, Color::BOLD))
        else
          Color.c('ℹ️ GA4 Not Linked', Color::GRAY)
        end

        puts "  • Technical Indexing:    #{idx_status}"
        puts "  • SERP Click Efficiency: #{ctr_status}"
        puts "  • SERP Cannibalization:  #{cann_status}"
        puts "  • On-Site Retention:     #{bounce_status}"
        puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}\n"

        puts "#{Color::BOLD}📊 30-DAY PERFORMANCE OVERVIEW#{Color::RESET}"
        puts "  • Organic Search Clicks:     #{Color.c(Base.format_number(d[:totals][:clicks]), Color::GREEN, Color::BOLD)}"
        puts "  • Total SERP Impressions:    #{Color.c(Base.format_number(d[:totals][:impressions]), Color::MAGENTA, Color::BOLD)}"
        puts "  • Average Search Position:   #{Color.c(d[:totals][:position].to_s, Color::YELLOW, Color::BOLD)}"
        puts "  • Average SERP CTR:          #{Color.c("#{d[:totals][:ctr]}%", Color::CYAN, Color::BOLD)}"
        if d[:ga4] && d[:ga4][:linked] && d[:ga4][:sessions] > 0
          puts "  • GA4 Total Sessions:        #{Color.c(Base.format_number(d[:ga4][:sessions]), Color::MAGENTA, Color::BOLD)} [Property #{d[:ga4][:property_id]}]"
          puts "  • GA4 Average Bounce Rate:   #{Color.c("#{d[:ga4][:bounce_rate]}%", Color::YELLOW, Color::BOLD)}"
          puts "  • GA4 Avg Session Duration:  #{Color.c(d[:ga4][:avg_duration].to_s, Color::CYAN, Color::BOLD)}"
        end
        puts

        tech = d[:technical]
        puts "#{Color::BOLD}🛠️  1. TECHNICAL CRAWL & INDEXATION HEALTH#{Color::RESET}"
        v_color = tech[:homepageVerdict] == 'PASS' ? Color.c('✅ PASS (Indexed & Eligible for SERPs)', Color::GREEN, Color::BOLD) : Color.c("⚠️ #{tech[:homepageVerdict]}", Color::RED, Color::BOLD)
        puts "  • Homepage Googlebot Verdict:  #{v_color}"
        puts "  • Google Index Coverage State: #{tech[:coverageState]}"
        c_match = tech[:canonicalMatch] ? Color.c("Matches declared canonical", Color::GREEN) : Color.c("⚠️ Canonical Mismatch Detected", Color::YELLOW)
        puts "  • Google-Selected Canonical:   #{tech[:googleCanonical]} (#{c_match})"
        puts "  • Crawl User-Agent:            Googlebot #{tech[:crawledAs]} (Mobile-First Indexing)"
        puts "  • Last Googlebot Crawl:        #{tech[:lastCrawl]}"
        sm_text = tech[:sitemapsCount] > 0 ? Color.c("#{tech[:sitemapsCount]} registered in Search Console", Color::GREEN) : Color.c("⚠️ No sitemaps found", Color::YELLOW)
        puts "  • XML Sitemaps:                #{sm_text}"
        if tech[:sitemapsErrors] > 0
          err_sms = tech[:sitemaps].select { |s| (s['errors'] || 0).to_i > 0 }
          err_sms.each do |sm|
            last_dl = sm['lastDownloaded'] ? sm['lastDownloaded'].split('T').first : 'Unknown'
            puts "    #{Color.c("⚠️ Notice: #{sm['path']} has #{sm['errors']} error (Last downloaded: #{last_dl}).", Color::YELLOW)}"
          end
        end
        puts

        puts "#{Color::BOLD}🎯 2. HIGH-IMPACT STRIKING-DISTANCE KEYWORDS (Page 2 ➔ Page 1 Quick Wins)#{Color::RESET}"
        if d[:opportunities].empty?
          puts Color.c("  ℹ️ No striking-distance queries found (pos 7–20 with >= 5 impressions).", Color::GRAY)
        else
          puts "Pos   | Impressions | Clicks | Est. Unlock  | Target Query & Landing Page"
          puts "--------------------------------------------------------------------------------"
          d[:opportunities].each do |o|
            pos_str  = o[:position].to_s.ljust(5)
            imp_str  = Base.format_number(o[:impressions]).ljust(11)
            c_str    = Base.format_number(o[:clicks]).ljust(6)
            gain_str = "+#{Base.format_number(o[:potential_gain])}/mo".ljust(12)
            page_short = o[:page].sub(%r{^https?://[^/]+}, '')
            page_short = '/' if page_short.empty?
            puts "#{Color.c(pos_str, Color::YELLOW)} | #{imp_str} | #{c_str} | #{Color.c(gain_str, Color::GREEN, Color::BOLD)} | #{Color.c(o[:query], Color::BOLD)} ➔ #{Color.c(page_short, Color::CYAN)}"
          end
          puts "💡 #{Color::BOLD}Action:#{Color::RESET} Add an H2 subheading and dedicated answering copy on these pages to push into the Top 3."
        end
        puts

        puts "#{Color::BOLD}⚡ 3. CTR CLICK-BLEED & TITLE HOOK DEFICITS (Top 10 Rankings)#{Color::RESET}"
        if d[:underperformers].empty?
          puts Color.c("  ✅ No critical Top 10 CTR click-bleed detected. Existing Page 1 rankings are converting at or above expected benchmarks.", Color::GREEN)
        else
          puts "Pos   | Impressions | Actual CTR | Expected | Lost Clicks  | Target Query & Landing Page"
          puts "----------------------------------------------------------------------------------------"
          d[:underperformers].each do |u|
            pos_str  = u[:position].to_s.ljust(5)
            imp_str  = Base.format_number(u[:impressions]).ljust(11)
            act_str  = "#{u[:actual_ctr]}%".ljust(10)
            exp_str  = "~#{u[:expected_ctr]}%".ljust(8)
            lost_str = "~#{Base.format_number(u[:lost_clicks])}/mo".ljust(12)
            page_short = u[:page].sub(%r{^https?://[^/]+}, '')
            page_short = '/' if page_short.empty?
            puts "#{Color.c(pos_str, Color::GREEN)} | #{imp_str} | #{Color.c(act_str, Color::RED)} | #{exp_str} | #{Color.c(lost_str, Color::YELLOW, Color::BOLD)} | #{Color.c(u[:query], Color::BOLD)} ➔ #{Color.c(page_short, Color::CYAN)}"
          end
          puts "💡 #{Color::BOLD}Action:#{Color::RESET} Rewrite the <title> tag and meta description with numbers, brackets, or clear benefit hooks to recover lost clicks immediately."
        end
        puts

        puts "#{Color::BOLD}🔀 4. KEYWORD CANNIBALIZATION (Multiple URLs Splitting SERP Equity)#{Color::RESET}"
        if d[:cannibalization].empty?
          puts Color.c("  ✅ Clean URL architecture! No internal keyword cannibalization detected.", Color::GREEN)
        else
          d[:cannibalization].each do |c|
            puts "  #{Color.c('⚠️ Conflict:', Color::RED, Color::BOLD)} Query #{Color.c("\"#{c[:query]}\"", Color::BOLD)} (#{Base.format_number(c[:total_impressions])} total imp) split across #{c[:pages].size} competing URLs:"
            c[:pages].each do |p|
              p_short = p[:page].sub(%r{^https?://[^/]+}, '')
              p_short = '/' if p_short.empty?
              puts "     ↳ Pos #{p[:position].to_s.ljust(4)} (#{Base.format_number(p[:impressions]).rjust(4)} imp, #{p[:clicks]} clicks) ➔ #{Color.c(p_short, Color::CYAN)}"
            end
          end
          puts "  💡 #{Color::BOLD}Fix:#{Color::RESET} Consolidate canonical signals or point internal links to 1 primary URL to concentrate ranking authority."
        end
        puts

        puts "#{Color::BOLD}📱 5. DEVICE EXPERIENCE & SERP PARITY#{Color::RESET}"
        puts "Device       | Clicks   | Impressions | CTR    | Position | Clicks Share"
        puts "-------------------------------------------------------------------------"
        d[:devices].each do |r|
          d_name = Base.format_device(r[:device]).ljust(12)
          c_str = Base.format_number(r[:clicks]).ljust(8)
          i_str = Base.format_number(r[:impressions]).ljust(11)
          ctr_str = "#{r[:ctr]}%".ljust(6)
          pos_str = r[:position].to_s.ljust(8)
          share_str = r[:share].to_s
          puts "#{d_name} | #{c_str} | #{i_str} | #{ctr_str} | #{pos_str} | #{share_str}"
        end
        if d[:mobileDeficit]
          puts "  #{Color.c('⚠️ Mobile CTR Alert: Mobile CTR is significantly lower than Desktop. Audit mobile LCP speed and small-screen snippet readability.', Color::YELLOW)}"
        end
        puts

        if d[:ga4] && d[:ga4][:linked]
          puts "#{Color::BOLD}📈 6. ON-SITE RETENTION & HIGH-BOUNCE ALERTS (via GA4)#{Color::RESET}"
          puts "  • 30-Day GA4 Sessions:        #{Base.format_number(d[:ga4][:sessions])}"
          puts "  • Overall Bounce Rate:         #{d[:ga4][:bounce_rate]}%"
          puts "  • Average Session Duration:    #{d[:ga4][:avg_duration]}"
          if d[:ga4][:high_bounce_pages].empty?
            puts Color.c("  ✅ No critical high-bounce landing pages (>80% with >= 10 sessions) detected.", Color::GREEN)
          else
            puts "  • Highest-Bounce Landing Pages (>= 10 sessions, >= 80% bounce):"
            d[:ga4][:high_bounce_pages].each_with_index do |hb, idx|
              puts "    #{idx + 1}. #{Color.c(hb[:path].ljust(30), Color::CYAN)} ➔ #{Color.c("#{hb[:sessions]} sess", Color::BOLD)} | #{Color.c("#{hb[:bounce_rate]}% bounce", Color::RED)} | #{hb[:duration]} avg"
            end
          end
          puts
        end

        puts "#{Color::BOLD}📋 7. PRIORITIZED ACTION PLAN (THE REAL VALUE ROADMAP)#{Color::RESET}"
        high_p = d[:actionPlan].select { |a| a[:priority] == 'high' }
        med_p  = d[:actionPlan].select { |a| a[:priority] == 'medium' }
        low_p  = d[:actionPlan].select { |a| a[:priority] == 'low' }

        idx = 1
        if high_p.any?
          puts "  #{Color.c('[🔴 HIGH PRIORITY - IMMEDIATE VALUE WINS]', Color::RED, Color::BOLD)}"
          high_p.each do |item|
            puts "    #{idx}. #{Color::BOLD}#{item[:title]}#{Color::RESET}"
            puts "       #{item[:detail]}"
            idx += 1
          end
        end

        if med_p.any?
          puts "  #{Color.c('[🟡 MEDIUM PRIORITY - HIGH-LEVERAGE GROWTH]', Color::YELLOW, Color::BOLD)}"
          med_p.each do |item|
            puts "    #{idx}. #{Color::BOLD}#{item[:title]}#{Color::RESET}"
            puts "       #{item[:detail]}"
            idx += 1
          end
        end

        if low_p.any?
          puts "  #{Color.c('[🟢 QUICK WIN / TECHNICAL MAINTENANCE]', Color::GREEN, Color::BOLD)}"
          low_p.each do |item|
            puts "    #{idx}. #{Color::BOLD}#{item[:title]}#{Color::RESET}"
            puts "       #{item[:detail]}"
            idx += 1
          end
        end
        puts
      end
    end
  end
end

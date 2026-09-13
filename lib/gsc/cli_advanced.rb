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
        puts Color.c("❌ Error: Query required. Example: gsc suggest \"moving boxes\"", Color::RED)
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
        puts Color.c("❌ Error: Query required. Example: gsc questions \"packing dishes\"", Color::RED)
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
        puts Color.c("❌ Error: Domain required. Example: gsc authority packinglog.com", Color::RED)
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
      url = target || "https://#{Config.default_domain || 'example.com'}"
      url = "https://#{url}" unless url =~ %r{^https?://}
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
      puts "\n#{Color::BOLD}📊 CORE WEB VITALS (Lab Metrics):#{Color::RESET}"
      puts "   • LCP (Largest Contentful Paint) : #{Color.c(m[:lcp] || 'N/A', Color::BOLD)}"
      puts "   • FCP (First Contentful Paint)   : #{Color.c(m[:fcp] || 'N/A', Color::BOLD)}"
      puts "   • CLS (Cumulative Layout Shift)  : #{Color.c(m[:cls] || 'N/A', Color::BOLD)}"
      puts "   • TBT (Total Blocking Time)      : #{Color.c(m[:tbt] || 'N/A', Color::BOLD)}"
      puts "   • Speed Index                    : #{Color.c(m[:speed_index] || 'N/A', Color::BOLD)}"

      opps = data[:opportunities] || []
      unless opps.empty?
        puts "\n#{Color::BOLD}💡 TOP SPEED OPPORTUNITIES:#{Color::RESET}"
        opps.each do |opp|
          puts "   • #{opp[:title]}: #{Color.c(opp[:display] || "#{opp[:savings_ms]}ms savings", Color::YELLOW)}"
        end
      end
      puts ""
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

    # 7. Internal Links Audit
    def self.handle_internal_links_command(target, options)
      base_url = target || "https://#{Config.default_domain || 'example.com'}"
      il = GSC::InternalLinks.new(base_url, limit: options[:limit] || 50)

      puts BANNER unless options[:json] || options[:in_dashboard]
      puts "🕸️ Auditing Internal Links & Orphan Pages for: #{Color.c(base_url, Color::CYAN)}...\n" unless options[:json]

      data = il.audit

      if options[:json]
        puts JSON.pretty_generate(data)
        return
      end

      puts "─" * 80
      puts "Pages Discovered: #{Color.c(data[:total_pages].to_s, Color::BOLD)}"
      puts "Orphan Pages:     #{Color.c(data[:orphans].length.to_s, data[:orphans].empty? ? Color::GREEN : Color::RED, Color::BOLD)}"
      puts "Weakly Linked:    #{Color.c(data[:weak_pages].length.to_s, Color::YELLOW, Color::BOLD)} (Only 1 incoming internal link)"
      puts "─" * 80

      orphans = data[:orphans] || []
      unless orphans.empty?
        puts "\n#{Color::BOLD}🚨 ORPHAN PAGES (0 incoming internal links - Crawl Dead Ends):#{Color::RESET}"
        orphans.each do |orp|
          puts "   • #{Color.c(orp, Color::RED)}"
        end
      end

      puts "\n#{Color::BOLD}🔝 MOST LINKED INTERNAL PAGES:#{Color::RESET}"
      (data[:top_linked] || []).each do |top|
        puts "   • #{top[:url]} (#{Color.c(top[:incoming_count].to_s, Color::CYAN)} incoming links)"
      end
      puts ""
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

      url = target || "https://#{Config.default_domain || 'example.com'}"
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
      base_url = target || "https://#{Config.default_domain || 'example.com'}"
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

    # 10. SERP & Social Preview
    def self.handle_preview_command(target, options)
      is_url = target.to_s.start_with?('http://', 'https://')
      url = options[:url] || (target if is_url)
      title = options[:title] || (target unless is_url)
      desc = options[:desc] || options[:description]

      url ||= "https://#{Config.default_domain || 'example.com'}"

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
      url = target || Config.default_domain || 'example.com'
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
      url = target || "https://#{Config.default_domain || 'example.com'}"
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
      domain = target || Config.default_domain || 'example.com'
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
  end
end

# frozen_string_literal: true

require 'shellwords'

module GSC
  class CLI
    module Dashboard
      module_function

      def run(options = {})
        puts Base::BANNER

        domains = Base.fetch_available_domains
        active = Config.default_domain
        if (active.nil? || active.empty?) && domains.any?
          active = Config.set_default_domain(domains.first)
        end

        if active
          puts "Active Target Domain: #{Color.c(active, Color::GREEN, Color::BOLD)}"
        else
          puts Color.c("No active domain configured. Run 'connect' to configure.", Color::YELLOW)
        end
        puts

        if domains.any?
          puts "#{Color::BOLD}🌐 Verified Domains (Type number 1-#{domains.size} to switch):#{Color::RESET}"
          domains.each_with_index do |dom, idx|
            marker = (dom == active) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""
            ga4_id = Config.ga4_property_id(dom)
            ga4_str = ga4_id ? Color.c("[GA4: #{ga4_id}]", Color::MAGENTA) : ""
            puts "  #{Color.c("[#{idx + 1}]", Color::CYAN, Color::BOLD)} #{dom.ljust(26)} #{ga4_str}#{marker}"
          end
          puts
        end

        print_main_menu_shortcuts

        current_group = nil

        loop do
          current_dom = Config.default_domain || 'no-domain'
          prompt_label = current_group ? "gsc [#{current_dom}] (#{current_group})> " : "gsc [#{current_dom}]> "
          print "#{Color::BOLD}#{Color::CYAN}#{prompt_label}#{Color::RESET}"

          raw = $stdin.gets
          break if raw.nil?

          input = raw.strip
          next if input.empty?

          # Universal quit
          break if %w[q quit exit bye :q q!].include?(input.downcase)

          # Return to main menu from sub-group
          if %w[b back .. main].include?(input.downcase)
            if current_group
              current_group = nil
              puts Color.c("↩ Back to main menu.\n", Color::DIM)
              print_main_menu_shortcuts
            end
            next
          end

          # Show help/menu
          if %w[? help menu commands].include?(input.downcase) || input == ' '
            case current_group
            when :keywords then print_keywords_menu
            when :analytics then print_analytics_menu
            when :ga4 then print_ga4_menu
            when :indexing then print_indexing_menu
            when :setup then print_setup_menu
            else
              print_main_menu_shortcuts
              print_commands_help
            end
            next
          end

          # Number: domain switch
          if input =~ /^\d+$/
            CLI.run([input, '--in-dashboard'])
            puts
            next
          end

          # Group switches from main menu
          if current_group.nil?
            case input.downcase
            when 'k', 'keywords'
              current_group = :keywords
              print_keywords_menu
              next
            when 'a', 'analytics'
              current_group = :analytics
              print_analytics_menu
              next
            when 'g', 'ga4', 'traffic'
              current_group = :ga4
              print_ga4_menu
              next
            when 'i', 'indexing', 'sitemaps'
              current_group = :indexing
              print_indexing_menu
              next
            when 's', 'setup', 'config'
              current_group = :setup
              print_setup_menu
              next
            end
          end

          # Built-in clear
          if %w[clear cls].include?(input.downcase)
            print "\e[H\e[2J"
            next
          end

          # Domains list
          if %w[domains list].include?(input.downcase)
            doms = Base.fetch_available_domains
            puts "\n🌐 Verified Domains:"
            doms.each_with_index do |d, idx|
              marker = (d == Config.default_domain) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""
              puts "  #{Color.c("[#{idx + 1}]", Color::CYAN, Color::BOLD)} #{d}#{marker}"
            end
            puts
            next
          end

          cmd_args = Shellwords.split(input) rescue input.split
          first = cmd_args[0].downcase

          # Sub-menu and global shortcut resolution
          resolved_cmd = case first
                         when 'p', 'perf' then 'performance'
                         when 'tq', 'queries', 'query' then 'top-queries'
                         when 'b', 'brand', 'brand-split' then 'brand'
                         when 'ctr', 'curve', 'ctr-curve', 'gain' then 'ctr-curve'
                         when 'tp', 'pages' then 'top-pages'
                         when 'o', 'opp' then 'opportunities'
                         when 'u', 'under', 'low' then 'underperformers'
                         when 'c', 'conflicts', 'cann' then 'cannibalization'
                         when 'd', 'decay' then 'decay'
                         when 'aud', 'audit' then 'audit'
                         when 'tr', 'trends' then 'trends'
                         when 'kp', 'planner' then 'planner'
                         when 'ke' then 'ke'
                         when 'imp', 'import', 'pi' then 'import'
                         when 'cr', 'credits', 'kec' then 'ke-credits'
                         when 'sv', 'saved', 'research' then 'saved'
                         when 'chk', 'check' then 'check'
                         when 'pb', 'prompts', 'prompt', 'playbooks', 'playbook' then 'prompts'
                         when 'r', 'live' then 'realtime'
                         when 'ga', 'bounce' then 'ga4'
                         when 'co', 'corr' then 'correlation'
                         when 'ad', 'ads' then 'ads'
                         when 'ch', 'channels' then 'channels'
                         when 'ins', 'inspect' then 'inspect'
                         when 'idx', 'index' then 'index'
                         when 'ib', 'queue', 'index-batch', 'batch-index' then 'index-batch'
                         when 'rm', 'remove' then 'remove'
                         when 'map', 'sitemaps' then 'sitemaps-list'
                         when 'sub', 'sitemaps-submit' then 'sitemaps-submit'
                         when 'bi', 'inspect-sitemap' then 'inspect-sitemap'
                         when 'z', 'zombies' then 'zombies'
                         when 'cg', 'connect-ga4' then 'connect-ga4'
                         when 'w', 'where' then 'where'
                         when 'v', 'version' then 'version'
                         else first
                         end

          if first == 'ck'
            cmd_args = ['connect', 'ke'] + cmd_args[1..]
          else
            cmd_args[0] = resolved_cmd
          end

          begin
            CLI.run(cmd_args + ['--in-dashboard'])
          rescue Interrupt
            puts "\n(Action cancelled)"
          rescue StandardError => e
            puts Color.c("❌ Error: #{e.message}", Color::RED)
          end

          puts
        end

        puts Color.c("\n👋 Exited interactive mode.", Color::DIM)
      end

      def print_main_menu_shortcuts
        puts "#{Color::BOLD}📂 Command Groups (Type letter to explore sub-shortcuts):#{Color::RESET}"
        puts "  #{Color.c('[k]', Color::CYAN, Color::BOLD)} Keywords & Trends    #{Color.c('[a]', Color::YELLOW, Color::BOLD)} Search Analytics    #{Color.c('[g]', Color::MAGENTA, Color::BOLD)} GA4 & Realtime"
        puts "  #{Color.c('[i]', Color::GREEN, Color::BOLD)} Indexing & Sitemaps  #{Color.c('[s]', Color::BLUE, Color::BOLD)} Setup & Config      #{Color.c('[?]', Color::WHITE, Color::BOLD)} All Commands"
        puts
        puts "#{Color::BOLD}⚡ Quick Shortcuts (Run directly from any prompt):#{Color::RESET}"
        puts "  #{Color.c('[pb]', Color::MAGENTA, Color::BOLD)}  AI Playbooks  #{Color.c('[p]', Color::YELLOW, Color::BOLD)}   Performance   #{Color.c('[tq]', Color::YELLOW, Color::BOLD)} Top Queries   #{Color.c('[tp]', Color::YELLOW, Color::BOLD)} Top Pages"
        puts "  #{Color.c('[o]', Color::YELLOW, Color::BOLD)}   Opportunities   #{Color.c('[u]', Color::YELLOW, Color::BOLD)}   Underperf     #{Color.c('[aud]', Color::CYAN, Color::BOLD)} Full Audit   #{Color.c('[r]', Color::GREEN, Color::BOLD)} GA4 Realtime"
        puts "  #{Color.c('[tr]', Color::CYAN, Color::BOLD)}  Trends <query>  #{Color.c('[kp]', Color::CYAN, Color::BOLD)}  Planner <kw>  #{Color.c('[ke]', Color::YELLOW, Color::BOLD)} Keywords <kw> #{Color.c('[imp]', Color::CYAN, Color::BOLD)} Import File"
        puts "  #{Color.c('[q]', Color::GRAY, Color::BOLD)}   Quit (or exit)"
        puts
      end

      def print_keywords_menu
        puts "\n#{Color::BOLD}📈 GOOGLE TRENDS & KEYWORD INTELLIGENCE:#{Color::RESET}"
        puts "  #{Color.c('[tr]  trends <query>', Color::CYAN, Color::BOLD)}       Real-time Google Trends 5-year/12-month demand & velocity"
        puts "  #{Color.c('[kp]  planner <seed>', Color::CYAN, Color::BOLD)}       Free autocomplete keyword expander & intent classifier"
        puts "  #{Color.c('[ke]  ke <query>', Color::YELLOW, Color::BOLD)}           Keywords Everywhere exact monthly volume, CPC & competition"
        puts "  #{Color.c('[imp] import <file>', Color::CYAN, Color::BOLD)}        Import Keywords Everywhere TSV/CSV or Google Ads export"
        puts "  #{Color.c('[sv]  saved', Color::GREEN, Color::BOLD)}                List saved domain keyword research snapshots"
        puts "  #{Color.c('[chk] check [id]', Color::GREEN, Color::BOLD)}           Re-check saved keywords against live Search Console rankings"
        puts "  #{Color.c('[cr]  ke-credits', Color::YELLOW, Color::BOLD)}           Check remaining Keywords Everywhere account balance"
        puts "  #{Color.c('[ck]  connect ke [key]', Color::GREEN, Color::BOLD)}     Connect Keywords Everywhere API key"
        puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
        puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
        puts
      end

      def print_analytics_menu
        puts "\n#{Color::BOLD}📊 SEARCH ANALYTICS & MONITORING:#{Color::RESET}"
        puts "  #{Color.c('[p]   performance', Color::YELLOW, Color::BOLD)}          Executive dashboard: Totals, Devices, Countries, Snippets, Queries"
        puts "  #{Color.c('[tq]  top-queries', Color::YELLOW, Color::BOLD)}          Top search queries, rankings, impressions, CTR, and position"
        puts "  #{Color.c('[tp]  top-pages', Color::YELLOW, Color::BOLD)}            Top landing pages driving clicks and impressions"
        puts "  #{Color.c('[o]   opportunities', Color::YELLOW, Color::BOLD)}        Striking-distance Page 2 queries (Pos 7–20) to push to Top 3"
        puts "  #{Color.c('[u]   underperformers', Color::YELLOW, Color::BOLD)}      Top 10 ranking queries with low CTR (title & meta win hooks)"
        puts "  #{Color.c('[c]   cannibalization', Color::RED, Color::BOLD)}      Detect multiple internal URLs competing for the same search query"
        puts "  #{Color.c('[d]   decay', Color::RED, Color::BOLD)}                28-day period-over-period trend analysis (decaying vs surging)"
        puts "  #{Color.c('[aud] audit', Color::CYAN, Color::BOLD)}                Automated 4-step comprehensive SEO & indexing health audit"
        puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
        puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
        puts
      end

      def print_ga4_menu
        puts "\n#{Color::BOLD}📈 GOOGLE ANALYTICS 4 (GA4) & POST-CLICK BEHAVIOR:#{Color::RESET}"
        puts "  #{Color.c('[r]   realtime [--watch]', Color::GREEN, Color::BOLD)}   Live active visitors, pages, and countries right now"
        puts "  #{Color.c('[ga]  ga4 [--organic]', Color::MAGENTA, Color::BOLD)}      Landing page bounce rates, engagement rates, sessions, duration"
        puts "  #{Color.c('[co]  correlation', Color::MAGENTA, Color::BOLD)}          Merge GSC keyword rankings with GA4 bounce rates per landing page"
        puts "  #{Color.c('[ad]  ads', Color::MAGENTA, Color::BOLD)}                  Google Ads campaign performance (Clicks, Cost, CPC, CPA, Conv)"
        puts "  #{Color.c('[ch]  channels', Color::MAGENTA, Color::BOLD)}             Omnichannel acquisition breakdown (Organic, Paid, Direct, Referral)"
        puts "  #{Color.c('[cg]  connect-ga4', Color::GREEN, Color::BOLD)}          Interactive GA4 linking wizard"
        puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
        puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
        puts
      end

      def print_indexing_menu
        puts "\n#{Color::BOLD}🔍 GOOGLEBOT INDEXING & SITEMAPS:#{Color::RESET}"
        puts "  #{Color.c('[ins] inspect <url>', Color::CYAN, Color::BOLD)}        Live Search Console URL inspection (verdict, coverage, canonical)"
        puts "  #{Color.c('[idx] index <url>', Color::GREEN, Color::BOLD)}          Notify Googlebot to crawl/index a URL immediately (URL_UPDATED)"
        puts "  #{Color.c('[rm]  remove <url>', Color::RED, Color::BOLD)}         Notify Googlebot a URL has been deleted (URL_DELETED)"
        puts "  #{Color.c('[map] sitemaps', Color::MAGENTA, Color::BOLD)}             List submitted sitemaps in Search Console and crawl status"
        puts "  #{Color.c('[sub] sitemaps-submit <url>', Color::MAGENTA, Color::BOLD)} Submit new XML sitemap to Google Search Console"
        puts "  #{Color.c('[bi]  inspect-sitemap <file>', Color::CYAN, Color::BOLD)} Bulk inspect all sitemap URLs in XML file"
        puts "  #{Color.c('[z]   zombies <sitemap>', Color::RED, Color::BOLD)}     Detect 90-day zero-impression pages wasting crawl budget"
        puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
        puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
        puts
      end

      def print_setup_menu
        puts "\n#{Color::BOLD}⚙️ SETUP, DOMAINS & CONFIGURATION:#{Color::RESET}"
        puts "  #{Color.c('[1-N] <num>', Color::CYAN, Color::BOLD)}                Switch active domain by number"
        puts "  #{Color.c('[c]   connect', Color::GREEN, Color::BOLD)}              1-Click Setup Wizard: auto-detects key or drag & drop"
        puts "  #{Color.c('[cg]  connect-ga4', Color::GREEN, Color::BOLD)}          Interactive GA4 linking wizard"
        puts "  #{Color.c('[ck]  connect ke [key]', Color::GREEN, Color::BOLD)}     Connect Keywords Everywhere API key"
        puts "  #{Color.c('[o]   open', Color::GREEN, Color::BOLD)}                 Reveal configuration directory (~/.config/gsc) in Finder"
        puts "  #{Color.c('[w]   where', Color::GREEN, Color::BOLD)}                Inspect CLI installation path, active credentials, and config"
        puts "  #{Color.c('[v]   version', Color::GREEN, Color::BOLD)}              Show version and runtime environment"
        puts "  #{Color.c('[u]   update', Color::GREEN, Color::BOLD)}               Fetch latest release from GitHub and self-update"
        puts "  #{Color.c('[b]   back', Color::DIM, Color::BOLD)}                 Return to main menu"
        puts "  #{Color.c('[q]   quit', Color::GRAY, Color::BOLD)}                 Exit gsc"
        puts
      end

      def print_commands_help
        puts <<~COMMANDS

          #{Color::BOLD}SETUP, CONFIGURATION & DOMAIN SWITCHING:#{Color::RESET}
            #{Color.c('connect', Color::GREEN)}                       1-Click Setup Wizard: auto-detects key or drag & drop
            #{Color.c('open', Color::GREEN)}                          Reveal config folder (~/.config/gsc) in Finder
            #{Color.c('use <domain>', Color::GREEN)}                 Set default active domain (saved in ~/.config/gsc/config.json)
            #{Color.c('where', Color::GREEN)}                        Show CLI location, active credentials, and config path
            #{Color.c('config', Color::GREEN)}                       View or update current CLI configuration
            #{Color.c('domains', Color::GREEN)}                      List all verified Search Console properties (highlights active)
            #{Color.c('version', Color::GREEN)}                      Show CLI version and runtime environment
            #{Color.c('update', Color::GREEN)}                       Fetch latest version from GitHub and self-update

          #{Color::BOLD}GOOGLE TRENDS & KEYWORD INTELLIGENCE:#{Color::RESET}
            #{Color.c('trends <keyword>', Color::CYAN).ljust(38)} Real-time Google Trends search demand, velocity & breakouts
            #{Color.c('planner <seed>', Color::CYAN).ljust(38)} Autocomplete expansion, search intent & opportunity scoring
            #{Color.c('planner-import <file>', Color::CYAN).ljust(38)} Import Google Ads Keyword Planner CSV/TSV export & score
            #{Color.c('ke <keyword|file>', Color::YELLOW).ljust(38)} Keywords Everywhere exact monthly volume, CPC & competition
            #{Color.c('ke-credits', Color::YELLOW).ljust(38)} Check remaining Keywords Everywhere account balance
            #{Color.c('connect ke [key]', Color::GREEN).ljust(38)} Connect Keywords Everywhere API key (~/.config/gsc/config.json)

          #{Color::BOLD}SEARCH ANALYTICS & MONITORING:#{Color::RESET}
            #{Color.c('performance', Color::YELLOW)}                  Executive dashboard: Totals, Devices, Countries, Snippets, Queries, Pages, Cities
            #{Color.c('top-queries', Color::YELLOW)}                  Top search queries, impressions, CTR, and average rankings
            #{Color.c('top-pages', Color::YELLOW)}                    Top indexed pages driving clicks & impressions
            #{Color.c('devices', Color::YELLOW)}                      Device breakdown (Desktop, Mobile, Tablet) with clicks share
            #{Color.c('countries', Color::YELLOW)}                    Geographic search demand by country (with flags & CTR)
            #{Color.c('cities', Color::YELLOW)}                       Top visitor cities, volume, bounce rates & retention (via GA4)
            #{Color.c('snippets', Color::YELLOW)}                     Search appearance & rich snippets (Reviews, Products, FAQs)
            #{Color.c('audit', Color::CYAN)}                        Automated 4-step SEO & Indexing Health Check

          #{Color::BOLD}ENTERPRISE GROWTH & AUDIT INTELLIGENCE:#{Color::RESET}
            #{Color.c('opportunities', Color::YELLOW)}                Striking-distance queries (Pos 7–20) to push to Page 1 / Top 3
            #{Color.c('underperformers', Color::YELLOW)}              High-ranking queries (Top 10) with low CTR (title tag wins)
            #{Color.c('cannibalization', Color::RED)}              Detect multiple internal URLs competing for the same query
            #{Color.c('decay', Color::RED)}                        Period-over-period decay detection (decaying vs surging)
            #{Color.c('brand', Color::GREEN)}                        Brand vs non-brand search query segmentation & traffic share
            #{Color.c('ctr-curve', Color::CYAN)}                    Expected SERP CTR curve & click gain simulator
            #{Color.c('strike', Color::YELLOW)}                       Striking-distance tactical playbook (title rewrites & headings)
            #{Color.c('answer <query>', Color::CYAN)}                Synthesize 40-60w direct answer for Featured Snippets
            #{Color.c('geo <url>', Color::GREEN)}                     Generative Engine Optimization (GEO/AEO) citability audit
            #{Color.c('firewall [url]', Color::YELLOW)}               AI Bot & Cloudflare WAF firewall blockade scanner
            #{Color.c('titles [url]', Color::CYAN)}                  Title tag length & pixel width overflow optimizer
            #{Color.c('headings <url>', Color::CYAN)}                Heading hierarchy tree validator (H1-H6 depth & skipping)
            #{Color.c('orphans [url]', Color::MAGENTA)}                 Internal link equity & orphan page rescue engine
            #{Color.c('speed-correlate', Color::GREEN)}               Correlate Core Web Vitals (LCP/CLS) with real GSC traffic

          #{Color::BOLD}GOOGLE INDEXING API & SITEMAPS:#{Color::RESET}
            #{Color.c('inspect <url>', Color::CYAN)}                 Live Google index check (coverage, canonical, crawl date)
            #{Color.c('index <url>', Color::GREEN)}                   Notify Googlebot to crawl/index URL immediately
            #{Color.c('index-batch [action]', Color::GREEN)}          Automated 200 URL/day quota queue manager
            #{Color.c('remove <url>', Color::RED)}                  Notify Googlebot a page has been removed
            #{Color.c('sitemaps-list', Color::MAGENTA)}                 List submitted sitemaps in Search Console
            #{Color.c('sitemaps-submit <url>', Color::MAGENTA)}         Submit new XML sitemap to Google Search Console
            #{Color.c('inspect-sitemap <file>', Color::CYAN)}        Bulk inspect indexation status for all sitemap URLs
            #{Color.c('index-sitemap <file>', Color::GREEN)}          Batch submit all sitemap URLs to Google Indexing API
            #{Color.c('zombies <sitemap>', Color::RED)}              Find zero-impression crawl waste pages over 90 days

          #{Color::BOLD}LOCAL CACHE & OFFLINE INTELLIGENCE:#{Color::RESET}
            #{Color.c('cache status', Color::GREEN)}                  Inspect local SQLite query cache size & snapshots
            #{Color.c('cache warm', Color::GREEN)}                    Warm local cache from GSC API
            #{Color.c('cache query <term>', Color::GREEN)}            Sub-10ms offline query search with filtering & sorting
            #{Color.c('cache pages <term>', Color::GREEN)}            Sub-10ms offline landing page search
            #{Color.c('cache diff', Color::CYAN)}                    Offline snapshot winner/loser delta comparator
            #{Color.c('cache clear', Color::RED)}                    Clear local database cache

          #{Color::BOLD}GOOGLE ANALYTICS 4 (GA4):#{Color::RESET}
            #{Color.c('realtime', Color::GREEN)}                      Stream live active visitors and active paths
            #{Color.c('pages', Color::MAGENTA)}                         Top landing pages with bounce rates, views & duration
            #{Color.c('sources', Color::MAGENTA)}                       Traffic acquisition channels (Organic, Direct, Social)
            #{Color.c('correlation', Color::MAGENTA)}                   Merge GSC rankings with GA4 bounce rates
            #{Color.c('ads', Color::MAGENTA)}                           Google Ads campaign performance
        COMMANDS
      end
    end
  end
end

# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../google_trends' if File.exist?(File.expand_path('../google_trends.rb', __dir__))
require_relative '../keyword_planner' if File.exist?(File.expand_path('../keyword_planner.rb', __dir__))
require_relative '../keywords_everywhere' if File.exist?(File.expand_path('../keywords_everywhere.rb', __dir__))
require_relative '../google_suggest' if File.exist?(File.expand_path('../google_suggest.rb', __dir__))

module GSC
  class CLI
    module Keywords
      module_function

      def run(command, target, extra, options)
        case command
        when 'trends', 'tr', 'google-trends', 'gtrends'
          handle_trends(target, options)
        when 'planner', 'kp', 'keywords'
          if target == 'import'
            handle_planner_import(extra, options)
          elsif target && (File.exist?(target) || target.end_with?('.csv', '.tsv', '.md'))
            handle_planner_import(target, options)
          else
            handle_planner_expand(target, options)
          end
        when 'planner-import', 'pi', 'import', 'imp'
          handle_planner_import(target, options)
        when 'saved', 'research', 'saved-keywords', 'sv'
          handle_saved(target, extra, options)
        when 'check', 'chk'
          handle_saved('check', target, options)
        when 'ke', 'keywordseverywhere', 'keywords-everywhere', 'k'
          if target == 'credits' || target == 'account'
            handle_ke_credits(options)
          elsif target == 'connect' || target == 'setup'
            handle_connect_ke(extra)
          else
            handle_ke(target, options)
          end
        when 'ke-credits', 'credits'
          handle_ke_credits(options)
        when 'suggest', 'autocomplete'
          handle_suggest(target, options)
        when 'questions', 'paa', 'intent-questions'
          handle_questions(target, options)
        else
          raise "Unknown keyword command: #{command}"
        end
      end

      def handle_trends(keyword, options)
        geo = options[:geo] || 'US'
        time = options[:time] || '5y'
        puts Base::BANNER unless options[:json] || options[:in_dashboard]
        puts "📈 Querying Google Trends for: #{Color.c(keyword, Color::CYAN)} (Geo: #{geo.empty? ? 'Worldwide' : geo}, Time: #{time})...\n" unless options[:json]

        res = GoogleTrends.fetch(keyword, geo: geo, time: time)
        unless res[:ok]
          if options[:json]
            puts JSON.pretty_generate({ error: res[:error] })
          else
            puts Color.c("❌ Google Trends Error: #{res[:error]}", Color::RED)
          end
          return
        end

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        puts "#{Color::BOLD}Search Term:#{Color::RESET}      #{Color.c(res[:keyword], Color::CYAN, Color::BOLD)}"
        puts "#{Color::BOLD}Region / Geo:#{Color::RESET}     #{res[:geo]}"
        puts "#{Color::BOLD}Timeframe:#{Color::RESET}        #{res[:time]}"
        puts "#{Color::BOLD}Trend Velocity:#{Color::RESET}   #{Color.c(res[:velocity_badge], Color::GREEN, Color::BOLD)}"
        puts "#{Color::BOLD}Peak Demand:#{Color::RESET}      #{Color.c("#{res[:peak_score]}/100", Color::YELLOW)} (#{res[:peak_date]})"
        puts "#{Color::BOLD}Current Score:#{Color::RESET}    #{res[:current_score]} / 100"
        puts ""
        puts "#{Color::BOLD}Demand Trajectory:#{Color::RESET}"
        puts "  [ #{Color.c(res[:sparkline], Color::CYAN)} ]"
        puts ""

        if res[:regions].any?
          puts "#{Color::BOLD}🌍 Top Geographic Regions:#{Color::RESET}"
          res[:regions].each_with_index do |r, i|
            bar_len = [(r[:score] / 10.0).round, 10].min
            bar = "█" * bar_len + " " * (10 - bar_len)
            puts "  #{(i + 1).to_s.rjust(2)}. #{r[:name].ljust(22)} [#{Color.c(bar, Color::CYAN)}] #{r[:score].to_s.rjust(3)}/100"
          end
          puts ""
        end

        if res[:rising_queries].any?
          puts "#{Color::BOLD}🔥 Rising & Breakout Related Searches:#{Color::RESET}"
          res[:rising_queries].each do |q|
            badge_color = q[:growth] == 'Breakout' ? Color::GREEN : Color::YELLOW
            puts "  • #{q[:query].ljust(35)} [#{Color.c(q[:growth], badge_color, Color::BOLD)}]"
          end
          puts ""
        end

        if res[:top_queries].any?
          puts "#{Color::BOLD}💡 Top Related Searches:#{Color::RESET}"
          res[:top_queries].each do |q|
            puts "  • #{q[:query].ljust(35)} (#{q[:score]}/100)"
          end
          puts ""
        end
      end

      def render_keyword_table(keywords, limit: nil)
        displayed = limit ? keywords.first(limit) : keywords

        puts "#{Color::BOLD}Opp Score | Volume/mo | CPC     | Comp | Tier   | Trend% [12m] | GSC Status                  | Intent        | Keyword#{Color::RESET}"
        puts "--------------------------------------------------------------------------------------------------------------------------------"
        displayed.each do |r|
          score = r[:opportunity_score] || r['opportunity_score'] || 0
          score_color = if score >= 80 then Color::GREEN
                        elsif score >= 50 then Color::CYAN
                        else Color::YELLOW
                        end
          score_str = Color.c(score.to_s.rjust(9), score_color, Color::BOLD)

          vol = r[:volume] || r['volume'] || 0
          vol_str = vol.to_s.reverse.scan(/.{1,3}/).join(',').reverse.rjust(9)

          cpc = r[:cpc] || r['cpc'] || '$0.00'
          cpc_str = cpc.to_s.rjust(7)

          comp = r[:competition] || r['competition'] || 0.0
          comp_str = sprintf('%.2f', comp.to_f).rjust(4)

          tier = r[:competition_tier] || r['competition_tier'] || 'Low'
          tier_str = tier.to_s.ljust(6)

          trend_pct = (r[:trend_pct] || r['trend_pct'] || 0).to_i
          hist = r[:monthly_history] || r['monthly_history'] || {}
          spark = if hist.is_a?(Hash) && hist.size >= 3
                    KeywordPlanner.render_sparkline(hist.values.reverse, max_points: 6)
                  else
                    ""
                  end
          trend_raw = (trend_pct >= 0 ? "+#{trend_pct}%" : "#{trend_pct}%")
          trend_str = spark.empty? ? trend_raw.rjust(12) : "#{trend_raw.rjust(5)} #{spark}".ljust(12)

          gsc_data = r[:gsc] || r['gsc'] || {}
          gsc_status = gsc_data[:status] || gsc_data['status'] || '🚀 Untargeted'
          gsc_str = gsc_status.ljust(27)

          intent = r[:intent] || r['intent'] || 'Informational'
          intent_str = intent.to_s.ljust(13)

          kw = r[:keyword] || r['keyword'] || ''
          kw_str = Color.c(kw, Color::BOLD)

          puts "#{score_str} | #{vol_str} | #{cpc_str} | #{comp_str} | #{tier_str} | #{trend_str} | #{gsc_str} | #{intent_str} | #{kw_str}"
        end
        puts ""
      end

      def handle_saved(subcmd, target, options)
        hostname, site_url, _ = Base.resolve_domain(options[:domain], nil, options)
        list = Config.list_saved_keywords(hostname)
        sub = subcmd.to_s.downcase

        if sub == 'delete' || sub == 'rm'
          if target.nil? || target.strip.empty?
            puts Color.c("❌ Error: Specify snapshot ID or filename to delete (e.g. gsc saved delete 1)", Color::RED)
            return
          end
          ok = Config.delete_saved_keywords(hostname, target)
          if ok
            puts Color.c("🗑️ Deleted keyword research snapshot: #{target}", Color::GREEN)
          else
            puts Color.c("❌ Snapshot not found: #{target}", Color::RED)
          end
          return
        end

        if sub == 'view' || sub == 'show'
          identifier = target || '1'
          data = Config.load_saved_keywords(hostname, identifier)
          if data.nil?
            puts Color.c("❌ Could not find saved snapshot '#{identifier}' for #{hostname}", Color::RED)
            return
          end

          if options[:json]
            puts JSON.pretty_generate(data)
            return
          end

          puts Base::BANNER unless options[:in_dashboard]
          puts "📂 SAVED KEYWORD SNAPSHOT: #{Color.c(data['seed'].to_s, Color::CYAN, Color::BOLD)} (#{data['source']})"
          puts "   Domain: #{hostname} · Saved: #{data['savedAt']} · Total Keywords: #{data['totalKeywords']}\n\n"

          render_keyword_table(data['keywords'] || [], limit: options[:limit] || 50)
          puts Color.c("Showing Top #{[data['totalKeywords'], options[:limit] || 50].min} of #{data['totalKeywords']} keywords.", Color::GRAY)
          return
        end

        if sub == 'check' || sub == 'track' || sub == 'rankings'
          identifier = target || '1'
          data = Config.load_saved_keywords(hostname, identifier)
          if data.nil?
            puts Color.c("❌ Could not find saved snapshot '#{identifier}' for #{hostname}", Color::RED)
            return
          end

          puts Base::BANNER unless options[:in_dashboard]
          puts "🔍 RE-CHECKING SAVED KEYWORDS AGAINST GOOGLE SEARCH CONSOLE"
          puts "   Snapshot: #{Color.c(data['seed'].to_s, Color::CYAN, Color::BOLD)} (#{data['totalKeywords']} keywords)"
          puts "   Target Property: #{Color.c(site_url || hostname, Color::CYAN)}\n\n"

          key_path = Auth.find_key(options[:key])
          unless key_path
            puts Color.c("❌ Error: Service account JSON key not found. Run gsc connect to configure.", Color::RED)
            return
          end

          service_account = JSON.parse(File.read(key_path))
          token = Auth.fetch_access_token(service_account)
          client = Client.new(token: token)
          api = API.new(client)

          raw_keywords = (data['keywords'] || []).map do |kw|
            {
              keyword: kw['keyword'] || kw[:keyword],
              volume: (kw['volume'] || kw[:volume] || 0).to_i,
              cpc: kw['cpc'] || kw[:cpc] || '$0.00',
              competition: (kw['competition'] || kw[:competition] || 0.0).to_f,
              competition_tier: kw['competition_tier'] || kw[:competition_tier] || 'Low',
              trend_pct: (kw['trend_pct'] || kw[:trend_pct] || 0).to_i,
              opportunity_score: (kw['opportunity_score'] || kw[:opportunity_score] || 0).to_i,
              intent: kw['intent'] || kw[:intent] || 'Informational',
              monthly_history: kw['monthly_history'] || kw[:monthly_history] || {}
            }
          end

          updated = KeywordPlanner.correlate_with_gsc(raw_keywords, api, site_url, days: options[:days] || 30)

          if options[:json]
            puts JSON.pretty_generate({
              domain: hostname,
              siteUrl: site_url,
              seed: data['seed'],
              checkedAt: Time.now.utc.iso8601,
              totalKeywords: updated.size,
              keywords: updated
            })
            return
          end

          render_keyword_table(updated, limit: options[:limit] || 50)

          ranking_count = updated.count { |k| k.dig(:gsc, :status) != '🚀 Untargeted' }
          top3_count = updated.count { |k| k.dig(:gsc, :position).to_f > 0 && k.dig(:gsc, :position).to_f <= 3.0 }
          page1_count = updated.count { |k| k.dig(:gsc, :position).to_f > 3.0 && k.dig(:gsc, :position).to_f <= 10.0 }
          striking_count = updated.count { |k| k.dig(:gsc, :position).to_f > 10.0 && k.dig(:gsc, :position).to_f <= 20.0 }

          puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "#{Color::BOLD}📊 KEYWORD RANKING & OPPORTUNITY TRACKER (#{hostname})#{Color::RESET}"
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "  🏆 Top 3 Rankings:            #{Color.c(top3_count.to_s, Color::GREEN, Color::BOLD)}"
          puts "  🥇 Page 1 Rankings (4–10):    #{Color.c(page1_count.to_s, Color::GREEN, Color::BOLD)}"
          puts "  🎯 Striking Distance (11–20): #{Color.c(striking_count.to_s, Color::YELLOW, Color::BOLD)}"
          puts "  🚀 Untargeted / Unranked:      #{Color.c((updated.size - ranking_count).to_s, Color::GRAY)}"
          puts "  📈 Total Tracked Keywords:    #{updated.size}"
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"
          return
        end

        if options[:json]
          puts JSON.pretty_generate({ domain: hostname, snapshots: list })
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
        puts "📁 SAVED KEYWORD RESEARCH ARCHIVES (#{Color.c(hostname, Color::CYAN, Color::BOLD)})"
        puts "   Location: #{Config.domain_keywords_dir(hostname)}\n\n"

        if list.empty?
          puts Color.c("ℹ️ No saved keyword research found for #{hostname}.", Color::YELLOW)
          puts "\n💡 Quick Start:"
          puts "   Run #{Color.c('gsc import docs/KW.md', Color::CYAN)} to import and save an export."
          puts "   Or run #{Color.c('gsc planner "seo audit" --save', Color::CYAN)} to save search ideas."
          puts
          return
        end

        puts "#{Color::BOLD}  # | Date       | Source                | Keywords | Seed / File#{Color::RESET}"
        puts "  --------------------------------------------------------------------------------"
        list.each_with_index do |item, idx|
          num = "[#{idx + 1}]".rjust(4)
          date_str = item['savedAt'].to_s.split('T').first.ljust(10)
          source_str = item['source'].to_s.gsub('_', ' ').capitalize.ljust(21)
          kw_count = item['totalKeywords'].to_s.rjust(8)
          seed_str = Color.c(item['seed'].to_s, Color::CYAN)
          puts "#{Color.c(num, Color::CYAN, Color::BOLD)} | #{date_str} | #{source_str} | #{kw_count} | #{seed_str}"
        end

        puts "\n💡 Commands:"
        puts "   #{Color.c('gsc saved view 1', Color::CYAN)}    # View stored keywords & metrics"
        puts "   #{Color.c('gsc saved check 1', Color::GREEN)}   # Re-check live against Search Console rankings"
        puts "   #{Color.c('gsc saved delete 1', Color::RED)}  # Delete archive snapshot"
        puts
      end

      def handle_planner_import(filepath, options)
        src_arg = filepath.to_s.strip
        if src_arg.empty?
          clip_sample = KeywordPlanner.read_clipboard.to_s
          if clip_sample.include?("\t") || clip_sample =~ /keyword/i
            src_arg = 'clipboard'
          else
            if options[:json]
              puts JSON.pretty_generate({ error: 'Please specify a file path or use clipboard (e.g. gsc import keywords.csv or gsc import clip)' })
            else
              puts Color.c("❌ Error: Please specify a file path to import or copy keyword data to clipboard.", Color::RED)
              puts "   Usage: #{Color.c('gsc import path/to/keywords.csv', Color::CYAN)}"
              puts "          #{Color.c('gsc import clip', Color::GREEN)}  (Imports directly from copied table)"
            end
            return
          end
        end

        puts Base::BANNER unless options[:json] || options[:in_dashboard]
        src_label = src_arg =~ /clip/i ? 'macOS Clipboard' : src_arg
        puts "📥 Importing keyword dataset from: #{Color.c(src_label, Color::CYAN)}...\n" unless options[:json]

        raw_keywords = KeywordPlanner.import_file(src_arg)

        api = nil
        site_url = nil
        begin
          key_path = Auth.find_key(options[:key])
          if key_path
            service_account = JSON.parse(File.read(key_path))
            token = Auth.fetch_access_token(service_account)
            client = Client.new(token: token)
            api = API.new(client)
            hostname, site_url, _ = Base.resolve_domain(options[:domain], nil, options)
            puts "🔗 Cross-referencing against Google Search Console: #{Color.c(site_url, Color::CYAN)}...\n" unless options[:json]
          end
        rescue StandardError
        end

        keywords = KeywordPlanner.correlate_with_gsc(raw_keywords, api, site_url, days: options[:days] || 30)
        limit = options[:limit] || 35
        displayed = keywords.first(limit)

        if options[:json]
          puts JSON.pretty_generate({
            file: filepath,
            totalKeywords: keywords.size,
            siteUrl: site_url,
            keywords: displayed
          })
          return
        end

        render_keyword_table(keywords, limit: limit)

        active_dom = hostname || Config.default_domain || 'global'
        src_label = (src_arg =~ /clip/i) ? 'clipboard-export' : File.basename(src_arg, '.*')
        saved_path = Config.save_keyword_research(active_dom, src_label, keywords, source: 'import')
        puts Color.c("💾 Saved snapshot to domain archive: #{saved_path}", Color::CYAN)
        puts "   Re-check anytime with: #{Color.c('gsc saved check 1', Color::GREEN)} or #{Color.c('gsc saved view 1', Color::YELLOW)}\n"
      end

      def handle_connect_ke(key_arg = nil)
        puts Base::BANNER unless $stdout.tty? == false
        puts "#{Color::BOLD}🔑 KEYWORDS EVERYWHERE API SETUP#{Color::RESET}\n"

        key = key_arg.to_s.strip
        if key.empty?
          existing = Config.keywords_everywhere_api_key
          if existing && !existing.empty?
            masked = "#{existing[0..5]}...#{existing[-4..]}" rescue "******"
            puts "Current API Key: #{Color.c(masked, Color::CYAN)}"
            print "Enter new API key (or press Enter to keep current): "
            input = $stdin.gets&.strip
            key = input unless input.nil? || input.empty?
            key = existing if key.empty?
          else
            puts "Get your Keywords Everywhere API key at: #{Color.c('https://keywordseverywhere.com/', Color::UNDERLINE)}"
            print "Paste your Keywords Everywhere API Key: "
            key = $stdin.gets&.strip
          end
        end

        if key.nil? || key.empty?
          puts Color.c("\n❌ No API key provided.", Color::RED)
          return
        end

        puts "\n⏳ Validating key with Keywords Everywhere API..."
        acct = KeywordsEverywhere.check_account(key)
        if acct[:ok]
          Config.set_keywords_everywhere_api_key(key)
          fmt_credits = acct[:credits].to_s.reverse.gsub(/(\d{3})(?=\d)/, ',').reverse
          puts Color.c("\n✅ SUCCESS! Keywords Everywhere API key connected.", Color::GREEN, Color::BOLD)
          puts "   💰 Remaining Credits: #{Color.c(fmt_credits, Color::CYAN, Color::BOLD)}"
          puts "   📁 Saved to: #{Color.c(Config::CONFIG_FILE, Color::GRAY)}"

          if acct[:credits].to_i == 0
            puts "\n" + Color.c("ℹ️ FREE ACCOUNT DETECTED (0 REST API Credits)", Color::YELLOW, Color::BOLD)
            puts "Keywords Everywhere gives free accounts #{Color.c('500 free lookups/day in their Web UI', Color::GREEN)},"
            puts "while their REST API requires purchased credits (1 credit = 1 keyword).\n\n"
            puts "#{Color::BOLD}🚀 3 FAST WORKFLOWS YOU CAN USE RIGHT NOW:#{Color::RESET}"
            puts "  1. #{Color.c('Free 500/day on Web + 1-Click Clipboard Import:', Color::GREEN, Color::BOLD)}"
            puts "     • Check search volume at: #{Color.c('https://keywordseverywhere.com/tools/bulk-keywords-data', Color::UNDERLINE)}"
            puts "     • Click 'Copy' -> Run: #{Color.c('gsc import clip', Color::CYAN, Color::BOLD)}"
            puts "  2. #{Color.c('100% Free Live Google Trends (Breakout & Related terms):', Color::BLUE, Color::BOLD)}"
            puts "     • Run: #{Color.c('gsc trends "seo audit"', Color::BLUE, Color::BOLD)}"
            puts "  3. #{Color.c('Top Up Credits for Automated Background CLI Lookups:', Color::GRAY, Color::BOLD)}"
            puts "     • Purchase credits at: https://keywordseverywhere.com/credit-packages.html"
            puts "     • Your key is already saved; it will work immediately upon top-up.\n"
          else
            puts "\nTry searching keywords:"
            puts "   #{Color.c('gsc ke "seo audit"', Color::YELLOW)}"
          end
        else
          puts Color.c("\n❌ Invalid API Key: #{acct[:error]}", Color::RED)
          puts "Please check your key and try again: #{Color.c('gsc connect ke', Color::CYAN)}"
        end
      end

      def handle_ke_credits(options = {})
        acct = KeywordsEverywhere.check_account
        if options[:json]
          puts JSON.pretty_generate(acct)
          return
        end
        if acct[:ok]
          fmt_credits = acct[:credits].to_s.reverse.gsub(/(\d{3})(?=\d)/, ',').reverse
          puts "\n💰 #{Color::BOLD}Keywords Everywhere Account Credits:#{Color::RESET} #{Color.c(fmt_credits, Color::GREEN, Color::BOLD)}"
          if acct[:credits].to_i == 0
            puts "\n" + Color.c("ℹ️ You have 0 paid REST API credits remaining.", Color::YELLOW)
            puts "• Free Web Alternative: Check volume on keywordseverywhere.com, click 'Copy', then run: #{Color.c('gsc import clip', Color::CYAN)}"
            puts "• Free Live Trends: #{Color.c('gsc trends "seo audit"', Color::BLUE)}"
            puts "• Top up credits at: https://keywordseverywhere.com/credit-packages.html"
          end
        else
          if acct[:error].to_s =~ /401|Unauthorized/i
            puts Color.c("\n❌ Invalid or expired API Key: #{acct[:error]}", Color::RED)
            puts "Update your key: #{Color.c('gsc connect ke', Color::CYAN)}"
          else
            puts Color.c("\n❌ Error: #{acct[:error]}", Color::RED)
            puts "Connect your key: #{Color.c('gsc connect ke', Color::CYAN)}"
          end
        end
      end

      def handle_ke(target, options = {})
        if target.nil? || target.strip.empty?
          puts Color.c("❌ Please provide a seed keyword or file path. e.g.: gsc ke 'seo audit'", Color::RED)
          return
        end

        country = options[:country] || 'us'
        currency = options[:currency] || 'usd'
        limit = (options[:limit] || 25).to_i

        unless KeywordsEverywhere.api_key
          if options[:json]
            puts JSON.pretty_generate({
              ok: false,
              error: "Keywords Everywhere API key not configured",
              recommendations: [
                { action: 'connect', cmd: 'gsc connect ke', desc: 'Connect Keywords Everywhere API key' },
                { action: 'google_trends', cmd: "gsc trends \"#{target}\"", desc: 'Use 100% free Google Trends without any API key' },
                { action: 'import_clipboard', cmd: 'gsc import clip', desc: 'Import 500 daily free web lookups from clipboard' }
              ]
            })
          else
            puts Color.c("\n❌ Keywords Everywhere API key not configured!\n", Color::RED, Color::BOLD)
            puts "#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
            puts "  1. Connect a key: #{Color.c('gsc connect ke', Color::CYAN, Color::BOLD)} (Get key at https://keywordseverywhere.com/)"
            puts "  2. Use 100% free Google Trends (No key needed!): #{Color.c("gsc trends \"#{target}\"", Color::BLUE, Color::BOLD)}"
            puts "  3. Use 500 free daily web lookups: Copy web table -> #{Color.c('gsc import clip', Color::GREEN, Color::BOLD)}\n"
          end
          return
        end

        keywords_to_check = []
        is_file = File.exist?(target) || target.end_with?('.csv', '.tsv', '.txt')
        if is_file
          if File.exist?(target)
            content = File.read(target, encoding: 'UTF-8') rescue ''
            keywords_to_check = content.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
          else
            puts Color.c("❌ File not found: #{target}", Color::RED)
            return
          end
        else
          suggestions = KeywordPlanner.expand(target, country: country, limit: [limit, 50].min)
          keywords_to_check = ([target] + suggestions).uniq
        end

        keywords_to_check = keywords_to_check.first([limit, 100].max)

        puts "⏳ Fetching volume & CPC data from Keywords Everywhere API..." unless options[:json]

        res = KeywordsEverywhere.fetch_data(keywords_to_check, country: country, currency: currency)
        unless res[:ok]
          err_str = res[:error].to_s
          if options[:json]
            reason = if err_str =~ /402|Insufficient Credits/i
                       'insufficient_credits'
                     elsif err_str =~ /401|Unauthorized/i
                       'unauthorized'
                     elsif err_str =~ /429|Rate Limit/i
                       'rate_limited'
                     else
                       'api_error'
                     end
            puts JSON.pretty_generate({
              ok: false,
              error: err_str,
              reason: reason,
              recommendations: [
                { action: 'import_clipboard', cmd: 'gsc import clip', desc: 'Use 500 free daily web lookups on keywordseverywhere.com and import via clipboard' },
                { action: 'google_trends', cmd: "gsc trends \"#{target}\"", desc: '100% Free real-time search interest & rising breakout queries' },
                { action: 'gsc_analytics', cmd: 'gsc top-queries', desc: 'Real impressions & clicks from your active Google Search Console domain' },
                { action: 'topup', url: 'https://keywordseverywhere.com/credit-packages.html', desc: 'Purchase API credits to enable automated background CLI lookups' }
              ]
            })
            return
          end

          if err_str =~ /402|Insufficient Credits/i
            puts Color.c("\n💳 Keywords Everywhere: Insufficient API Credits (0 remaining)\n", Color::YELLOW, Color::BOLD)
            puts "Your API key is active, but Keywords Everywhere's REST API requires paid credits."
            puts "The 500 free lookups/day are available on their website.\n\n"
            puts "#{Color::BOLD}🚀 4 RECOMMENDED ALTERNATIVES (START RIGHT NOW):#{Color::RESET}\n"
            puts "  1. #{Color.c('Free 500 Lookups / Day on Web + 1-Click Clipboard Import', Color::GREEN, Color::BOLD)}"
            puts "     • Go to: #{Color.c('https://keywordseverywhere.com/tools/bulk-keywords-data', Color::UNDERLINE)}"
            puts "     • Enter keywords -> Click #{Color.c('Check Volume', Color::BOLD)} -> Click #{Color.c('Copy', Color::CYAN)}"
            puts "     • In your terminal, run:"
            puts "       #{Color.c('gsc import clip', Color::CYAN, Color::BOLD)}\n"
            puts "  2. #{Color.c('Google Trends Intelligence (100% Free, Zero Setup)', Color::BLUE, Color::BOLD)}"
            puts "     • Live interest curves, breakout queries, and seasonal demand:"
            puts "       #{Color.c("gsc trends \"#{target}\"", Color::BLUE, Color::BOLD)}\n"
            puts "  3. #{Color.c('Your Real Search Console Rankings & Opportunities', Color::MAGENTA, Color::BOLD)}"
            puts "     • High-impression queries and Page 2 striking-distance keywords:"
            puts "       #{Color.c('gsc top-queries', Color::MAGENTA, Color::BOLD)}  or  #{Color.c('gsc opportunities', Color::MAGENTA, Color::BOLD)}\n"
            puts "  4. #{Color.c('Top Up API Credits for Automated Background CLI Lookups', Color::GRAY, Color::BOLD)}"
            puts "     • Purchase credits at: #{Color.c('https://keywordseverywhere.com/credit-packages.html', Color::UNDERLINE)}"
            puts "     • Your key is already saved; it will work immediately once credited.\n"
          elsif err_str =~ /401|Unauthorized/i
            puts Color.c("\n🔑 Invalid or Expired Keywords Everywhere API Key", Color::RED, Color::BOLD)
            puts "Your API key was rejected by api.keywordseverywhere.com (HTTP 401).\n\n"
            puts "#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
            puts "  • Check or generate your API key at: #{Color.c('https://keywordseverywhere.com/first-install-addon.html', Color::UNDERLINE)}"
            puts "  • Reconnect key: #{Color.c('gsc connect ke <KEY>', Color::CYAN, Color::BOLD)}"
            puts "  • Or use free Google Trends without any key: #{Color.c("gsc trends \"#{target}\"", Color::BLUE)}"
          elsif err_str =~ /429|Rate Limit/i
            puts Color.c("\n⏳ Keywords Everywhere Rate Limit Exceeded", Color::YELLOW, Color::BOLD)
            puts "Too many requests were sent in a short period.\n\n"
            puts "#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
            puts "  • Wait 15-30 seconds and retry: #{Color.c("gsc ke \"#{target}\"", Color::CYAN)}"
            puts "  • Reduce batch size with: #{Color.c("gsc ke \"#{target}\" --limit 10", Color::CYAN)}"
          else
            puts Color.c("\n❌ Keywords Everywhere API Error: #{err_str}", Color::RED)
            puts "\n#{Color::BOLD}RECOMMENDATIONS:#{Color::RESET}"
            puts "  • Try free Google Trends instead: #{Color.c("gsc trends \"#{target}\"", Color::BLUE)}"
            puts "  • Or check account status with: #{Color.c('gsc ke-credits', Color::CYAN)}"
          end
          return
        end

        items = res[:data]

        site_url = options[:site] || Config.default_domain
        has_gsc = false
        if site_url && Auth.find_key(options[:key])
          begin
            auth = Auth.new(Auth.find_key(options[:key]))
            api = API.new(auth.token)
            items = KeywordPlanner.correlate_with_gsc(items, api, site_url, days: options[:days] || 30)
            has_gsc = true
          rescue StandardError
          end
        end

        items.sort_by! { |i| [-i[:opportunity_score].to_i, -i[:volume].to_i] }
        items = items.first(limit)

        if options[:json]
          puts JSON.pretty_generate({
            seed: target,
            provider: 'keywordseverywhere',
            country: country,
            currency: currency,
            count: items.size,
            siteUrl: site_url,
            keywords: items
          })
          return
        end

        puts "\n#{Color::BOLD}🔍 KEYWORDS EVERYWHERE SEARCH DEMAND#{Color::RESET} (Seed: #{Color.c(target, Color::CYAN)})"
        puts "   Country: #{country.upcase} · Provider: Google Keyword Planner via Keywords Everywhere API"
        puts "   Correlated with GSC: #{has_gsc ? Color.c(site_url, Color::GREEN) : Color.c('None', Color::GRAY)}\n\n"

        printf "  %-34s %10s %8s %7s %10s  %-14s %s\n",
               "KEYWORD", "VOL/MO", "CPC", "COMP", "OPP SCORE", "INTENT", (has_gsc ? "GSC RANK STATUS" : "")
        puts "  " + ("─" * (has_gsc ? 110 : 85))

        items.each do |item|
          opp = item[:opportunity_score]
          opp_color = opp >= 70 ? Color::GREEN : (opp >= 45 ? Color::YELLOW : Color::GRAY)
          cpc_str = format("$%.2f", item[:cpc])
          vol_str = item[:volume] > 0 ? item[:volume].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse : '-'
          comp_str = format("%.2f", item[:competition])

          intent_color = case item[:intent]
                         when 'Transactional' then Color::GREEN
                         when 'Commercial'    then Color::CYAN
                         when 'Informational' then Color::MAGENTA
                         else                      Color::GRAY
                         end

          gsc_col = (has_gsc && item[:gsc]) ? item[:gsc][:status] : ""

          printf "  %-34s %10s %8s %7s   %s  %-14s %s\n",
                 Color.c(item[:keyword].to_s[0..33], Color::BOLD),
                 vol_str,
                 cpc_str,
                 comp_str,
                 Color.c(format("%3d/100", opp), opp_color, Color::BOLD),
                 Color.c(item[:intent], intent_color),
                 gsc_col
        end

        puts "  " + ("─" * (has_gsc ? 110 : 85))
        puts "  💡 #{Color::BOLD}Opportunity Score (0-100):#{Color::RESET} High search volume + low ad competition index."
        puts
      end

      def handle_planner_expand(seed, options)
        if seed.nil? || seed.strip.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Please specify a seed keyword (e.g. gsc planner "seo audit")' })
          else
            puts Color.c("❌ Error: Please specify a seed keyword.", Color::RED)
            puts "   Usage: #{Color.c('gsc planner "seo audit"', Color::CYAN)}"
          end
          return
        end

        puts Base::BANNER unless options[:json] || options[:in_dashboard]
        country = options[:country] || 'us'
        limit = options[:limit] || 40
        puts "💡 Expanding keyword ideas for seed: #{Color.c(seed, Color::CYAN)} (Country: #{country})...\n" unless options[:json]

        raw_keywords = KeywordPlanner.expand(seed, country: country, limit: limit)

        api = nil
        site_url = nil
        begin
          key_path = Auth.find_key(options[:key])
          if key_path
            service_account = JSON.parse(File.read(key_path))
            token = Auth.fetch_access_token(service_account)
            client = Client.new(token: token)
            api = API.new(client)
            hostname, site_url, _ = Base.resolve_domain(options[:domain], nil, options)
            puts "🔗 Cross-referencing against Google Search Console: #{Color.c(site_url, Color::CYAN)}...\n" unless options[:json]
          end
        rescue StandardError
        end

        keywords = KeywordPlanner.correlate_with_gsc(raw_keywords, api, site_url, days: options[:days] || 30)

        if options[:json]
          puts JSON.pretty_generate({
            seed: seed,
            country: country,
            siteUrl: site_url,
            count: keywords.size,
            suggestions: keywords
          })
          return
        end

        puts "#{Color::BOLD}Intent        | GSC Status                  | Keyword Suggestion#{Color::RESET}"
        puts "--------------------------------------------------------------------------------------------------"
        keywords.each do |r|
          intent_color = case r[:intent]
                         when 'Commercial' then Color::YELLOW
                         when 'Transactional' then Color::GREEN
                         when 'Informational' then Color::CYAN
                         else Color::GRAY
                         end
          intent_str = Color.c(r[:intent].ljust(13), intent_color)
          gsc_status = r.dig(:gsc, :status) || '🚀 Untargeted'
          gsc_str = gsc_status.ljust(27)
          kw_str = Color.c(r[:keyword], Color::BOLD)

          puts "#{intent_str} | #{gsc_str} | #{kw_str}"
        end
        puts ""
        puts Color.c("Total Keyword Ideas Generated: #{keywords.size}", Color::GRAY)
        puts ""
      end

      def handle_suggest(target, options)
        query = target.to_s.strip
        if query.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Query required. Example: gsc suggest "seo audit"' })
          else
            puts Color.c("❌ Error: Query required. Example: gsc suggest \"seo audit\"", Color::RED)
          end
          return
        end

        alphabet = options[:alphabet] || false
        suggest = GSC::GoogleSuggest.new(query, options)
        results = suggest.fetch(alphabet: alphabet, questions: false)

        if options[:json]
          puts JSON.pretty_generate(results)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_questions(target, options)
        query = target.to_s.strip
        if query.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'Query required. Example: gsc questions "seo audit"' })
          else
            puts Color.c("❌ Error: Query required. Example: gsc questions \"seo audit\"", Color::RED)
          end
          return
        end

        suggest = GSC::GoogleSuggest.new(query, options)
        results = suggest.fetch(questions: true)

        if options[:json]
          puts JSON.pretty_generate(results)
          return
        end

        puts Base::BANNER unless options[:in_dashboard]
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
    end
  end
end

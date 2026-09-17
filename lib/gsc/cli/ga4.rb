# frozen_string_literal: true

require 'json'
require_relative 'base'

module GSC
  class CLI
    module GA4
      module_function

      def run(command, target, extra, options, api, hostname, site_url)
        case command
        when 'ga4', 'bounce'
          handle_ga4(api, hostname, options)
        when 'correlation', 'engagement'
          handle_correlation(api, hostname, site_url, options)
        when 'ga4-properties', 'ga4-list'
          handle_ga4_properties(api, hostname, options)
        when 'realtime', 'live', 'r'
          handle_realtime(api, hostname, options)
        when 'ads', 'campaigns'
          handle_ads(api, hostname, options)
        when 'channels', 'traffic'
          handle_channels(api, hostname, options)
        else
          raise "Unknown GA4 command: #{command}"
        end
      end

      def handle_ga4(api, hostname, options)
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "No GA4 property linked for domain '#{hostname}'. Run 'gsc config set-ga4 <property_id> -d #{hostname}' or pass '--property <id>'."
            })
          else
            puts "\n#{Color.c("⚠️  No GA4 Property ID linked for domain: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "\nGoogle Analytics 4 is not yet linked for #{Color.c(hostname, Color::CYAN)}."
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify a property ID directly:"
            puts "   #{Color.c("gsc ga4 --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        traffic_label = options[:organic] ? "Organic Search Only" : "All Traffic"
        puts "📈 Fetching GA4 landing page behavioral metrics for #{Color.c(hostname, Color::CYAN)} [Property #{property_id}] (#{traffic_label}, Past #{options[:days]} days)..." unless options[:json]

        limit = (options[:limit] || 25) * 3
        res = api.query_ga4_report(property_id, days: options[:days], limit: limit, organic_only: options[:organic], hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          if raw_rows.empty?
            if options[:json]
              puts JSON.pretty_generate([])
            else
              puts Color.c("⚠️ No landing page behavioral data found in GA4 for this date range.", Color::YELLOW)
            end
            return
          end

          pages_map = {}
          raw_rows.each do |row|
            path_val = row.dig('dimensionValues', 0, 'value') || '/'
            norm = Base.normalize_path(path_val)

            sessions = row.dig('metricValues', 0, 'value').to_i
            users    = row.dig('metricValues', 1, 'value').to_i
            eng_rate = row.dig('metricValues', 2, 'value').to_f
            bounce   = row.dig('metricValues', 3, 'value').to_f
            duration = row.dig('metricValues', 4, 'value').to_f
            views    = row.dig('metricValues', 5, 'value').to_i

            pages_map[norm] ||= { path: norm, sessions: 0, users: 0, views: 0, total_duration_secs: 0.0, weighted_eng: 0.0, weighted_bounce: 0.0 }
            entry = pages_map[norm]
            entry[:sessions] += sessions
            entry[:users] += users
            entry[:views] += views
            entry[:total_duration_secs] += (duration * sessions)
            entry[:weighted_eng] += (eng_rate * sessions)
            entry[:weighted_bounce] += (bounce * sessions)
          end

          data = pages_map.values.map do |e|
            s = e[:sessions]
            avg_eng = s.positive? ? (e[:weighted_eng] / s) * 100.0 : 0.0
            avg_bounce = s.positive? ? (e[:weighted_bounce] / s) * 100.0 : 0.0
            avg_dur = s.positive? ? (e[:total_duration_secs] / s) : 0.0

            {
              path: e[:path],
              sessions: s,
              users: e[:users],
              views: e[:views],
              engagement_rate: avg_eng.round(1),
              bounce_rate: avg_bounce.round(1),
              duration_seconds: avg_dur.round(1),
              duration_formatted: Base.format_duration(avg_dur)
            }
          end

          sort_key = case options[:sort]&.to_s&.downcase
          when 'bounce' then :bounce_rate
          when 'eng', 'engagement' then :engagement_rate
          when 'dur', 'duration', 'time' then :duration_seconds
          when 'views', 'pageviews' then :views
          when 'users' then :users
          else :sessions
          end

          is_asc = (options[:order] == 'asc')
          data.sort_by! { |d| d[sort_key] || 0 }
          data.reverse! unless is_asc

          display_rows = data.first(options[:limit] || 25)

          if options[:json]
            puts JSON.pretty_generate(display_rows)
          else
            puts "\n#{Color::BOLD}Sessions | Bounce | Eng Rate | Avg Time | Views | Landing Page Path#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            display_rows.each do |r|
              s_col = r[:sessions].to_s.ljust(8)

              b_pct = "#{r[:bounce_rate]}%"
              b_col = if r[:bounce_rate] >= 70.0
                Color.c(b_pct.ljust(6), Color::RED, Color::BOLD)
              elsif r[:bounce_rate] <= 40.0
                Color.c(b_pct.ljust(6), Color::GREEN)
              else
                b_pct.ljust(6)
              end

              e_col = "#{r[:engagement_rate]}%".ljust(8)
              d_col = r[:duration_formatted].ljust(8)
              v_col = r[:views].to_s.ljust(5)
              p_col = Color.c(r[:path], Color::CYAN)

              puts "#{s_col} | #{b_col} | #{e_col} | #{d_col} | #{v_col} | #{p_col}"
            end

            puts "\nTotal Landing Pages: #{data.size} (Showing #{display_rows.size})\n"
          end

          if options[:csv]
            csv_rows = display_rows.map do |r|
              [r[:path], r[:sessions], r[:users], "#{r[:bounce_rate]}%", "#{r[:engagement_rate]}%", r[:duration_seconds], r[:views]]
            end
            Base.write_csv(options[:csv], %w[Path Sessions ActiveUsers BounceRate EngagementRate DurationSeconds PageViews], csv_rows)
            puts Color.c("📁 Exported GA4 report to #{options[:csv]}", Color::CYAN) unless options[:json]
          end
        else
          handle_ga4_api_error(res, property_id, hostname, options)
        end
      end

      def handle_correlation(api, hostname, site_url, options)
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Correlation requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Correlation requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "\nSearch Console measures #{Color::BOLD}Pre-Click SERP rankings#{Color::RESET}, while GA4 measures #{Color::BOLD}Post-Click on-site behavior#{Color::RESET}."
            puts "To correlate them, link your GA4 Property ID to this domain:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc correlation --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        traffic_mode = options[:organic] ? "Organic Search Only" : "All Traffic"
        puts "🔗 Correlating Search Console Rankings with GA4 On-Site Behavior for #{Color.c(hostname, Color::CYAN)}..." unless options[:json]
        puts "   GSC: #{Color.c(site_url, Color::CYAN)} | GA4 Property: #{Color.c(property_id, Color::MAGENTA)} (#{traffic_mode}, #{options[:days]}d)\n" unless options[:json]

        gsc_res = api.query_analytics(site_url, days: options[:days], dimensions: ['page'], row_limit: 250)
        unless gsc_res[:ok]
          if options[:json]
            puts JSON.pretty_generate({ error: "GSC Error: #{gsc_res[:data]}" })
          else
            puts Color.c("❌ Search Console Error (#{gsc_res[:status]}): #{gsc_res[:data]}", Color::RED)
          end
          return
        end

        ga4_res = api.query_ga4_report(property_id, days: options[:days], limit: 250, organic_only: options[:organic], hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        unless ga4_res[:ok]
          handle_ga4_api_error(ga4_res, property_id, hostname, options)
          return
        end

        gsc_rows = gsc_res.dig(:data, 'rows') || []
        ga4_rows = ga4_res.dig(:data, 'rows') || []

        ga4_index = {}
        ga4_rows.each do |r|
          path_val = r.dig('dimensionValues', 0, 'value') || '/'
          norm = Base.normalize_path(path_val)

          sessions = r.dig('metricValues', 0, 'value').to_i
          eng_rate = r.dig('metricValues', 2, 'value').to_f
          bounce   = r.dig('metricValues', 3, 'value').to_f
          dur      = r.dig('metricValues', 4, 'value').to_f
          views    = r.dig('metricValues', 5, 'value').to_i

          ga4_index[norm] ||= { sessions: 0, views: 0, total_dur: 0.0, weighted_eng: 0.0, weighted_bounce: 0.0 }
          e = ga4_index[norm]
          e[:sessions] += sessions
          e[:views] += views
          e[:total_dur] += (dur * sessions)
          e[:weighted_eng] += (eng_rate * sessions)
          e[:weighted_bounce] += (bounce * sessions)
        end

        merged = []
        gsc_seen = {}

        gsc_rows.each do |row|
          full_url = row['keys'][0]
          norm = Base.normalize_path(full_url)
          gsc_seen[norm] = true

          clicks = row['clicks'].to_i
          imp    = row['impressions'].to_i
          pos    = row['position'].to_f.round(1)
          ctr    = (row['ctr'].to_f * 100.0).round(1)

          ga4_data = ga4_index[norm]
          if ga4_data
            s = ga4_data[:sessions]
            b_rate = s.positive? ? (ga4_data[:weighted_bounce] / s) * 100.0 : 0.0
            e_rate = s.positive? ? (ga4_data[:weighted_eng] / s) * 100.0 : 0.0
            dur    = s.positive? ? (ga4_data[:total_dur] / s) : 0.0
          else
            s = 0
            b_rate = 0.0
            e_rate = 0.0
            dur = 0.0
          end

          diagnosis = if clicks >= 10 && dur >= 90.0
            '🛠️ ENGAGED TOOL'
          elsif clicks >= 10 && b_rate >= 70.0 && dur < 45.0
            '🚨 HIGH BOUNCE'
          elsif pos >= 7.0 && (dur >= 60.0 || (s >= 10 && b_rate <= 35.0))
            '⭐ HIDDEN GEM'
          elsif clicks >= 15 && s < 5
            '⚠️ TRACKING GAP'
          elsif pos <= 5.0 && ctr >= 5.0 && b_rate <= 50.0 && s >= 10
            '💎 WINNER'
          elsif s.zero? && clicks.zero?
            '💤 DORMANT'
          else
            'HEALTHY'
          end

          merged << {
            path: norm,
            url: full_url,
            clicks: clicks,
            impressions: imp,
            position: pos,
            ctr: ctr,
            sessions: s,
            bounce_rate: b_rate.round(1),
            engagement_rate: e_rate.round(1),
            duration_seconds: dur.round(1),
            duration_formatted: Base.format_duration(dur),
            diagnosis: diagnosis
          }
        end

        ga4_index.each do |norm, e|
          next if gsc_seen[norm]
          s = e[:sessions]
          b_rate = s.positive? ? (e[:weighted_bounce] / s) * 100.0 : 0.0
          e_rate = s.positive? ? (e[:weighted_eng] / s) * 100.0 : 0.0
          dur    = s.positive? ? (e[:total_dur] / s) : 0.0

          merged << {
            path: norm,
            url: "https://#{hostname}#{norm}",
            clicks: 0,
            impressions: 0,
            position: 99.0,
            ctr: 0.0,
            sessions: s,
            bounce_rate: b_rate.round(1),
            engagement_rate: e_rate.round(1),
            duration_seconds: dur.round(1),
            duration_formatted: Base.format_duration(dur),
            diagnosis: 'DIRECT/REFERRAL'
          }
        end

        merged.sort_by! { |m| [m[:diagnosis] == '🚨 HIGH BOUNCE' ? 0 : 1, -m[:clicks], -m[:sessions]] }
        display_rows = merged.first(options[:limit] || 25)

        if options[:json]
          puts JSON.pretty_generate(display_rows)
        else
          puts "#{Color::BOLD}GSC Clicks | GSC Pos | GA4 Sess | Bounce | Avg Time | Insight               | Page Path#{Color::RESET}"
          puts "---------------------------------------------------------------------------------------------------------"
          display_rows.each do |r|
            c_col = r[:clicks].to_s.ljust(10)
            p_col = r[:position].to_s.ljust(7)
            s_col = r[:sessions].to_s.ljust(8)

            b_pct = "#{r[:bounce_rate]}%"
            b_col = if r[:bounce_rate] >= 70.0 && r[:sessions] > 0
              Color.c(b_pct.ljust(6), Color::RED, Color::BOLD)
            elsif r[:bounce_rate] <= 40.0 && r[:sessions] > 0
              Color.c(b_pct.ljust(6), Color::GREEN)
            else
              b_pct.ljust(6)
            end

            t_col = r[:duration_formatted].ljust(8)

            diag_str = case r[:diagnosis]
            when '🚨 HIGH BOUNCE' then Color.c('🚨 HIGH BOUNCE'.ljust(21), Color::RED, Color::BOLD)
            when '🛠️ ENGAGED TOOL' then Color.c('🛠️ ENGAGED TOOL'.ljust(21), Color::CYAN, Color::BOLD)
            when '⭐ HIDDEN GEM' then Color.c('⭐ HIDDEN GEM'.ljust(21), Color::YELLOW, Color::BOLD)
            when '⚠️ TRACKING GAP' then Color.c('⚠️ TRACKING GAP'.ljust(21), Color::YELLOW)
            when '💎 WINNER' then Color.c('💎 WINNER'.ljust(21), Color::GREEN, Color::BOLD)
            else Color.c(r[:diagnosis].ljust(21), Color::GRAY)
            end

            path_col = Color.c(r[:path], Color::CYAN)

            puts "#{c_col} | #{p_col} | #{s_col} | #{b_col} | #{t_col} | #{diag_str} | #{path_col}"
          end

          high_bounce = merged.select { |m| m[:diagnosis] == '🚨 HIGH BOUNCE' }
          gems        = merged.select { |m| m[:diagnosis] == '⭐ HIDDEN GEM' }
          tools       = merged.select { |m| m[:diagnosis] == '🛠️ ENGAGED TOOL' }

          if tools.any?
            puts "\n💡 #{Color::BOLD}Engaged Tool / Utility Action Plan:#{Color::RESET} #{tools.size} interactive pages show exceptional time on page (>90s). Since users get their answer and leave, add embedded CTAs, related tools, or app trials to convert these active users."
          end
          if high_bounce.any?
            puts "💡 #{Color::BOLD}High Bounce Action Plan:#{Color::RESET} #{high_bounce.size} pages receive search clicks but abandon quickly (<45s with >70% bounce). Check for search intent mismatch (e.g. consumer searches landing on B2B features) or optimize above-the-fold content."
          end
          if gems.any?
            puts "💡 #{Color::BOLD}Hidden Gem Action Plan:#{Color::RESET} #{gems.size} pages show exceptional visitor stickiness despite lower rankings. Build internal links from your homepage to push them into the Top 3 on Google."
          end
          puts
        end

        if options[:csv]
          csv_rows = display_rows.map do |r|
            [r[:path], r[:url], r[:clicks], r[:impressions], r[:position], "#{r[:ctr]}%", r[:sessions], "#{r[:bounce_rate]}%", "#{r[:engagement_rate]}%", r[:duration_seconds], r[:diagnosis]]
          end
          Base.write_csv(options[:csv], %w[Path URL GSCClicks GSCImpressions GSCPosition GSCCTR GA4Sessions GA4BounceRate GA4EngagementRate GA4Duration Diagnosis], csv_rows)
          puts Color.c("📁 Exported correlation report to #{options[:csv]}", Color::CYAN) unless options[:json]
        end
      end

      def handle_ga4_properties(api, hostname, options)
        puts "🔍 Discovering Google Analytics 4 properties accessible by service account...\n" unless options[:json]
        res = api.list_ga4_summaries
        if res[:ok]
          summaries = res.dig(:data, 'accountSummaries') || []
          properties = []
          summaries.each do |acc|
            acc_name = acc['displayName'] || acc['account']
            (acc['propertySummaries'] || []).each do |prop|
              prop_id = prop['property'].sub(%r{^properties/}, '')
              prop_name = prop['displayName']
              properties << {
                propertyId: prop_id,
                displayName: prop_name,
                accountName: acc_name,
                fullResource: prop['property']
              }
            end
          end

          linked_prop = Config.ga4_property_id(hostname)

          if options[:json]
            puts JSON.pretty_generate(properties)
          elsif properties.empty?
            puts Color.c("⚠️ No GA4 properties found accessible by this service account.", Color::YELLOW)
            puts "\n#{Color::BOLD}To grant access:#{Color::RESET}"
            puts "1. Go to: https://analytics.google.com/"
            puts "2. In Admin > Property Access Management, add your service account email with Viewer role."
          else
            puts "#{Color::BOLD}Property ID  | GA4 Property Name           | Account Name#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            properties.each do |p|
              id_str = Color.c(p[:propertyId].ljust(12), Color::MAGENTA, Color::BOLD)
              name_str = p[:displayName].ljust(27)
              acc_str  = Color.c(p[:accountName], Color::GRAY)

              is_linked = (p[:propertyId] == linked_prop)
              matches_dom = p[:displayName].downcase.include?(hostname.downcase.sub(/\..*$/, ''))

              tag = if is_linked
                " #{Color.c('👈 [LINKED to ' + hostname + ']', Color::GREEN, Color::BOLD)}"
              elsif matches_dom
                " #{Color.c('👈 [Recommended for ' + hostname + ']', Color::CYAN)}"
              else
                ""
              end

              puts "#{id_str} | #{name_str} | #{acc_str}#{tag}"
            end

            puts "\nTo link a property to #{Color.c(hostname, Color::CYAN)}:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}\n\n"
          end
        else
          handle_ga4_api_error(res, nil, hostname, options)
        end
      end

      def handle_realtime(api, hostname, options)
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Realtime monitoring requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Realtime monitoring requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc realtime --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        interval = options[:watch] ? [options[:watch], 3].max : nil
        title_map = api.query_ga4_title_map(property_id, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])

        begin
          loop do
            print "\e[H\e[2J" if interval && !options[:json]

            res = api.query_ga4_realtime(property_id, limit: options[:limit] || 25)
            if res[:ok]
              data = res[:data] || {}
              reported_total = data.dig('totals', 0, 'metricValues', 0, 'value')&.to_i
              raw_rows = data['rows'] || []

              page_counts = Hash.new(0)
              country_counts = Hash.new(0)
              breakdown = []

              raw_rows.each do |r|
                page = r.dig('dimensionValues', 0, 'value')
                page = '/' if page.nil? || page.strip.empty?
                country = r.dig('dimensionValues', 1, 'value')
                country = 'Unknown' if country.nil? || country.strip.empty?
                active = r.dig('metricValues', 0, 'value').to_i

                path = if page.start_with?('/')
                         page
                       elsif title_map[page]
                         title_map[page]
                       elsif page =~ %r{/(?:[a-zA-Z0-9_\-\./]+)}
                         page[%r{/(?:[a-zA-Z0-9_\-\./]+)}]
                       else
                         match = title_map.find { |t, _| t.downcase.include?(page.downcase) || page.downcase.include?(t.downcase) }
                         match ? match[1] : '-'
                       end

                display_key = path.start_with?('/') ? path : page
                page_counts[display_key] += active
                country_counts[country] += active
                breakdown << { path: path, page: page, country: country, active_users: active }
              end

              row_max = raw_rows.map { |r| r.dig('metricValues', 0, 'value').to_i }.max || 0
              page_max = page_counts.values.max || 0
              total_active = reported_total || [row_max, page_max].max || 0
              if total_active.zero? && raw_rows.any?
                total_active = [row_max, page_max, 1].max
              end

              payload = {
                domain: hostname,
                property_id: property_id,
                total_active_users: total_active,
                timestamp: Time.now.iso8601,
                top_pages: page_counts.sort_by { |_k, v| -v }.first(options[:limit] || 15).map { |k, v| { page: k, active_users: v } },
                top_countries: country_counts.sort_by { |_k, v| -v }.first(10).map { |k, v| { country: k, active_users: v } },
                active_streams: breakdown
              }

              if options[:json]
                puts JSON.pretty_generate(payload)
              else
                header_text = "⚡ GA4 REALTIME VISITOR MONITOR: #{hostname} [Property #{property_id}]"
                time_str = Time.now.strftime("%Y-%m-%d %H:%M:%S")
                puts "#{Color::BOLD}#{Color.c(header_text, Color::CYAN)} (#{time_str})#{Color::RESET}"
                puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}"

                count_color = total_active > 0 ? Color::GREEN : Color::YELLOW
                puts "  👥 Active Users (Last 30 Mins): #{Color.c(total_active.to_s, count_color, Color::BOLD)}"
                puts "#{Color::BOLD}══════════════════════════════════════════════════════════════════════════════#{Color::RESET}\n"

                if total_active.zero? && raw_rows.empty?
                  puts Color.c("  (No active visitors on site in the last 30 minutes)\n", Color::GRAY)
                else
                  puts "#{Color::BOLD}Active Users | Country         | URL Path                       | Page / Screen Title#{Color::RESET}"
                  puts "------------------------------------------------------------------------------------------------------------------------"
                  breakdown.first(options[:limit] || 25).each do |b|
                    u_col = Color.c(b[:active_users].to_s.ljust(12), Color::GREEN, Color::BOLD)
                    c_col = b[:country].to_s[0..14].ljust(15)
                    path_str = b[:path].to_s[0..29].ljust(30)
                    path_col = Color.c(path_str, Color::MAGENTA, Color::BOLD)
                    p_col = Color.c(b[:page], Color::CYAN)
                    puts "#{u_col} | #{c_col} | #{path_col} | #{p_col}"
                  end
                  puts

                  if country_counts.any?
                    top_c = country_counts.sort_by { |_k, v| -v }.first(5).map { |c, count| "#{c}: #{count}" }.join(" | ")
                    puts "🌍 Top Countries: #{top_c}\n\n"
                  end
                end

                if interval
                  puts Color.c("⏳ Refreshing every #{interval}s (Press Ctrl+C to exit)...", Color::GRAY)
                end
              end
            else
              handle_ga4_api_error(res, property_id, hostname, options)
              break
            end

            break unless interval
            sleep interval
          end
        rescue Interrupt
          puts "\n👋 Exited live monitor." unless options[:json]
        end
      end

      def handle_ads(api, hostname, options)
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Google Ads reporting requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Google Ads reporting requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc ads --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        puts "📢 Fetching Google Ads campaign performance for #{Color.c(hostname, Color::CYAN)} [Property #{property_id}] (Past #{options[:days]} days)..." unless options[:json]

        res = api.query_ga4_ads(property_id, days: options[:days], limit: options[:limit] || 50)
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          if raw_rows.empty?
            if options[:json]
              puts JSON.pretty_generate({
                domain: hostname,
                property_id: property_id,
                campaigns: [],
                message: "No Google Ads campaign data recorded in GA4 for this date range."
              })
            else
              puts Color.c("\nℹ️  No Google Ads data found in GA4 for the past #{options[:days]} days.", Color::YELLOW)
              puts "• Check that Google Ads is linked in GA4 (Admin > Product Links > Google Ads Links)."
              puts "• Ensure Auto-tagging is enabled in Google Ads settings."
              puts "• Note: Google Ads cost/click metrics typically take 12–24 hours to populate in GA4.\n\n"
            end
            return
          end

          campaigns = []
          raw_rows.each do |row|
            camp_name = row.dig('dimensionValues', 0, 'value') || '(not set)'
            ad_group  = row.dig('dimensionValues', 1, 'value') || '(not set)'

            clicks    = row.dig('metricValues', 0, 'value').to_i
            cost      = row.dig('metricValues', 1, 'value').to_f
            cpc       = row.dig('metricValues', 2, 'value').to_f
            sessions  = row.dig('metricValues', 3, 'value').to_i
            conv      = row.dig('metricValues', 4, 'value').to_i
            bounce    = row.dig('metricValues', 5, 'value').to_f

            cpa = conv.positive? ? (cost / conv) : 0.0

            campaigns << {
              campaign: camp_name,
              ad_group: ad_group,
              clicks: clicks,
              cost: cost.round(2),
              cpc: cpc.round(2),
              sessions: sessions,
              conversions: conv,
              cpa: cpa.round(2),
              bounce_rate: (bounce * 100.0).round(1)
            }
          end

          campaigns.reject! { |c| c[:campaign] == '(not set)' && c[:clicks].zero? && c[:cost].zero? }

          if campaigns.empty?
            if options[:json]
              puts JSON.pretty_generate([])
            else
              puts Color.c("\nℹ️  No Google Ads clicks or spend recorded in GA4 for the past #{options[:days]} days.", Color::YELLOW, Color::BOLD)
              puts "\n#{Color::BOLD}Diagnostic Checklist:#{Color::RESET}"
              puts "  1. #{Color::BOLD}Campaign Hasn't Served Yet:#{Color::RESET} If your campaign was published recently, check Google Ads for 'Your campaign hasn't served in the past week' (often due to pending ad review, account security tasks, or low bids)."
              puts "  2. #{Color::BOLD}0 Impressions / Clicks:#{Color::RESET} GA4 only logs campaigns once Google Ads serves impressions and records traffic."
              puts "  3. #{Color::BOLD}GA4 Product Link:#{Color::RESET} Verify Google Ads is linked in GA4 (Admin > Product Links > Google Ads Links) with auto-tagging enabled."
              puts "  4. #{Color::BOLD}Sync Latency:#{Color::RESET} Ad spend & click metrics take 12–24 hours to populate in GA4 after ads begin serving.\n\n"
            end
            return
          end

          campaigns.sort_by! { |c| -c[:clicks] }

          if options[:json]
            puts JSON.pretty_generate(campaigns)
          else
            puts "\n#{Color::BOLD}Clicks | Cost ($) | Avg CPC | Sessions | Conv | CPA ($) | Bounce | Campaign Name [Ad Group]#{Color::RESET}"
            puts "-------------------------------------------------------------------------------------------------------"
            total_clicks = 0
            total_cost = 0.0
            total_sessions = 0
            total_conv = 0

            campaigns.first(options[:limit] || 25).each do |c|
              total_clicks += c[:clicks]
              total_cost += c[:cost]
              total_sessions += c[:sessions]
              total_conv += c[:conversions]

              clk_col = c[:clicks].to_s.ljust(6)
              cost_col = "$#{format('%.2f', c[:cost])}".ljust(8)
              cpc_col = "$#{format('%.2f', c[:cpc])}".ljust(7)
              sess_col = c[:sessions].to_s.ljust(8)
              conv_col = Color.c(c[:conversions].to_s.ljust(4), c[:conversions].positive? ? Color::GREEN : Color::GRAY)
              cpa_col = c[:conversions].positive? ? "$#{format('%.2f', c[:cpa])}".ljust(7) : "-".ljust(7)
              bnc_col = "#{c[:bounce_rate]}%".ljust(6)
              name_col = "#{Color.c(c[:campaign], Color::CYAN)} [#{Color.c(c[:ad_group], Color::GRAY)}]"

              puts "#{clk_col} | #{cost_col} | #{cpc_col} | #{sess_col} | #{conv_col} | #{cpa_col} | #{bnc_col} | #{name_col}"
            end

            puts "#{Color::BOLD}═══════════════════════════════════════════════════════════════════════════════════════#{Color::RESET}"
            total_cpa = total_conv.positive? ? "$#{format('%.2f', total_cost / total_conv)}" : "-"
            puts "Totals: #{total_clicks} clicks | $#{format('%.2f', total_cost)} cost | #{total_sessions} sessions | #{total_conv} conv | CPA: #{total_cpa}\n\n"
          end

          if options[:csv]
            csv_rows = campaigns.map do |c|
              [c[:campaign], c[:ad_group], c[:clicks], c[:cost], c[:cpc], c[:sessions], c[:conversions], c[:cpa], "#{c[:bounce_rate]}%"]
            end
            Base.write_csv(options[:csv], %w[Campaign AdGroup Clicks Cost AvgCPC Sessions Conversions CPA BounceRate], csv_rows)
            puts Color.c("📁 Exported Google Ads report to #{options[:csv]}", Color::CYAN) unless options[:json]
          end
        else
          handle_ga4_api_error(res, property_id, hostname, options)
        end
      end

      def handle_channels(api, hostname, options)
        property_id = options[:property] || Config.ga4_property_id(hostname)
        unless property_id
          if options[:json]
            puts JSON.pretty_generate({
              error: 'no_ga4_property_linked',
              domain: hostname,
              hint: "Traffic channel reporting requires a linked GA4 Property ID. Run 'gsc config set-ga4 <property_id> -d #{hostname}'."
            })
          else
            puts "\n#{Color.c("⚠️  Traffic channel reporting requires a linked GA4 Property for: #{hostname}", Color::YELLOW, Color::BOLD)}"
            puts "To link your GA4 Property ID to this domain, run:"
            puts "   #{Color.c("gsc config set-ga4 <property_id> -d #{hostname}", Color::GREEN, Color::BOLD)}"
            puts "\nOr specify directly:"
            puts "   #{Color.c("gsc channels --property <property_id>", Color::CYAN)}"
            puts "   #{Color.c("gsc ga4-properties", Color::CYAN)} (to discover accessible GA4 properties)"
            puts
          end
          return
        end

        puts "🚦 Fetching Omnichannel acquisition breakdown for #{Color.c(hostname, Color::CYAN)} [Property #{property_id}] (Past #{options[:days]} days)..." unless options[:json]

        res = api.query_ga4_channels(property_id, days: options[:days], limit: options[:limit] || 25, hostname: (options[:all_hosts] ? nil : hostname), site_only: options[:site_only])
        if res[:ok]
          raw_rows = res.dig(:data, 'rows') || []
          if raw_rows.empty?
            if options[:json]
              puts JSON.pretty_generate([])
            else
              puts Color.c("⚠️ No acquisition channel data found in GA4 for this date range.", Color::YELLOW)
            end
            return
          end

          channels = []
          raw_rows.each do |row|
            channel  = row.dig('dimensionValues', 0, 'value') || '(not set)'
            source   = row.dig('dimensionValues', 1, 'value') || '(not set)'

            sessions = row.dig('metricValues', 0, 'value').to_i
            users    = row.dig('metricValues', 1, 'value').to_i
            eng_rate = row.dig('metricValues', 2, 'value').to_f
            bounce   = row.dig('metricValues', 3, 'value').to_f
            duration = row.dig('metricValues', 4, 'value').to_f
            conv     = row.dig('metricValues', 5, 'value').to_i

            channels << {
              channel: channel,
              source_medium: source,
              sessions: sessions,
              users: users,
              engagement_rate: (eng_rate * 100.0).round(1),
              bounce_rate: (bounce * 100.0).round(1),
              duration_seconds: duration.round(1),
              duration_formatted: Base.format_duration(duration),
              conversions: conv
            }
          end

          channels.sort_by! { |c| -c[:sessions] }

          if options[:json]
            puts JSON.pretty_generate(channels)
          else
            puts "\n#{Color::BOLD}Sessions | Users | Eng Rate | Bounce | Avg Time | Conv | Channel Group [Source / Medium]#{Color::RESET}"
            puts "-----------------------------------------------------------------------------------------------"
            channels.first(options[:limit] || 20).each do |c|
              s_col = c[:sessions].to_s.ljust(8)
              u_col = c[:users].to_s.ljust(5)
              e_col = "#{c[:engagement_rate]}%".ljust(8)

              b_pct = "#{c[:bounce_rate]}%"
              b_col = if c[:bounce_rate] >= 70.0
                Color.c(b_pct.ljust(6), Color::RED)
              elsif c[:bounce_rate] <= 40.0
                Color.c(b_pct.ljust(6), Color::GREEN)
              else
                b_pct.ljust(6)
              end

              d_col = c[:duration_formatted].ljust(8)
              cv_col = Color.c(c[:conversions].to_s.ljust(4), c[:conversions].positive? ? Color::GREEN : Color::GRAY)
              ch_col = "#{Color.c(c[:channel], Color::CYAN)} [#{Color.c(c[:source_medium], Color::GRAY)}]"

              puts "#{s_col} | #{u_col} | #{e_col} | #{b_col} | #{d_col} | #{cv_col} | #{ch_col}"
            end

            total_s = channels.sum { |c| c[:sessions] }
            total_u = channels.sum { |c| c[:users] }
            total_cv = channels.sum { |c| c[:conversions] }
            puts "\nTotal Channels: #{channels.size} | Total Sessions: #{total_s} | Total Users: #{total_u} | Conversions: #{total_cv}\n\n"
          end

          if options[:csv]
            csv_rows = channels.map do |c|
              [c[:channel], c[:source_medium], c[:sessions], c[:users], "#{c[:engagement_rate]}%", "#{c[:bounce_rate]}%", c[:duration_seconds], c[:conversions]]
            end
            Base.write_csv(options[:csv], %w[Channel SourceMedium Sessions Users EngagementRate BounceRate DurationSeconds Conversions], csv_rows)
            puts Color.c("📁 Exported Channel Acquisition report to #{options[:csv]}", Color::CYAN) unless options[:json]
          end
        else
          handle_ga4_api_error(res, property_id, hostname, options)
        end
      end

      def handle_ga4_api_error(res, property_id, hostname, options)
        msg = res.dig(:data, 'error', 'message') || res[:data].to_s
        status = res[:status]

        if options[:json]
          puts JSON.pretty_generate({ error: msg, status: status })
          return
        end

        puts Color.c("\n❌ Google Analytics API Error (#{status}): #{msg}", Color::RED, Color::BOLD)

        is_disabled_api = msg =~ /has not been used in project|SERVICE_DISABLED|is disabled|enable it by visiting/i ||
                          (res.dig(:data, 'error', 'details')&.any? { |d| d['reason'] == 'SERVICE_DISABLED' } rescue false)

        if is_disabled_api
          url = msg[/https:\/\/[^\s]+/, 0] || (res.dig(:data, 'error', 'details', 0, 'links', 0, 'url') rescue nil)
          puts "\n#{Color.c("⚙️  ACTION REQUIRED: Google Cloud API Not Enabled", Color::YELLOW, Color::BOLD)}"
          puts "The requested Google Analytics API is disabled in your Google Cloud Project."
          if url
            puts "\n👉 #{Color::BOLD}Click this link to enable it in 1 click:#{Color::RESET}"
            puts "   #{Color.c(url, Color::CYAN, Color::BOLD)}"
          end
          puts "\nAfter clicking #{Color::BOLD}'ENABLE'#{Color::RESET} in Google Cloud Console, wait 1–2 minutes for Google propagation and retry."
          puts
          return
        end

        if status == 403
          sa_key = Auth.find_key
          sa_email = (JSON.parse(File.read(sa_key))['client_email'] rescue nil) if sa_key
          puts "\n#{Color::BOLD}How to Fix 403 (Permission Denied):#{Color::RESET}"
          puts "1. Copy your Service Account email:"
          if sa_email
            puts "   👉 #{Color.c(sa_email, Color::CYAN, Color::BOLD)}"
          else
            puts "   👉 (Check your service account JSON key)"
          end
          puts "2. Open Google Analytics: #{Color.c('https://analytics.google.com/', Color::CYAN)}"
          puts "3. Click ⚙️ #{Color::BOLD}Admin#{Color::RESET} (bottom-left corner)"
          if property_id && !property_id.to_s.strip.empty?
            puts "4. In Property Settings, click #{Color::BOLD}Property Access Management#{Color::RESET} (for Property #{property_id})"
          else
            puts "4. Click #{Color::BOLD}Account Access Management#{Color::RESET} (or Property Access Management)"
          end
          puts "5. Click the blue #{Color::BOLD}'+'#{Color::RESET} button (top-right) ➔ #{Color::BOLD}Add users#{Color::RESET}"
          puts "6. Paste your service account email and assign the #{Color::BOLD}Viewer#{Color::RESET} role."
          puts
        elsif status == 404
          puts "\nProperty ID '#{property_id}' was not found. Please verify your numeric GA4 Property ID.\n"
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'json'
require 'cgi'
require 'uri'
require_relative 'base'
require_relative '../indexing_queue' if File.exist?(File.expand_path('../indexing_queue.rb', __dir__))
require_relative '../sitemap_loader' if File.exist?(File.expand_path('../sitemap_loader.rb', __dir__))
require_relative '../indexnow' if File.exist?(File.expand_path('../indexnow.rb', __dir__))

module GSC
  class CLI
    module Indexing
      module_function

      def run(command, target, extra, options, api, site_url, hostname, https_origin)
        case command
        when 'inspect', 'i'
          handle_inspect(target, api, site_url, hostname, options)
        when 'inspect-sitemap'
          handle_inspect_sitemap(target, api, site_url, hostname, https_origin, options)
        when 'index', 'idx'
          handle_index(target, api, hostname, options)
        when 'index-batch', 'queue', 'batch-index'
          handle_index_batch(target, extra, api, https_origin, options)
        when 'remove', 'rm'
          handle_remove(target, api, hostname, options)
        when 'status'
          handle_status(target, api, hostname, options)
        when 'sitemaps-list', 'sitemaps'
          handle_sitemaps_list(api, site_url, options)
        when 'sitemaps-submit'
          handle_sitemaps_submit(target, api, site_url, https_origin, options)
        when 'auto', 'index-sitemap'
          handle_index_sitemap(target, api, hostname, https_origin, options)
        when 'indexnow', 'in'
          handle_indexnow(target, extra, options)
        when 'indexnow-sitemap', 'ins'
          handle_indexnow_sitemap(target, options)
        else
          raise "Unknown indexing command: #{command}"
        end
      end

      def handle_inspect(target, api, site_url, hostname, options)
        Base.require_target!(target, "inspect https://#{hostname}/page", options)
        puts "🔍 Inspecting URL via Search Console API:\n   #{Color.c(target, Color::CYAN)} (Property: #{site_url})\n" unless options[:json]
        res = api.inspect_url(target, site_url)
        if options[:json]
          r = res.dig(:data, 'inspectionResult', 'indexStatusResult') || {}
          rich_test_url = "https://search.google.com/test/rich-results?url=#{CGI.escape(target)}"
          gsc_inspect_url = "https://search.google.com/search-console/inspect?resource_id=#{CGI.escape(site_url)}&id=#{CGI.escape(target)}"
          puts JSON.pretty_generate(r.merge('url' => target, 'ok' => res[:ok], 'status' => res[:status], 'google_rich_results_test_url' => rich_test_url, 'gsc_web_inspection_url' => gsc_inspect_url))
        elsif res[:ok]
          r = res.dig(:data, 'inspectionResult', 'indexStatusResult')
          if r
            verdict_color = (r['verdict'] == 'PASS') ? Color::GREEN : Color::YELLOW
            puts Color.c('📋 INDEXATION DIAGNOSTICS:', Color::BOLD)
            puts "   Verdict:          #{Color.c(r['verdict'], verdict_color, Color::BOLD)}"
            puts "   Coverage Status:  #{r['coverageState'] || 'Unknown'}"
            puts "   Indexing Allowed: #{r['indexingState'] == 'INDEXING_ALLOWED' ? Color.c('ALLOWED', Color::GREEN) : Color.c(r['indexingState'] || 'NO', Color::RED)}"
            puts "   Robots.txt:       #{r['robotsTxtState'] == 'ALLOWED' ? Color.c('ALLOWED', Color::GREEN) : Color.c(r['robotsTxtState'] || 'BLOCKED', Color::RED)}"
            puts "   Last Crawled:     #{Color.c(r['lastCrawlTime'] || 'Never / Not yet recorded', Color::CYAN)}"
            puts "   User Canonical:   #{r['userCanonical'] || 'None specified'}"
            puts "   Google Canonical: #{r['googleCanonical'] || 'None assigned'}"

            rich_test_url = "https://search.google.com/test/rich-results?url=#{CGI.escape(target)}"
            gsc_inspect_url = "https://search.google.com/search-console/inspect?resource_id=#{CGI.escape(site_url)}&id=#{CGI.escape(target)}"
            puts "\n" + Color.c('🔗 OFFICIAL GOOGLE VERIFICATION TOOLS:', Color::BOLD)
            puts "   Rich Results Test:  #{Color.c(rich_test_url, Color::CYAN)}"
            puts "   GSC Web Inspection: #{Color.c(gsc_inspect_url, Color::CYAN)}"
            if options[:open]
              puts Color.green("\n🚀 Opening Google Rich Results Test in your browser...")
              Base.open_in_browser(rich_test_url)
            else
              puts Color.gray("\n   💡 Tip: Pass '--open' (or '-o') to launch the Rich Results Test in your browser.")
            end
          else
            puts JSON.pretty_generate(res[:data])
          end
        else
          puts Color.c("❌ Inspection Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end
      end

      def handle_inspect_sitemap(target, api, site_url, hostname, https_origin, options)
        puts "📥 Loading sitemap for bulk inspection on #{Color.c(hostname, Color::CYAN)}..." unless options[:json]
        urls = SitemapLoader.resolve_urls(target, https_origin, quiet: options[:json])
        puts "🔍 Bulk inspecting #{Color.c(urls.size.to_s, Color::BOLD)} URLs via Search Console API (#{site_url})...\n" unless options[:json]

        results = []
        pass_count = 0
        queue_count = 0
        error_count = 0

        unless options[:json]
          puts Color.c("  #   | Status   | Last Crawl  | Coverage Status                     | URL", Color::DIM)
          puts "  ------------------------------------------------------------------------------------------------"
        end

        urls.each_with_index do |u, idx|
          idx_str = (idx + 1).to_s.rjust(4)
          res = api.inspect_url(u, site_url)

          if res[:ok]
            r = res.dig(:data, 'inspectionResult', 'indexStatusResult')
            verdict  = r ? r['verdict'] : 'UNKNOWN'
            coverage = ((r && r['coverageState']) || 'Unknown').ljust(35)
            last_cr  = (r && r['lastCrawlTime']) ? r['lastCrawlTime'].split('T').first : 'Never     '

            if verdict == 'PASS'
              pass_count += 1
              puts "  #{idx_str} | #{Color.c('✅ PASS', Color::GREEN)}   | #{last_cr} | #{coverage} | #{u}" unless options[:json]
            else
              queue_count += 1
              puts "  #{idx_str} | #{Color.c('⏳ QUEUE', Color::YELLOW)}  | #{last_cr} | #{coverage} | #{u}" unless options[:json]
            end

            results << {
              url: u,
              verdict: verdict,
              coverage: r&.dig('coverageState') || 'Unknown',
              last_crawl: r&.dig('lastCrawlTime') || 'Never',
              robots_txt: r&.dig('robotsTxtState') || 'Unknown'
            }
          else
            error_count += 1
            puts "  #{idx_str} | #{Color.c('❌ ERROR', Color::RED)}  | ---------- | HTTP #{res[:status].to_s.ljust(30)} | #{u}" unless options[:json]
            results << { url: u, verdict: 'ERROR', error: "HTTP #{res[:status]}" }
          end

          sleep(options[:delay] / 1000.0) if options[:delay] > 0
        end

        if options[:json]
          puts JSON.pretty_generate({ total: urls.size, indexedPass: pass_count, pendingQueue: queue_count, errors: error_count, urls: results })
        else
          puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "#{Color::BOLD}📊 BULK INDEXATION SUMMARY (#{urls.size} URLs)#{Color::RESET}"
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
          puts "  ✅ Indexed on Google (PASS): #{Color.c(pass_count.to_s, Color::GREEN, Color::BOLD)} (#{'%.1f' % ((pass_count.to_f / urls.size) * 100)}%)"
          puts "  ⏳ Pending / Queue:          #{Color.c(queue_count.to_s, Color::YELLOW, Color::BOLD)} (#{'%.1f' % ((queue_count.to_f / urls.size) * 100)}%)"
          puts "  ❌ Errors:                   #{Color.c(error_count.to_s, Color::RED, Color::BOLD)}" if error_count > 0
          puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"

          if options[:csv]
            Base.write_csv(options[:csv], %w[URL Verdict Coverage LastCrawl RobotsTxt], results.map(&:values))
            puts Color.c("📁 Exported audit table to #{options[:csv]}\n", Color::CYAN)
          end
        end
      end

      def handle_index(target, api, hostname, options)
        Base.require_target!(target, "index https://#{hostname}/new-page", options)
        puts "🚀 Sending #{Color::BOLD}URL_UPDATED#{Color::RESET} indexing request for:\n   #{Color.c(target, Color::CYAN)}" unless options[:json]
        return if Base.dry_run?(options)

        res = api.publish_url(target, 'URL_UPDATED')
        if options[:json]
          puts JSON.pretty_generate(res[:data] || { ok: res[:ok], status: res[:status] })
        elsif res[:ok]
          puts Color.c("\n✅ Success! Google Indexing API accepted the URL (HTTP 200).", Color::GREEN)
          notify_time = res.dig(:data, 'urlNotificationMetadata', 'latestUpdate', 'notifyTime') || Time.now.iso8601
          puts "   Notify Time: #{notify_time}"
          puts Color.c("\nGooglebot will prioritize crawling this URL shortly.", Color::DIM)
        else
          puts Color.c("\n❌ Indexing API Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end
      end

      def handle_index_batch(target, extra, api, https_origin, options)
        queue = GSC::IndexingQueue.new
        action = target.to_s.strip.downcase

        case action
        when 'add', 'enqueue'
          input_source = extra || target
          urls = []
          if input_source && (input_source.end_with?('.xml') || input_source.include?('sitemap'))
            puts "📥 Extracting URLs from XML sitemap: #{Color.c(input_source, Color::CYAN)}..." unless options[:json]
            urls = SitemapLoader.resolve_urls(input_source, https_origin, quiet: options[:json])
          elsif input_source && File.exist?(input_source)
            puts "📥 Reading URLs from local file: #{Color.c(input_source, Color::CYAN)}..." unless options[:json]
            urls = File.readlines(input_source, chomp: true).map(&:strip).reject(&:empty?)
          elsif input_source && input_source.start_with?('http://', 'https://')
            urls = [input_source]
          elsif !$stdin.tty?
            urls = $stdin.readlines.map(&:strip).reject(&:empty?)
          end

          added = queue.add_urls(urls)
          st = queue.status
          if options[:json]
            puts JSON.pretty_generate({ added: added, queue_status: st })
          else
            puts Color.c("✅ Successfully enqueued #{added} new URLs into the indexing queue.", Color::GREEN)
            puts "   Pending in queue:       #{Color.c(st[:pending_count].to_s, Color::CYAN)}"
            puts "   Daily quota remaining:   #{Color.c(st[:daily_quota_remaining].to_s, Color::YELLOW)} / #{st[:daily_quota_limit]}"
            puts "\nTo process pending queue, run: #{Color.c('gsc index-batch run', Color::CYAN)}"
          end

        when 'run', 'process', 'execute'
          batch_size = options[:batch_size] || 50
          puts "🚀 Processing Google Indexing queue (Batch size: #{batch_size}, Dry run: #{options[:dry_run] || false})...\n" unless options[:json]

          res = queue.process_batch(api, batch_size: batch_size, dry_run: options[:dry_run])
          if options[:json]
            puts JSON.pretty_generate(res)
          else
            if res[:status] == :queue_empty
              puts Color.c("ℹ️ #{res[:message]}", Color::YELLOW)
            elsif res[:status] == :quota_exhausted
              puts Color.c("⚠️  #{res[:message]}", Color::YELLOW, Color::BOLD)
            else
              puts Color.c("✅ Batch processed: #{res[:successful]} succeeded, #{res[:failed]} failed.", res[:failed] > 0 ? Color::YELLOW : Color::GREEN)
              puts "   Remaining in queue:      #{Color.c(res[:remaining_in_queue].to_s, Color::CYAN)}"
              puts "   Today's quota remaining: #{Color.c(res[:daily_quota_remaining].to_s, Color::YELLOW)} / 200 URLs"
              if res[:results].any? && !options[:dry_run]
                puts "\nRecent Submissions:"
                res[:results].first(5).each do |r|
                  status_col = r[:ok] ? Color.c('✔ 200 OK', Color::GREEN) : Color.c("✖ #{r[:error]}", Color::RED)
                  puts "  • #{r[:url]} [#{status_col}]"
                end
              end
            end
          end

        when 'clear', 'reset'
          queue.clear(:all)
          if options[:json]
            puts JSON.pretty_generate({ ok: true, message: 'Queue cleared' })
          else
            puts Color.c("🗑️  Indexing queue cleared.", Color::GREEN)
          end

        else
          st = queue.status
          if options[:json]
            puts JSON.pretty_generate(st)
          else
            puts "📋 #{Color::BOLD}Google Indexing API Batch Queue Status#{Color::RESET}\n"
            puts "   Pending URLs:          #{Color.c(st[:pending_count].to_s, Color::CYAN, Color::BOLD)}"
            puts "   Submitted Today:       #{Color.c(st[:daily_quota_used].to_s, Color::MAGENTA)}"
            puts "   Daily Quota Remaining: #{Color.c("#{st[:daily_quota_remaining]} / #{st[:daily_quota_limit]} URLs", Color::YELLOW, Color::BOLD)}"
            puts "   Total Ever Submitted:  #{Color.c(st[:submitted_count].to_s, Color::GRAY)}"
            puts "   Total Failed:          #{Color.c(st[:failed_count].to_s, Color::GRAY)}"
            puts "   Quota Date:            #{st[:last_reset_date]} (Resets daily at 00:00 UTC)"
            puts "\nCommands:"
            puts "   • #{Color.c('gsc index-batch add <url|sitemap.xml|file.txt>', Color::CYAN)} - Enqueue URLs"
            puts "   • #{Color.c('gsc index-batch run [--batch-size 50] [--dry-run]', Color::CYAN)} - Process queue"
            puts "   • #{Color.c('gsc index-batch clear', Color::CYAN)}                           - Reset queue"
            puts ""
          end
        end
      end

      def handle_remove(target, api, hostname, options)
        Base.require_target!(target, "remove https://#{hostname}/page", options)
        puts "🗑️ Sending #{Color::BOLD}URL_DELETED#{Color::RESET} request for:\n   #{Color.c(target, Color::RED)}" unless options[:json]
        return if Base.dry_run?(options)

        res = api.publish_url(target, 'URL_DELETED')
        if options[:json]
          puts JSON.pretty_generate(res[:data] || { ok: res[:ok], status: res[:status] })
        elsif res[:ok]
          puts Color.c("\n✅ Success! Google Indexing API recorded URL deletion.", Color::GREEN)
        else
          puts Color.c("\n❌ Indexing API Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end
      end

      def handle_status(target, api, hostname, options)
        Base.require_target!(target, "status https://#{hostname}/page", options)
        puts "🔍 Querying Indexing API metadata for:\n   #{Color.c(target, Color::CYAN)}\n" unless options[:json]
        res = api.get_url_status(target)
        if options[:json]
          puts JSON.pretty_generate(res[:data])
        elsif res[:ok]
          puts Color.c("✅ Latest Notification Record:", Color::GREEN)
          puts JSON.pretty_generate(res[:data])
        else
          puts Color.c("❌ Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end
      end

      def handle_sitemaps_list(api, site_url, options)
        puts "📑 Fetching submitted sitemaps for #{Color.c(site_url, Color::CYAN)}...\n" unless options[:json]
        res = api.list_sitemaps(site_url)
        if options[:json]
          puts JSON.pretty_generate(res[:data] || {})
        elsif res[:ok]
          sitemaps = res.dig(:data, 'sitemap') || []
          if sitemaps.empty?
            puts Color.c("ℹ️ No sitemaps currently submitted in Search Console for this property.", Color::YELLOW)
          else
            puts "#{Color::BOLD}Type         | Last Downloaded | Errors | Warnings | Path#{Color::RESET}"
            puts "--------------------------------------------------------------------------------"
            sitemaps.each do |sm|
              type    = (sm['type'] || 'sitemap').ljust(12)
              last_dl = sm['lastDownloaded'] ? sm['lastDownloaded'].split('T').first : 'Never     '
              errors  = (sm['errors'] || 0).to_s.ljust(6)
              warns   = (sm['warnings'] || 0).to_s.ljust(8)
              puts "#{type} | #{last_dl}      | #{errors} | #{warns} | #{Color.c(sm['path'], Color::CYAN)}"
            end
          end
          puts
        else
          puts Color.c("❌ Error (#{res[:status]}): #{res[:data]}", Color::RED)
        end
      end

      def handle_sitemaps_submit(target, api, site_url, https_origin, options)
        sitemap_url = target || "#{https_origin}/sitemap.xml"
        puts "📤 Submitting sitemap to Google Search Console:\n   #{Color.c(sitemap_url, Color::CYAN)} (Property: #{site_url})\n" unless options[:json]
        res = api.submit_sitemap(site_url, sitemap_url)
        if options[:json]
          puts JSON.pretty_generate({ ok: res[:ok], status: res[:status], sitemap: sitemap_url })
        elsif res[:ok] || res[:status] == 204
          puts Color.c("✅ Success! Sitemap registered with Google Search Console.", Color::GREEN)
        else
          puts Color.c("❌ Failed to submit sitemap (#{res[:status]}): #{res[:data]}", Color::RED)
        end
      end

      def handle_index_sitemap(target, api, hostname, https_origin, options)
        puts "📥 Loading XML sitemap for #{Color.c(hostname, Color::CYAN)}..." unless options[:json]
        urls = SitemapLoader.resolve_urls(target, https_origin, quiet: options[:json])
        puts "📋 Found #{Color.c(urls.size.to_s, Color::BOLD)} URLs. Submitting batch to Google Indexing API...\n" unless options[:json]

        success_count = 0
        fail_count    = 0
        results = []

        urls.each_with_index do |u, idx|
          progress = "[#{idx + 1}/#{urls.size}]".rjust(urls.size.to_s.length + 3)
          print "  #{Color.c(progress, Color::GRAY)} #{u} " unless options[:json]

          if options[:dry_run]
            puts Color.c('[DRY RUN]', Color::YELLOW) unless options[:json]
            success_count += 1
            results << { url: u, status: 'dry_run' }
            next
          end

          res = api.publish_url(u, 'URL_UPDATED')
          if res[:ok]
            success_count += 1
            puts Color.c('✔ OK', Color::GREEN) unless options[:json]
            results << { url: u, status: 'ok', notifyTime: res.dig(:data, 'urlNotificationMetadata', 'latestUpdate', 'notifyTime') }
          else
            fail_count += 1
            msg = res.dig(:data, 'error', 'message') || "HTTP #{res[:status]}"
            puts Color.c("✖ Failed (#{msg})", Color::RED) unless options[:json]
            results << { url: u, status: 'failed', error: msg }
          end

          sleep(options[:delay] / 1000.0) if options[:delay] > 0
        end

        if options[:json]
          puts JSON.pretty_generate({ total: urls.size, success: success_count, failed: fail_count, results: results })
        else
          Base.print_batch_summary(success_count, fail_count, urls.size)
        end
      end

      def handle_indexnow(target, extra, options)
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
          handle_indexnow_sitemap(sitemap_target, options)
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

        puts Base::BANNER unless options[:in_dashboard]
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

      def handle_indexnow_sitemap(target, options)
        sitemap = target || options[:sitemap] || 'sitemap.xml'
        key = options[:key] || IndexNow.get_or_create_key
        limit = options[:limit] ? options[:limit].to_i : nil

        puts Base::BANNER unless options[:in_dashboard]
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
    end
  end
end

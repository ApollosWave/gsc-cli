# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'net/http'
require 'uri'
require_relative 'base'
require_relative '../vault' if File.exist?(File.expand_path('../vault.rb', __dir__))
require_relative '../prompts' if File.exist?(File.expand_path('../prompts.rb', __dir__))
require_relative '../command_registry' if File.exist?(File.expand_path('../command_registry.rb', __dir__))

module GSC
  class CLI
    module Setup
      DEFAULT_UPDATE_URL = ENV['GSC_UPDATE_URL'] || 'https://raw.githubusercontent.com/ApollosWave/gsc-cli/main/dist/gsc'

      module_function

      def run(command, target, extra, args, options, parser = nil)
        case command
        when 'vault'
          handle_vault(target, extra, args[3], options)
        when 'use', 'switch', 'sw'
          handle_use(target, options)
        when /^\d+$/
          handle_use(command, options)
        when 'domains', 'list'
          handle_use(nil, options)
        when 'connect', 'setup', 'init', 'install'
          if target.to_s.downcase == 'ke' || target.to_s.downcase == 'keywordseverywhere'
            Keywords.handle_connect_ke(extra)
          elsif target.to_s.downcase == 'indexnow' || target.to_s.downcase == 'in'
            Indexing.handle_indexnow('connect', extra, options)
          else
            handle_connect_wizard
          end
        when 'connect-ga4', 'setup-ga4', 'link-ga4'
          handle_connect_ga4_wizard(options)
        when 'connect-ke', 'setup-ke', 'link-ke', 'connect-keywordseverywhere'
          Keywords.handle_connect_ke(target)
        when 'open'
          handle_open_command
        when 'where', 'which'
          print_where_info(options)
        when 'version', '-v', '--version'
          print_version_info(options)
        when 'update', 'upgrade'
          handle_update_command(options)
        when 'prompts', 'prompt', 'playbooks', 'playbook'
          handle_prompts_command(target, extra, options)
        when 'skills', 'skill', 'init-skill'
          subcmd = (command == 'init-skill') ? 'install' : target
          handle_skills_command(subcmd, options)
        when 'config'
          handle_config_command(target, extra, args[3], options)
        when 'commands', 'palette', 'schema'
          handle_commands(options)
        when 'help'
          handle_help(parser, options)
        else
          raise "Unknown setup command: #{command}"
        end
      end

      def handle_vault(subcmd, target, extra, options)
        action = subcmd.to_s.downcase
        action = 'list' if action.empty? || action == 'vault'

        case action
        when 'status'
          stat = GSC::Vault.status
          if options[:json]
            puts JSON.pretty_generate(stat)
          else
            puts Base::BANNER unless options[:in_dashboard]
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

          puts Base::BANNER unless options[:in_dashboard]
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

      def handle_use(domain_arg, options)
        domains = Base.fetch_available_domains
        active = Config.default_domain

        # Check Agency Vault alias or domain match
        if domain_arg && !domain_arg.empty?
          vault_entry = GSC::Vault.find_entry(domain_arg)
          if vault_entry
            switch_res = GSC::Vault.switch_to(domain_arg)
            clean = switch_res[:domain]
            if options[:json]
              puts JSON.pretty_generate({ status: 'ok', activeDomain: clean, vaultEntry: vault_entry })
              return
            end
            puts Base::BANNER unless options[:in_dashboard]
            puts Color.c("✅ Switched active property to: #{clean}", Color::GREEN, Color::BOLD)
            puts Color.c("   🔑 Authenticated via Agency Vault [AES-256-GCM] (#{vault_entry['client_email']})", Color::CYAN)
            puts Color.c("   Saved to #{Config::CONFIG_FILE}", Color::GRAY)
            return
          end
        end

        if domain_arg.nil? || domain_arg.empty?
          if options[:json]
            puts JSON.pretty_generate({ activeDomain: active, availableDomains: domains })
            return
          end

          puts Base::BANNER
          if active
            puts "Current active domain is: #{Color.c(active, Color::GREEN, Color::BOLD)}\n\n"
          else
            puts Color.c("No active domain is currently set.\n\n", Color::YELLOW)
          end

          if domains.empty?
            puts "No domains configured or accessible yet."
            puts "Usage: gsc use <domain>"
            return
          end

          puts "#{Color::BOLD} #  | Domain                       | GA4 Link Status#{Color::RESET}"
          puts "------------------------------------------------------------------"
          domains.each_with_index do |dom, idx|
            num_str = Color.c("[#{idx + 1}]".ljust(4), Color::CYAN, Color::BOLD)
            ga4_id = Config.ga4_property_id(dom)
            ga4_str = ga4_id ? Color.c("[GA4: #{ga4_id}]", Color::MAGENTA) : Color.c("[GA4: Not linked]", Color::GRAY)
            suffix = (dom == active) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN, Color::BOLD)}" : ""
            puts "#{num_str}| #{dom.ljust(28)} | #{ga4_str}#{suffix}"
          end
          puts "------------------------------------------------------------------"

          if $stdin.tty?
            print "\nSelect domain number (1-#{domains.size}) to switch active, or press Enter to keep current: "
            choice = $stdin.gets&.strip
            if choice && choice =~ /^\d+$/
              num = choice.to_i
              if num >= 1 && num <= domains.size
                domain_arg = domains[num - 1]
              else
                puts Color.c("Invalid selection.", Color::YELLOW)
                return
              end
            elsif choice && !choice.empty? && choice != 'q'
              domain_arg = choice
            else
              return
            end
          else
            puts "\nTo switch domains, run: #{Color.c('gsc use <number|domain>', Color::CYAN)}"
            return
          end
        elsif domain_arg =~ /^\d+$/
          num = domain_arg.to_i
          if num >= 1 && num <= domains.size
            domain_arg = domains[num - 1]
          else
            puts Color.c("❌ Error: Invalid domain number #{num}. Must be between 1 and #{domains.size}.", Color::RED)
            exit 1
          end
        end

        clean = Config.set_default_domain(domain_arg)
        if options[:json]
          puts JSON.pretty_generate({ status: 'ok', activeDomain: clean })
          return
        end
        if options[:in_dashboard]
          puts Color.c("✅ Switched active domain to: #{clean}", Color::GREEN, Color::BOLD)
          return
        end

        puts Base::BANNER
        puts Color.c("✅ Active default domain set to: #{clean}", Color::GREEN, Color::BOLD)
        puts Color.c("   Saved to #{Config::CONFIG_FILE}", Color::GRAY)
        puts "\nNow all commands (#{Color.c('gsc top-queries')}, #{Color.c('gsc audit')}, #{Color.c('gsc performance')}) will automatically target #{Color.c(clean, Color::CYAN)} without needing -d!"
        puts
      end

      def handle_connect_wizard
        puts Base::BANNER
        puts "#{Color::BOLD}🪄  GSC INTERACTIVE SETUP WIZARD#{Color::RESET}\n"

        key_file = nil

        existing_key = Auth.find_key(nil)
        if existing_key && File.exist?(existing_key)
          sa = JSON.parse(File.read(existing_key)) rescue {}
          if sa['client_email']
            puts "🔑 Found existing key already configured:"
            puts "   #{Color.c(existing_key, Color::CYAN)} (#{sa['client_email']})"
            print "Keep and test this key? [Y/n]: "
            choice = $stdin.gets&.strip
            if choice.nil? || choice.empty? || choice.downcase == 'y'
              key_file = existing_key
            end
          end
        end

        unless key_file
          begin
            downloads_dir = File.expand_path('~/Downloads')
            if Dir.exist?(downloads_dir)
              recent_keys = Dir.glob(File.join(downloads_dir, '*.json')).select do |f|
                next false if (File.size(f) rescue 999_999) > 50_000
                content = File.read(f) rescue ""
                content.include?('"client_email"') && content.include?('"private_key"')
              end.sort_by { |f| File.mtime(f) rescue Time.at(0) }.reverse

              if recent_keys.any?
                latest = recent_keys.first
                sa = JSON.parse(File.read(latest)) rescue {}
                if sa['client_email']
                  puts "🔍 Found recently downloaded service account key in Downloads:"
                  puts "   #{Color.c(File.basename(latest), Color::CYAN)} (#{sa['client_email']})"
                  print "Use this key? [Y/n]: "
                  choice = $stdin.gets&.strip
                  if choice.nil? || choice.empty? || choice.downcase == 'y'
                    key_file = latest
                  end
                end
              end
            end
          rescue Errno::EPERM, StandardError
          end
        end

        unless key_file
          puts "\n👉 #{Color::BOLD}Drag and drop your downloaded Google Cloud JSON key into this terminal#{Color::RESET}"
          print "(or paste the file path): "
          input = $stdin.gets&.strip
          if input.nil? || input.empty?
            puts Color.c("Setup cancelled.", Color::YELLOW)
            exit 0
          end

          cleaned_path = input.gsub(/^['"]|['"]$/, '').gsub('\\ ', ' ')
          cleaned_path = File.expand_path(cleaned_path)
          unless File.exist?(cleaned_path)
            puts Color.c("❌ Error: File not found at: #{cleaned_path}", Color::RED)
            exit 1
          end
          key_file = cleaned_path
        end

        begin
          sa = JSON.parse(File.read(key_file))
          unless sa['client_email'] && sa['private_key']
            puts Color.c("❌ Error: Selected JSON file is missing client_email or private_key.", Color::RED)
            exit 1
          end
        rescue StandardError => e
          puts Color.c("❌ Error parsing JSON: #{e.message}", Color::RED)
          exit 1
        end

        dest = File.join(Config::CONFIG_DIR, 'service-account.json')
        FileUtils.mkdir_p(Config::CONFIG_DIR)
        File.chmod(0700, Config::CONFIG_DIR) rescue nil
        FileUtils.cp(key_file, dest) unless File.expand_path(key_file) == File.expand_path(dest)
        File.chmod(0600, dest) rescue nil
        Config.set_key_path(dest)
        puts Color.c("\n✅ Key configured at: #{dest}", Color::GREEN, Color::BOLD)
        puts "   Service Account: #{Color.c(sa['client_email'], Color::CYAN)}"

        print "\n🔄 Testing connection to Google OAuth2 API... "
        token = nil
        begin
          token = Auth.fetch_access_token(sa)
          puts Color.c("Connected! (Token acquired)", Color::GREEN)
        rescue StandardError => e
          puts Color.c("Failed! #{e.message}", Color::RED)
          exit 1
        end

        print "🌐 Querying verified Search Console domain properties... "
        client = Client.new(token: token)
        api = API.new(client)
        sites_res = api.list_sites

        if sites_res[:ok]
          entries = sites_res.dig(:data, 'siteEntry') || []
          if entries.empty?
            puts Color.c("\n⚠️  No domain properties found in Search Console yet.", Color::YELLOW)
            puts "\n#{Color::BOLD}Next Step:#{Color::RESET}"
            puts "1. Go to: https://search.google.com/search-console/"
            puts "2. In Settings > Users and permissions, click 'Add user'"
            puts "3. Paste: #{Color.c(sa['client_email'], Color::CYAN)}"
            puts "4. Set permission to #{Color::BOLD}Owner#{Color::RESET} and click Add."
            puts "\nThen run #{Color.c('gsc domains', Color::CYAN)} anytime to verify!"
          else
            puts Color.c("Found #{entries.size} properties!\n", Color::GREEN)
            puts "#{Color::BOLD}Available Search Console Domains:#{Color::RESET}"
            entries.each_with_index do |s, idx|
              puts "  #{idx + 1}) #{Color.c(s['siteUrl'], Color::CYAN)}"
            end

            print "\nChoose a default domain (1-#{entries.size}) [1]: "
            choice = $stdin.gets&.strip
            idx = (choice && !choice.empty?) ? (choice.to_i - 1) : 0
            idx = 0 if idx < 0 || idx >= entries.size

            selected_url = entries[idx]['siteUrl']
            clean_dom = Config.set_default_domain(selected_url)
            puts Color.c("✅ Default domain set to: #{clean_dom}", Color::GREEN, Color::BOLD)
          end
        end

        puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
        puts "#{Color::BOLD}🎉 SETUP COMPLETE!#{Color::RESET}"
        puts "You can now run:"
        puts "   #{Color.c('gsc top-queries', Color::CYAN)}     - See your Google search rankings"
        puts "   #{Color.c('gsc performance', Color::CYAN)}     - 30-day search performance summary"
        puts "   #{Color.c('gsc audit', Color::CYAN)}           - Full automated SEO audit"
        puts "   #{Color.c('gsc open', Color::CYAN)}            - Reveal config folder in Finder"
        puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"
      end

      def handle_connect_ga4_wizard(options = {})
        puts Base::BANNER
        puts "#{Color::BOLD}📊 GA4 INTERACTIVE LINKING WIZARD#{Color::RESET}\n"

        key_path = Auth.find_key(options[:key])
        unless key_path && File.exist?(key_path)
          puts Color.c("❌ Error: No Google Service Account key found.", Color::RED)
          puts "Please run #{Color.c('gsc connect', Color::GREEN, Color::BOLD)} first to set up your Google credentials."
          exit 1
        end

        sa = JSON.parse(File.read(key_path)) rescue {}
        sa_email = sa['client_email']
        unless sa_email
          puts Color.c("❌ Error: Could not read client_email from #{key_path}", Color::RED)
          exit 1
        end

        puts "🔑 Using Service Account: #{Color.c(sa_email, Color::CYAN, Color::BOLD)}\n\n"

        puts "#{Color::BOLD}STEP 1: Enable Google Analytics APIs#{Color::RESET}"
        puts "  Open Google Cloud Console (in your browser):"
        puts "  👉 #{Color.c('https://console.cloud.google.com/apis/library/analyticsdata.googleapis.com', Color::CYAN)} (Data API - for metrics)"
        puts "  👉 #{Color.c('https://console.cloud.google.com/apis/library/analyticsadmin.googleapis.com', Color::CYAN)} (Admin API - for auto-discovery)"
        puts "  Click the #{Color::BOLD}'ENABLE'#{Color::RESET} button on each page.\n\n"

        puts "#{Color::BOLD}STEP 2: Grant Viewer Access in Google Analytics 4#{Color::RESET}"
        puts "  1. Open Google Analytics: #{Color.c('https://analytics.google.com/', Color::CYAN)}"
        puts "  2. Click #{Color::BOLD}Admin#{Color::RESET} (gear icon at bottom-left of your sidebar)"
        puts "  3. In Property settings, click #{Color::BOLD}Property access management#{Color::RESET}"
        puts "  4. Click the blue #{Color::BOLD}'+'#{Color::RESET} button at top-right ➔ #{Color::BOLD}Add users#{Color::RESET}"
        puts "  5. Paste your service account email:"
        puts "     👉 #{Color.c(sa_email, Color::CYAN, Color::BOLD)}"
        puts "  6. Assign the #{Color::BOLD}Viewer#{Color::RESET} role, uncheck 'Notify new users', and click #{Color::BOLD}Add#{Color::RESET}.\n\n"

        puts "#{Color::BOLD}STEP 3: Find Your Numeric GA4 Property ID#{Color::RESET}"
        puts "  • Option A: Look at the top-left property switcher (under your property name)"
        puts "  • Option B: In #{Color::BOLD}Admin ➔ Property details#{Color::RESET}, copy the 9-digit #{Color::BOLD}Property ID#{Color::RESET} (e.g. 123456789)\n\n"

        default_dom = options[:domain] || Config.default_domain
        prompt_text = default_dom ? "Which domain should this GA4 property link to? [#{default_dom}]: " : "Which domain should this GA4 property link to?: "
        print prompt_text
        input_dom = $stdin.gets&.strip
        target_dom = (input_dom && !input_dom.empty?) ? input_dom : default_dom
        if target_dom.nil? || target_dom.empty?
          puts Color.c("\nDomain required for GA4 link.", Color::RED)
          exit 1
        end
        target_dom = target_dom.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')

        current_id = Config.ga4_property_id(target_dom)
        id_prompt = current_id ? " [#{current_id}]" : ""
        print "Enter your 9-digit GA4 Property ID#{id_prompt}: "
        input_id = $stdin.gets&.strip
        property_id = (input_id && !input_id.empty?) ? input_id : current_id

        if property_id.nil? || property_id.empty?
          puts Color.c("\nLinking cancelled.", Color::YELLOW)
          exit 0
        end

        clean_id = property_id.to_s.strip.sub(%r{^properties/}, '')
        puts "\n🔄 Testing connection to GA4 Property #{clean_id}..."

        begin
          token = Auth.fetch_access_token(sa)
          client = Client.new(token: token)
          api = API.new(client)

          test_res = api.query_ga4_report(clean_id, days: 7, limit: 1)
          if test_res[:ok]
            Config.set_ga4_property_id(clean_id, target_dom)
            puts Color.c("✅ Connection verified! Successfully queried Google Analytics Data API.", Color::GREEN, Color::BOLD)
            puts Color.c("🎉 Linked GA4 Property #{clean_id} to #{target_dom}!", Color::GREEN, Color::BOLD)
            puts "\nYou can now run:"
            puts "   #{Color.c('gsc ga4', Color::CYAN)}             - Landing page bounce rates, engagement rates & duration"
            puts "   #{Color.c('gsc correlation', Color::CYAN)}     - Merged GSC keyword rankings + GA4 on-site retention"
            puts "   #{Color.c('gsc audit', Color::CYAN)}           - Comprehensive 5-step SEO & GA4 health audit"
          else
            puts Color.c("\n⚠️ Live test returned error (#{test_res[:status]}): #{test_res.dig(:data, 'error', 'message')}", Color::YELLOW)
            print "Save Property ID anyway? [y/N]: "
            choice = $stdin.gets&.strip
            if choice =~ /^y/i
              Config.set_ga4_property_id(clean_id, target_dom)
              puts Color.c("💾 Saved Property ID #{clean_id} for #{target_dom}.", Color::GREEN)
              puts "Make sure to enable the API in Google Cloud and grant Viewer role in GA4 Admin."
            else
              puts Color.c("Setup aborted.", Color::YELLOW)
            end
          end
        rescue StandardError => e
          puts Color.c("\n❌ OAuth / Network Error: #{e.message}", Color::RED)
        end
        puts
      end

      def handle_open_command
        dir = Config::CONFIG_DIR
        FileUtils.mkdir_p(dir)
        puts "📂 Opening #{Color.c(dir, Color::CYAN)} in Finder..."
        if RUBY_PLATFORM =~ /darwin/
          system('open', dir)
        elsif RUBY_PLATFORM =~ /linux/
          system('xdg-open', dir)
        elsif RUBY_PLATFORM =~ /mswin|mingw|cygwin/
          system('explorer', dir)
        else
          puts "Directory: #{dir}"
        end
      end

      def print_where_info(options)
        key_path = Auth.find_key(options[:key])
        sa = key_path ? (JSON.parse(File.read(key_path)) rescue {}) : {}

        if options[:json]
          puts JSON.pretty_generate({
            executable: File.expand_path($PROGRAM_NAME),
            configDirectory: Config::CONFIG_DIR,
            configFile: Config::CONFIG_FILE,
            activeKey: key_path,
            serviceAccount: sa['client_email'],
            activeDomain: Config.default_domain
          })
          return
        end

        puts Base::BANNER
        puts "#{Color::BOLD}📍 GSC CLI INSTALLATION & ENVIRONMENT:#{Color::RESET}"
        puts "   Executable:       #{Color.c(File.expand_path($PROGRAM_NAME), Color::CYAN)}"
        puts "   Config Directory: #{Color.c(Config::CONFIG_DIR, Color::CYAN)}"
        puts "   Config File:      #{Color.c(Config::CONFIG_FILE, Color::CYAN)}"
        if key_path
          puts "   Active Key:       #{Color.c(key_path, Color::GREEN)} (#{sa['client_email']})"
        else
          puts "   Active Key:       #{Color.c('None found (run: gsc connect)', Color::YELLOW)}"
        end
        active_dom = Config.default_domain
        puts "   Active Domain:    #{active_dom ? Color.c(active_dom, Color::GREEN, Color::BOLD) : Color.c('(none - run: gsc use <domain>)', Color::GRAY)}"
        puts
      end

      def print_version_info(options)
        if options[:json]
          puts JSON.pretty_generate({
            name: 'gsc',
            version: VERSION,
            ruby: RUBY_VERSION,
            platform: RUBY_PLATFORM,
            executable: File.expand_path($PROGRAM_NAME),
            configFile: Config::CONFIG_FILE
          })
        else
          puts "#{Color::BOLD}gsc#{Color::RESET} version #{Color.c(VERSION, Color::GREEN, Color::BOLD)} (Ruby #{RUBY_VERSION} #{RUBY_PLATFORM})"
          puts "   Executable: #{File.expand_path($PROGRAM_NAME)}"
          puts "   Config:     #{Config::CONFIG_FILE}"
        end
      end

      def handle_update_command(options)
        repo_url = Config.load['update_url'] || ENV['GSC_UPDATE_URL'] || DEFAULT_UPDATE_URL

        uri = URI(repo_url)
        raise "Security Error: Update URL must use HTTPS: #{repo_url}" unless uri.scheme == 'https'

        puts "🔄 Checking for updates from: #{Color.c(repo_url, Color::CYAN)}..." unless options[:json]

        begin
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 6
          http.read_timeout = 10

          req = Net::HTTP::Get.new(uri.request_uri)
          req['User-Agent'] = "gsc-cli/#{VERSION}"
          res = http.request(req)

          if res.code != '200'
            raise "Could not fetch update from #{repo_url} (HTTP #{res.code})"
          end

          remote_script = res.body
          remote_version = remote_script[/VERSION\s*=\s*['"]([^'"]+)['"]/, 1] || 'unknown'

          if remote_version == VERSION
            if options[:json]
              puts JSON.pretty_generate({ status: 'up-to-date', currentVersion: VERSION })
            else
              puts Color.c("✨ You are already running the latest version of gsc (#{VERSION})!", Color::GREEN, Color::BOLD)
            end
            return
          end

          require 'tempfile'
          temp = Tempfile.new(['gsc-update', '.rb'])
          temp.write(remote_script)
          temp.close

          syntax_ok = system('ruby', '-c', temp.path, out: File::NULL, err: File::NULL)
          unless syntax_ok
            temp.unlink
            raise "Downloaded script failed Ruby syntax verification."
          end

          target_bin = File.expand_path($PROGRAM_NAME)
          dest_paths = [target_bin]
          default_local = File.expand_path('~/.local/bin/gsc')
          dest_paths << default_local if File.exist?(default_local) && !dest_paths.include?(default_local)

          dest_paths.each do |path|
            File.write(path, remote_script)
            File.chmod(0755, path)
          end
          temp.unlink

          if options[:json]
            puts JSON.pretty_generate({ status: 'updated', from: VERSION, to: remote_version, paths: dest_paths })
          else
            puts Color.c("🎉 Successfully updated gsc from v#{VERSION} to v#{remote_version}!", Color::GREEN, Color::BOLD)
            puts "   Updated binary: #{dest_paths.join(', ')}"
          end
        rescue StandardError => e
          if options[:json]
            puts JSON.pretty_generate({ error: e.message })
          else
            puts Color.c("❌ Update failed: #{e.message}", Color::RED)
            puts "💡 To change update URL, run: #{Color.c('gsc config set-update-url <url>', Color::CYAN)}"
          end
          exit 1
        end
      end

      def copy_to_clipboard(text)
        if RUBY_PLATFORM =~ /darwin/i
          IO.popen("pbcopy", "w") { |io| io.write(text) }
          true
        elsif system("which xclip > /dev/null 2>&1")
          IO.popen("xclip -selection clipboard", "w") { |io| io.write(text) }
          true
        elsif system("which wl-copy > /dev/null 2>&1")
          IO.popen("wl-copy", "w") { |io| io.write(text) }
          true
        else
          false
        end
      rescue StandardError
        false
      end

      def handle_prompts_command(target, extra, options = {})
        domain = options[:domain] || Config.default_domain || '<domain>'

        if options[:json]
          if target && (target =~ /^\d+$/ || ['master', 'mega', 'all'].include?(target.downcase))
            item = Prompts.find(target.to_i)
            if item
              rendered = Prompts.render_prompt(item[:id], domain: domain, seed: options[:seed], url: options[:url])
              puts JSON.pretty_generate(item.merge(rendered_prompt: rendered, activeDomain: domain))
            else
              puts JSON.pretty_generate({ error: "Playbook ##{target} not found" })
            end
          else
            list = Prompts.all.map do |p|
              p.merge(rendered_prompt: Prompts.render_prompt(p[:id], domain: domain, seed: options[:seed], url: options[:url]))
            end
            puts JSON.pretty_generate({
              playbookCount: list.size,
              activeDomain: domain,
              playbooks: list
            })
          end
          return
        end

        if target
          item = if target =~ /^\d+$/
                   Prompts.find(target.to_i)
                 elsif ['master', 'mega', 'all'].include?(target.downcase)
                   Prompts.find(0)
                 else
                   Prompts.all.find do |p|
                     p[:title].downcase.include?(target.downcase) ||
                     p[:category].downcase.include?(target.downcase)
                   end
                 end
          if item
            show_playbook_detail(item[:id], domain, options)
            return
          end
        end

        loop do
          puts Base::BANNER unless options[:in_dashboard]
          puts "#{Color::BOLD}🤖 #{Prompts.all.size} AUTONOMOUS AI SEO PLAYBOOKS & PROMPTS#{Color::RESET} (Domain: #{Color.c(domain, Color::CYAN)})"
          puts "   Select any playbook to inspect, copy to clipboard, or run directly.\n"

          current_cat = nil
          Prompts.all.each do |p|
            if p[:category] != current_cat
              current_cat = p[:category]
              puts "\n" + Color.c(p[:category_name], Color::BOLD, Color::MAGENTA)
            end
            id_str = Color.c("[#{p[:id].to_s.rjust(2)}]", Color::CYAN, Color::BOLD)
            title_str = p[:title].ljust(44)
            impact_str = Color.c(p[:impact], Color::GRAY)
            puts "  #{id_str} #{title_str} #{impact_str}"
          end

          puts "\n" + ("─" * 70)
          print "\nEnter Playbook # (0-#{Prompts.all.size - 1}), search term, or 'q' to exit: "
          input = $stdin.gets&.strip
          break if input.nil? || input.empty? || ['q', 'exit', 'quit'].include?(input.downcase)

          if input =~ /^\d+$/
            choice = input.to_i
            item = Prompts.find(choice)
            if item
              action = show_playbook_detail(choice, domain, options)
              break if action == :exit
            else
              puts Color.c("❌ Invalid choice. Please choose 0-#{Prompts.all.size - 1}", Color::RED)
            end
          else
            matches = Prompts.all.select do |p|
              p[:title].downcase.include?(input.downcase) ||
              p[:category].downcase.include?(input.downcase) ||
              p[:template].downcase.include?(input.downcase)
            end
            if matches.empty?
              puts Color.c("\n❌ No playbooks matched '#{input}'.", Color::YELLOW)
              sleep 1.2
            else
              puts "\n" + Color.c("🔍 Search Results for '#{input}':", Color::GREEN, Color::BOLD)
              matches.each do |p|
                puts "  #{Color.c("[#{p[:id].to_s.rjust(2)}]", Color::CYAN, Color::BOLD)} #{p[:title].ljust(44)} #{Color.c(p[:impact], Color::GRAY)}"
              end
              print "\nEnter Playbook # to view (or Enter to go back): "
              sub_choice = $stdin.gets&.strip
              if sub_choice =~ /^\d+$/
                show_playbook_detail(sub_choice.to_i, domain, options)
              end
            end
          end
        end
      end

      def show_playbook_detail(id, domain, options = {})
        item = Prompts.find(id)
        unless item
          puts Color.c("❌ Playbook ##{id} not found.", Color::RED)
          return
        end

        rendered = Prompts.render_prompt(id, domain: domain, seed: options[:seed], url: options[:url])

        puts "\n" + ("═" * 70)
        puts "#{Color::BOLD}📋 PLAYBOOK ##{item[:id]}: #{item[:title].upcase}#{Color::RESET}"
        puts "   Category: #{item[:category_name]} · #{Color.c(item[:impact], Color::GREEN)}"
        puts "   Underlying CLI Command: #{Color.c(item[:cli_command], Color::CYAN)}"
        puts ("─" * 70)
        puts "\n#{Color::BOLD}🤖 READY-TO-PASTE PROMPT FOR YOUR AI AGENT / ASSISTANT:#{Color::RESET}\n\n"
        puts Color.c(rendered, Color::YELLOW)
        puts "\n" + ("─" * 70)

        if options[:copy]
          copied = copy_to_clipboard(rendered)
          if copied
            puts Color.c("📋 Copied to clipboard automatically!", Color::GREEN, Color::BOLD)
            return
          end
        end

        print "\n[c] Copy to Clipboard | [r] Run CLI Command Now | [Enter] Back: "
        sub = $stdin.gets&.strip&.downcase
        case sub
        when 'c', 'copy'
          copied = copy_to_clipboard(rendered)
          if copied
            puts Color.c("\n✅ Copied prompt to clipboard! Paste it into your AI agent.\n", Color::GREEN, Color::BOLD)
          else
            puts Color.c("\n❌ Clipboard tool not available.\n", Color::RED)
          end
          print "Press Enter to continue..."
          $stdin.gets
        when 'r', 'run'
          cmd_to_run = item[:cli_command].sub(/ --json$/, '')
          puts "\n🚀 Running: #{Color.c(cmd_to_run, Color::CYAN, Color::BOLD)}...\n\n"
          system("gsc #{cmd_to_run.sub(/^gsc /, '')}")
          print "\nPress Enter to continue..."
          $stdin.gets
        when 'q', 'quit', 'exit'
          return :exit
        end
      end

      def handle_skills_command(subcommand, options)
        gemini_dir  = File.expand_path('~/.gemini/config/skills/gsc')
        gemini_path = File.join(gemini_dir, 'SKILL.md')

        claude_dir  = File.expand_path('~/.claude/skills/gsc')
        claude_path = File.join(claude_dir, 'SKILL.md')

        local_dir   = File.expand_path('.agents/skills/gsc')
        local_path  = File.join(local_dir, 'SKILL.md')

        case subcommand
        when 'install', 'setup', 'update'
          installed = []

          if Dir.exist?(File.expand_path('~/.gemini')) || (!Dir.exist?(File.expand_path('~/.claude')) && !options[:local])
            FileUtils.mkdir_p(gemini_dir)
            File.write(gemini_path, CommandRegistry::SKILL_MD_CONTENT)
            installed << { platform: 'Antigravity / Gemini', path: gemini_path }
          end

          if Dir.exist?(File.expand_path('~/.claude'))
            FileUtils.mkdir_p(claude_dir)
            File.write(claude_path, CommandRegistry::SKILL_MD_CONTENT)
            installed << { platform: 'Claude Code', path: claude_path }
          end

          if options[:local] || Dir.exist?(File.expand_path('.agents'))
            FileUtils.mkdir_p(local_dir)
            File.write(local_path, CommandRegistry::SKILL_MD_CONTENT)
            installed << { platform: 'Universal Workspace (.agents)', path: local_path }
          end

          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', installed: installed })
          else
            puts Base::BANNER
            puts Color.c("✅ Agent Skill installed successfully across detected platforms:", Color::GREEN, Color::BOLD)
            installed.each do |inst|
              puts "   • #{Color.c(inst[:platform], Color::BOLD)}: #{Color.c(inst[:path], Color::CYAN)}"
            end
            puts "\nAI agents will now automatically detect and trigger GSC commands for SEO and indexing tasks."
            puts
          end
        when 'show', 'cat', 'raw'
          puts CommandRegistry::SKILL_MD_CONTENT
        else
          installed = []
          installed << { platform: 'Antigravity / Gemini', path: gemini_path } if File.exist?(gemini_path)
          installed << { platform: 'Claude Code', path: claude_path } if File.exist?(claude_path)
          installed << { platform: 'Universal Workspace (.agents)', path: local_path } if File.exist?(local_path)

          if options[:json]
            puts JSON.pretty_generate({
              skill: 'gsc',
              installed: !installed.empty?,
              locations: installed,
              description: 'Automates Google Search Console, Google Indexing API, live URL index inspection, sitemap batch submission, and search ranking analytics.'
            })
            return
          end

          puts Base::BANNER
          puts "#{Color::BOLD}🤖 GSC AI AGENT SKILL (Platform-Agnostic):#{Color::RESET}"
          if installed.empty?
            puts "   Status:   #{Color.c('⚠️ Not currently installed', Color::YELLOW, Color::BOLD)}"
            puts "   Install:  Run #{Color.c('gsc skills install', Color::CYAN)} to auto-detect and install for your agent."
          else
            puts "   Status:   #{Color.c('✅ Installed and active', Color::GREEN, Color::BOLD)}"
            installed.each do |inst|
              puts "   • #{inst[:platform]}: #{Color.c(inst[:path], Color::CYAN)}"
            end
          end
          puts
          puts "#{Color::BOLD}Agent Features & Capabilities:#{Color::RESET}"
          puts "   • #{Color.c('gsc top-queries --json', Color::CYAN)}      - Query real SERP rankings, impressions, and CTR"
          puts "   • #{Color.c('gsc inspect <url> --json', Color::CYAN)}    - Live index status & Googlebot crawl verdict"
          puts "   • #{Color.c('gsc index <url> --json', Color::CYAN)}      - Instant Googlebot re-crawl notification"
          puts "   • #{Color.c('gsc audit --json', Color::CYAN)}            - Automated 4-step SEO & indexing health audit"
          puts "   • #{Color.c('gsc domains --json', Color::CYAN)}          - List verified properties & active domain"
          puts
          puts "#{Color::BOLD}Available subcommands:#{Color::RESET}"
          puts "   #{Color.c('gsc skills', Color::CYAN)}                    Display skill status across agent platforms"
          puts "   #{Color.c('gsc skills install', Color::CYAN)}            Auto-install to ~/.gemini, ~/.claude, and .agents"
          puts "   #{Color.c('gsc skills show', Color::CYAN)}               Print raw SKILL.md markdown for any agent"
          puts
        end
      end

      def handle_config_command(subcommand, subvalue, subextra_or_options = nil, maybe_options = {})
        if subextra_or_options.is_a?(Hash)
          options = subextra_or_options
          subextra = nil
        else
          subextra = subextra_or_options
          options = maybe_options || {}
        end

        case subcommand
        when 'set'
          key = subvalue.to_s.strip
          val = subextra.to_s.strip
          if key.empty? || val.empty?
            if options[:json]
              puts JSON.pretty_generate({ error: 'Usage: gsc config set <key> <value>' })
            else
              puts Color.c("❌ Error: Please specify key and value.", Color::RED)
              puts "Example: gsc config set opr_api_key opr_live_xxxx"
              puts "Example: gsc config set pagespeed_api_key AIzaSyxxxx"
            end
            exit 1
          end

          Config.set(key, val)
          if key == 'opr_api_key'
            Config.set('openpagerank_api_key', val)
          elsif key == 'openpagerank_api_key'
            Config.set('opr_api_key', val)
          end

          masked = val.length > 8 ? "#{val[0..7]}...#{val[-4..-1]}" : "***"
          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', key: key, value: masked, configFile: Config::CONFIG_FILE })
          else
            puts Base::BANNER
            puts Color.c("✅ Saved configuration: #{Color.c(key, Color::CYAN)} = #{Color.c(masked, Color::GREEN)}", Color::GREEN, Color::BOLD)
            puts Color.c("   📁 Stored in #{Config::CONFIG_FILE}", Color::GRAY)
          end
          return

        when 'get'
          key = subvalue.to_s.strip
          val = Config.get(key)
          if options[:json]
            puts JSON.pretty_generate({ key: key, value: val })
          else
            puts val || "(not set)"
          end
          return

        when 'set-domain', 'domain'
          if subvalue.nil? || subvalue.empty?
            if options[:json]
              puts JSON.pretty_generate({ error: 'Please specify a domain' })
            else
              puts Color.c("❌ Error: Please specify a domain.", Color::RED)
            end
            exit 1
          end
          clean = Config.set_default_domain(subvalue)
          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', defaultDomain: clean })
          else
            puts Base::BANNER
            puts Color.c("✅ Default domain updated to: #{clean}", Color::GREEN, Color::BOLD)
          end
        when 'set-key', 'key'
          if subvalue.nil? || !File.exist?(subvalue)
            if options[:json]
              puts JSON.pretty_generate({ error: "Key file does not exist: #{subvalue}" })
            else
              puts Color.c("❌ Error: Key file does not exist: #{subvalue}", Color::RED)
            end
            exit 1
          end
          dest = File.join(Config::CONFIG_DIR, 'service-account.json')
          FileUtils.mkdir_p(Config::CONFIG_DIR)
          File.chmod(0700, Config::CONFIG_DIR) rescue nil
          FileUtils.cp(subvalue, dest)
          File.chmod(0600, dest) rescue nil
          Config.set_key_path(dest)
          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', keyPath: dest })
          else
            puts Base::BANNER
            puts Color.c("✅ Service account key copied to: #{dest}", Color::GREEN, Color::BOLD)
          end
        when 'set-update-url', 'update-url'
          if subvalue.nil? || subvalue.empty?
            if options[:json]
              puts JSON.pretty_generate({ error: 'Please specify an update URL' })
            else
              puts Color.c("❌ Error: Please specify an update URL.", Color::RED)
            end
            exit 1
          end
          Config.save('update_url' => subvalue)
          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', updateUrl: subvalue })
          else
            puts Base::BANNER
            puts Color.c("✅ Update source URL saved to: #{subvalue}", Color::GREEN, Color::BOLD)
          end
        when 'set-ga4', 'ga4'
          if subvalue.nil? || subvalue.empty?
            if options[:json]
              puts JSON.pretty_generate({ error: 'Please specify a numeric GA4 Property ID' })
            else
              puts Color.c("❌ Error: Please specify a numeric GA4 Property ID.", Color::RED)
              puts "Example: gsc config set-ga4 123456789 [-d example.com]"
            end
            exit 1
          end
          target_dom = options[:domain] || Config.default_domain
          saved_id = Config.set_ga4_property_id(subvalue, target_dom)
          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', domain: target_dom, ga4PropertyId: saved_id })
          else
            puts Base::BANNER
            dom_str = target_dom ? " for domain #{Color.c(target_dom, Color::CYAN)}" : ""
            puts Color.c("✅ GA4 Property #{Color.c(saved_id, Color::MAGENTA, Color::BOLD)} linked#{dom_str}!", Color::GREEN, Color::BOLD)
          end
        when 'unlink-ga4'
          target_dom = options[:domain] || Config.default_domain
          Config.unlink_ga4_property(target_dom)
          if options[:json]
            puts JSON.pretty_generate({ status: 'ok', unlinkedDomain: target_dom })
          else
            puts Base::BANNER
            puts Color.c("✅ Unlinked GA4 property for domain #{Color.c(target_dom, Color::CYAN)}.", Color::GREEN)
          end
        else
          cfg = Config.load
          key_path = Auth.find_key(options[:key])
          sa = key_path ? (JSON.parse(File.read(key_path)) rescue {}) : {}

          if options[:json]
            puts JSON.pretty_generate(cfg.merge({
              configFile: Config::CONFIG_FILE,
              keyLocation: key_path,
              serviceAccount: sa['client_email']
            }))
            return
          end

          puts Base::BANNER
          puts "#{Color::BOLD}⚙️  GSC CLI CONFIGURATION:#{Color::RESET}"
          puts "   Config File:     #{Color.c(Config::CONFIG_FILE, Color::CYAN)}"
          puts "   Default Domain:  #{cfg['default_domain'] ? Color.c(cfg['default_domain'], Color::GREEN, Color::BOLD) : Color.c('(not set - run: gsc use <domain>)', Color::GRAY)}"
          if key_path
            puts "   Key Location:    #{Color.c(key_path, Color::CYAN)}"
            puts "   Service Account: #{Color.c(sa['client_email'], Color::GREEN)}"
          else
            puts "   Key Location:    #{Color.c('Not found', Color::RED)}"
          end
          opr = cfg['opr_api_key'] || cfg['openpagerank_api_key']
          if opr
            m_opr = opr.length > 8 ? "#{opr[0..7]}...#{opr[-4..-1]}" : "***"
            puts "   OpenPageRank:    #{Color.c(m_opr, Color::GREEN)} (Active)"
          else
            puts "   OpenPageRank:    #{Color.c('(not set - run: gsc config set opr_api_key <key>)', Color::GRAY)}"
          end

          ps = cfg['pagespeed_api_key']
          if ps
            m_ps = ps.length > 8 ? "#{ps[0..7]}...#{ps[-4..-1]}" : "***"
            puts "   PageSpeed API:   #{Color.c(m_ps, Color::GREEN)} (Active)"
          end

          ke = cfg['keywords_everywhere_api_key']
          if ke
            m_ke = ke.length > 8 ? "#{ke[0..7]}...#{ke[-4..-1]}" : "***"
            puts "   Keywords Evr:    #{Color.c(m_ke, Color::GREEN)} (Active)"
          end

          puts "\n   #{Color::BOLD}Linked GA4 Properties per Domain:#{Color::RESET}"
          ga4_props = cfg['ga4_properties'] || {}
          if ga4_props.empty?
            puts "      #{Color.c('(None linked yet. Use: gsc config set-ga4 <id> -d <domain>)', Color::GRAY)}"
          else
            ga4_props.each do |dom, pid|
              active_star = (dom == cfg['default_domain']) ? " #{Color.c('👈 [ACTIVE]', Color::GREEN)}" : ""
              puts "      • #{Color.c(dom, Color::CYAN)} ➔ #{Color.c(pid, Color::MAGENTA, Color::BOLD)}#{active_star}"
            end
          end
          puts
          puts "#{Color::BOLD}Configuration shortcuts:#{Color::RESET}"
          puts "   gsc connect                  Interactive setup wizard (drag & drop key)"
          puts "   gsc use <domain>             Set active default domain"
          puts "   gsc config set <key> <val>   Set API key (e.g. opr_api_key, pagespeed_api_key)"
          puts "   gsc config get <key>         Read a stored configuration value"
        end
      end

      def handle_commands(options)
        if options[:json]
          puts JSON.pretty_generate({
            cli: 'gsc',
            activeDomain: Config.default_domain,
            commandCount: CommandRegistry::COMMAND_REGISTRY.sum { |c| c[:commands].size },
            categories: CommandRegistry::COMMAND_REGISTRY
          })
        else
          print_commands_help
        end
      end

      def handle_help(parser, options = {})
        puts Base::BANNER
        puts parser if parser
        print_commands_help
      end

      def print_setup_instructions
        puts Color.c("\n❌ Error: Google Service Account Key JSON not found!\n", Color::RED, Color::BOLD)
        puts <<~SETUP
          #{Color::BOLD}QUICK SETUP GUIDE (2 Minutes):#{Color::RESET}

          #{Color::CYAN}1. Google Cloud Console:#{Color::RESET}
             • Go to: https://console.cloud.google.com/
             • In 'APIs & Services' > 'Library', enable:
               - #{Color::BOLD}Web Search Indexing API#{Color::RESET}
               - #{Color::BOLD}Google Search Console API#{Color::RESET}
               - #{Color::BOLD}Google Analytics Data API#{Color::RESET} (for on-site metrics & retention)
               - #{Color::BOLD}Google Analytics Admin API#{Color::RESET} (for auto-discovering GA4 properties)
             • In 'IAM & Admin' > 'Service Accounts', create a service account.
             • Click the service account > 'Keys' > 'Add Key' > 'Create new key' > 'JSON'.
             • Download the key.

          #{Color::CYAN}2. Run 1-Click Connect:#{Color::RESET}
             • Run: #{Color.c('gsc connect', Color::GREEN, Color::BOLD)}
             • It will automatically find the key in Downloads or let you drag & drop it!

          #{Color::CYAN}3. Google Search Console Permissions:#{Color::RESET}
             • Copy your Service Account email (shown during gsc connect).
             • Go to: https://search.google.com/search-console/
             • Select your property > 'Settings' > 'Users and permissions'.
             • Click #{Color::BOLD}'Add User'#{Color::RESET} with permission #{Color::BOLD}Owner#{Color::RESET}.

          Then re-run: #{Color::BOLD}gsc domains#{Color::RESET} to verify!
        SETUP
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
            #{Color.c('underperformers', Color::YELLOW)}              Top 10 queries with low CTR (easy title & meta hook wins)
            #{Color.c('cannibalization', Color::RED)}                Detect multiple URLs competing for the same query
            #{Color.c('decay [--compare 28]', Color::RED)}           Period-over-period trend analysis (Decaying vs Surging)
            #{Color.c('zombies [sitemap]', Color::RED)}              Detect zero-impression pages in sitemap wasting crawl budget

          #{Color::BOLD}GOOGLE ANALYTICS 4 (GA4) & POST-CLICK BEHAVIOR:#{Color::RESET}
            #{Color.c('connect-ga4', Color::MAGENTA)}                 Interactive GA4 linking wizard (walks through setup & tests live)
            #{Color.c('config set-ga4 <id>', Color::MAGENTA)}         Link a GA4 Property ID to active domain (stored in config)
            #{Color.c('config unlink-ga4', Color::MAGENTA)}           Unlink GA4 Property ID from active domain
            #{Color.c('realtime [--watch]', Color::MAGENTA)}          Live active visitors, pages, and countries right now
            #{Color.c('ga4 [--organic]', Color::MAGENTA)}             Landing page bounce rates, engagement rates, sessions, duration
            #{Color.c('correlation [--organic]', Color::MAGENTA)}     Merge GSC keyword rankings with GA4 bounce rates per landing page
            #{Color.c('ads [--days 30]', Color::MAGENTA)}             Google Ads campaign performance (Clicks, Cost, CPC, CPA, Conv)
            #{Color.c('channels [--days 30]', Color::MAGENTA)}        Omnichannel acquisition breakdown (Organic, Paid, Direct, Referral)
            #{Color.c('ga4-properties', Color::MAGENTA)}              Discover all GA4 Property IDs accessible by your service account

          #{Color::BOLD}INDEXING & SITEMAP COMMANDS:#{Color::RESET}
            #{Color.c('index <url>', Color::GREEN)}                  Notify Googlebot to crawl/index a URL (URL_UPDATED)
            #{Color.c('remove <url>', Color::GREEN)}                 Notify Googlebot a URL has been deleted (URL_DELETED)
            #{Color.c('status <url>', Color::GREEN)}                 Check Google Indexing API metadata for a URL
            #{Color.c('inspect <url>', Color::CYAN)}                Live Search Console URL inspection (coverage, canonical, crawl date)
            #{Color.c('inspect-sitemap [path|url]', Color::CYAN)}  Bulk inspect all sitemap URLs & generate health report
            #{Color.c('index-sitemap [path|url]', Color::GREEN)}    Submit all URLs in an XML sitemap for batch indexing
            #{Color.c('sitemaps-list', Color::MAGENTA)}                List submitted sitemaps in Search Console & status
            #{Color.c('sitemaps-submit <url>', Color::MAGENTA)}        Submit / re-submit an XML sitemap to Search Console

          #{Color::BOLD}OFFLINE CACHE (TURN 20):#{Color::RESET}
            #{Color.c('cache status', Color::CYAN)}                   Inspect offline cache database, engine & snapshot size
            #{Color.c('cache warm [domain]', Color::CYAN)}            Fetch live GSC search data and persist locally
            #{Color.c('cache query [filter]', Color::CYAN)}           Instant (<10ms) offline query search and analysis
            #{Color.c('cache pages [filter]', Color::CYAN)}           Instant (<10ms) offline page performance review
            #{Color.c('cache diff <snap1> <snap2>', Color::CYAN)}     Offline delta analysis between historical snapshots
            #{Color.c('cache clear [domain]', Color::CYAN)}           Purge offline snapshots for domain or entirely

          #{Color::BOLD}AUTONOMOUS AI, GEO & AUDITING SUITE (v2.2):#{Color::RESET}
            #{Color.c('doctor', Color::GREEN)}                       Zero-dependency architecture certification (<100ms cold start)
            #{Color.c('vault [status|list|add]', Color::GREEN)}      Agency credential vault with AES-256-GCM encryption
            #{Color.c('geo [url]', Color::CYAN)}                     Generative Engine Optimization (GEO) & citability audit
            #{Color.c('cite-sim <url|file> [q]', Color::CYAN)}       AI Search Citation Simulator (ChatGPT, Perplexity, Claude)
            #{Color.c('answer <query>', Color::CYAN)}                Direct answer & information gain snippet synthesizer
            #{Color.c('aio-hunter [query|domain]', Color::CYAN)}     Google AI Overview (AIO) radar & citation gap hunter
            #{Color.c('soft-404 <url|file>', Color::RED)}            404 & Soft-404 crawl waste diagnostic & server rules
            #{Color.c('sparklines [query|page]', Color::YELLOW)}     Terminal ASCII sparklines & visual trajectory graphs
            #{Color.c('strike [domain]', Color::YELLOW)}             Striking-distance playbook: rewrites & link anchors
            #{Color.c('skill-pack [dir]', Color::CYAN)}              Export autonomous AI Agent Skill package

          #{Color::BOLD}AGENT & PROGRAMMATIC INTEGRATION:#{Color::RESET}
            #{Color.c('skills [install|show]', Color::CYAN)}        Inspect, install, or export the AI Agent Skill
            #{Color.c('-j, --json', Color::CYAN)}                   Machine-readable JSON output for all commands

          #{Color::BOLD}EXAMPLES BY WORKFLOW:#{Color::RESET}

          #{Color.c('1. Domain Setup & Switching:', Color::CYAN, Color::BOLD)}
            gsc connect                                  # Interactive 1-click credential setup
            gsc domains                                  # List all verified properties (choose by number)
            gsc use                                      # Interactive numbered domain switcher
            gsc use 2                                    # Switch active domain by number
            gsc use example.com                          # Switch active domain by name
            gsc where                                    # Inspect CLI path, active key, and config file

          #{Color.c('2. GA4 Linking & Analytics:', Color::CYAN, Color::BOLD)}
            gsc connect-ga4                              # Interactive GA4 linking wizard
            gsc config set-ga4 123456789                 # Link GA4 property ID to active domain
            gsc ga4-properties                           # Discover accessible GA4 properties
            gsc ga4 --organic                            # View landing page bounce rates & engagement
            gsc correlation                              # Correlate SERP rankings with on-site bounce rates
            gsc ads                                      # Google Ads campaign performance, cost & CPC
            gsc channels                                 # Omnichannel traffic sources (Organic, Paid, Direct)

          #{Color.c('3. Live Realtime Visitor Monitoring:', Color::CYAN, Color::BOLD)}
            gsc realtime                                 # Snapshot of active visitors, URLs & countries
            gsc realtime --watch                         # Stream live visitors in terminal (refreshes every 5s)
            gsc realtime -d example.com --watch 3        # Stream specific domain every 3s
            gsc realtime --json                          # Machine-readable JSON output for live dashboards

          #{Color.c('4. Search Performance & Multi-Dimensional Analytics:', Color::CYAN, Color::BOLD)}
            gsc performance                              # Executive 360° dashboard (Devices, Countries, Snippets, Cities)
            gsc devices                                  # Desktop vs Mobile vs Tablet search traffic breakdown
            gsc countries --limit 20                     # Top countries driving organic search impressions & clicks
            gsc cities --limit 20                        # Top visitor cities and behavioral retention (via GA4)
            gsc snippets                                 # Rich snippet appearances (Review stars, Product listings, FAQs)
            gsc top-queries                              # Top search keywords, impressions, CTR, position
            gsc top-queries -s imp --days 7              # Sort queries by highest impression volume
            gsc top-pages -s clicks                      # Top traffic-driving landing pages
            gsc opportunities --min-imp 10               # Striking-distance queries (Pos 7–20) to push to Top 3
            gsc underperformers                          # Fix low CTR titles on existing Top 10 rankings
            gsc cannibalization                          # Detect internal URL ranking conflicts
            gsc decay --compare 28                       # Compare last 28 days vs prior 28 days
            gsc zombies public/sitemap.xml               # Find zero-impression crawl waste pages
            gsc audit                                    # Comprehensive 4-step SEO & GA4 health audit

          #{Color.c('5. Google Indexing & Sitemaps:', Color::CYAN, Color::BOLD)}
            gsc inspect https://example.com/pricing      # Live Google index check (coverage, canonical, date)
            gsc index https://example.com/new-page       # Notify Googlebot to crawl/index URL immediately
            gsc remove https://example.com/deleted-page  # Notify Googlebot a page has been removed
            gsc status https://example.com/page          # Check Google Indexing API submission status
            gsc sitemaps-list                            # List submitted sitemaps in Search Console
            gsc sitemaps-submit https://example.com/sitemap.xml # Submit new XML sitemap to Google
            gsc index-sitemap public/sitemap.xml         # Batch submit all sitemap URLs to Google Indexing API
            gsc inspect-sitemap public/sitemap.xml       # Bulk inspect indexation status for all sitemap URLs

          #{Color.c('6. Agent & JSON Export:', Color::CYAN, Color::BOLD)}
            gsc top-queries --json                       # Clean JSON output for AI agents & pipelines
            gsc top-pages --csv pages.csv                # Export top pages to CSV
            gsc skills show                              # View the AI Agent Skill prompt
            gsc skills install                           # Install agent skill to ~/.gemini/config

          #{Color.c('7. Trends, Autocomplete & Keyword Intelligence:', Color::CYAN, Color::BOLD)}
            gsc trends "seo audit"                       # Google Trends search interest & regional demand
            gsc trends "technical seo" --geo US          # Filter trends to United States
            gsc trends "core web vitals" --time 12m      # 12-month interest timeline & momentum
            gsc planner "search console"                 # Free autocomplete expansion & opportunity scoring
            gsc planner-import keywords.csv              # Import Google Ads Keyword Planner export & rank
            gsc ke "technical seo"                       # Keywords Everywhere search volume, CPC & competition
            gsc ke-credits                               # Check remaining Keywords Everywhere credit balance
            gsc connect ke                               # Link Keywords Everywhere API key

          #{Color.c('8. Offline Cache & Speed (Turn 20):', Color::CYAN, Color::BOLD)}
            gsc cache warm                               # Cache search performance data locally for instant querying
            gsc cache query "search console"             # Query cached data in <10ms without hitting Google API
            gsc cache diff snap_1 snap_2                 # Compare rankings between two offline snapshots

        COMMANDS
      end
    end
  end
end

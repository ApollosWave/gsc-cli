# frozen_string_literal: true

require 'uri'
require 'json'

module GSC
  class CLI
    module Base
      BANNER = <<~BANNER
        #{Color::BOLD}#{Color::CYAN}╔══════════════════════════════════════════════════════════════╗
        ║     🚀 GOOGLE SEARCH CONSOLE & INDEXING API (RUBY CLI)       ║
        ╚══════════════════════════════════════════════════════════════╝#{Color::RESET}
      BANNER

      COUNTRY_NAMES = {
        'usa' => 'United States 🇺🇸',
        'gbr' => 'United Kingdom 🇬🇧',
        'can' => 'Canada 🇨🇦',
        'aus' => 'Australia 🇦🇺',
        'ind' => 'India 🇮🇳',
        'bra' => 'Brazil 🇧🇷',
        'deu' => 'Germany 🇩🇪',
        'fra' => 'France 🇫🇷',
        'esp' => 'Spain 🇪🇸',
        'ita' => 'Italy 🇮🇹',
        'mex' => 'Mexico 🇲🇽',
        'jpn' => 'Japan 🇯🇵',
        'kor' => 'South Korea 🇰🇷',
        'nld' => 'Netherlands 🇳🇱',
        'swe' => 'Sweden 🇸🇪',
        'nor' => 'Norway 🇳🇴',
        'dnk' => 'Denmark 🇩🇰',
        'fin' => 'Finland 🇫🇮',
        'che' => 'Switzerland 🇨🇭',
        'aut' => 'Austria 🇦🇹',
        'bel' => 'Belgium 🇧🇪',
        'irl' => 'Ireland 🇮🇪',
        'nzl' => 'New Zealand 🇳🇿',
        'sgp' => 'Singapore 🇸🇬',
        'hkg' => 'Hong Kong 🇭🇰',
        'are' => 'UAE 🇦🇪',
        'sau' => 'Saudi Arabia 🇸🇦',
        'kwt' => 'Kuwait 🇰🇼',
        'isr' => 'Israel 🇮🇱',
        'tur' => 'Turkey 🇹🇷',
        'pol' => 'Poland 🇵🇱',
        'ukr' => 'Ukraine 🇺🇦',
        'zaf' => 'South Africa 🇿🇦',
        'col' => 'Colombia 🇨🇴',
        'arg' => 'Argentina 🇦🇷',
        'chl' => 'Chile 🇨🇱',
        'per' => 'Peru 🇵🇪',
        'pak' => 'Pakistan 🇵🇰',
        'bgd' => 'Bangladesh 🇧🇩',
        'phl' => 'Philippines 🇵🇭',
        'vnm' => 'Vietnam 🇻🇳',
        'tha' => 'Thailand 🇹🇭',
        'mys' => 'Malaysia 🇲🇾',
        'idn' => 'Indonesia 🇮🇩',
        'chn' => 'China 🇨🇳',
        'twn' => 'Taiwan 🇹🇼',
        'prt' => 'Portugal 🇵🇹',
        'grc' => 'Greece 🇬🇷',
        'cze' => 'Czech Republic 🇨🇿',
        'rou' => 'Romania 🇷🇴',
        'hun' => 'Hungary 🇭🇺',
        'egy' => 'Egypt 🇪🇬',
        'nga' => 'Nigeria 🇳🇬',
        'ken' => 'Kenya 🇰🇪',
        'mar' => 'Morocco 🇲🇦',
        'arm' => 'Armenia 🇦🇲',
        'aze' => 'Azerbaijan 🇦🇿',
        'bgr' => 'Bulgaria 🇧🇬',
        'bhr' => 'Bahrain 🇧🇭',
        'brn' => 'Brunei 🇧🇳',
        'civ' => 'Ivory Coast 🇨🇮',
        'cyp' => 'Cyprus 🇨🇾',
        'dom' => 'Dominican Rep. 🇩🇴',
        'dza' => 'Algeria 🇩🇿',
        'gtm' => 'Guatemala 🇬🇹',
        'hrv' => 'Croatia 🇭🇷',
        'irn' => 'Iran 🇮🇷',
        'irq' => 'Iraq 🇮🇶',
        'jam' => 'Jamaica 🇯🇲',
        'jor' => 'Jordan 🇯🇴',
        'lby' => 'Libya 🇱🇾',
        'ltu' => 'Lithuania 🇱🇹',
        'lva' => 'Latvia 🇱🇻',
        'est' => 'Estonia 🇪🇪',
        'qat' => 'Qatar 🇶🇦',
        'omn' => 'Oman 🇴🇲',
        'srb' => 'Serbia 🇷🇸',
        'svk' => 'Slovakia 🇸🇰',
        'svn' => 'Slovenia 🇸🇮',
        'isl' => 'Iceland 🇮🇸',
        'lux' => 'Luxembourg 🇱🇺',
        'lka' => 'Sri Lanka 🇱🇰',
        'npl' => 'Nepal 🇳🇵',
        'tun' => 'Tunisia 🇹🇳',
        'gha' => 'Ghana 🇬🇭'
      }.freeze

      APPEARANCE_NAMES = {
        'REVIEW_SNIPPET'        => '⭐ Review Snippets',
        'PRODUCT_SNIPPETS'      => '🏷️ Product Snippets',
        'MERCHANT_LISTINGS'     => '🏪 Merchant Listings',
        'PAGE_EXPERIENCE'       => '⚡ Page Experience',
        'GOOD_PAGE_EXPERIENCE'  => '✅ Good Page Experience',
        'FAQ'                   => '❓ FAQ Rich Results',
        'VIDEO'                 => '🎥 Video Snippets',
        'RECIPE'                => '🍲 Recipe Rich Results',
        'EVENT'                 => '📅 Event Listings',
        'HOW_TO'                => '📋 How-To Rich Results',
        'SUBMIT_ACTION'         => '📝 Sitelinks Searchbox',
        'AMP_ARTICLE'           => '⚡ AMP Article',
        'ORGANIC_SHOPPING'      => '🛍️ Organic Shopping',
        'TRANSLATED_RESULT'     => '🌐 Translated Result'
      }.freeze

      module_function

      def resolve_domain(domain_arg, target_arg, options = {})
        raw = domain_arg
        if raw.nil? || raw.empty?
          if target_arg && target_arg.start_with?('http://', 'https://')
            raw = URI(target_arg).hostname
          else
            raw = ENV['GSC_DOMAIN'] || Config.default_domain
          end
        end

        if raw.nil? || raw.empty?
          if options[:json]
            puts JSON.pretty_generate({ error: 'No target domain specified. Run gsc use <domain> or pass -d <domain>.' })
          else
            puts Color.c("\n⚠️  No target domain specified!", Color::YELLOW, Color::BOLD)
            puts "Please specify a domain using one of the following:"
            puts "  1. Set a global active domain:  #{Color.c('gsc use <domain>', Color::CYAN)}"
            puts "  2. Pass domain flag:            #{Color.c('gsc <command> -d <domain>', Color::CYAN)}"
            puts "  3. Set environment variable:    #{Color.c('export GSC_DOMAIN=<domain>', Color::CYAN)}"
            puts
          end
          exit 1
        end

        if raw.start_with?('sc-domain:')
          hostname = raw.sub('sc-domain:', '')
          site_url = raw
        elsif raw.start_with?('http://', 'https://')
          uri = URI(raw)
          hostname = uri.hostname
          site_url = raw.end_with?('/') ? raw : "#{raw}/"
        else
          hostname = raw.chomp('/')
          site_url = "sc-domain:#{hostname}"
        end

        https_origin = "https://#{hostname}"
        [hostname, site_url, https_origin]
      end

      def require_target!(target, example, options = {})
        return if target && !target.empty?

        if options[:json]
          puts JSON.pretty_generate({ error: 'Target URL is required', example: "gsc #{example}" })
        else
          puts Color.c("❌ Error: Please provide a URL target.", Color::RED)
          puts "Example: gsc #{example}"
        end
        exit 1
      end

      def dry_run?(options)
        if options[:dry_run]
          puts Color.c('⚠️ [DRY-RUN] Preview mode active. No live API call made.', Color::YELLOW) unless options[:json]
          true
        else
          false
        end
      end
      def simulate_dry_run?(options); dry_run?(options); end

      def print_batch_summary(success, fail, total)
        puts "\n#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}"
        puts "#{Color::BOLD}🎉 BATCH INDEXATION COMPLETE#{Color::RESET}"
        puts "   ✅ Successfully Submitted: #{Color.c(success.to_s, Color::GREEN, Color::BOLD)} / #{total}"
        puts "   ❌ Failed Requests:        #{Color.c(fail.to_s, Color::RED, Color::BOLD)}" if fail > 0
        puts "#{Color::BOLD}══════════════════════════════════════════════════════════════#{Color::RESET}\n"
      end

      def write_csv(path, headers, rows)
        File.open(path, 'w', encoding: 'UTF-8') do |f|
          escaped_headers = headers.map { |h| "\"#{h.to_s.gsub('"', '""')}\"" }
          f.puts escaped_headers.join(',')
          rows.each do |row|
            escaped = row.map do |v|
              str = v.to_s
              str = "'#{str}" if str =~ /\A[=+\-@\t\r]/
              "\"#{str.gsub('"', '""')}\""
            end
            f.puts escaped.join(',')
          end
        end
      end

      def format_api_error(data)
        if data.is_a?(Hash)
          data.dig('error', 'message') || data['error'] || data['message'] || data.to_json
        else
          data.to_s
        end
      end

      def format_currency(val)
        parts = sprintf('%.2f', val.to_f).split('.')
        parts[0] = parts[0].reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
        parts.join('.')
      end

      def normalize_path(url_or_path)
        return '/' if url_or_path.nil? || url_or_path.empty?
        p = url_or_path.to_s.sub(%r{^https?://[^/]+}, '').split('?').first.split('#').first.downcase.chomp('/')
        p.empty? ? '/' : p
      end

      def format_duration(seconds)
        sec = seconds.to_i
        return "0s" if sec <= 0
        m = sec / 60
        s = sec % 60
        m > 0 ? "#{m}m #{s}s" : "#{s}s"
      end

      def expected_ctr_for(pos)
        case pos
        when 0.0...1.5 then 28.0
        when 1.5...2.5 then 15.0
        when 2.5...3.5 then 11.0
        when 3.5...4.5 then 8.0
        when 4.5...6.0 then 6.0
        when 6.0...8.0 then 4.5
        else 3.0
        end
      end

      def format_number(n)
        n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      def format_country(code)
        COUNTRY_NAMES[code.to_s.downcase] || code.to_s.upcase
      end

      def format_device(dev)
        case dev.to_s.upcase
        when 'DESKTOP' then '💻 Desktop'
        when 'MOBILE'  then '📱 Mobile'
        when 'TABLET'  then '📟 Tablet'
        else dev.to_s.capitalize
        end
      end

      def format_appearance(type)
        APPEARANCE_NAMES[type.to_s.upcase] || type.to_s.tr('_', ' ').capitalize
      end

      def resolve_sort_params(field, order)
        canonical_field = case field&.to_s&.downcase&.strip
        when 'imp', 'impr', 'impressions'
          :impressions
        when 'pos', 'rank', 'position'
          :position
        when 'ctr'
          :ctr
        when 'clicks', 'click'
          :clicks
        when nil, ''
          nil
        else
          field.to_s.downcase.strip.to_sym
        end

        canonical_order = if order && !order.to_s.strip.empty?
          order.to_s.downcase.strip.start_with?('asc') ? :asc : :desc
        elsif canonical_field == :position
          :asc
        else
          :desc
        end

        [canonical_field, canonical_order]
      end

      def sort_analytics_rows(rows, sort_field, order)
        field, dir = resolve_sort_params(sort_field, order)

        if field
          rows.sort do |a, b|
            val_a = a[field] || 0
            val_b = b[field] || 0
            cmp = val_a <=> val_b
            cmp = (cmp.nil? ? 0 : cmp)
            dir == :asc ? cmp : -cmp
          end
        else
          rows.sort do |a, b|
            clicks_cmp = (b[:clicks] || 0) <=> (a[:clicks] || 0)
            if clicks_cmp.zero?
              imp_cmp = (b[:impressions] || 0) <=> (a[:impressions] || 0)
              if imp_cmp.zero?
                (a[:position] || 999.0) <=> (b[:position] || 999.0)
              else
                imp_cmp
              end
            else
              clicks_cmp
            end
          end
        end
      end

      def fetch_available_domains
        domains = []
        key_path = Auth.find_key
        if key_path && File.exist?(key_path)
          begin
            sa = JSON.parse(File.read(key_path))
            token = Auth.fetch_access_token(sa)
            client = Client.new(token: token)
            api = API.new(client)
            res = api.list_sites
            if res[:ok]
              (res.dig(:data, 'siteEntry') || []).each do |s|
                clean = s['siteUrl'].sub(%r{^https?://}, '').sub(/^sc-domain:/, '').chomp('/')
                domains << clean unless domains.include?(clean)
              end
            end
          rescue StandardError
            # fallback to config
          end
        end

        Config.ga4_properties.keys.each do |d|
          domains << d unless domains.include?(d)
        end

        domains.sort
      end

      def copy_to_clipboard(text)
        if RUBY_PLATFORM =~ /darwin/
          IO.popen('pbcopy', 'w') { |f| f << text }
          true
        elsif system('which xclip > /dev/null 2>&1')
          IO.popen('xclip -selection clipboard', 'w') { |f| f << text }
          true
        else
          false
        end
      rescue StandardError
        false
      end

      def open_in_browser(url)
        return false if url.nil? || url.to_s.strip.empty?
        return false if ENV['CI'] || ENV['HEADLESS']

        if RUBY_PLATFORM =~ /darwin/
          system('open', url.to_s)
        elsif RUBY_PLATFORM =~ /linux/
          return false unless ENV['DISPLAY'] || ENV['WAYLAND_DISPLAY']
          system('xdg-open', url.to_s)
        elsif RUBY_PLATFORM =~ /mswin|mingw|cygwin/
          system('start', '', url.to_s)
        else
          false
        end
      rescue StandardError
        false
      end
    end
  end
end

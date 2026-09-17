# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'set'

module GSC
  class HreflangValidator
    # Common ISO 639-1 two-letter language codes
    ISO_639_1_LANGUAGES = Set.new(%w[
      aa ab ae af ak am an ar as av ay az ba be bg bh bi bm bn bo br bs ca ce ch co cr cs cu cv cy da de dv dz ee el
      en eo es et eu fa ff fi fj fo fr fy ga gd gl gn gu gv ha he hi ho hr ht hu hy hz ia id ie ig ii ik io is it iu
      ja jv ka kg ki kj kk kl km kn ko kr ks ku kv kw ky la lb lg li ln lo lt lu lv mg mh mi mk ml mn mr ms mt my na
      nb nd ne ng nl nn no nr nv ny oc oj om or os pa pi pl ps pt qu rm rn ro ru rw sa sc sd se sg si sk sl sm sn so
      sq sr ss st su sv sw ta te tg th ti tk tl tn to tr ts tt tw ty ug uk ur uz ve vi vo wa wo xh yi yo za zh zu
    ]).freeze

    # Common script codes (4 letters, Titlecase)
    SCRIPT_CODES = Set.new(%w[
      Hans Hant Cyrl Latn Arab Deva
    ]).freeze

    # ISO 3166-1 alpha-2 two-letter uppercase country/region codes
    ISO_3166_1_REGIONS = Set.new(%w[
      AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ
      CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO
      FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE
      JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO
      MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW
      PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM
      TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW
    ]).freeze

    # Known common mistakes & corrections
    CODE_CORRECTIONS = {
      'en-uk' => 'en-GB (The ISO 3166-1 region code for the UK is "GB", not "UK")',
      'uk'    => 'uk is Ukrainian; for United Kingdom English, use "en-GB"',
      'jp'    => 'jp is country code; for Japanese language, use "ja" or "ja-JP"',
      'kr'    => 'kr is country code; for Korean language, use "ko" or "ko-KR"',
      'sp'    => 'sp is invalid; for Spanish, use "es"',
      'ge'    => 'ge is Georgia; for German, use "de"',
      'cz'    => 'cz is Czech Republic country code; for Czech language, use "cs"',
      'se'    => 'se is Northern Sami; for Swedish, use "sv" or "sv-SE"',
      'dk'    => 'dk is Denmark country code; for Danish language, use "da" or "da-DK"',
      'gr'    => 'gr is Greece country code; for Greek language, use "el" or "el-GR"',
      'es-la' => 'es-LA is invalid ("LA" is Laos, not Latin America; use "es-419" or country-specific codes)',
      'es-sa' => 'es-SA is invalid ("SA" is Saudi Arabia; use country-specific codes like es-AR, es-CL)',
      'cn'    => 'cn is country code; for Chinese, use "zh", "zh-Hans", or "zh-Hant"'
    }.freeze

    attr_reader :options, :url, :html, :headers

    def initialize(options = {})
      @options = options
    end

    def self.audit(target, options = {})
      new(options).audit(target)
    end

    def audit(target)
      @url, @html, @headers = load_target(target)
      tags = extract_hreflang_tags(@html, @headers, @url)

      # Validate language/region codes
      tags.each { |tag| validate_tag_code(tag) }

      # Self-referencing check
      self_ref_found = check_self_reference(tags, @url)

      # x-default check
      x_default_tag = tags.find { |t| t[:hreflang].downcase == 'x-default' }

      # Graph Reciprocity Check (for remote URLs)
      if @options[:check_reciprocity] != false && @url.match?(%r{^https?://})
        verify_reciprocity(tags, @url)
      end

      evaluate_health(tags, self_ref_found, x_default_tag)
    end

    private

    def load_target(target)
      target_str = target.to_s.strip
      if target_str.match?(%r{^https?://})
        uri = URI.parse(target_str)
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) gsc-cli/2.1'
        req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 10) do |http|
          http.request(req)
        end
        [target_str, res.body.to_s.dup.force_encoding('UTF-8').scrub, res.to_hash]
      elsif File.exist?(target_str)
        [target_str, File.read(target_str, encoding: 'UTF-8'), {}]
      else
        # In-memory HTML string (e.g. test fixtures)
        base = @options[:url] || 'https://example.com/'
        [base, target_str, {}]
      end
    rescue StandardError => e
      [target_str.to_s, "<html><head><!-- Error: #{e.message} --></head><body></body></html>", {}]
    end

    def extract_hreflang_tags(html_content, resp_headers, base_url)
      tags = []

      # 1. Extract from HTML <link ...>
      html_content.scan(/<link\b([^>]*?)>/im) do |match|
        attrs_str = match.first
        rel = extract_attr(attrs_str, 'rel')&.downcase
        next unless rel == 'alternate'

        hreflang = extract_attr(attrs_str, 'hreflang')
        href = extract_attr(attrs_str, 'href')
        next if hreflang.nil? || href.nil? || href.empty?

        resolved_href = resolve_url(href, base_url)
        tags << {
          source: :html,
          hreflang: hreflang.strip,
          href: resolved_href,
          raw_href: href,
          issues: [],
          status: :pending
        }
      end

      # 2. Extract from HTTP response headers (Link: <...>; rel="alternate"; hreflang="...")
      link_headers = Array(resp_headers['link']) + Array(resp_headers['Link'])
      link_headers.each do |lh|
        lh.split(',').each do |part|
          if part =~ /<([^>]+)>\s*;\s*rel\s*=\s*(?:["']?alternate["']?)/i
            href = $1
            hreflang = nil
            if part =~ /hreflang\s*=\s*["']?([^;"'\s]+)["']?/i
              hreflang = $1
            end
            if hreflang && href
              resolved_href = resolve_url(href, base_url)
              tags << {
                source: :http_header,
                hreflang: hreflang.strip,
                href: resolved_href,
                raw_href: href,
                issues: [],
                status: :pending
              }
            end
          end
        end
      end

      tags
    end

    def validate_tag_code(tag)
      code = tag[:hreflang].strip
      return if code.downcase == 'x-default'

      # Check for uppercase language code error (e.g., "EN", "EN-us")
      if code =~ /^[A-Z]{2}(?:-|$)/
        tag[:issues] << :uppercase_language
      end

      # Check for known common misconceptions
      lowered = code.downcase
      if CODE_CORRECTIONS.key?(lowered)
        tag[:issues] << :common_mistake
        tag[:correction] = CODE_CORRECTIONS[lowered]
      end

      # Split by hyphen
      parts = code.split('-')
      lang = parts[0].downcase

      unless ISO_639_1_LANGUAGES.include?(lang)
        tag[:issues] << :invalid_language unless tag[:issues].include?(:common_mistake)
      end

      if parts.size == 2
        subtag = parts[1]
        if subtag.length == 4 # Script (e.g. Hans, Hant)
          unless SCRIPT_CODES.include?(subtag.capitalize)
            tag[:issues] << :invalid_script
          end
        elsif subtag.length == 2 # Region (e.g. US, GB)
          region_upper = subtag.upcase
          unless ISO_3166_1_REGIONS.include?(region_upper)
            tag[:issues] << :invalid_region unless tag[:issues].include?(:common_mistake)
          end
          if subtag =~ /^[a-z]{2}$/
            tag[:issues] << :lowercase_region
          end
        elsif subtag == '419' # UN M.49 code for Latin America & Caribbean (valid in Google)
          # valid
        else
          tag[:issues] << :invalid_format
        end
      elsif parts.size > 2
        # e.g., zh-Hans-CN
        script = parts[1]
        region = parts[2]
        unless SCRIPT_CODES.include?(script.capitalize)
          tag[:issues] << :invalid_script
        end
        unless ISO_3166_1_REGIONS.include?(region.upcase)
          tag[:issues] << :invalid_region
        end
      end
    end

    def check_self_reference(tags, origin_url)
      norm_origin = normalize_url(origin_url)
      match = tags.find do |t|
        normalize_url(t[:href]) == norm_origin && t[:hreflang].downcase != 'x-default'
      end

      !match.nil?
    end

    def verify_reciprocity(tags, origin_url)
      norm_origin = normalize_url(origin_url)

      tags.each do |tag|
        norm_target = normalize_url(tag[:href])
        if norm_target == norm_origin
          tag[:status] = :self_referential
          next
        end

        # Fetch the alternate page and check for reciprocal link
        begin
          uri = URI.parse(tag[:href])
          req = Net::HTTP::Get.new(uri)
          req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) gsc-cli/2.1'

          res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 4, read_timeout: 5) do |http|
            http.request(req)
          end

          if res.code.to_i >= 400
            tag[:status] = :http_error
            tag[:issues] << "http_#{res.code}".to_sym
            next
          end

          dest_html = res.body.to_s.dup.force_encoding('UTF-8').scrub
          dest_tags = extract_hreflang_tags(dest_html, res.to_hash, tag[:href])

          # Check if dest_tags contains a link back to origin_url
          return_tag = dest_tags.find { |dt| normalize_url(dt[:href]) == norm_origin }

          if return_tag
            tag[:status] = :confirmed
            tag[:return_hreflang] = return_tag[:hreflang]
          else
            tag[:status] = :missing_return
            tag[:issues] << :missing_reciprocal_tag
          end
        rescue StandardError => e
          tag[:status] = :unreachable
          tag[:issues] << :network_error
        end
      end
    end

    def evaluate_health(tags, self_ref_found, x_default_tag)
      total = tags.size

      if total.zero?
        return {
          url: @url,
          total_tags: 0,
          health_score: 50.0,
          grade: 'C',
          self_reference: false,
          has_x_default: false,
          reciprocal_count: 0,
          unreciprocated_count: 0,
          invalid_code_count: 0,
          issues_summary: { missing_hreflang: 1 },
          prescriptions: ['Add bidirectional hreflang alternate tags to properly localize international audience.'],
          cluster_snippets: { html: '', sitemap_xml: '' },
          tags: []
        }
      end

      invalid_codes = tags.count { |t| (t[:issues] & %i[invalid_language invalid_region invalid_script common_mistake uppercase_language]).any? }
      unreciprocated = tags.count { |t| t[:status] == :missing_return }
      confirmed = tags.count { |t| t[:status] == :confirmed || t[:status] == :self_referential }

      score = 100.0
      score -= 25.0 unless self_ref_found
      score -= 15.0 unless x_default_tag
      score -= [invalid_codes * 15.0, 30.0].min
      score -= [unreciprocated * 20.0, 40.0].min

      score = [[score.round(1), 100.0].min, 0.0].max
      grade = compute_grade(score)

      summary = {
        total_tags: total,
        self_referencing: self_ref_found,
        x_default: !x_default_tag.nil?,
        confirmed_reciprocal: confirmed,
        unreciprocated: unreciprocated,
        invalid_codes: invalid_codes
      }

      prescriptions = generate_prescriptions(self_ref_found, x_default_tag, invalid_codes, unreciprocated, tags)
      snippets = generate_cluster_snippets(tags, @url)

      {
        url: @url,
        total_tags: total,
        health_score: score,
        grade: grade,
        self_reference: self_ref_found,
        has_x_default: !x_default_tag.nil?,
        reciprocal_count: confirmed,
        unreciprocated_count: unreciprocated,
        invalid_code_count: invalid_codes,
        issues_summary: summary,
        prescriptions: prescriptions,
        cluster_snippets: snippets,
        tags: tags
      }
    end

    def generate_prescriptions(self_ref, x_def, invalid_count, unrecip_count, tags)
      recs = []

      unless self_ref
        recs << "Add a self-referencing hreflang tag pointing back to #{@url}. Per Google guidelines, every language variant must include its own URL."
      end

      unless x_def
        recs << "Include an 'x-default' hreflang tag to handle international users whose language/region is not explicitly matched."
      end

      if invalid_count > 0
        mistakes = tags.select { |t| t[:correction] }
        if mistakes.any?
          mistakes.each do |m|
            recs << "Fix invalid hreflang code '#{m[:hreflang]}': #{m[:correction]}."
          end
        else
          recs << "Correct #{invalid_count} invalid ISO 639-1 language or ISO 3166-1 region codes."
        end
      end

      if unrecip_count > 0
        recs << "Resolve #{unrecip_count} missing return tags. Hreflang links must be bidirectional; alternate pages must point back to origin."
      end

      recs
    end

    def generate_cluster_snippets(tags, base_url)
      html_lines = []
      xml_lines = []

      tags.each do |t|
        html_lines << "<link rel=\"alternate\" hreflang=\"#{t[:hreflang]}\" href=\"#{t[:href]}\" />"
        xml_lines << "  <xhtml:link rel=\"alternate\" hreflang=\"#{t[:hreflang]}\" href=\"#{t[:href]}\" />"
      end

      {
        html: html_lines.join("\n"),
        sitemap_xml: xml_lines.join("\n")
      }
    end

    def compute_grade(score)
      case score
      when 90.0..100.0 then 'A+'
      when 80.0...90.0 then 'A'
      when 70.0...80.0 then 'B'
      when 55.0...70.0 then 'C'
      when 40.0...55.0 then 'D'
      else 'F'
      end
    end

    def extract_attr(tag_str, attr_name)
      if tag_str =~ /\b#{attr_name}\s*=\s*(['"])(.*?)\1/i
        $2.strip
      elsif tag_str =~ /\b#{attr_name}\s*=\s*([^\s>]+)/i
        $1.strip
      else
        nil
      end
    end

    def resolve_url(href, base)
      return href if href.match?(%r{^https?://})
      URI.join(base, href).to_s
    rescue StandardError
      href
    end

    def normalize_url(url)
      u = url.to_s.strip.downcase.sub(%r{/$}, '')
      u.split('#').first
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'
require 'time'
require_relative 'google_suggest' if File.exist?(File.expand_path('google_suggest.rb', __dir__))

module GSC
  class SerpFeatureDetector
    attr_reader :query, :options

    def initialize(query, options = {})
      @query = query.to_s.dup.force_encoding('UTF-8').scrub.strip
      @options = options
    end

    def detect
      intent = classify_intent(@query)
      paa_questions = extract_live_paa_questions(@query)
      live_serp = sample_live_serp(@query)

      ai_overview = detect_ai_overview(@query, intent)
      featured_snippet = detect_featured_snippet(@query, intent)
      local_pack = detect_local_pack(@query)
      video_carousel = detect_video_carousel(@query, live_serp)
      forum_discussions = detect_forum_discussions(@query, live_serp)
      shopping_pack = detect_shopping_pack(@query, intent)
      sitelinks = detect_sitelinks(@query, intent)

      zero_click = calculate_zero_click_risk(
        ai_overview: ai_overview,
        featured_snippet: featured_snippet,
        paa_count: paa_questions.size,
        local_pack: local_pack,
        shopping_pack: shopping_pack,
        video_carousel: video_carousel
      )

      playbook = generate_capture_playbook(
        query: @query,
        intent: intent,
        ai_overview: ai_overview,
        featured_snippet: featured_snippet,
        paa_questions: paa_questions
      )

      {
        query: @query,
        timestamp: Time.now.utc.iso8601,
        intent: intent,
        zero_click_threat: zero_click,
        features: {
          ai_overview: ai_overview,
          featured_snippet: featured_snippet,
          people_also_ask: {
            detected: !paa_questions.empty?,
            count: paa_questions.size,
            questions: paa_questions
          },
          local_3_pack: local_pack,
          video_carousel: video_carousel,
          discussions_and_forums: forum_discussions,
          shopping_pack: shopping_pack,
          sitelinks: sitelinks
        },
        serp_sampling: live_serp,
        playbook: playbook
      }
    end

    private

    def classify_intent(query)
      q = query.downcase

      if q =~ /\b(near me|in [a-z]+|city|store|repair|dentist|plumber|gym|shop|restaurant|agency)\b/i
        { primary: 'Local', secondary: 'Commercial', description: 'User seeking physical or regional local service' }
      elsif q =~ /\b(buy|order|purchase|coupon|discount|deal|cheap|for sale|pricing|price|cost)\b/i
        { primary: 'Transactional', secondary: 'Commercial', description: 'User is ready to make an immediate purchase' }
      elsif q =~ /\b(best|top|review|vs|versus|compare|alternative|alternatives|software|tool|app|guide)\b/i
        { primary: 'Commercial', secondary: 'Informational', description: 'User evaluating products or services before purchasing' }
      elsif q =~ /\b(login|portal|website|account|dashboard|sign in|app\.|\.com)\b/i
        { primary: 'Navigational', secondary: 'Brand', description: 'User navigating to a specific brand destination' }
      else
        { primary: 'Informational', secondary: 'Research', description: 'User seeking knowledge, definitions, answers or tutorials' }
      end
    end

    def extract_live_paa_questions(query)
      suggest = GSC::GoogleSuggest.new(query)
      raw = suggest.fetch(questions: true)
      extracted = []

      if raw.is_a?(Hash)
        raw.each_value do |items|
          Array(items).each do |item|
            term = item.is_a?(Hash) ? item[:term] : item.to_s
            clean = term.to_s.strip
            extracted << clean if !clean.empty? && !extracted.include?(clean)
          end
        end
      elsif raw.is_a?(Array)
        raw.each do |entry|
          if entry.is_a?(Array) && entry[1].is_a?(Array)
            entry[1].each do |item|
              term = item.is_a?(Hash) ? item[:term] : item.to_s
              clean = term.to_s.strip
              extracted << clean if !clean.empty? && !extracted.include?(clean)
            end
          elsif entry.is_a?(Hash) && entry[:term]
            term = entry[:term].to_s.strip
            extracted << term if !term.empty? && !extracted.include?(term)
          end
        end
      end

      # Filter for relevance to query tokens
      tokens = query.downcase.split(/\s+/).reject { |t| t.length < 3 }
      relevant = if tokens.empty?
                   extracted
                 else
                   matched = extracted.select { |q| tokens.any? { |t| q.downcase.include?(t) } }
                   matched.empty? ? extracted : matched
                 end

      relevant.first(8)
    rescue StandardError
      []
    end

    def sample_live_serp(query)
      results = []
      uri = URI("https://www.bing.com/search?q=#{URI.encode_www_form_component(query)}&setlang=en-US&cc=US")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 3
      http.read_timeout = 3
      req = Net::HTTP::Get.new(uri.request_uri)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
      req['Accept-Language'] = 'en-US,en;q=0.9'

      res = http.request(req)
      if res.is_a?(Net::HTTPSuccess)
        body = res.body.to_s.dup.force_encoding('UTF-8').scrub
        matches = body.scan(/<li class="b_algo"[^>]*>.*?<h2><a[^>]*href="([^"]+)"[^>]*>(.*?)<\/a><\/h2>(?:.*?<p[^>]*>(.*?)<\/p>)?/im)
        matches.first(6).each_with_index do |(url, raw_title, raw_snippet), idx|
          title = raw_title.to_s.gsub(/<[^>]+>/, '').strip
          snippet = raw_snippet.to_s.gsub(/<[^>]+>/, '').strip
          domain = URI.parse(url).host rescue url
          results << {
            position: idx + 1,
            title: title,
            url: url,
            domain: domain,
            snippet: snippet[0..140]
          }
        end
      end
      results
    rescue StandardError
      []
    end

    def detect_ai_overview(query, intent)
      q = query.downcase
      triggers = []
      probability = 15

      if intent[:primary] == 'Informational'
        probability += 40
        triggers << 'Informational search intent'
      end

      if q =~ /^(what is|how to|why does|how do|what are|difference between|steps to|guide to)\b/i
        probability += 35
        triggers << 'Interrogative / procedural query prefix'
      elsif q.include?(' vs ') || q.include?(' versus ')
        probability += 30
        triggers << 'Direct comparative product/concept syntax'
      end

      if q.split(/\s+/).size >= 4
        probability += 10
        triggers << 'Long-tail semantic query depth'
      end

      probability = [probability, 95].min
      detected = probability >= 60

      {
        detected: detected,
        probability_pct: probability,
        triggers: triggers,
        displacement_pixels: detected ? 850 : 0,
        impact: detected ? 'Severe: Google Gemini AI Overview displaces Top 1 organic result below the viewport fold.' : 'Low: Traditional organic listings occupy top positions.',
        counter_strategy: 'Structure content with direct 40–50 word definition answer, bulleted takeaways, and FAQPage/Question JSON-LD markup.'
      }
    end

    def detect_featured_snippet(query, intent)
      q = query.downcase
      format = :none
      probability = 10
      target_recipe = ''

      if q =~ /^(how to|steps to|guide|tutorial|how do i)\b/i
        format = :ordered_list
        probability = 90
        target_recipe = 'Use an ordered list (<ol><li>) with 5–8 actionable sequential steps directly under an H2 heading.'
      elsif q.include?(' vs ') || q.include?('difference between') || q =~ /\b(pricing|cost|plans|tiers|specs)\b/i
        format = :table
        probability = 75
        target_recipe = 'Provide a structured HTML <table> with clear column headers (<th>) comparing key attributes and metrics.'
      elsif q =~ /\b(best|top|types of|examples of|list of)\b/i
        format = :unordered_list
        probability = 80
        target_recipe = 'Use an unordered bullet list (<ul><li>) highlighting 5–10 items with bold introductory headers.'
      elsif q =~ /^(what is|who is|definition of|meaning of|what does)\b/i || intent[:primary] == 'Informational'
        format = :paragraph
        probability = 85
        target_recipe = 'Place target query in <h2>, followed immediately by a concise 42–55 word direct definition answer block.'
      end

      {
        detected: format != :none,
        target_format: format.to_s,
        probability_pct: probability,
        optimal_length: format == :paragraph ? '40–60 words (~280–350 chars)' : '5–8 structured items',
        capture_prescription: target_recipe
      }
    end

    def detect_local_pack(query)
      q = query.downcase
      is_local = q =~ /\b(near me|in [a-z]+|city|store|repair|dentist|plumber|gym|shop|restaurant|agency|services|near)\b/i
      {
        detected: !!is_local,
        probability_pct: is_local ? 90 : 5,
        notes: is_local ? 'Triggers Google Maps 3-Pack; local organic listings appear below maps.' : 'No local intent detected.'
      }
    end

    def detect_video_carousel(query, live_serp)
      q = query.downcase
      has_video_kw = q =~ /\b(how to|tutorial|review|walkthrough|guide|setup|install|demo|video|diy|unboxing)\b/i
      serp_has_youtube = live_serp.any? { |r| r[:url].to_s.include?('youtube.com') }
      detected = !!(has_video_kw || serp_has_youtube)

      {
        detected: detected,
        probability_pct: detected ? 80 : 15,
        notes: detected ? 'Video carousel likely above or between organic results. YouTube videos dominate.' : 'Low video intent.'
      }
    end

    def detect_forum_discussions(query, live_serp)
      q = query.downcase
      has_forum_kw = q =~ /\b(reddit|quora|worth it|opinions|review|anyone tried|experiences|recommendations|issues)\b/i
      serp_has_forum = live_serp.any? { |r| r[:url].to_s =~ /(reddit\.com|quora\.com|community\.)/i }
      detected = !!(has_forum_kw || serp_has_forum)

      {
        detected: detected,
        probability_pct: detected ? 85 : 20,
        notes: detected ? 'Google "Discussions and Forums" module active. Authentic first-person experiences prioritized.' : 'Standard commercial/informational listings dominate.'
      }
    end

    def detect_shopping_pack(query, intent)
      q = query.downcase
      is_shopping = (intent[:primary] == 'Transactional') || (q =~ /\b(buy|price|cost|cheap|best|discount|sale|store|deals|shop|coupon)\b/i)
      {
        detected: !!is_shopping,
        probability_pct: is_shopping ? 85 : 10,
        notes: is_shopping ? 'Product grid / Google Shopping carousels occupy top above-the-fold position.' : 'Non-e-commerce SERP.'
      }
    end

    def detect_sitelinks(query, intent)
      is_brand = (intent[:primary] == 'Navigational') || (query.split(/\s+/).size <= 2 && query =~ /^[A-Z][a-zA-Z0-9]+$/)
      {
        detected: !!is_brand,
        probability_pct: is_brand ? 90 : 15,
        notes: is_brand ? 'Expanded 6-pack or 4-pack branded sitelinks trigger for primary domain.' : 'Standard single-line snippets.'
      }
    end

    def calculate_zero_click_risk(ai_overview:, featured_snippet:, paa_count:, local_pack:, shopping_pack:, video_carousel:)
      score = 10
      score += 35 if ai_overview[:detected]
      score += 25 if featured_snippet[:detected]
      score += 15 if paa_count >= 3
      score += 10 if local_pack[:detected]
      score += 10 if shopping_pack[:detected]
      score += 5  if video_carousel[:detected]

      score = [score, 100].min

      level = case score
              when 0..30   then 'LOW'
              when 31..55  then 'MODERATE'
              when 56..79  then 'HIGH'
              else              'SEVERE'
              end

      ctr_drop = case level
                 when 'LOW'      then '-5% to -10%'
                 when 'MODERATE' then '-15% to -25%'
                 when 'HIGH'     then '-30% to -45%'
                 when 'SEVERE'   then '-50% to -65%'
                 end

      {
        score: score,
        level: level,
        estimated_organic_ctr_suppression: ctr_drop,
        summary: "Zero-Click Threat is #{level} (#{score}/100). SERP features push standard organic rankings down."
      }
    end

    def generate_capture_playbook(query:, intent:, ai_overview:, featured_snippet:, paa_questions:)
      playbook = []

      if featured_snippet[:detected]
        playbook << {
          target: "Featured Snippet (#{featured_snippet[:target_format].capitalize})",
          action: featured_snippet[:capture_prescription],
          priority: 'P1 - High Impact'
        }
      end

      if ai_overview[:detected]
        playbook << {
          target: 'Google Gemini AI Overview Citation',
          action: 'Provide authoritative factual statistics with citability markers (author bio, published date, quantitative percentages).',
          priority: 'P1 - High Impact'
        }
      end

      if !paa_questions.empty?
        playbook << {
          target: 'People Also Ask (PAA) Inclusion',
          action: "Inject H3 headings answering top questions: \"#{paa_questions.first(3).join('", "')}\" using Schema.org FAQPage JSON-LD.",
          priority: 'P2 - Traffic Expansion'
        }
      end

      playbook << {
        target: 'Entity Disambiguation',
        action: 'Include sameAs Wikidata / Wikipedia references and Organization structured data to anchor topical authority.',
        priority: 'P3 - Topical Authority'
      }

      playbook
    end
  end
end

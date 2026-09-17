# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'zlib'
require 'stringio'

module GSC
  class GeoAuditor
    AI_BOTS = {
      'GPTBot'             => { provider: 'OpenAI (ChatGPT Search)', critical: true },
      'ClaudeBot'          => { provider: 'Anthropic (Claude AI)', critical: true },
      'PerplexityBot'      => { provider: 'Perplexity AI Search', critical: true },
      'Google-Extended'    => { provider: 'Google (Gemini & AI Overviews)', critical: true },
      'Applebot-Extended'  => { provider: 'Apple Intelligence', critical: false },
      'CCBot'              => { provider: 'Common Crawl (Open LLM Datasets)', critical: false }
    }.freeze

    QUESTION_HEADING_REGEX = /\b(what|why|how|can|does|is|are|which|best|vs|versus|difference|guide|review|pricing|steps|definition)\b/i

    attr_reader :url, :html, :http_status, :headers, :response_time_ms

    def initialize(url_or_domain)
      raw = url_or_domain.to_s.strip
      raw = "https://#{raw}" unless raw =~ %r{^https?://}
      @url = raw
      @uri = URI.parse(@url)
    end

    def audit
      fetch_page
      return { error: true, message: "HTTP #{@http_status} fetching #{@url}" } unless @http_status == 200 && !@html.empty?

      ai_crawler_status = audit_ai_crawlers
      answer_density    = audit_direct_answers
      fact_density      = audit_factual_citability
      entity_authority  = audit_entity_schema
      temporal_freshness = audit_freshness

      # Scoring (0-100)
      crawler_score = calculate_crawler_score(ai_crawler_status)
      answer_score  = calculate_answer_score(answer_density)
      fact_score    = calculate_fact_score(fact_density)
      entity_score  = calculate_entity_score(entity_authority)

      total_score = crawler_score + answer_score + fact_score + entity_score

      recommendations = generate_recommendations(
        ai_crawler_status,
        answer_density,
        fact_density,
        entity_authority,
        temporal_freshness
      )

      {
        url: @url,
        score: total_score,
        grade: score_grade(total_score),
        category_scores: {
          ai_bot_access: { score: crawler_score, max: 25 },
          direct_answers: { score: answer_score, max: 25 },
          facts_and_data: { score: fact_score, max: 25 },
          entity_schema: { score: entity_score, max: 25 }
        },
        ai_crawlers: ai_crawler_status,
        direct_answers: answer_density,
        facts_and_citability: fact_density,
        entity_knowledge_graph: entity_authority,
        freshness: temporal_freshness,
        recommendations: recommendations
      }
    end

    private

    def fetch_page
      start_t = Time.now
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == 'https')
      http.open_timeout = 8
      http.read_timeout = 15

      req = Net::HTTP::Get.new(@uri.request_uri.empty? ? '/' : @uri.request_uri)
      req['User-Agent'] = "Mozilla/5.0 (compatible; GSC-GEO-Auditor/#{GSC::VERSION}; +https://apolloswave.com)"
      req['Accept-Encoding'] = 'gzip'

      res = http.request(req)
      @response_time_ms = ((Time.now - start_t) * 1000).round(1)
      @http_status = res.code.to_i
      @headers = res.to_hash

      raw_body = res.body || ''
      body_str = if res['content-encoding'] =~ /gzip/i && !raw_body.empty?
                   begin
                     Zlib::GzipReader.new(StringIO.new(raw_body)).read
                   rescue StandardError
                     raw_body
                   end
                 else
                   raw_body
                 end
      @html = body_str.to_s.dup.force_encoding('UTF-8').scrub
    rescue StandardError => e
      @http_status = 0
      @html = ''
      @error_msg = e.message
    end

    def audit_ai_crawlers
      robots_url = "#{@uri.scheme}://#{@uri.host}:#{@uri.port}/robots.txt"
      robots_txt = ''
      begin
        res = Net::HTTP.get_response(URI.parse(robots_url))
        robots_txt = res.body.to_s.dup.force_encoding('UTF-8').scrub if res.code == '200'
      rescue StandardError
        robots_txt = ''
      end

      # Check robots meta in page
      robots_meta = @html[/<meta\s+[^>]*name=['"]robots['"][^>]*content=['"]([^'"]+)['"]/i, 1] || ''
      noindex = robots_meta =~ /noindex/i
      nosnippet = robots_meta =~ /nosnippet/i

      checker = RobotsChecker.new(@url)
      bot_results = {}

      AI_BOTS.each do |bot_name, meta|
        rule = checker.check(@uri.path, bot_name)
        allowed = rule[:allowed] && !noindex
        bot_results[bot_name] = {
          provider: meta[:provider],
          allowed: allowed,
          critical: meta[:critical],
          rule: rule[:matched_rule] ? "#{rule[:matched_rule][:type]}: #{rule[:matched_rule][:path]}" : 'Default (Allowed)'
        }
      end

      {
        robots_txt_found: !robots_txt.empty?,
        meta_noindex: !!noindex,
        meta_nosnippet: !!nosnippet,
        bots: bot_results,
        all_critical_allowed: bot_results.select { |_, v| v[:critical] }.all? { |_, v| v[:allowed] }
      }
    end

    def audit_direct_answers
      # Find headings that look like user questions
      headings = []
      @html.scan(/<(h[23])[^>]*>(.*?)<\/\1>/im) do |tag, text|
        clean = text.gsub(/<[^>]+>/, '').strip
        next if clean.empty?

        is_question = (clean =~ QUESTION_HEADING_REGEX) || clean.end_with?('?')
        headings << { tag: tag, text: clean, is_question: !!is_question }
      end

      # Analyze paragraphs following question headings
      answer_blocks = []
      headings.select { |h| h[:is_question] }.each do |h|
        pattern = /<#{h[:tag]}[^>]*>#{Regexp.escape(h[:text])}<\/#{h[:tag]}>\s*<p[^>]*>(.*?)<\/p>/im
        match = @html[pattern, 1]
        if match
          ans_text = match.gsub(/<[^>]+>/, '').strip
          words = ans_text.split(/\s+/).size
          # Ideal direct answer for LLM citation is 30-80 words
          optimal = words >= 30 && words <= 80
          answer_blocks << {
            question: h[:text],
            answer_preview: ans_text[0..120] + (ans_text.length > 120 ? '...' : ''),
            word_count: words,
            optimal_length: optimal
          }
        end
      end

      {
        total_question_headings: headings.count { |h| h[:is_question] },
        direct_answer_blocks_found: answer_blocks.size,
        optimal_answers_count: answer_blocks.count { |a| a[:optimal_length] },
        samples: answer_blocks.first(3)
      }
    end

    def audit_factual_citability
      clean = @html.gsub(/<script\b[^>]*>.*?<\/script>/im, ' ')
                   .gsub(/<style\b[^>]*>.*?<\/style>/im, ' ')

      # Count statistical data points
      percentages = clean.scan(/\b\d+(?:\.\d+)?%/).size
      currency_points = clean.scan(/(?:\$|€|£)\s*\d+(?:,\d{3})*(?:\.\d+)?/).size
      numbers = clean.scan(/\b\d+(?:,\d{3})+(?:\.\d+)?\b/).size
      recent_years = clean.scan(/\b(202[4-6])\b/).size

      # Count structured list items
      list_items = clean.scan(/<li\b[^>]*>(.*?)<\/li>/im).size

      # Count table rows
      table_rows = clean.scan(/<tr\b[^>]*>/im).size

      {
        percentage_mentions: percentages,
        currency_mentions: currency_points,
        large_numbers: numbers,
        recent_year_mentions: recent_years,
        bullet_list_items: list_items,
        comparison_table_rows: table_rows,
        high_fact_density: (percentages + currency_points + numbers >= 5) || (list_items >= 6)
      }
    end

    def audit_entity_schema
      schemas = []
      @html.scan(/<script\s+[^>]*type=['"]application\/ld\+json['"][^>]*>(.*?)<\/script>/im) do |m|
        content = m.first.to_s.strip
        begin
          parsed = JSON.parse(content)
          schemas.concat(parsed.is_a?(Array) ? parsed : [parsed])
        rescue StandardError
          nil
        end
      end

      types = schemas.map { |s| s['@type'] }.compact.flatten
      same_as = []
      author_info = nil
      brand_info = nil

      schemas.each do |s|
        same_as.concat(Array(s['sameAs'])) if s['sameAs']
        author_info ||= s['author'] if s['author']
        brand_info ||= (s['brand'] || s['name']) if %w[Organization Brand WebSite Product].include?(s['@type'])
      end

      same_as_domains = same_as.map do |link|
        begin
          URI.parse(link.to_s).host
        rescue StandardError
          link.to_s
        end
      end.compact.uniq

      has_wiki = same_as_domains.any? { |d| d =~ /wikipedia|wikidata/i }
      has_social_entity = same_as_domains.any? { |d| d =~ /linkedin|twitter|x\.com|youtube|github/i }

      {
        schema_count: schemas.size,
        schema_types: types.uniq,
        has_organization_or_brand: types.any? { |t| %w[Organization Brand WebSite].include?(t) },
        has_faq_or_howto: types.any? { |t| %w[FAQPage HowTo QAPage].include?(t) },
        has_article_schema: types.any? { |t| %w[Article NewsArticle BlogPosting TechArticle].include?(t) },
        has_author: !author_info.nil?,
        same_as_links_count: same_as.size,
        same_as_domains: same_as_domains,
        wikidata_or_wikipedia_linked: has_wiki,
        social_entity_linked: has_social_entity
      }
    end

    def audit_freshness
      published = @html[/<meta\s+[^>]*property=['"]article:published_time['"][^>]*content=['"]([^'"]+)['"]/i, 1] ||
                  @html[/<meta\s+[^>]*name=['"]pubdate['"][^>]*content=['"]([^'"]+)['"]/i, 1]
      modified  = @html[/<meta\s+[^>]*property=['"]article:modified_time['"][^>]*content=['"]([^'"]+)['"]/i, 1] ||
                  @html[/<meta\s+[^>]*name=['"]last-modified['"][^>]*content=['"]([^'"]+)['"]/i, 1]

      {
        published_date: published,
        modified_date: modified,
        has_dates: !published.nil? || !modified.nil?
      }
    end

    def calculate_crawler_score(ai_crawlers)
      score = 0
      critical_bots = ai_crawlers[:bots].select { |_, b| b[:critical] }
      allowed_count = critical_bots.count { |_, b| b[:allowed] }

      score += (allowed_count.to_f / [critical_bots.size, 1].max * 20).round
      score += 5 unless ai_crawlers[:meta_nosnippet] || ai_crawlers[:meta_noindex]
      score
    end

    def calculate_answer_score(answers)
      score = 0
      score += 8 if answers[:total_question_headings] >= 2
      score += 10 if answers[:direct_answer_blocks_found] >= 2
      score += 7 if answers[:optimal_answers_count] >= 1
      [score, 25].min
    end

    def calculate_fact_score(facts)
      score = 0
      score += 8 if (facts[:percentage_mentions] + facts[:currency_mentions] + facts[:large_numbers]) >= 3
      score += 9 if facts[:bullet_list_items] >= 5
      score += 5 if facts[:recent_year_mentions] >= 1
      score += 3 if facts[:comparison_table_rows] >= 2
      [score, 25].min
    end

    def calculate_entity_score(entity)
      score = 0
      score += 7 if entity[:has_organization_or_brand]
      score += 7 if entity[:has_faq_or_howto] || entity[:has_article_schema]
      score += 6 if entity[:same_as_links_count] >= 1
      score += 5 if entity[:wikidata_or_wikipedia_linked] || entity[:social_entity_linked]
      [score, 25].min
    end

    def score_grade(score)
      case score
      when 85..100 then 'A (Exceptional AI Search Citability)'
      when 70..84  then 'B (Good - Minor Entity & Direct Answer Gaps)'
      when 50..69  then 'C (Moderate - Missing Key AI Bot Access or Schema)'
      else              'D/F (Poor - High Risk of Being Ignored by LLMs)'
      end
    end

    def generate_recommendations(crawlers, answers, facts, entity, freshness)
      recs = []

      # AI Crawlers
      blocked = crawlers[:bots].select { |_, b| !b[:allowed] }
      if blocked.any?
        names = blocked.keys.join(', ')
        recs << "Unblock #{names} in /robots.txt to permit ChatGPT, Claude, and Perplexity from quoting this URL."
      end
      if crawlers[:meta_nosnippet]
        recs << "Remove 'nosnippet' directive from robots meta tag; LLMs require snippet extraction to cite your content."
      end

      # Direct Answers
      if answers[:direct_answer_blocks_found] == 0
        recs << "Add 2+ question headings (H2/H3 'What is...', 'How to...') followed immediately by a concise 40-60 word definition paragraph."
      elsif answers[:optimal_answers_count] == 0
        recs << "Tighten paragraph lengths following question headings to 40-70 words. Overly long prose reduces LLM snippet selection."
      end

      # Factual Citability
      if !facts[:high_fact_density]
        recs << "Inject concrete statistics (percentages, metrics, pricing) and bulleted key takeaways; LLMs favor citing verified data points over generic prose."
      end
      if facts[:bullet_list_items] < 4
        recs << "Add structured bulleted summaries (<ul>/<li>) beneath major section headers for easy machine extraction."
      end

      # Entity Schema
      if !entity[:has_organization_or_brand]
        recs << "Add JSON-LD 'Organization' or 'Brand' structured data with official entity name and logo."
      end
      if entity[:same_as_links_count] == 0
        recs << "Add 'sameAs' links inside your Organization JSON-LD pointing to Wikipedia, Wikidata, LinkedIn, or Twitter/X to disambiguate your brand in LLM Knowledge Graphs."
      end
      if !entity[:has_faq_or_howto]
        recs << "Implement FAQPage JSON-LD schema wrapping your common questions and answers."
      end

      # Freshness
      unless freshness[:has_dates]
        recs << "Include visible publication and modification dates (and 'datePublished'/'dateModified' in schema) to signal content freshness to AI answer engines."
      end

      recs
    end
  end
end

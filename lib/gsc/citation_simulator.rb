# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module GSC
  class CitationSimulator
    MODELS = %w[perplexity chatgpt claude aio].freeze
    DEFAULT_MODEL = 'perplexity'

    STOPWORDS = %w[
      a about above after again against all am an and any are aren't as at be because
      been before being below between both but by can't cannot could couldn't did didn't
      do does doesn't doing don't down during each few for from further had hadn't has
      hasn't have haven't having he he'd he'll he's her here here's hers herself him
      himself his how how's i i'd i'll i'm i've if in into is isn't it it's its itself
      let's me more most mustn't my myself no nor not of off on once only or other ought
      our ours ourselves out over own same shan't she she'd she'll she's should shouldn't
      so some such than that that's the their theirs them themselves then there there's
      these they they'd they'll they're they've this those through to too under until
      up very was wasn't we we'd we'll we're we've were weren't what what's when when's
      where where's which while who who's whom why why's with won't would wouldn't
      you you'd you'll you're you've your yours yourself yourselves
    ].freeze

    attr_reader :options, :model, :query

    def initialize(options = {})
      @options = options
      @model = (options[:model] || DEFAULT_MODEL).to_s.downcase
      @model = DEFAULT_MODEL unless MODELS.include?(@model)
      @query = options[:query]&.to_s&.strip
    end

    def self.simulate(html_or_url, query = nil, options = {})
      opts = options.merge(query: query || options[:query])
      new(opts).simulate(html_or_url)
    end

    def simulate(target)
      url, html, http_status = load_content(target)
      inferred_query = @query.to_s.empty? ? infer_query_from_html(html) : @query

      chunks = extract_content_chunks(html)
      scored_chunks = score_chunks(chunks, inferred_query)

      best_chunk = scored_chunks.first || default_chunk(inferred_query)
      extracted_quotes = extract_verifiable_quotes(best_chunk, inferred_query)

      cls_score = compute_citation_likelihood(best_chunk, chunks, html, inferred_query)
      grade = compute_grade(cls_score)

      emulated_answer = synthesize_emulated_answer(best_chunk, inferred_query, extracted_quotes, url)
      prescriptions = generate_prescriptions(best_chunk, cls_score, html)

      {
        url: url,
        http_status: http_status,
        target_query: inferred_query,
        model_profile: @model,
        citation_likelihood_score: cls_score,
        grade: grade,
        status: cls_score >= 70 ? 'HIGH CITABILITY' : (cls_score >= 45 ? 'MODERATE CITABILITY' : 'LOW CITABILITY'),
        emulated_ai_response: emulated_answer,
        extracted_quotes: extracted_quotes,
        top_cited_chunk: {
          heading: best_chunk[:heading],
          text: best_chunk[:text],
          word_count: best_chunk[:word_count],
          facts_count: best_chunk[:facts_count],
          fact_density: best_chunk[:fact_density],
          relevance_score: best_chunk[:relevance_score]
        },
        signals: {
          total_chunks_analyzed: chunks.size,
          facts_detected: best_chunk[:facts_count],
          has_schema: html.include?('application/ld+json'),
          has_author: html.match?(/author|written by|byline/i),
          has_published_date: html.match?(/\d{4}-\d{2}-\d{2}|published|updated/i),
          has_comparative_table: html.include?('<table')
        },
        prescriptions: prescriptions
      }
    end

    private

    def load_content(target)
      target_str = target.to_s.strip
      if target_str.match?(%r{^https?://})
        uri = URI.parse(target_str)
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
        req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 10) do |http|
          http.request(req)
        end
        [target_str, res.body.to_s.dup.force_encoding('UTF-8').scrub, res.code.to_i]
      elsif File.exist?(target_str)
        [target_str, File.read(target_str, encoding: 'UTF-8'), 200]
      else
        # Raw HTML or string passed directly
        [target_str.start_with?('http') ? target_str : 'local-document', target_str, 200]
      end
    rescue StandardError => e
      [target_str.to_s, "<html><body><h1>Error loading content: #{e.message}</h1></body></html>", 0]
    end

    def infer_query_from_html(html)
      h1_match = (html =~ %r{<h1[^>]*>(.*?)</h1>}i) ? clean_text($1) : ''
      return h1_match unless h1_match.empty?

      if html =~ %r{<title[^>]*>(.*?)</title>}i
        title_part = (clean_text($1).split(/[|\-–]/).first || '').strip
        return title_part unless title_part.empty?
      end

      'core product benefits and comparison'
    end

    def extract_content_chunks(html)
      # Strip non-content blocks
      cleaned = html.gsub(%r{<(script|style|nav|footer|header|aside|svg|noscript)[^>]*>.*?</\1>}im, ' ')
      cleaned = cleaned.gsub(/<!--.*?-->/m, ' ')

      chunks = []
      current_heading = 'Main Content'

      # Match sections, headings, paragraphs, and list blocks
      cleaned.scan(%r{<(h[1-4]|p|li|blockquote|table)[^>]*>(.*?)</\1>}im) do |tag, content|
        raw_text = clean_text(content)
        next if raw_text.length < 25

        if tag.start_with?('h')
          current_heading = raw_text
        else
          words = raw_text.split(/\s+/)
          next if words.size < 6

          facts_count = count_facts(raw_text)
          fact_density = (facts_count.to_f / words.size * 100.0).round(1)

          chunks << {
            tag: tag,
            heading: current_heading,
            text: raw_text,
            word_count: words.size,
            facts_count: facts_count,
            fact_density: fact_density,
            relevance_score: 0.0
          }
        end
      end

      chunks.empty? ? [default_chunk('general content')] : chunks
    end

    def score_chunks(chunks, query_str)
      query_tokens = tokenize(query_str)
      return chunks if query_tokens.empty?

      chunks.each do |chunk|
        chunk_tokens = tokenize("#{chunk[:heading]} #{chunk[:text]}")
        overlap = query_tokens & chunk_tokens

        # Base token match ratio
        base_score = (overlap.size.to_f / [query_tokens.size, 1].max) * 40.0

        # Exact phrase bonus
        exact_bonus = chunk[:text].downcase.include?(query_str.downcase) ? 25.0 : 0.0

        # Fact density bonus (up to 20 points)
        fact_bonus = [chunk[:fact_density] * 2.0, 20.0].min

        # Optimal word count sweet spot (40-80 words)
        length_score = case chunk[:word_count]
                       when 40..80 then 15.0
                       when 25..39, 81..120 then 10.0
                       when 15..24, 121..180 then 5.0
                       else 2.0
                       end

        # Model specific bias
        model_bias = case @model
                     when 'perplexity' then chunk[:tag] == 'table' || chunk[:facts_count] >= 2 ? 10.0 : 0.0
                     when 'chatgpt' then chunk[:heading].match?(/how|steps|guide/i) ? 8.0 : 0.0
                     when 'claude' then chunk[:text].include?('because') || chunk[:text].include?('defined as') ? 8.0 : 0.0
                     when 'aio' then chunk[:word_count].between?(45, 65) ? 10.0 : 0.0
                     else 0.0
                     end

        chunk[:relevance_score] = (base_score + exact_bonus + fact_bonus + length_score + model_bias).round(1)
      end

      chunks.sort_by { |c| -c[:relevance_score] }
    end

    def extract_verifiable_quotes(chunk, query_str)
      sentences = chunk[:text].split(/(?<=[.!?])\s+/).map(&:strip).reject(&:empty?)
      query_tokens = tokenize(query_str)

      scored_sentences = sentences.map do |sent|
        s_tokens = tokenize(sent)
        overlap = query_tokens & s_tokens
        facts = count_facts(sent)
        score = (overlap.size * 3) + (facts * 4) + (sent.length.between?(50, 160) ? 5 : 0)
        { text: sent, score: score, facts: facts }
      end

      top = scored_sentences.sort_by { |s| -s[:score] }.first(2)
      top.map { |s| s[:text] }
    end

    def compute_citation_likelihood(best_chunk, all_chunks, html, query_str)
      score = 0.0

      # 1. Best chunk relevance (max 35)
      score += [best_chunk[:relevance_score] * 0.45, 35.0].min

      # 2. Fact and statistical density (max 25)
      fact_pts = [best_chunk[:facts_count] * 6.0, 25.0].min
      score += fact_pts

      # 3. Structural Clarity (max 15)
      score += 5.0 if best_chunk[:heading] && best_chunk[:heading] != 'Main Content'
      score += 5.0 if html.include?('<table') || html.include?('<ul>') || html.include?('<ol>')
      score += 5.0 if html.include?('application/ld+json')

      # 4. E-E-A-T & Trust verification markers (max 15)
      score += 5.0 if html.match?(/author|written by|reviewed by/i)
      score += 5.0 if html.match?(/\d{4}-\d{2}-\d{2}|published|updated/i)
      score += 5.0 if html.match?(/sources|references|citations|study|data/i)

      # 5. Length & Conciseness suitability (max 10)
      if best_chunk[:word_count].between?(35, 85)
        score += 10.0
      elsif best_chunk[:word_count].between?(20, 120)
        score += 5.0
      end

      # Evasive / AI fluff penalty (-10)
      if best_chunk[:text].match?(/in today's (fast-paced|digital) world|it is important to remember|as mentioned earlier/i)
        score -= 10.0
      end

      [[score.round(1), 100.0].min, 5.0].max
    end

    def synthesize_emulated_answer(best_chunk, query_str, quotes, url)
      quote_str = quotes.first || best_chunk[:text]
      host = (URI.parse(url).host rescue nil) || (url.start_with?('http') ? url : 'document')

      case @model
      when 'perplexity'
        "Based on #{host}, #{quote_str} [1]\n\n[1] #{url} — \"#{quote_str}\""
      when 'chatgpt'
        "According to #{host}'s documentation, #{quote_str}.\n\nSource: #{url}"
      when 'claude'
        "#{quote_str}\n\nKey citation verified from #{host} (#{url})."
      when 'aio'
        "Here is what you need to know: #{quote_str}\n\n(Cited from #{url})"
      end
    end

    def generate_prescriptions(best_chunk, score, html)
      steps = []

      if best_chunk[:facts_count] < 2
        steps << "Embed at least 2 explicit numerical metrics, percentages, or benchmark statistics in the lead sentence."
      end

      if !best_chunk[:word_count].between?(40, 75)
        steps << "Refactor the core answer block to 45–65 words. Currently at #{best_chunk[:word_count]} words (LLMs heavily favor concise 50w propositions)."
      end

      unless html.include?('application/ld+json')
        steps << "Add Schema.org JSON-LD (FAQPage, Article, or TechArticle) to provide machine-readable ground truth."
      end

      unless html.match?(/author|written by|reviewed by/i)
        steps << "Add an explicit author byline with credentials (E-E-A-T trust signals are heavily weighted by RAG retrievers)."
      end

      unless html.include?('<table')
        steps << "Convert comparison points into an HTML <table>. Perplexity and AI Overviews preferentially cite tabular data."
      end

      steps << "Format the section header as a direct question matching user search intent (e.g. 'How does X work?')." if steps.size < 3
      steps
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

    def count_facts(text)
      count = 0
      # Percentages and currencies ($199, 45%, 3.5x, €50, £10)
      count += text.scan(/\b(?:\$|€|£)\d+(?:\.\d+)?|\b\d+(?:\.\d+)?%|\b\d+(?:\.\d+)?x\b/i).size
      # Numerical values > 1900 or decimals or speeds (e.g. 250ms, 4.2s, 10,000, 2026)
      count += text.scan(/\b\d{1,3}(?:,\d{3})+\b|\b\d+(?:\.\d+)?(?:ms|s|gb|mb|kb|km|mph|users|hours|days)\b/i).size
      # Proper technical capitalized words / acronyms (e.g. HTTP/2, REST, API, JSON-LD, LCP, CLS)
      count += text.scan(/\b[A-Z]{2,6}\b/).size
      count
    end

    def tokenize(str)
      str.to_s.downcase.gsub(/[^a-z0-9\s]/, ' ').split(/\s+/).reject do |t|
        t.empty? || STOPWORDS.include?(t)
      end.uniq
    end

    def clean_text(html_str)
      html_str.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip
    end

    def default_chunk(query_str)
      {
        tag: 'p',
        heading: 'Overview',
        text: "Direct authoritative summary answering #{query_str}.",
        word_count: 7,
        facts_count: 1,
        fact_density: 14.3,
        relevance_score: 50.0
      }
    end
  end
end

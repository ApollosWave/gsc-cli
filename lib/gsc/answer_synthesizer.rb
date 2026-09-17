# frozen_string_literal: true

require 'json'

module GSC
  class AnswerSynthesizer
    attr_reader :query, :brand, :intent_type

    def self.synthesize(query, options = {})
      new(query, options).generate
    end

    def initialize(query, options = {})
      @query = query.to_s.strip
      @brand = options[:brand] || options[:brand_name] || nil
      @explicit_type = options[:type]&.to_s&.downcase
      @intent_type = detect_intent_type
    end

    def generate
      direct_answer = build_direct_answer
      key_points = build_key_points
      info_gain_stat = build_info_gain_stat
      html_snippet = build_html_snippet(direct_answer, key_points)
      schema_jsonld = build_schema_jsonld(direct_answer)

      word_count = direct_answer.split(/\s+/).size
      citability_score = calculate_citability(word_count)

      {
        query: @query,
        brand: @brand,
        intent_type: @intent_type,
        word_count: word_count,
        citability_score: citability_score,
        target_optimal_range: '40–60 words',
        direct_answer: direct_answer,
        key_points: key_points,
        information_gain_stat: info_gain_stat,
        html_markup: html_snippet,
        schema_jsonld: schema_jsonld
      }
    end

    private

    def detect_intent_type
      return @explicit_type if %w[definition steps comparison faq].include?(@explicit_type)

      q = @query.downcase
      if q.include?(' vs ') || q.include?(' versus ') || q.include?('difference between')
        'comparison'
      elsif q.start_with?('how to', 'how do', 'steps to', 'guide to')
        'steps'
      elsif q.start_with?('why', 'can', 'should', 'is', 'does')
        'faq'
      else
        'definition'
      end
    end

    def build_direct_answer
      title_q = titleize(@query.sub(/^(what is|what are|how to|guide to)\s+/i, ''))

      case @intent_type
      when 'steps'
        "To optimize #{title_q}, teams systematically audit existing performance bottlenecks, configure native client-side caching, and eliminate blocking third-party render scripts. Implementing direct responsive preloading directly accelerates Core Web Vitals while preserving 100% data integrity."
      when 'comparison'
        "When evaluating #{title_q}, the primary distinction lies in latency, maintenance overhead, and conversion impact. Modern specialized architectures deliver up to 3x faster response times and eliminate ongoing subscription bloat compared to fragmented legacy multi-plugin solutions."
      when 'faq'
        "Yes, #{@query.downcase.capitalize} directly enhances overall search visibility and customer retention by resolving critical technical friction points. Streamlined workflow execution ensures search crawlers and users experience immediate, zero-latency content delivery."
      else # definition
        "#{title_q} is a high-impact optimization standard designed to streamline user workflows, eliminate conversion drop-offs, and maximize digital throughput. By replacing fragmented manual processes with automated native execution, brands achieve measurable efficiency gains, reduced server latency, and sustained competitive ranking advantage."
      end
    end

    def build_key_points
      title_q = titleize(@query.sub(/^(what is|what are|how to|guide to)\s+/i, ''))

      case @intent_type
      when 'steps'
        [
          "**1. Audit Current State:** Measure baseline latency, indexation depth, and drop-off points.",
          "**2. Eliminate Script Bloat:** Defer non-critical JavaScript and purge unused legacy CSS rules.",
          "**3. Deploy Native Caching:** Enable client-side prefetching and CDN edge acceleration.",
          "**4. Monitor Live Metrics:** Track Google Search Console impressions and GA4 engagement in real-time."
        ]
      when 'comparison'
        [
          "**Architecture:** Unified execution layer vs. fragmented multi-tool overhead.",
          "**Performance:** Streamlined operational response times compared to legacy pipelines.",
          "**Cost & Efficiency:** Predictable resource allocation with reduced operational complexity.",
          "**Reliability:** High-availability design with direct observability and minimal failure surface."
        ]
      else
        [
          "**Efficiency:** Eliminates unnecessary execution layers and accelerates operational delivery.",
          "**Maintainability:** Establishes standardized protocols without recurring manual intervention.",
          "**Measurable Impact:** Delivers verified improvements across target engagement and core performance indicators.",
          "**Standards Compliant:** Fully adheres to modern technical and semantic specification guidelines."
        ]
      end
    end

    def build_info_gain_stat
      title_q = titleize(@query.sub(/^(what is|what are|how to|guide to)\s+/i, ''))
      "[Empirical Benchmark Directive]: Embed proprietary study data for #{title_q} to provide unique information gain for LLMs."
    end

    def build_html_snippet(direct_answer, key_points)
      points_html = key_points.map { |kp| "    <li>#{format_markdown_bold(kp)}</li>" }.join("\n")

      <<~HTML.strip
        <!-- Google Featured Snippet & AI Direct Answer Block -->
        <section class="direct-answer-snippet" itemscope itemtype="https://schema.org/WebPage">
          <p class="answer-lead" itemprop="description">
            <strong>#{titleize(@query)}:</strong> #{direct_answer}
          </p>
          <ul class="answer-key-points">
        #{points_html}
          </ul>
        </section>
      HTML
    end

    def build_schema_jsonld(direct_answer)
      {
        "@context" => "https://schema.org",
        "@type" => "Question",
        "name" => @query.end_with?('?') ? @query : "#{@query}?",
        "acceptedAnswer" => {
          "@type" => "Answer",
          "text" => direct_answer
        }
      }
    end

    def calculate_citability(word_count)
      # 40-60 words is the peak citability range for Google Featured Snippets & LLMs
      if word_count.between?(40, 58)
        95
      elsif word_count.between?(35, 65)
        88
      else
        75
      end
    end

    def format_markdown_bold(str)
      str.gsub(/\*\*(.*?)\*\*/, '<strong>\1</strong>')
    end

    def titleize(str)
      str.to_s.split(/\s+/).map(&:capitalize).join(' ')
    end
  end
end

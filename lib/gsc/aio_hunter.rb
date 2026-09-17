# encoding: utf-8
# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'json'
require 'time'
require_relative 'serp_feature_detector'
require_relative 'answer_synthesizer'
require_relative 'google_suggest'

module GSC
  class AioHunter
    attr_reader :target, :options, :api, :site_url

    def initialize(target = nil, options = {}, api = nil, site_url = nil)
      @target = target.to_s.dup.force_encoding('UTF-8').scrub.strip
      @options = options || {}
      @api = api
      @site_url = site_url
    end

    def self.analyze(target = nil, options = {}, api = nil, site_url = nil)
      new(target, options, api, site_url).analyze
    end

    def analyze
      if single_query_mode?
        analyze_query(@target)
      else
        analyze_portfolio
      end
    end

    private

    def single_query_mode?
      return false if @target.empty?
      return false if @target =~ /\.(com|org|net|io|app|co|dev|store)$/i
      return false if @target =~ %r{^https?://}i
      true
    end

    def analyze_query(query)
      intent = classify_intent(query)
      trigger_prob = calculate_aio_probability(query, intent)
      ctr_suppression = calculate_ctr_suppression(trigger_prob)

      # Check target domain ranking & citation eligibility from GSC if available
      user_domain = extract_clean_domain(@options[:domain] || @site_url || '')
      ranking_data = fetch_query_ranking(query, user_domain)

      domain_ranked = !ranking_data.nil?
      domain_pos = domain_ranked ? ranking_data[:position] : nil
      domain_top3 = domain_ranked && domain_pos <= 3.0

      citation_gap = user_domain.empty? ? 0 : (domain_top3 ? 0 : [100, (trigger_prob * 1.1).round].min)
      capture_recipe = synthesize_capture_recipe(query, intent)

      {
        mode: :query,
        query: query,
        target_domain: user_domain.empty? ? nil : user_domain,
        timestamp: Time.now.utc.iso8601,
        intent: intent,
        aio_presence: {
          detected: trigger_prob >= 50,
          probability_percent: trigger_prob,
          status: aio_status_badge(trigger_prob),
          ctr_suppression_estimate: "#{ctr_suppression}%"
        },
        citation_analysis: {
          domain_evaluated: !user_domain.empty?,
          domain_ranked: domain_ranked,
          ranking_position: domain_pos,
          top_3_prime_candidate: domain_top3,
          citation_gap_index: citation_gap,
          eligibility_status: domain_top3 ? "HIGH ELIGIBILITY (Ranks Pos #{domain_pos})" : (domain_ranked ? "STRIKING DISTANCE (Pos #{domain_pos})" : "UNRANKED / UNVERIFIED")
        },
        opportunity_score: calculate_opportunity_score(trigger_prob, domain_top3, ranking_data ? ranking_data[:impressions] : nil),
        capture_recipe: capture_recipe
      }
    end

    def analyze_portfolio
      queries = fetch_gsc_queries

      domain = extract_clean_domain(@target.empty? ? (@options[:domain] || @site_url || 'portfolio') : @target)

      limit = (@options[:limit] || 25).to_i
      min_imp = (@options[:min_imp] || 10).to_i

      filtered = queries.select { |q| q[:impressions].to_i >= min_imp }

      analyzed_items = filtered.map do |row|
        q = row[:query]
        intent = classify_intent(q)
        prob = calculate_aio_probability(q, intent)
        suppression = calculate_ctr_suppression(prob)
        pos = row[:position].to_f.round(1)
        top3 = pos <= 3.0
        opp_score = calculate_opportunity_score(prob, top3, row[:impressions].to_i)

        {
          query: q,
          clicks: row[:clicks].to_i,
          impressions: row[:impressions].to_i,
          position: pos,
          ctr: (row[:ctr].to_f * 100.0).round(2),
          intent: intent,
          aio_probability: prob,
          ctr_suppression: suppression,
          top_3_prime: top3,
          opportunity_score: opp_score,
          recipe_summary: synthesize_short_recipe(intent)
        }
      end

      analyzed_items.sort_by! { |item| -item[:opportunity_score] }
      top_items = analyzed_items.first(limit)

      total_queries = analyzed_items.size
      aio_triggering = analyzed_items.count { |i| i[:aio_probability] >= 50 }
      currently_cited = analyzed_items.count { |i| i[:top_3_prime] && i[:aio_probability] >= 50 }
      high_threat_queries = analyzed_items.count { |i| !i[:top_3_prime] && i[:aio_probability] >= 60 }

      {
        mode: :portfolio,
        domain: domain,
        total_queries_audited: total_queries,
        summary: {
          total_monitored_queries: total_queries,
          aio_triggering_queries: aio_triggering,
          aio_penetration_rate: total_queries.zero? ? 0.0 : ((aio_triggering.to_f / total_queries) * 100.0).round(1),
          currently_cited_count: currently_cited,
          high_threat_uncited_count: high_threat_queries,
          portfolio_aio_vulnerability_index: total_queries.zero? ? 0.0 : ((high_threat_queries.to_f / total_queries) * 100.0).round(1)
        },
        opportunities: top_items
      }
    end

    def fetch_query_ranking(query, domain)
      return nil unless @api && !domain.empty?

      begin
        days = (@options[:days] || 28).to_i
        end_date = (Date.today - 2).strftime('%Y-%m-%d')
        start_date = (Date.today - 2 - days).strftime('%Y-%m-%d')
        property = @site_url || "sc-domain:#{domain}"
        res = @api.query_search_analytics(property, start_date: start_date, end_date: end_date, dimensions: %w[query])
        rows = res['rows'] || []
        match = rows.find { |r| r['keys'][0].to_s.downcase == query.downcase }
        if match
          {
            clicks: match['clicks'] || 0,
            impressions: match['impressions'] || 0,
            position: (match['position'] || 0).round(1)
          }
        end
      rescue StandardError
        nil
      end
    end

    def fetch_gsc_queries
      if @api && @site_url
        begin
          days = (@options[:days] || 30).to_i
          res = @api.query_search_analytics(
            @site_url,
            start_date: (Date.today - days).strftime('%Y-%m-%d'),
            end_date: Date.today.strftime('%Y-%m-%d'),
            dimensions: ['query'],
            row_limit: 100
          )
          if res && res['rows']
            return res['rows'].map do |r|
              {
                query: r['keys'].first.to_s,
                clicks: r['clicks'] || 0,
                impressions: r['impressions'] || 0,
                ctr: r['ctr'] || 0.0,
                position: r['position'] || 0.0
              }
            end
          end
        rescue StandardError
          # GSC query failed
        end
      end

      []
    end

    def calculate_aio_probability(query, intent)
      score = 20 # Baseline

      case intent
      when :informational_how_to
        score += 65 # High Gemini AIO trigger rate
      when :informational_definition
        score += 60
      when :commercial_comparison
        score += 50
      when :commercial_best
        score += 45
      when :navigational
        score -= 15
      when :transactional
        score -= 10
      end

      # Interrogative keywords check
      if query =~ /\b(how|what|why|when|where|who|can|should|does|which)\b/i
        score += 15
      end

      # Length bonus: complex conversational queries trigger AIO far more often
      words_count = query.split.size
      score += 10 if words_count >= 5

      [[score, 98].min, 5].max
    end

    def calculate_ctr_suppression(prob)
      if prob >= 80
        45 # 45% click suppression
      elsif prob >= 60
        35
      elsif prob >= 40
        20
      else
        5
      end
    end

    def classify_intent(query)
      q = query.downcase
      if q =~ /\b(how to|steps|fix|guide|tutorial|setup)\b/i
        :informational_how_to
      elsif q =~ /\b(what is|what are|definition|meaning|explained)\b/i
        :informational_definition
      elsif q =~ /\b(vs|versus|difference between|compared to|comparison)\b/i
        :commercial_comparison
      elsif q =~ /\b(best|top|review|reviews|alternatives)\b/i
        :commercial_best
      elsif q =~ /\b(buy|cheap|discount|coupon|download|order)\b/i
        :transactional
      else
        :navigational
      end
    end

    def calculate_opportunity_score(prob, cited, imp = nil)
      # High AIO presence + high impressions + currently not cited = highest opportunity score
      base = prob * 0.6
      vol_factor = imp ? [40.0, Math.log10([imp.to_i, 10].max) * 10.0].min : 30.0
      uncited_multiplier = cited ? 0.4 : 1.0

      [100, ((base + vol_factor) * uncited_multiplier).round].min
    end

    def synthesize_capture_recipe(query, intent)
      case intent
      when :informational_how_to
        {
          strategy: "Direct Ordered List & Steps Schema",
          direct_answer_draft: "To #{query.sub(/^how to /i, '')}, follow these 4 steps: (1) Audit current baseline performance, (2) Apply targeted responsive optimizations, (3) Inline critical assets, and (4) Verify with real-user Core Web Vitals telemetry.",
          recommended_schema: "HowTo (with step.itemListElement)",
          recommended_heading: "How to #{query.sub(/^how to /i, '').capitalize} (4-Step Technical Protocol)",
          content_elements: [
            "Immediate 35-50 word direct answer paragraph above fold",
            "Numbered ordered list (<ol>) with clear actionable bold prefixes",
            "Step-by-step HowTo JSON-LD schema markup"
          ]
        }
      when :informational_definition
        subject = query.sub(/^what is (a |an )?/i, '').strip
        {
          strategy: "Authoritative Definitional Snippet",
          direct_answer_draft: "#{subject.capitalize} refers to a core methodology and operational framework designed to deliver measurable performance improvements, structural efficiency, and verified outcome reliability.",
          recommended_schema: "DefinedTerm / Article / FAQPage",
          recommended_heading: "What is #{subject.capitalize}? Definition & Architecture",
          content_elements: [
            "Exact is-a definitional statement in first sentence (<45 words)",
            "One verifiable numeric statistic or performance benchmark",
            "itemprop='description' or Schema.org Answer markup"
          ]
        }
      when :commercial_comparison
        {
          strategy: "Direct Markdown Comparison Matrix",
          direct_answer_draft: "When evaluating #{query}, key trade-offs center on operational speed, architectural flexibility, and long-term maintenance overhead across competing alternatives.",
          recommended_schema: "Table / Comparison Article Schema",
          recommended_heading: "#{query.capitalize}: Feature & Performance Comparison",
          content_elements: [
            "Clear side-by-side comparison table (HTML <table> or GFM)",
            "Summary paragraph stating winner for specific use cases",
            "Bullet list highlighting pros & cons per option"
          ]
        }
      else
        {
          strategy: "FAQPage Structured Question & Direct Quote",
          direct_answer_draft: "#{query.capitalize} delivers essential workflow automation for digital teams, maximizing ROI through unified analytics and instant developer CLI operations.",
          recommended_schema: "FAQPage / SoftwareApplication",
          recommended_heading: "Understanding #{query.capitalize}",
          content_elements: [
            "High-contrast bulleted takeaways",
            "Schema.org FAQPage block targeting exact query syntax",
            "Verified author credentials (E-E-A-T) citation badge"
          ]
        }
      end
    end

    def synthesize_short_recipe(intent)
      case intent
      when :informational_how_to    then "Inject 4-step ordered list + HowTo schema"
      when :informational_definition then "Add 40-word definitional snippet above fold"
      when :commercial_comparison    then "Add side-by-side comparison table"
      when :commercial_best          then "Add structured pros/cons list & rating schema"
      else                                "Add FAQPage Q&A block"
      end
    end

    def aio_status_badge(prob)
      if prob >= 75
        "🚨 HIGH PROBABILITY (Active AIO SERP)"
      elsif prob >= 50
        "⚠️ MODERATE PROBABILITY (Likely AIO)"
      else
        "✅ LOW PROBABILITY (Traditional Organic SERP)"
      end
    end

    def extract_clean_domain(url_or_domain)
      d = url_or_domain.to_s.sub(%r{^https?://}i, '').sub(%r{/.*$}, '').strip
      d.sub(%r{^www\.}i, '')
    end
  end
end

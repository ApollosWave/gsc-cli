# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'date'

module GSC
  class IntentShift
    TRANSACTIONAL_MODIFIERS = %w[
      buy order purchase discount coupon price pricing cost cheap deal shop store subscription checkout hire
    ].freeze

    COMMERCIAL_MODIFIERS = %w[
      best top review reviews vs versus compare comparison alternative alternatives recommended software tool platform
    ].freeze

    INFORMATIONAL_MODIFIERS = %w[
      how what why when where who guide tutorial tips steps learn ideas strategy example examples template explain
    ].freeze

    NAVIGATIONAL_MODIFIERS = %w[
      login log-in signin sign-in portal account dashboard support helpdesk download
    ].freeze

    attr_reader :options, :api, :domain

    def initialize(options = {}, api = nil, domain = nil)
      @options = options
      @api = api
      @domain = domain.to_s.strip
    end

    def self.analyze(options = {}, api = nil, domain = nil)
      new(options, api, domain).analyze
    end

    def analyze
      rows = collect_rows
      shifts = detect_intent_shifts(rows)
      summarize_portfolio(shifts)
    end

    def self.classify_query(query, brand = nil)
      q = query.to_s.downcase.strip

      if brand && !brand.empty? && q.include?(brand.downcase)
        return :navigational if NAVIGATIONAL_MODIFIERS.any? { |m| q.include?(m) }
      end

      return :navigational if NAVIGATIONAL_MODIFIERS.any? { |m| q.match?(/\b#{Regexp.escape(m)}\b/) }
      return :transactional if TRANSACTIONAL_MODIFIERS.any? { |m| q.match?(/\b#{Regexp.escape(m)}\b/) }
      return :commercial if COMMERCIAL_MODIFIERS.any? { |m| q.match?(/\b#{Regexp.escape(m)}\b/) }
      return :informational if INFORMATIONAL_MODIFIERS.any? { |m| q.match?(/\b#{Regexp.escape(m)}\b/) }

      :informational
    end

    def self.classify_page(url)
      u = url.to_s.downcase
      if u =~ %r{/(?:cart|checkout|pricing|buy|products?|shop|store|orders?)(?:/|$|\?|#)}
        :transactional
      elsif u =~ %r{/(?:blog|guides?|tutorials?|learn|how-to|articles?|docs|knowledge-base)(?:/|$|\?|#)}
        :informational
      elsif u =~ %r{/(?:comparison|compare|vs|alternatives?|best|reviews?)(?:/|$|\?|#)}
        :commercial
      elsif u =~ %r{/(?:login|portal|accounts?|dashboard|signin)(?:/|$|\?|#)}
        :navigational
      else
        :hybrid
      end
    end

    private

    def collect_rows
      if @api
        begin
          days = (@options[:days] || 28).to_i
          end_date = (Date.today - 2).strftime('%Y-%m-%d')
          start_date = (Date.today - 2 - days).strftime('%Y-%m-%d')
          res = @api.search_analytics(@domain, start_date: start_date, end_date: end_date, dimensions: %w[query page])
          raw_rows = res['rows'] || []
          if raw_rows.any?
            return raw_rows.map do |r|
              {
                query: r['keys'][0],
                page: r['keys'][1],
                clicks: r['clicks'] || 0,
                impressions: r['impressions'] || 0,
                ctr: ((r['ctr'] || 0) * 100.0).round(2),
                position: (r['position'] || 0).round(1)
              }
            end
          end
        rescue StandardError
          # GSC query failed
        end
      end

      []
    end

    def detect_intent_shifts(rows)
      brand = @options[:brand] || @domain.split('.').first

      shifts = []

      rows.each do |row|
        q_intent = self.class.classify_query(row[:query], brand)
        p_intent = self.class.classify_page(row[:page])

        mismatch = false
        risk_level = :none
        diagnosis = nil
        prescription = nil

        # Scenario 1: Informational/Commercial query ranking on a purely Transactional page
        if (q_intent == :informational || q_intent == :commercial) && p_intent == :transactional
          mismatch = true
          risk_level = row[:position] > 10.0 ? :high : :medium
          diagnosis = "Google expects #{q_intent.to_s.upcase} research content, but ranking URL is a TRANSACTIONAL #{File.basename(row[:page])} page."
          prescription = "Publish a dedicated #{q_intent} guide/comparison landing page to capture Top 3 SERP intent instead of sending users to checkout/product page."

        # Scenario 2: Transactional query ranking on an Informational blog post
        elsif q_intent == :transactional && p_intent == :informational
          mismatch = true
          risk_level = :medium
          diagnosis = "Users have HIGH BUYING INTENT (#{row[:query]}), but are landing on an INFORMATIONAL blog article."
          prescription = "Embed prominent 1-click checkout widgets, pricing tables, and product CTAs directly above the fold in this blog post."

        # Scenario 3: Commercial comparison query landing on generic pricing page
        elsif q_intent == :commercial && p_intent == :hybrid
          mismatch = true
          risk_level = :low
          diagnosis = "Comparison query landing on generic page."
          prescription = "Deploy a structured vs/comparison matrix table."
        end

        shifts << {
          query: row[:query],
          page: row[:page],
          clicks: row[:clicks],
          impressions: row[:impressions],
          position: row[:position],
          ctr: row[:ctr],
          query_intent: q_intent,
          page_intent: p_intent,
          has_mismatch: mismatch,
          risk_level: risk_level,
          diagnosis: diagnosis,
          prescription: prescription
        }
      end

      shifts
    end

    def summarize_portfolio(shifts)
      total = shifts.size
      mismatched = shifts.select { |s| s[:has_mismatch] }
      high_risk  = shifts.select { |s| s[:risk_level] == :high }

      intent_counts = {
        informational: shifts.count { |s| s[:query_intent] == :informational },
        transactional: shifts.count { |s| s[:query_intent] == :transactional },
        commercial: shifts.count { |s| s[:query_intent] == :commercial },
        navigational: shifts.count { |s| s[:query_intent] == :navigational }
      }

      volatility_score = ((mismatched.size.to_f / [total, 1].max) * 100.0).round(1)

      prescriptions = mismatched.map { |m| m[:prescription] }.compact.uniq
      grade = total.zero? ? 'N/A' : (volatility_score > 40.0 ? 'HIGH RISK' : (volatility_score > 20.0 ? 'MODERATE' : 'OPTIMAL'))

      {
        domain: @domain,
        total_queries_analyzed: total,
        intent_distribution: intent_counts,
        mismatched_queries_count: mismatched.size,
        high_risk_shifts_count: high_risk.size,
        portfolio_volatility_pct: volatility_score,
        risk_grade: grade,
        prescriptions: prescriptions,
        shifts: shifts
      }
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'date'
require_relative 'ctr_curve'
require_relative 'intent_shift'

module GSC
  class KeywordValue
    DEFAULT_AOV = 75.0
    DEFAULT_CONV_RATE = 0.025 # 2.5%
    DEFAULT_MARGIN = 0.60    # 60% gross margin

    attr_reader :options, :api, :domain, :aov, :conv_rate, :margin, :target_pos

    def initialize(options = {}, api = nil, domain = nil)
      @options = options
      @api = api
      @domain = domain.to_s.strip
      @aov = (options[:aov] || DEFAULT_AOV).to_f
      @conv_rate = (options[:conv_rate] || DEFAULT_CONV_RATE).to_f
      @margin = (options[:margin] || DEFAULT_MARGIN).to_f
      @target_pos = (options[:target_pos] || 3).to_i
    end

    def self.analyze(options = {}, api = nil, domain = nil)
      new(options, api, domain).analyze
    end

    def analyze
      rows = fetch_rows
      target_ctr = GSC::CtrCurve.benchmark_for(@target_pos)

      analyzed_keywords = rows.map do |row|
        analyze_row(row, target_ctr)
      end

      # Sort by monthly revenue upside descending
      analyzed_keywords.sort_by! { |k| -k[:monthly_revenue_upside] }

      synthesize_portfolio(analyzed_keywords)
    end

    private

    def analyze_row(row, target_ctr)
      query = row[:query]
      imp = row[:impressions] || 0
      clicks = row[:clicks] || 0
      pos = (row[:position] || 100.0).round(1)
      ctr = row[:ctr] || (imp > 0 ? ((clicks.to_f / imp) * 100.0).round(2) : 0.0)

      # Classify intent to apply dynamic conversion multipliers
      intent = GSC::IntentShift.classify_query(query)
      intent_multiplier = case intent
                          when :transactional then 2.0
                          when :commercial    then 1.2
                          when :navigational  then 1.5
                          else 0.6 # informational
                          end

      effective_conv_rate = (@conv_rate * intent_multiplier).round(4)

      # Current realized monthly revenue
      current_orders = (clicks * effective_conv_rate).round(1)
      current_revenue = (current_orders * @aov).round(2)
      current_gross_profit = (current_revenue * @margin).round(2)

      # Projected revenue at target position (e.g. Top 3)
      if pos <= @target_pos
        projected_clicks = clicks
        incremental_clicks = 0
        potential_revenue = current_revenue
        monthly_upside = 0.0
      else
        projected_clicks = ((target_ctr / 100.0) * imp).round
        incremental_clicks = [projected_clicks - clicks, 0].max
        potential_orders = (projected_clicks * effective_conv_rate).round(1)
        potential_revenue = (potential_orders * @aov).round(2)
        monthly_upside = [potential_revenue - current_revenue, 0.0].max.round(2)
      end
      annual_upside = (monthly_upside * 12).round(2)

      # Value Index score (0-100)
      # High score if: in striking distance (pos 4-15), high upside, high intent
      pos_weight = if pos.between?(4.0, 10.0) then 1.0
                   elsif pos.between?(10.1, 20.0) then 0.8
                   elsif pos <= 3.0 then 0.3 # already top 3
                   else 0.4
                   end

      raw_score = (pos_weight * 40) + ([monthly_upside / 50.0, 40].min) + (intent_multiplier * 10)
      value_score = [[raw_score.round, 100].min, 1].max

      action = if pos <= 3.0
                 "👑 Top 3 Defend: Protect ranking with fresh content updates & internal hub equity."
               elsif pos.between?(4.0, 10.0)
                 "🚀 Page-1 Striking Distance: +$#{format_currency(monthly_upside)}/mo upside! Optimize title CTR & add FAQ schema."
               elsif pos.between?(10.1, 20.0)
                 "🎯 Page-2 Striking Query: +$#{format_currency(monthly_upside)}/mo upside. Expand content depth & earn 2 backlinks."
               else
                 "🌱 Deep Discovery: Expand keyword topic cluster to lift organic visibility."
               end

      {
        query: query,
        intent: intent,
        position: pos,
        impressions: imp,
        clicks: clicks,
        ctr: ctr,
        effective_conv_rate: (effective_conv_rate * 100.0).round(2),
        current_orders: current_orders,
        current_monthly_revenue: current_revenue,
        current_gross_profit: current_gross_profit,
        potential_clicks: projected_clicks,
        incremental_clicks: incremental_clicks,
        potential_monthly_revenue: potential_revenue,
        monthly_revenue_upside: monthly_upside,
        annual_revenue_upside: annual_upside,
        value_score: value_score,
        action: action
      }
    end

    def synthesize_portfolio(keywords)
      total_current_rev = keywords.sum { |k| k[:current_monthly_revenue] }.round(2)
      total_potential_rev = keywords.sum { |k| k[:potential_monthly_revenue] }.round(2)
      total_monthly_upside = keywords.sum { |k| k[:monthly_revenue_upside] }.round(2)
      total_annual_upside = (total_monthly_upside * 12).round(2)

      striking_count = keywords.count { |k| k[:position].between?(4.0, 20.0) }
      high_intent_count = keywords.count { |k| k[:intent] == :transactional || k[:intent] == :commercial }

      {
        domain: @domain,
        parameters: {
          aov: @aov,
          conversion_rate_pct: (@conv_rate * 100.0).round(2),
          profit_margin_pct: (@margin * 100.0).round(2),
          target_position: @target_pos
        },
        total_keywords_analyzed: keywords.size,
        striking_distance_keywords: striking_count,
        high_commercial_intent_keywords: high_intent_count,
        financials: {
          current_monthly_revenue: total_current_rev,
          current_annual_run_rate: (total_current_rev * 12).round(2),
          potential_monthly_revenue: total_potential_rev,
          unlocked_monthly_upside: total_monthly_upside,
          unlocked_annual_pipeline_upside: total_annual_upside
        },
        keywords: keywords
      }
    end

    def fetch_rows
      if @api
        begin
          days = (@options[:days] || 28).to_i
          end_date = (Date.today - 2).strftime('%Y-%m-%d')
          start_date = (Date.today - 2 - days).strftime('%Y-%m-%d')
          res = @api.search_analytics(@domain, start_date: start_date, end_date: end_date, dimensions: %w[query])
          rows = res['rows'] || []
          if rows.any?
            return rows.first(25).map do |r|
              {
                query: r['keys'][0],
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

    def format_currency(val)
      parts = sprintf('%.2f', val.to_f).split('.')
      parts[0] = parts[0].reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      parts.join('.')
    end
  end
end

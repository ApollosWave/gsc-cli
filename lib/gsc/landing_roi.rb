# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'uri'

module GSC
  class LandingRoi
    DEFAULT_AOV = 75.0            # Average Order Value / Customer LTV ($)
    DEFAULT_CONV_RATE = 0.025     # 2.5% Conversion rate of engaged visitors
    DEFAULT_BENCHMARK_BOUNCE = 45.0 # 45% standard healthy bounce rate
    DEFAULT_CPC = 1.50            # Replacement PPC cost per click

    attr_reader :options, :aov, :conv_rate, :benchmark_bounce, :cpc

    def initialize(options = {})
      @options = options
      @aov = (options[:aov] || DEFAULT_AOV).to_f
      @conv_rate = (options[:conv_rate] || DEFAULT_CONV_RATE).to_f
      @benchmark_bounce = (options[:benchmark_bounce] || DEFAULT_BENCHMARK_BOUNCE).to_f
      @cpc = (options[:cpc] || DEFAULT_CPC).to_f
    end

    # Analyzes combined GSC pre-click and GA4 post-click data
    def analyze_pages(pages_data)
      analyzed = pages_data.map do |page|
        analyze_single_page(page)
      end

      # Sort by highest monthly revenue leak by default
      analyzed.sort_by! { |p| -(p[:monthly_revenue_leak] || 0.0) }

      total_clicks = analyzed.sum { |p| p[:clicks] || 0 }
      total_sessions = analyzed.sum { |p| p[:sessions] || 0 }
      total_leak = analyzed.sum { |p| p[:monthly_revenue_leak] || 0.0 }
      total_actual_rev = analyzed.sum { |p| p[:actual_revenue_est] || 0.0 }
      total_lost_visitors = analyzed.sum { |p| p[:lost_visitors] || 0 }

      quadrant_summary = {
        cash_cows: analyzed.count { |p| p[:quadrant] == :cash_cow },
        revenue_leakers: analyzed.count { |p| p[:quadrant] == :revenue_leaker },
        hidden_gems: analyzed.count { |p| p[:quadrant] == :hidden_gem },
        zombies: analyzed.count { |p| p[:quadrant] == :zombie }
      }

      {
        total_pages: analyzed.size,
        total_clicks: total_clicks,
        total_sessions: total_sessions,
        total_monthly_leak: total_leak.round(2),
        total_annual_leak: (total_leak * 12.0).round(2),
        total_actual_revenue_est: total_actual_rev.round(2),
        total_lost_visitors: total_lost_visitors,
        quadrants: quadrant_summary,
        assumptions: {
          aov: @aov,
          conv_rate_pct: (@conv_rate * 100.0).round(2),
          benchmark_bounce_pct: @benchmark_bounce,
          estimated_cpc: @cpc
        },
        pages: analyzed
      }
    end

    def analyze_single_page(page)
      url = page[:url] || page['url'] || page[:path] || page['path'] || '/'
      clicks = (page[:clicks] || page['clicks'] || 0).to_i
      impressions = (page[:impressions] || page['impressions'] || 0).to_i
      position = (page[:position] || page['position'] || 0.0).to_f.round(1)
      ctr = (page[:ctr] || page['ctr'] || 0.0).to_f.round(2)
      sessions = (page[:sessions] || page['sessions'] || clicks).to_i
      bounce_rate = (page[:bounce_rate] || page['bounce_rate'] || estimate_bounce_rate(clicks, position)).to_f.round(1)
      duration = (page[:duration] || page['duration'] || page[:duration_seconds] || 60.0).to_f.round(1)

      # Economic Calculations
      excess_bounce = [0.0, bounce_rate - @benchmark_bounce].max
      lost_visitors = (clicks * (excess_bounce / 100.0)).round
      monthly_revenue_leak = (lost_visitors * @conv_rate * @aov).round(2)
      annual_revenue_leak = (monthly_revenue_leak * 12.0).round(2)

      engaged_clicks = [0, clicks - lost_visitors].max
      actual_revenue_est = (engaged_clicks * @conv_rate * @aov).round(2)
      traffic_asset_value = (clicks * @cpc).round(2)

      # Page Economic Health Index (PEHI 0-100)
      # High clicks + low bounce + high duration = 100
      pehi_score = calculate_pehi(clicks, bounce_rate, duration)

      # Strategic Quadrant
      quadrant = classify_quadrant(clicks, bounce_rate, duration, position)

      # Conversion Prescriptions & Fixes
      prescriptions = generate_cro_prescriptions(bounce_rate, duration, clicks, position)

      {
        url: url,
        clicks: clicks,
        impressions: impressions,
        position: position,
        ctr: ctr,
        sessions: sessions,
        bounce_rate: bounce_rate,
        duration_seconds: duration,
        pehi_score: pehi_score,
        quadrant: quadrant,
        lost_visitors: lost_visitors,
        monthly_revenue_leak: monthly_revenue_leak,
        annual_revenue_leak: annual_revenue_leak,
        actual_revenue_est: actual_revenue_est,
        traffic_asset_value: traffic_asset_value,
        prescriptions: prescriptions
      }
    end

    private

    def calculate_pehi(clicks, bounce_rate, duration)
      score = 50.0

      # Bounce Rate Component (max +/- 30pts)
      if bounce_rate <= 35.0
        score += 30.0
      elsif bounce_rate <= 45.0
        score += 15.0
      elsif bounce_rate >= 75.0
        score -= 30.0
      elsif bounce_rate >= 60.0
        score -= 15.0
      end

      # Duration Component (max +/- 15pts)
      if duration >= 120.0
        score += 15.0
      elsif duration >= 60.0
        score += 8.0
      elsif duration <= 25.0
        score -= 15.0
      elsif duration <= 45.0
        score -= 8.0
      end

      # Volume Bonus (max +5pts)
      score += 5.0 if clicks >= 100

      score.clamp(0.0, 100.0).round
    end

    def classify_quadrant(clicks, bounce_rate, duration, position)
      if clicks >= 25 && bounce_rate <= @benchmark_bounce && duration >= 45.0
        :cash_cow
      elsif clicks >= 25 && bounce_rate > @benchmark_bounce
        :revenue_leaker
      elsif clicks < 25 && bounce_rate <= @benchmark_bounce && duration >= 60.0
        :hidden_gem
      else
        :zombie
      end
    end

    def generate_cro_prescriptions(bounce_rate, duration, clicks, position)
      fixes = []

      if bounce_rate >= 70.0
        fixes << "🚨 HIGH BOUNCE TRAP: Place sticky, high-contrast CTA button above 450px fold."
        fixes << "🛡️ ADD SOCIAL PROOF: Insert customer rating stars, logos, or guarantee badge in the top viewport."
      elsif bounce_rate > 55.0
        fixes << "⚡ REDUCE BOUNCE: Add interactive jump-links / Table of Contents to lower drop-off."
      end

      if duration < 30.0
        fixes << "⏱️ LOW TIME ON PAGE: Searchers are not finding answers instantly; add a 2-sentence executive summary under H1."
      end

      if clicks >= 50 && bounce_rate > 60.0
        fixes << "💰 HIGH TRAFFIC BLEED: Priority CRO target. Run A/B test on hero headline and primary action."
      end

      if position >= 7.0 && bounce_rate <= 40.0
        fixes << "⭐ HIDDEN HIGH CONVERTER: Searchers love this page (low bounce). Build 3 internal links to push from pos #{position} to Top 3."
      end

      fixes << "✅ HEALTHY ENGAGEMENT: Maintain current content structure and monitor core queries." if fixes.empty?
      fixes
    end

    def estimate_bounce_rate(clicks, position)
      # Fallback heuristic when GA4 is not linked:
      # Informational / deeper SERP positions generally experience higher bounce rates
      base = 50.0
      base += 5.0 if position > 5.0
      base += 8.0 if position > 10.0
      base.clamp(35.0, 80.0)
    end
  end
end

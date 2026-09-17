# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'date'

module GSC
  class MobileParity
    DEFAULT_GAP_THRESHOLD = 2.0 # 2+ position gap
    DEFAULT_MIN_IMP = 5

    attr_reader :options, :api, :domain

    def initialize(options = {}, api = nil, domain = nil)
      @options = options
      @api = api
      @domain = domain.to_s.strip
    end

    def self.audit(options = {}, api = nil, domain = nil)
      new(options, api, domain).audit
    end

    def audit
      paired_data = fetch_paired_data
      analyzed = analyze_pairs(paired_data)
      synthesize_report(analyzed)
    end

    private

    def analyze_pairs(pairs)
      gap_thresh = (@options[:gap_threshold] || DEFAULT_GAP_THRESHOLD).to_f
      min_imp = (@options[:min_imp] || DEFAULT_MIN_IMP).to_i

      results = []

      pairs.each do |p|
        d = p[:desktop] || { clicks: 0, impressions: 0, ctr: 0.0, position: 100.0 }
        m = p[:mobile]  || { clicks: 0, impressions: 0, ctr: 0.0, position: 100.0 }

        next if (d[:impressions] + m[:impressions]) < min_imp

        pos_gap = (m[:position] - d[:position]).round(1) # positive = desktop ranks better
        ctr_gap = (m[:ctr] - d[:ctr]).round(2)

        # Estimate lost mobile clicks if mobile matched desktop CTR
        expected_mob_clicks = ((d[:ctr] / 100.0) * m[:impressions]).round
        lost_clicks = [expected_mob_clicks - m[:clicks], 0].max

        status = if pos_gap >= 5.0
                   :critical_suppression
                 elsif pos_gap >= gap_thresh
                   :moderate_suppression
                 elsif pos_gap <= -2.0
                   :mobile_advantaged
                 else
                   :parity
                 end

        diagnosis, remediation = diagnose(p[:query], pos_gap, ctr_gap, d, m)

        results << {
          query: p[:query],
          status: status,
          pos_gap: pos_gap,
          ctr_gap: ctr_gap,
          lost_clicks: lost_clicks,
          desktop: d,
          mobile: m,
          diagnosis: diagnosis,
          remediation: remediation
        }
      end

      # Sort by worst mobile suppression first (highest positive pos_gap)
      results.sort_by { |r| -r[:pos_gap] }
    end

    def diagnose(query, pos_gap, ctr_gap, d, m)
      if pos_gap >= 5.0
        [
          "Severe Mobile Demotion: Ranks Pos #{d[:position]} on Desktop but crashes to Pos #{m[:position]} on Mobile.",
          "Audit mobile Core Web Vitals (CLS/INP), inspect touch target sizes (<48px), and ensure above-the-fold content isn't hidden in accordions on mobile."
        ]
      elsif pos_gap >= 2.0
        [
          "Moderate Mobile Position Lag: Mobile is trailing Desktop by #{pos_gap} positions.",
          "Check mobile viewport viewport meta tag, eliminate intrusive interstitials, and compress mobile hero LCP image."
        ]
      elsif ctr_gap <= -3.0 && pos_gap.abs < 2.0
        [
          "CTR Parity Mismatch: Position is stable, but Mobile CTR (#{m[:ctr]}%) is significantly lower than Desktop (#{d[:ctr]}%).",
          "Test title tag truncation on mobile screens (keep < 55 characters) and test rich snippets/favicons."
        ]
      elsif pos_gap <= -2.0
        [
          "Mobile Favored: Mobile ranks #{pos_gap.abs} positions higher than Desktop.",
          "Maintain mobile experience; review desktop page speed and responsiveness."
        ]
      else
        [
          "SERP Parity Aligned: Mobile and Desktop performance are in healthy equilibrium.",
          "Continue monitoring across core algorithm updates."
        ]
      end
    end

    def synthesize_report(analyzed)
      total = analyzed.size
      critical = analyzed.select { |r| r[:status] == :critical_suppression }
      moderate = analyzed.select { |r| r[:status] == :moderate_suppression }
      parity   = analyzed.select { |r| r[:status] == :parity }
      favored  = analyzed.select { |r| r[:status] == :mobile_advantaged }

      total_lost_clicks = analyzed.sum { |r| r[:lost_clicks] }

      total_desktop_clicks = analyzed.sum { |r| r[:desktop][:clicks] }
      total_mobile_clicks  = analyzed.sum { |r| r[:mobile][:clicks] }
      combined_clicks = total_desktop_clicks + total_mobile_clicks

      mob_share_pct = combined_clicks > 0 ? ((total_mobile_clicks.to_f / combined_clicks) * 100.0).round(1) : 0.0

      # Parity Health Score: 100 max, penalized heavily by critical and moderate suppression
      score = if total.zero?
                100
              else
                penalty = (critical.size * 18) + (moderate.size * 6)
                [[100 - penalty, 10].max, 100].min
              end

      grade = if total.zero?
                'A'
              else
                case score
                when 90..100 then 'A'
                when 75..89  then 'B'
                when 55..74  then 'C'
                else 'F'
                end
              end

      remediations = (critical + moderate).map { |r| r[:remediation] }.compact.uniq

      {
        domain: @domain,
        total_queries_analyzed: total,
        traffic_distribution: {
          mobile_share_pct: mob_share_pct,
          desktop_share_pct: combined_clicks > 0 ? (100.0 - mob_share_pct).round(1) : 0.0,
          total_mobile_clicks: total_mobile_clicks,
          total_desktop_clicks: total_desktop_clicks
        },
        health_score: score,
        grade: grade,
        critical_suppression_count: critical.size,
        moderate_suppression_count: moderate.size,
        parity_count: parity.size,
        mobile_favored_count: favored.size,
        total_estimated_lost_mobile_clicks: total_lost_clicks,
        priority_remediations: remediations,
        disparities: analyzed
      }
    end

    def fetch_paired_data
      if @api
        begin
          days = (@options[:days] || 28).to_i
          end_date = (Date.today - 2).strftime('%Y-%m-%d')
          start_date = (Date.today - 2 - days).strftime('%Y-%m-%d')

          raw_rows = if @api.respond_to?(:query_analytics)
                       target_site = @options[:site_url] || (@domain.start_with?('sc-domain:', 'http') ? @domain : "sc-domain:#{@domain}")
                       res = @api.query_analytics(target_site, days: days, dimensions: %w[query device], row_limit: 5000)
                       if (!res[:ok] || (res.dig(:data, 'rows') || []).empty?) && target_site.start_with?('sc-domain:')
                         # Fallback to URL-prefix
                         fallback_res = @api.query_analytics("https://#{@domain}/", days: days, dimensions: %w[query device], row_limit: 5000)
                         res = fallback_res if fallback_res[:ok] && (fallback_res.dig(:data, 'rows') || []).any?
                       end
                       res[:ok] ? (res.dig(:data, 'rows') || []) : []
                     elsif @api.respond_to?(:search_analytics)
                       res = @api.search_analytics(@domain, start_date: start_date, end_date: end_date, dimensions: %w[query device])
                       res['rows'] || []
                     else
                       []
                     end

          if raw_rows.any?
            grouped = {}
            raw_rows.each do |r|
              keys = r['keys'] || []
              q = keys[0]
              dev = keys[1].to_s.upcase
              next unless q && dev

              grouped[q] ||= {}
              grouped[q][dev] = {
                clicks: (r['clicks'] || 0).to_i,
                impressions: (r['impressions'] || 0).to_i,
                ctr: ((r['ctr'] || 0.0) * 100.0).round(2),
                position: (r['position'] || 100.0).to_f.round(1)
              }
            end

            return grouped.map do |q, devs|
              {
                query: q,
                desktop: devs['DESKTOP'],
                mobile: devs['MOBILE']
              }
            end
          end
        rescue StandardError
          # GSC query failed
        end
      end

      []
    end
  end
end

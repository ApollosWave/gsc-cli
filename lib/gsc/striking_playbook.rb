# frozen_string_literal: true

require 'json'

module GSC
  class StrikingPlaybook
    attr_reader :opportunities, :playbooks, :site_url, :brand_name

    def self.generate(api, site_url, options = {})
      new(api, site_url, options).build
    end

    def initialize(api, site_url, options = {})
      @api = api
      @site_url = site_url.to_s
      @options = options
      @days = options[:days] || 30
      @min_pos = options[:min_pos] || 7.0
      @max_pos = options[:max_pos] || 20.0
      @min_imp = options[:min_imp] || 10
      @limit = options[:limit] || 5
      @brand_name = options[:brand_name] || extract_brand_name(@site_url)
      @opportunities = []
      @playbooks = []
    end

    def build
      fetch_striking_opportunities!
      generate_playbooks!

      {
        site_url: @site_url,
        brand_name: @brand_name,
        days: @days,
        filters: { min_pos: @min_pos, max_pos: @max_pos, min_imp: @min_imp },
        total_opportunities_found: @opportunities.size,
        playbooks: @playbooks,
        projected_monthly_clicks: @playbooks.sum { |p| p[:projected_gain] }
      }
    end

    private

    def fetch_striking_opportunities!
      return if @api.nil?

      res = @api.query_analytics(
        @site_url,
        days: @days,
        dimensions: %w[query page],
        row_limit: 2500
      )
      return unless res[:ok]

      raw_rows = res.dig(:data, 'rows') || []

      raw_rows.each do |r|
        q = r['keys'][0].to_s.strip
        p = r['keys'][1].to_s.strip
        pos = r['position'].to_f.round(1)
        imp = r['impressions'].to_i
        clicks = r['clicks'].to_i
        ctr = ((clicks.to_f / [imp, 1].max) * 100.0).round(2)

        next unless pos >= @min_pos && pos <= @max_pos
        next unless imp >= @min_imp

        # Projected Top 3 CTR (~11.5%)
        target_ctr = 11.5
        potential_clicks = [((imp * (target_ctr / 100.0)) - clicks).round, 1].max
        # Score prioritizing high impressions and proximity to position 7
        score = (potential_clicks * (1.0 / [pos - 4.0, 1.0].max) * 10.0).round(1)

        tier = if pos <= 10.5
                 :tier_1_expedite # Pos 7–10: On the brink of Page 1 Top 5
               elsif pos <= 14.5
                 :tier_2_strike   # Pos 11–14: High strike leverage
               else
                 :tier_3_foundation # Pos 15–20: Page 2 climb
               end

        @opportunities << {
          query: q,
          page: p,
          position: pos,
          impressions: imp,
          clicks: clicks,
          ctr: ctr,
          potential_gain: potential_clicks,
          score: score,
          tier: tier
        }
      end

      @opportunities.sort_by! { |o| -o[:score] }
    end

    def generate_playbooks!
      top_opps = @opportunities.first(@limit)

      @playbooks = top_opps.map do |opp|
        query = opp[:query]
        page = opp[:page]
        title_case_query = titleize(query)

        # 1. Synthesize Title Tag Rewrites
        titles = synthesize_titles(title_case_query, @brand_name)

        # 2. Heading Injection Recipes
        headings = synthesize_headings(title_case_query)

        # 3. Internal Link Anchors
        anchors = synthesize_anchors(query, @brand_name)

        # 4. Information Gain / FAQ snippet
        faq = synthesize_faq(query, title_case_query, @brand_name)

        # 5. Step-by-step checklist
        checklist = [
          "Update <title> tag to front-load \"#{query}\" (under 60 chars / 568px)",
          "Insert new <h2>: \"#{headings[:h2]}\"",
          "Add 150–250 words covering #{headings[:h3s].join(' and ')}",
          "Deploy 3 internal links with anchor \"#{anchors[:exact]}\" pointing to #{page}",
          "Embed FAQ snippet with Schema.org FAQPage JSON-LD",
          "Submit #{page} to Google Indexing API via `gsc index #{page}`"
        ]

        opp.merge(
          projected_gain: opp[:potential_gain],
          title_rewrites: titles,
          heading_recipes: headings,
          internal_link_anchors: anchors,
          faq_snippet: faq,
          action_checklist: checklist
        )
      end
    end

    def synthesize_titles(query, brand)
      [
        "#{query}: Official Guide & Top Features | #{brand}",
        "#{brand} #{query} – Boost Results Fast",
        "Best #{query} for Scaling Businesses (2026) | #{brand}"
      ].map { |t| t.length > 60 ? "#{t[0..56]}..." : t }
    end

    def synthesize_headings(query)
      {
        h2: "Why #{query} Is Essential for Conversion & Growth",
        h3s: [
          "How to Implement #{query} Without Coding",
          "Top Mistakes to Avoid With #{query}"
        ]
      }
    end

    def synthesize_anchors(query, brand)
      {
        exact: query,
        partial: "best #{query} solutions",
        branded: "#{brand} #{query}",
        contextual: "learn more about #{query}"
      }
    end

    def synthesize_faq(raw_query, title_query, brand)
      question = if raw_query =~ /^(how|what|why|can|is|does|where)/i
                   "#{title_query}?"
                 else
                   "What is #{title_query} and how does #{brand} support it?"
                 end

      answer = "#{title_query} provides essential optimization for modern online workflows. With #{brand}, teams leverage purpose-built automation to streamline implementation, eliminate technical bottlenecks, and accelerate measurable business performance within days."

      { question: question, answer: answer }
    end

    def titleize(str)
      str.to_s.split(/\s+/).map(&:capitalize).join(' ')
    end

    def extract_brand_name(url)
      uri = URI.parse(url.start_with?('http') ? url : "https://#{url.sub(/^sc-domain:/, '')}")
      host = uri.host || url
      host.sub(/^www\./, '').split('.').first.capitalize
    rescue StandardError
      'Brand'
    end
  end
end

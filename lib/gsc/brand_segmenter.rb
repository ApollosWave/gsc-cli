# frozen_string_literal: true

module GSC
  class BrandSegmenter
    attr_reader :brand_tokens

    # Suffixes to strip when deriving brand name from domain (e.g., exampleapp -> example)
    STRIP_SUFFIXES = %w[app apps io co tech hq get try official shop store ltd inc net org].freeze

    def initialize(domain: nil, custom_brand: nil)
      @brand_tokens = resolve_tokens(domain, custom_brand)
    end

    def brand?(query)
      return false if @brand_tokens.empty? || query.to_s.strip.empty?

      q = normalize(query)
      # Check exact token containment or multi-word phrase containment
      @brand_tokens.any? do |token|
        token_clean = normalize(token)
        q.include?(token_clean) || q.gsub(/\s+/, '').include?(token_clean.gsub(/\s+/, ''))
      end
    end

    def segment(rows)
      brand_rows = []
      non_brand_rows = []

      rows.each do |row|
        q = row[:query] || row['query'] || ''
        if brand?(q)
          brand_rows << row
        else
          non_brand_rows << row
        end
      end

      {
        brand: brand_rows,
        non_brand: non_brand_rows,
        summary: calculate_summary(brand_rows, non_brand_rows)
      }
    end

    private

    def normalize(str)
      str.to_s.downcase.gsub(/[^a-z0-9\s]/, ' ').squeeze(' ').strip
    end

    def resolve_tokens(domain, custom_brand)
      tokens = []

      if custom_brand && !custom_brand.to_s.strip.empty?
        cb = normalize(custom_brand)
        tokens << cb
        tokens << cb.gsub(/\s+/, '')
        cb.split(/\s+/).each do |w|
          tokens << w if w.length >= 4 && !%w[pro app apps the inc llc ltd corp].include?(w)
        end
      end

      if domain && !domain.to_s.strip.empty?
        # Clean domain
        clean_dom = domain.to_s.sub(/^https?:\/\//i, '').sub(/^sc-domain:/i, '').split('/').first.to_s.downcase
        parts = clean_dom.split('.')
        # Main apex stem (e.g., exampleapp from exampleapp.com)
        stem = parts.first || ''
        
        tokens << stem unless stem.empty?

        # Try stripping known suffixes
        STRIP_SUFFIXES.each do |suffix|
          if stem.end_with?(suffix) && stem.length > (suffix.length + 3)
            base = stem[0...-suffix.length]
            tokens << base
            # Add spaced variant if it looks compound (e.g. quickcart -> quick cart)
            tokens << base.sub(/(super|pack|cart|speed|quick|auto|mega|hyper)/i, '\1 ').strip
          end
        end

        # Also add compound space variations
        tokens << stem.sub(/(super|pack|cart|speed|quick|auto|mega|hyper)/i, '\1 ').strip
      end

      tokens.map { |t| normalize(t) }.reject { |t| t.length < 3 }.uniq
    end

    def calculate_summary(brand_rows, non_brand_rows)
      total_rows = brand_rows.size + non_brand_rows.size
      
      b_clicks = brand_rows.sum { |r| r[:clicks] || r['clicks'] || 0 }
      b_imp = brand_rows.sum { |r| r[:impressions] || r['impressions'] || 0 }
      b_ctr = b_imp > 0 ? (b_clicks.to_f / b_imp * 100).round(2) : 0.0
      b_pos = if b_imp > 0
                (brand_rows.sum { |r| (r[:position] || r['position'] || 0.0).to_f * (r[:impressions] || r['impressions'] || 0).to_f } / b_imp.to_f).round(1)
              elsif brand_rows.any?
                (brand_rows.sum { |r| (r[:position] || r['position'] || 0.0).to_f } / brand_rows.size).round(1)
              else
                0.0
              end

      nb_clicks = non_brand_rows.sum { |r| r[:clicks] || r['clicks'] || 0 }
      nb_imp = non_brand_rows.sum { |r| r[:impressions] || r['impressions'] || 0 }
      nb_ctr = nb_imp > 0 ? (nb_clicks.to_f / nb_imp * 100).round(2) : 0.0
      nb_pos = if nb_imp > 0
                 (non_brand_rows.sum { |r| (r[:position] || r['position'] || 0.0).to_f * (r[:impressions] || r['impressions'] || 0).to_f } / nb_imp.to_f).round(1)
               elsif non_brand_rows.any?
                 (non_brand_rows.sum { |r| (r[:position] || r['position'] || 0.0).to_f } / non_brand_rows.size).round(1)
               else
                 0.0
               end

      total_clicks = b_clicks + nb_clicks
      total_imp = b_imp + nb_imp

      {
        total_queries: total_rows,
        brand: {
          queries_count: brand_rows.size,
          clicks: b_clicks,
          impressions: b_imp,
          ctr: b_ctr,
          avg_position: b_pos,
          click_share: total_clicks > 0 ? (b_clicks.to_f / total_clicks * 100).round(1) : 0.0,
          impression_share: total_imp > 0 ? (b_imp.to_f / total_imp * 100).round(1) : 0.0
        },
        non_brand: {
          queries_count: non_brand_rows.size,
          clicks: nb_clicks,
          impressions: nb_imp,
          ctr: nb_ctr,
          avg_position: nb_pos,
          click_share: total_clicks > 0 ? (nb_clicks.to_f / total_clicks * 100).round(1) : 0.0,
          impression_share: total_imp > 0 ? (nb_imp.to_f / total_imp * 100).round(1) : 0.0
        }
      }
    end
  end
end

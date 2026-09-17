# frozen_string_literal: true

module GSC
  class CannibalizationAnalyzer
    def self.analyze(rows, min_imp: 10, min_secondary_ratio: 0.15)
      grouped = Hash.new { |h, k| h[k] = [] }

      rows.each do |r|
        query = r[:query] || r['query'] || r.dig('keys', 0)
        page  = r[:page]  || r['page']  || r.dig('keys', 1)
        clicks = r[:clicks] || r['clicks'] || 0
        imp    = r[:impressions] || r['impressions'] || 0
        pos    = (r[:position] || r['position'] || 100.0).to_f.round(1)

        next unless query && page

        grouped[query] << {
          page: page,
          clicks: clicks,
          impressions: imp,
          position: pos
        }
      end

      conflicts = []
      total_wasted_imp = 0

      grouped.each do |query, pages|
        next if pages.size < 2

        total_imp = pages.sum { |p| p[:impressions] }
        next if total_imp < min_imp

        sorted_pages = pages.sort_by { |p| -p[:impressions] }
        primary = sorted_pages[0]
        secondary = sorted_pages[1]

        sec_ratio = secondary[:impressions].to_f / total_imp
        next if sec_ratio < min_secondary_ratio

        severity = calculate_severity(primary, secondary, total_imp, sec_ratio)
        remedy = determine_remedy(primary, secondary, query)

        # Wasted / split impressions from secondary+ competing pages
        diluted_imp = pages[1..].sum { |p| p[:impressions] }
        total_wasted_imp += diluted_imp

        conflicts << {
          query: query,
          severity: severity,
          total_impressions: total_imp,
          total_clicks: pages.sum { |p| p[:clicks] },
          competing_pages_count: pages.size,
          diluted_impressions: diluted_imp,
          remedy: remedy,
          pages: sorted_pages.map do |p|
            share = ((p[:impressions].to_f / total_imp) * 100).round(1)
            p.merge(
              impression_share: share,
              impression_share_str: "#{share}%"
            )
          end
        }
      end

      # Sort by severity (CRITICAL > HIGH > MODERATE > LOW) then total impressions
      severity_order = { 'CRITICAL' => 4, 'HIGH' => 3, 'MODERATE' => 2, 'LOW' => 1 }
      conflicts.sort_by! { |c| [-severity_order[c[:severity]], -c[:total_impressions]] }

      critical_count = conflicts.count { |c| c[:severity] == 'CRITICAL' }
      health_score = [100 - (conflicts.size * 10 + critical_count * 15), 0].max

      grade = case health_score
              when 90..100 then 'A'
              when 80..89  then 'B'
              when 70..79  then 'C'
              when 60..69  then 'D'
              else 'F'
              end

      {
        total_queries_evaluated: grouped.size,
        conflicts_count: conflicts.size,
        critical_count: critical_count,
        total_diluted_impressions: total_wasted_imp,
        health_score: health_score,
        health_grade: grade,
        conflicts: conflicts
      }
    end

    def self.calculate_severity(primary, secondary, total_imp, sec_ratio)
      # If both rank on Page 1 or 2 and share is closely split
      if (primary[:position] <= 20.0 || secondary[:position] <= 20.0) && (sec_ratio >= 0.35 || total_imp >= 50)
        'CRITICAL'
      elsif sec_ratio >= 0.25 || total_imp >= 25
        'HIGH'
      elsif sec_ratio >= 0.15
        'MODERATE'
      else
        'LOW'
      end
    end

    def self.determine_remedy(primary, secondary, _query)
      p_path = primary[:page].sub(%r{^https?://[^/]+}, '')
      p_path = '/' if p_path.empty?
      s_path = secondary[:page].sub(%r{^https?://[^/]+}, '')
      s_path = '/' if s_path.empty?

      # Case 1: Secondary page actually ranks higher than primary!
      if secondary[:position] < (primary[:position] - 1.5)
        {
          action: 'FLIP_FLOP_CONSOLIDATION',
          recommendation: "Googlebot prefers secondary page (#{s_path} ranks Pos #{secondary[:position]} vs #{primary[:position]}). Set canonical from #{p_path} pointing to #{s_path}, or 301 redirect #{p_path} to #{s_path}."
        }
      # Case 2: Inverted or duplicate slugs in same directory
      elsif slug_similarity(p_path, s_path) > 0.7
        {
          action: '301_REDIRECT',
          recommendation: "Near-identical slug intent. 301 redirect secondary #{s_path} into primary #{p_path} to merge PageRank."
        }
      # Case 3: Distinct topics accidentally colliding
      else
        {
          action: 'CANONICAL_OR_LINK_DE_OPTIMIZE',
          recommendation: "Differentiate content angles: set canonical pointing to #{p_path}, and remove \"#{_query}\" keyword from secondary #{s_path}'s H1/title."
        }
      end
    end

    def self.slug_similarity(path1, path2)
      tokens1 = path1.downcase.split(/[^a-z0-9]+/).reject { |t| t.length < 2 }
      tokens2 = path2.downcase.split(/[^a-z0-9]+/).reject { |t| t.length < 2 }
      return 0.0 if tokens1.empty? || tokens2.empty?

      common = (tokens1 & tokens2).size
      common.to_f / [tokens1.size, tokens2.size].max
    end
  end
end

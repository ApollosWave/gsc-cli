# frozen_string_literal: true

require 'json'

module GSC
  class QuestionsHarvester
    QUESTION_WORDS = %w[
      who what where when why how can does do did is are should which will would could
    ].freeze

    PHRASE_PATTERNS = [
      /\b(difference between|vs|versus|compared to)\b/i,
      /\b(best way to|how to|guide to|ways to|steps to)\b/i,
      /\b(provider|providers|apps?|tools?|alternatives?|options?|solutions?)\s+(that|to|for|with)\b/i,
      /\b(worth it|is it worth)\b/i,
      /\b(pros and cons)\b/i,
      /\?$/
    ].freeze

    def self.harvest(rows, min_imp: 1, filter_page: nil, brand: nil, synthesize: false)
      # rows: Array of {"keys" => [query, page], "clicks" => n, "impressions" => n, "ctr" => f, "position" => f}
      raw_questions = {}

      rows.each do |r|
        keys = r['keys'] || []
        query = keys[0].to_s.strip
        page  = keys[1].to_s.strip

        next if query.empty?
        next if filter_page && !page.downcase.include?(filter_page.downcase)

        q_lower = query.downcase
        is_question = false
        matched_type = nil

        # Check question words as distinct tokens
        QUESTION_WORDS.each do |w|
          if q_lower =~ /\b#{w}\b/
            is_question = true
            matched_type ||= w.upcase
            break
          end
        end

        # Check phrase patterns
        unless is_question
          PHRASE_PATTERNS.each do |pat|
            if q_lower =~ pat
              is_question = true
              matched_type = 'PHRASE'
              break
            end
          end
        end

        next unless is_question

        clicks = (r['clicks'] || 0).to_i
        impressions = (r['impressions'] || 0).to_i
        ctr = (r['ctr'] || 0.0).to_f
        position = (r['position'] || 0.0).to_f.round(1)

        next if impressions < min_imp

        # Capitalize query nicely as question sentence
        formatted_question = query.sub(/^[a-z]/, &:upcase)
        formatted_question += '?' unless formatted_question.end_with?('?')

        dedup_key = [formatted_question.downcase, page.downcase]

        if raw_questions[dedup_key]
          existing = raw_questions[dedup_key]
          existing[:clicks] += clicks
          existing[:impressions] += impressions
          existing[:position] = [existing[:position], position].min
          existing[:ctr] = existing[:impressions].positive? ? ((existing[:clicks].to_f / existing[:impressions]) * 100.0).round(2) : 0.0
          existing[:tier] = classify_tier(existing[:position], existing[:impressions])
          existing[:opportunity_score] = calculate_opportunity_score(existing[:impressions], existing[:position], existing[:clicks])
        else
          opp_tier = classify_tier(position, impressions)
          score = calculate_opportunity_score(impressions, position, clicks)

          raw_questions[dedup_key] = {
            raw_query: query,
            question: formatted_question,
            type: matched_type,
            page: page,
            clicks: clicks,
            impressions: impressions,
            ctr: (ctr * 100).round(2),
            position: position,
            tier: opp_tier,
            opportunity_score: score
          }
        end
      end

      # Sort: High opportunity first, then by impressions descending
      sorted_questions = raw_questions.values.sort_by { |q| [-q[:opportunity_score], -q[:impressions]] }

      # Group by page
      by_page = Hash.new { |h, k| h[k] = [] }
      sorted_questions.each do |q|
        by_page[q[:page]] << q
      end

      {
        total_questions_harvested: sorted_questions.size,
        high_opportunity_count: sorted_questions.count { |q| q[:tier] == 'HIGH_OPPORTUNITY' },
        defense_count: sorted_questions.count { |q| q[:tier] == 'SERP_DEFENSE' },
        pages_covered: by_page.keys.size,
        questions: sorted_questions,
        grouped_by_page: by_page,
        recommended_faq_schemas: generate_faq_schemas(by_page, brand: brand, synthesize: synthesize)
      }
    end

    def self.classify_tier(position, impressions)
      if position.between?(4.0, 20.0) && impressions >= 3
        'HIGH_OPPORTUNITY'
      elsif position.between?(1.0, 3.9)
        'SERP_DEFENSE'
      else
        'LONG_TAIL'
      end
    end

    def self.calculate_opportunity_score(impressions, position, clicks)
      # Weight: High impressions ranking in striking distance (pos 4-20) gets highest score
      pos_factor = case position
                   when 4.0..10.0 then 3.0 # Page 1 striking distance (huge win potential)
                   when 11.0..20.0 then 2.0 # Page 2 striking distance
                   when 1.0..3.9 then 1.5 # Defend position 1-3
                   else 0.8
                   end

      ((impressions * pos_factor) + (clicks * 5)).round(1)
    end

    def self.generate_faq_schemas(grouped_by_page, max_per_page: 5, brand: nil, synthesize: false)
      schemas = {}

      grouped_by_page.each do |page, q_list|
        top_qs = q_list.first(max_per_page)
        entities = top_qs.map do |q|
          answer_text = if synthesize
                          begin
                            require_relative 'answer_synthesizer' unless defined?(GSC::AnswerSynthesizer)
                            res = GSC::AnswerSynthesizer.synthesize(q[:question], brand: brand)
                            res[:direct_answer]
                          rescue StandardError
                            "Authoritative answer explaining #{q[:question]} for #{page.sub(%r{^https?://[^/]+}, '')}."
                          end
                        else
                          "Detailed guidance answering \"#{q[:question]}\" for #{page.sub(%r{^https?://[^/]+}, '')}."
                        end

          {
            '@type' => 'Question',
            'name' => q[:question],
            'acceptedAnswer' => {
              '@type' => 'Answer',
              'text' => answer_text
            }
          }
        end

        schemas[page] = {
          '@context' => 'https://schema.org',
          '@type' => 'FAQPage',
          'mainEntity' => entities
        }
      end

      schemas
    end
  end
end

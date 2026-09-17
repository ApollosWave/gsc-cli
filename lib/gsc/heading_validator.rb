# frozen_string_literal: true

require 'json'

module GSC
  class HeadingValidator
    attr_reader :headings, :counts, :violations, :score, :grade, :depth

    def self.analyze(html, target_keywords: nil)
      new(html, target_keywords: target_keywords).audit
    end

    def initialize(html, target_keywords: nil)
      @html = html.to_s.dup.force_encoding('UTF-8').scrub
      @target_keywords = extract_keyword_tokens(target_keywords)
      @headings = []
      @counts = { 'h1' => 0, 'h2' => 0, 'h3' => 0, 'h4' => 0, 'h5' => 0, 'h6' => 0 }
      @violations = []
      @score = 100
      @grade = 'A'
      @depth = 0
    end

    def audit
      parse_headings!
      validate_hierarchy!
      calculate_score!
      audit_keywords! if @target_keywords && !@target_keywords.empty?

      {
        score: @score,
        grade: @grade,
        depth: @depth,
        count: @headings.size,
        counts: @counts,
        h1_count: @counts['h1'],
        empty_count: @headings.count { |h| h[:empty] },
        headings: @headings,
        violations: @violations,
        keyword_analysis: @keyword_analysis,
        summary: summary_text,
        ascii_tree: render_ascii_tree(colorize: false),
        color_tree: render_ascii_tree(colorize: true)
      }
    end

    def render_ascii_tree(colorize: false)
      return '   (No headings found on page)' if @headings.empty?

      lines = []
      @headings.each_with_index do |h, idx|
        level = h[:level]
        tag_str = "[#{h[:tag].upcase}]"
        prefix = '   ' + ('  ' * (level - 1)) + (level == 1 ? '■ ' : '├── ')

        text_str = h[:empty] ? '(Empty Heading Tag)' : h[:text]
        # Truncate very long heading in display
        display_text = text_str.length > 75 ? "#{text_str[0..72]}..." : text_str

        # Check if this heading has an attached violation
        v_msgs = h[:violations].map { |v| v[:message] }
        v_suffix = v_msgs.empty? ? '' : " ⚠️  #{v_msgs.join('; ')}"

        if colorize && defined?(Color)
          tag_color = case level
                      when 1 then Color::CYAN
                      when 2 then Color::BLUE
                      when 3 then Color::MAGENTA
                      else Color::GRAY
                      end
          colored_tag = Color.c(tag_str, tag_color, Color::BOLD)
          colored_text = h[:empty] ? Color.c(display_text, Color::RED, Color::DIM) : display_text
          colored_suffix = v_suffix.empty? ? '' : Color.c(v_suffix, Color::YELLOW, Color::BOLD)
          lines << "#{prefix}#{colored_tag} #{colored_text}#{colored_suffix}"
        else
          lines << "#{prefix}#{tag_str} #{display_text}#{v_suffix}"
        end
      end

      lines.join("\n")
    end

    private

    def parse_headings!
      idx = 0
      @html.scan(%r{<(h[1-6])(?:\s+[^>]*)?>(.*?)</\1>}im) do |tag, content|
        idx += 1
        clean = clean_text(content)
        level = tag[1].to_i
        is_empty = clean.empty?

        h_info = {
          index: idx,
          tag: tag.downcase,
          level: level,
          text: clean,
          length: clean.length,
          empty: is_empty,
          violations: []
        }

        @headings << h_info
        @counts[tag.downcase] += 1
        @depth = level if level > @depth
      end
    end

    def validate_hierarchy!
      return if @headings.empty?

      # 1. Check if first heading is H1
      first_h = @headings.first
      if first_h[:level] != 1
        v = {
          type: :first_not_h1,
          severity: :warning,
          tag: first_h[:tag],
          index: 1,
          message: "Page starts with <#{first_h[:tag]}> instead of <h1>"
        }
        @violations << v
        first_h[:violations] << v
      end

      # 2. Check H1 count
      if @counts['h1'] == 0
        @violations << {
          type: :missing_h1,
          severity: :critical,
          message: 'Missing <h1> tag. Document has 0 top-level headings.'
        }
      elsif @counts['h1'] > 1
        extra_h1s = @headings.select { |h| h[:tag] == 'h1' }[1..]
        extra_h1s.each do |eh|
          v = {
            type: :multiple_h1,
            severity: :warning,
            tag: 'h1',
            index: eh[:index],
            message: "Multiple <h1> tag detected at position ##{eh[:index]} ('#{eh[:text][0..40]}...')"
          }
          @violations << v
          eh[:violations] << v
        end
      end

      # 3. Check sequential depth skips (e.g. H1 -> H3 or H2 -> H4)
      prev_level = nil
      @headings.each do |h|
        curr_level = h[:level]

        if prev_level && curr_level > prev_level + 1
          skipped = (prev_level + 1...curr_level).map { |lvl| "<h#{lvl}>" }.join(', ')
          v = {
            type: :skipped_level,
            severity: :warning,
            tag: h[:tag],
            index: h[:index],
            from_level: prev_level,
            to_level: curr_level,
            message: "Skipped heading level: jumped from <h#{prev_level}> to <h#{curr_level}> (skipped #{skipped})"
          }
          @violations << v
          h[:violations] << v
        end

        # 4. Check empty heading
        if h[:empty]
          v = {
            type: :empty_heading,
            severity: :error,
            tag: h[:tag],
            index: h[:index],
            message: "Empty <#{h[:tag]}> tag with no text content"
          }
          @violations << v
          h[:violations] << v
        end

        # 5. Check overlong heading (> 80 chars)
        if h[:length] > 80
          v = {
            type: :overlong_heading,
            severity: :info,
            tag: h[:tag],
            index: h[:index],
            message: "Heading length (#{h[:length]} chars) exceeds 80 chars; risk of topical dilution"
          }
          @violations << v
          h[:violations] << v
        end

        prev_level = curr_level
      end
    end

    def calculate_score!
      if @headings.empty?
        @score = 0
        @grade = 'F'
        return
      end

      deductions = 0
      @violations.each do |v|
        deductions += case v[:type]
                      when :missing_h1 then 30
                      when :multiple_h1 then 15
                      when :skipped_level then 10
                      when :empty_heading then 10
                      when :first_not_h1 then 10
                      when :overlong_heading then 5
                      else 5
                      end
      end

      @score = [100 - deductions, 0].max
      @grade = case @score
               when 90..100 then 'A'
               when 80..89  then 'B'
               when 70..79  then 'C'
               when 60..69  then 'D'
               else 'F'
               end
    end

    def audit_keywords!
      h1 = @headings.find { |h| h[:tag] == 'h1' }
      h1_matches = []
      if h1
        h1_text = h1[:text].downcase
        h1_matches = @target_keywords.select { |kw| h1_text.include?(kw) }
      end

      h2_matches = {}
      @headings.select { |h| h[:tag] == 'h2' }.each do |h2|
        h2_text = h2[:text].downcase
        matched = @target_keywords.select { |kw| h2_text.include?(kw) }
        h2_matches[h2[:text]] = matched unless matched.empty?
      end

      @keyword_analysis = {
        target_keywords: @target_keywords,
        h1_has_keyword: !h1_matches.empty?,
        h1_matched_keywords: h1_matches,
        h2_matched_count: h2_matches.size,
        h2_matches: h2_matches
      }
    end

    def extract_keyword_tokens(keywords)
      return [] if keywords.nil? || keywords.to_s.strip.empty?

      if keywords.is_a?(Array)
        keywords.map { |k| k.to_s.downcase.strip }.reject(&:empty?)
      else
        keywords.to_s.downcase.split(/[,|\s]+/).map(&:strip).reject { |w| w.length < 3 }
      end
    end

    def clean_text(str)
      str.to_s
         .dup
         .force_encoding('UTF-8')
         .scrub
         .gsub(/<[^>]+>/, ' ')
         .gsub(/&amp;/, '&')
         .gsub(/&lt;/, '<')
         .gsub(/&gt;/, '>')
         .gsub(/&quot;/, '"')
         .gsub(/&#39;/, "'")
         .gsub(/&nbsp;/, ' ')
         .gsub(/\s+/, ' ')
         .strip
    end

    def summary_text
      counts_str = @counts.select { |_k, v| v > 0 }.map { |k, v| "#{v}x #{k.upcase}" }.join(', ')
      "Heading Health Score: #{@score}/100 (Grade #{@grade}) | Depth: H#{@depth} | Total: #{@headings.size} (#{counts_str}) | #{@violations.size} violations"
    end
  end
end

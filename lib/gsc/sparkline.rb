# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'color'

module GSC
  class Sparkline
    TICKS = ["\u2581", "\u2582", "\u2583", "\u2584", "\u2585", "\u2586", "\u2587", "\u2588"].freeze

    # Renders a single-line Unicode sparkline
    # options:
    #   colored: true (gradient from red/trough to green/peak)
    #   invert: true (lower values get higher ticks, e.g. SERP position)
    #   max_points: limit number of values (resamples if larger)
    def self.render(values, options = {})
      vals = normalize_values(values)
      return '' if vals.empty?

      vals = resample(vals, options[:max_points]) if options[:max_points] && vals.size > options[:max_points]

      min_val = vals.min
      max_val = vals.max
      range = max_val - min_val

      chars = vals.map do |v|
        idx = if range.zero?
                TICKS.size / 2
              else
                pos = (v - min_val) / range.to_f
                pos = 1.0 - pos if options[:invert]
                [((pos * (TICKS.size - 1)).round), TICKS.size - 1].min
              end

        tick = TICKS[idx]
        if options[:colored]
          color_tick(tick, idx, TICKS.size)
        else
          tick
        end
      end

      chars.join
    end

    # Renders a multi-line ASCII terminal chart with Y-axis labels and X-axis
    def self.chart(values, options = {})
      vals = normalize_values(values)
      return '' if vals.empty?

      height = [options[:height] || 5, 2].max
      dates = options[:dates] || []

      min_val = vals.min
      max_val = vals.max
      range = [max_val - min_val, 1.0].max

      y_label_width = [max_val.round.to_s.length, min_val.round.to_s.length, 3].max

      rows = []

      # Render each chart line from top to bottom
      (height - 1).downto(0) do |row_idx|
        threshold = min_val + (range * (row_idx.to_f / (height - 1)))
        label = row_idx == height - 1 ? max_val.round.to_s : (row_idx.zero? ? min_val.round.to_s : '')
        y_axis = label.rjust(y_label_width) + ' ┤ '

        line_chars = vals.map do |v|
          normalized = (v - min_val) / range.to_f
          char_level = (normalized * (height - 1)).round

          if char_level == row_idx
            Color.bold(Color.cyan('•'))
          elsif char_level > row_idx
            Color.cyan('│')
          else
            ' '
          end
        end

        rows << "#{y_axis}#{line_chars.join}"
      end

      # X-axis line
      axis_pad = ' '.rjust(y_label_width)
      rows << "#{axis_pad} ┼─#{'─' * vals.size}"

      # X-axis date milestones if available
      if dates.any? && dates.size == vals.size
        step = [vals.size / 4, 1].max
        label_line = ' ' * vals.size
        0.step(vals.size - 1, step) do |i|
          d_str = dates[i].to_s.sub(/^\d{4}-/, '') # MM-DD
          label_line[i, d_str.length] = d_str if i + d_str.length <= label_line.length
        end
        rows << "#{axis_pad}   #{label_line}"
      end

      rows.join("\n")
    end

    # Computes trend velocity and momentum
    def self.momentum(values)
      vals = normalize_values(values)
      return { change_pct: 0.0, trend: :stable, velocity: 'FLAT' } if vals.size < 2

      mid = vals.size / 2
      first_half = vals[0...mid]
      second_half = vals[mid..-1]

      avg_first = first_half.sum.to_f / [first_half.size, 1].max
      avg_second = second_half.sum.to_f / [second_half.size, 1].max

      change_pct = avg_first.zero? ? (avg_second > 0 ? 100.0 : 0.0) : (((avg_second - avg_first) / avg_first) * 100.0).round(1)

      trend = if change_pct >= 25.0
                :surging
              elsif change_pct >= 5.0
                :rising
              elsif change_pct <= -25.0
                :collapsing
              elsif change_pct <= -5.0
                :decaying
              else
                :stable
              end

      velocity_badge = case trend
                       when :surging then '🚀 SURGING (+%+.1f%%)' % change_pct
                       when :rising then '📈 RISING (+%+.1f%%)' % change_pct
                       when :collapsing then '💥 COLLAPSING (%+.1f%%)' % change_pct
                       when :decaying then '📉 DECAYING (%+.1f%%)' % change_pct
                       else '➡️ STABLE (%+.1f%%)' % change_pct
                       end

      {
        change_pct: change_pct,
        trend: trend,
        velocity: velocity_badge,
        start_avg: avg_first.round(1),
        end_avg: avg_second.round(1)
      }
    end

    private

    def self.normalize_values(values)
      Array(values).map { |v| v.is_a?(Hash) ? (v[:value] || v['value'] || 0) : v }.map(&:to_f)
    end

    def self.resample(vals, max_pts)
      return vals if vals.size <= max_pts
      step = vals.size.to_f / max_pts
      (0...max_pts).map do |i|
        idx = (i * step).round
        vals[[idx, vals.size - 1].min]
      end
    end

    def self.color_tick(tick, idx, total)
      pct = idx.to_f / (total - 1)
      if pct >= 0.75
        Color.green(tick)
      elsif pct >= 0.4
        Color.yellow(tick)
      else
        Color.red(tick)
      end
    end
  end
end

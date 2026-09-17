# frozen_string_literal: true

module GSC
class GoogleTrends
  TRENDS_HOST = 'trends.google.com'

  def self.normalize_time(time_str)
    case time_str.to_s.strip.downcase
    when '5y', '5-y', 'past-5-years', '5years' then 'today 5-y'
    when '12m', '1y', 'past-12-months', '12months', '1year' then 'today 12-m'
    when '3m', 'past-3-months', '3months' then 'today 3-m'
    when '1m', 'past-month', '30d' then 'today 1-m'
    when '7d', 'past-week' then 'now 7-d'
    when '1d', '24h', 'today' then 'now 1-d'
    when 'all' then 'all'
    else
      time_str.to_s.strip.empty? ? 'today 5-y' : time_str.to_s.strip
    end
  end

  def self.render_sparkline(values, max_points: 36)
    return '' if values.nil? || values.empty?
    bucketed = if values.size > max_points
                 chunk_size = (values.size.to_f / max_points).ceil
                 values.each_slice(chunk_size).map { |slice| (slice.sum.to_f / slice.size).round }
               else
                 values
               end
    min_val = bucketed.min.to_f
    max_val = bucketed.max.to_f
    range = max_val - min_val
    range = 1.0 if range.zero?
    sparks = ["\u2581", "\u2582", "\u2583", "\u2584", "\u2585", "\u2586", "\u2587", "\u2588"]
    bucketed.map do |v|
      idx = [((v - min_val) / range * (sparks.length - 1)).round, sparks.length - 1].min
      sparks[idx]
    end.join
  end

  def self.fetch(keyword, geo: 'US', time: '5y')
    http = Net::HTTP.new(TRENDS_HOST, 443)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 25

    init_req = Net::HTTP::Get.new('/trends/explore')
    init_req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    init_res = http.request(init_req)
    cookies = init_res.get_fields('set-cookie')&.map { |c| c.split(';').first }&.join('; ')

    norm_time = normalize_time(time)
    clean_geo = geo.to_s.upcase == 'WORLDWIDE' ? '' : geo.to_s.strip
    req_obj = {
      comparisonItem: [{ keyword: keyword, geo: clean_geo, time: norm_time }],
      category: 0,
      property: ''
    }
    explore_path = '/trends/api/explore?hl=en-US&tz=-180&req=' + URI.encode_www_form_component(JSON.generate(req_obj))
    explore_req = Net::HTTP::Get.new(explore_path)
    explore_req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    explore_req['Accept'] = 'application/json, text/plain, */*'
    explore_req['Referer'] = 'https://trends.google.com/trends/explore'
    explore_req['Cookie'] = cookies if cookies

    explore_res = http.request(explore_req)
    if explore_res.code == '302'
      loc = explore_res['location'].to_s
      return { ok: false, error: "Google Trends rate limit or bot challenge triggered (HTTP 302 redirect to #{loc.include?('sorry') ? 'Google CAPTCHA' : 'redirect'}). Google is temporarily throttling Trends requests from this network. Try again in a few minutes, or use 'gsc suggest' / 'gsc planner'." }
    elsif explore_res.code == '429' || init_res.code == '429'
      return { ok: false, error: "Google Trends rate limit reached (HTTP 429 - Too Many Requests). Google is temporarily throttling Trends requests from this network. Try again in a few minutes, or use 'gsc suggest' / 'gsc planner'." }
    elsif !explore_res.is_a?(Net::HTTPSuccess)
      return { ok: false, error: "Google Trends Explore API error (HTTP #{explore_res.code})" }
    end

    raw_exp = explore_res.body.to_s
    clean_body = raw_exp.index('{') ? raw_exp[raw_exp.index('{')..] : raw_exp
    explore_data = JSON.parse(clean_body) rescue nil
    widgets = explore_data&.dig('widgets') || []

    ts_widget = widgets.find { |w| w['id'] == 'TIMESERIES' }
    geo_widget = widgets.find { |w| w['id'] == 'GEO_MAP' }
    queries_widget = widgets.find { |w| w['id'] == 'RELATED_QUERIES' }

    timeline = []
    if ts_widget
      ts_path = '/trends/api/widgetdata/multiline?hl=en-US&tz=-180&req=' + URI.encode_www_form_component(JSON.generate(ts_widget['request'])) + '&token=' + ts_widget['token']
      ts_req = Net::HTTP::Get.new(ts_path)
      ts_req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      ts_req['Accept'] = 'application/json, text/plain, */*'
      ts_req['Referer'] = 'https://trends.google.com/trends/explore'
      ts_req['Cookie'] = cookies if cookies
      ts_res = http.request(ts_req)
      if ts_res.is_a?(Net::HTTPSuccess)
        raw_ts = ts_res.body.to_s
        ts_clean = raw_ts.index('{') ? raw_ts[raw_ts.index('{')..] : raw_ts
        ts_data = JSON.parse(ts_clean) rescue {}
        timeline = ts_data.dig('default', 'timelineData') || []
      end
    end

    regions = []
    if geo_widget
      geo_path = '/trends/api/widgetdata/comparedgeo?hl=en-US&tz=-180&req=' + URI.encode_www_form_component(JSON.generate(geo_widget['request'])) + '&token=' + geo_widget['token']
      geo_req = Net::HTTP::Get.new(geo_path)
      geo_req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      geo_req['Referer'] = 'https://trends.google.com/trends/explore'
      geo_req['Cookie'] = cookies if cookies
      geo_res = http.request(geo_req)
      if geo_res.is_a?(Net::HTTPSuccess)
        raw_geo = geo_res.body.to_s
        geo_clean = raw_geo.index('{') ? raw_geo[raw_geo.index('{')..] : raw_geo
        geo_data = JSON.parse(geo_clean) rescue {}
        raw_regions = geo_data.dig('default', 'geoMapData') || []
        regions = raw_regions.map do |r|
          { name: r['geoName'], score: (r['value']&.first || 0) }
        end.sort_by { |r| -r[:score] }.reject { |r| r[:score].zero? }
      end
    end

    top_queries = []
    rising_queries = []
    if queries_widget
      q_path = '/trends/api/widgetdata/relatedsearches?hl=en-US&tz=-180&req=' + URI.encode_www_form_component(JSON.generate(queries_widget['request'])) + '&token=' + queries_widget['token']
      q_req = Net::HTTP::Get.new(q_path)
      q_req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      q_req['Accept'] = 'application/json, text/plain, */*'
      q_req['Referer'] = 'https://trends.google.com/trends/explore'
      q_req['Cookie'] = cookies if cookies
      q_res = http.request(q_req)
      if q_res.is_a?(Net::HTTPSuccess)
        raw_q = q_res.body.to_s
        q_clean = raw_q.index('{') ? raw_q[raw_q.index('{')..] : raw_q
        q_data = JSON.parse(q_clean) rescue {}
        ranked = q_data.dig('default', 'rankedList') || []
        top_queries = (ranked.first&.dig('rankedKeyword') || []).map do |q|
          { query: q['query'], score: q['value'] }
        end
        rising_queries = (ranked.last&.dig('rankedKeyword') || []).map do |q|
          { query: q['query'], growth: q['formattedValue'] }
        end
      end
    end

    points = timeline.map do |pt|
      {
        date: pt['formattedTime'] || pt['formattedAxisTime'],
        score: (pt['value']&.first || 0)
      }
    end

    scores = points.map { |p| p[:score] }
    peak_val = scores.max || 0
    peak_pt = points.find { |p| p[:score] == peak_val }
    curr_val = scores.last || 0

    split = [points.size / 5, 4].max
    baseline = points.first(split).map { |p| p[:score] }.sum.to_f / split
    recent   = points.last(split).map { |p| p[:score] }.sum.to_f / split
    growth_pct = baseline > 0 ? (((recent - baseline) / baseline) * 100).round : 0

    velocity_badge = if growth_pct >= 250
                       "+#{growth_pct}% 🚀 (Explosive Breakout)"
                     elsif growth_pct >= 80
                       "+#{growth_pct}% 🔥 (Strong Surging)"
                     elsif growth_pct >= 15
                       "+#{growth_pct}% 📈 (Growing Demand)"
                     elsif growth_pct >= -15
                       "#{growth_pct}% ⚖️ (Stable Demand)"
                     else
                       "#{growth_pct}% 📉 (Cooling / Declining)"
                     end

    {
      ok: true,
      keyword: keyword,
      geo: clean_geo.empty? ? 'Worldwide' : clean_geo,
      time: norm_time,
      peak_score: peak_val,
      peak_date: peak_pt ? peak_pt[:date] : nil,
      current_score: curr_val,
      growth_pct: growth_pct,
      velocity_badge: velocity_badge,
      sparkline: render_sparkline(scores),
      points_count: points.size,
      regions: regions.first(10),
      top_queries: top_queries.first(8),
      rising_queries: rising_queries.first(8),
      points: points
    }
  rescue StandardError => e
    { ok: false, error: e.message }
  end
end
end

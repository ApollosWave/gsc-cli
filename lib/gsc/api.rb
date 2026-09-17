# frozen_string_literal: true

module GSC
  class API
    def initialize(client)
      @client = client
    end

    # Indexing API: Publish URL (URL_UPDATED / URL_DELETED)
    def publish_url(url, type = 'URL_UPDATED')
      @client.post('https://indexing.googleapis.com/v3/urlNotifications:publish', { url: url, type: type })
    end

    # Indexing API: Metadata status
    def get_url_status(url)
      @client.get("https://indexing.googleapis.com/v3/urlNotifications/metadata?url=#{URI.encode_www_form_component(url)}")
    end

    # URL Inspection API
    def inspect_url(inspection_url, site_url)
      @client.post('https://searchconsole.googleapis.com/v1/urlInspection/index:inspect', {
        inspectionUrl: inspection_url,
        siteUrl: site_url
      })
    end

# Search Analytics API
def query_analytics(site_url, days: 30, dimensions: ['query'], row_limit: 50, start_row: 0, start_date: nil, end_date: nil, filters: nil)
  end_d   = end_date || Date.today.iso8601
  start_d = start_date || (Date.today - days).iso8601

  body = {
    startDate: start_d,
    endDate: end_d
  }
  body[:rowLimit] = row_limit if row_limit
  body[:startRow] = start_row if start_row && start_row > 0
  body[:dimensions] = dimensions if dimensions && !dimensions.empty?
  body[:dimensionFilterGroups] = [{ filters: filters }] if filters && !filters.empty?

  endpoint = "https://searchconsole.googleapis.com/webmasters/v3/sites/#{URI.encode_www_form_component(site_url)}/searchAnalytics/query"
  res = @client.post(endpoint, body)
  res.merge(start_date: start_d, end_date: end_d)
end

# Unified search_analytics interface supporting string/symbol rows access and property prefix fallback
def search_analytics(site_url, start_date: nil, end_date: nil, days: 30, dimensions: ['query'], row_limit: 5000, start_row: 0, filters: nil)
  raw_site = site_url.to_s.strip
  target_site = if raw_site.start_with?('sc-domain:', 'http://', 'https://')
                  raw_site
                else
                  "sc-domain:#{raw_site}"
                end

  res = query_analytics(
    target_site,
    days: days,
    dimensions: dimensions,
    row_limit: row_limit,
    start_row: start_row,
    start_date: start_date,
    end_date: end_date,
    filters: filters
  )

  # Fallback to URL-prefix if sc-domain returns empty or forbidden
  if (!res[:ok] || (res.dig(:data, 'rows') || []).empty?) && target_site.start_with?('sc-domain:')
    clean_dom = target_site.sub(/^sc-domain:/, '')
    fallback_res = query_analytics(
      "https://#{clean_dom}/",
      days: days,
      dimensions: dimensions,
      row_limit: row_limit,
      start_row: start_row,
      start_date: start_date,
      end_date: end_date,
      filters: filters
    )
    res = fallback_res if fallback_res[:ok] && (fallback_res.dig(:data, 'rows') || []).any?
  end

  rows = res.dig(:data, 'rows') || []
  {
    'rows' => rows,
    :rows  => rows,
    :data  => res[:data] || { 'rows' => rows },
    'data' => res[:data] || { 'rows' => rows },
    :ok    => res[:ok],
    :status => res[:status],
    :start_date => res[:start_date],
    :end_date => res[:end_date]
  }
end
alias_method :query_search_analytics, :search_analytics

# Fetch all analytics rows across pagination (handles >25,000 queries via startRow)
def query_all_analytics(site_url, days: 30, dimensions: ['query'], start_date: nil, end_date: nil, max_total: nil)
  all_rows = []
  start_row = 0
  chunk_size = 5000
  last_res = nil

  loop do
    res = query_analytics(
      site_url,
      days: days,
      dimensions: dimensions,
      row_limit: chunk_size,
      start_row: start_row,
      start_date: start_date,
      end_date: end_date
    )
    last_res = res
    return res unless res[:ok]

    rows = res.dig(:data, 'rows') || []
    all_rows.concat(rows)

    break if rows.size < chunk_size
    break if max_total && all_rows.size >= max_total

    start_row += chunk_size
    # Google Search Console Search Analytics API hard limit: startRow cannot exceed 25,000
    break if start_row >= 25000
  end

  {
    ok: true,
    status: 200,
    start_date: last_res ? last_res[:start_date] : nil,
    end_date: last_res ? last_res[:end_date] : nil,
    data: {
      'rows' => all_rows,
      'responseAggregationType' => last_res ? last_res.dig(:data, 'responseAggregationType') : 'byPage'
    }
  }
end

    # Verified Sites List
    def list_sites
      @client.get('https://searchconsole.googleapis.com/webmasters/v3/sites')
    end

    # Sitemaps List
    def list_sitemaps(site_url)
      @client.get("https://searchconsole.googleapis.com/webmasters/v3/sites/#{URI.encode_www_form_component(site_url)}/sitemaps")
    end

    # Submit Sitemap
    def submit_sitemap(site_url, feedpath)
      @client.put("https://searchconsole.googleapis.com/webmasters/v3/sites/#{URI.encode_www_form_component(site_url)}/sitemaps/#{URI.encode_www_form_component(feedpath)}")
    end

    # Helper to construct GA4 dimension filters (e.g. hostName isolation, organic traffic)
    def build_ga4_filter(hostname: nil, organic_only: false, site_only: false)
      filters = []
      if hostname && !hostname.empty?
        clean_host = hostname.to_s.sub(%r{^https?://}, '').sub(/^sc-domain:/, '').sub(/^www\./, '').chomp('/')
        escaped_host = Regexp.escape(clean_host)

        match_val = if site_only
          "^(www\\.)?#{escaped_host}$"
        else
          "(^|.*\\.)#{escaped_host}$"
        end

        filters << {
          filter: {
            fieldName: 'hostName',
            stringFilter: {
              matchType: 'FULL_REGEXP',
              value: match_val
            }
          }
        }
      end

      if organic_only
        filters << {
          filter: {
            fieldName: 'sessionMedium',
            stringFilter: {
              matchType: 'EXACT',
              value: 'organic'
            }
          }
        }
      end

      if filters.size == 1
        filters.first
      elsif filters.size > 1
        { andGroup: { expressions: filters } }
      end
    end

    # Google Analytics 4 Data API (runReport)
    def query_ga4_report(property_id, days: 30, limit: 100, organic_only: false, hostname: nil, site_only: false)
      clean_id = property_id.to_s.sub(%r{^properties/}, '')
      endpoint = "https://analyticsdata.googleapis.com/v1beta/properties/#{clean_id}:runReport"

      body = {
        dateRanges: [{ startDate: "#{days}daysAgo", endDate: 'yesterday' }],
        dimensions: [{ name: 'pagePath' }],
        metrics: [
          { name: 'sessions' },
          { name: 'activeUsers' },
          { name: 'engagementRate' },
          { name: 'bounceRate' },
          { name: 'averageSessionDuration' },
          { name: 'screenPageViews' }
        ],
        limit: limit
      }

      filter = build_ga4_filter(hostname: hostname, organic_only: organic_only, site_only: site_only)
      body[:dimensionFilter] = filter if filter

      @client.post(endpoint, body)
    end

    # Google Analytics Admin API (accountSummaries)
    def list_ga4_summaries
      @client.get('https://analyticsadmin.googleapis.com/v1beta/accountSummaries')
    end

    # Google Analytics 4 Realtime API (runRealtimeReport)
    def query_ga4_realtime(property_id, limit: 30)
      clean_id = property_id.to_s.sub(%r{^properties/}, '')
      endpoint = "https://analyticsdata.googleapis.com/v1beta/properties/#{clean_id}:runRealtimeReport"

      body = {
        dimensions: [
          { name: 'unifiedScreenName' },
          { name: 'country' }
        ],
        metrics: [
          { name: 'activeUsers' }
        ],
        metricAggregations: ['TOTAL'],
        limit: limit
      }

      @client.post(endpoint, body)
    end

    # Google Analytics 4 Page Title to URL Path resolution map
    def query_ga4_title_map(property_id, days: 30, hostname: nil, site_only: false)
      clean_id = property_id.to_s.sub(%r{^properties/}, '')
      endpoint = "https://analyticsdata.googleapis.com/v1beta/properties/#{clean_id}:runReport"

      body = {
        dateRanges: [{ startDate: "#{days}daysAgo", endDate: 'today' }],
        dimensions: [{ name: 'pageTitle' }, { name: 'pagePath' }],
        metrics: [{ name: 'screenPageViews' }],
        limit: 250
      }

      filter = build_ga4_filter(hostname: hostname, site_only: site_only)
      body[:dimensionFilter] = filter if filter

      res = @client.post(endpoint, body)
      map = {}
      if res[:ok]
        (res.dig(:data, 'rows') || []).each do |r|
          title = r.dig('dimensionValues', 0, 'value')
          path  = r.dig('dimensionValues', 1, 'value')
          map[title] ||= path if title && path
        end
      end
      map
    rescue StandardError
      {}
    end

    # Google Analytics 4 Google Ads Report
    def query_ga4_ads(property_id, days: 30, limit: 50)
      clean_id = property_id.to_s.sub(%r{^properties/}, '')
      endpoint = "https://analyticsdata.googleapis.com/v1beta/properties/#{clean_id}:runReport"

      body = {
        dateRanges: [{ startDate: "#{days}daysAgo", endDate: 'yesterday' }],
        dimensions: [
          { name: 'sessionGoogleAdsCampaignName' },
          { name: 'sessionGoogleAdsAdGroupName' }
        ],
        metrics: [
          { name: 'advertiserAdClicks' },
          { name: 'advertiserAdCost' },
          { name: 'advertiserAdCostPerClick' },
          { name: 'sessions' },
          { name: 'conversions' },
          { name: 'bounceRate' }
        ],
        limit: limit
      }

      @client.post(endpoint, body)
    end

    # Google Analytics 4 Omnichannel Traffic Acquisition Report
    def query_ga4_channels(property_id, days: 30, limit: 25, hostname: nil, site_only: false)
      clean_id = property_id.to_s.sub(%r{^properties/}, '')
      endpoint = "https://analyticsdata.googleapis.com/v1beta/properties/#{clean_id}:runReport"

      body = {
        dateRanges: [{ startDate: "#{days}daysAgo", endDate: 'yesterday' }],
        dimensions: [
          { name: 'sessionDefaultChannelGroup' },
          { name: 'sessionSourceMedium' }
        ],
        metrics: [
          { name: 'sessions' },
          { name: 'totalUsers' },
          { name: 'engagementRate' },
          { name: 'bounceRate' },
          { name: 'averageSessionDuration' },
          { name: 'conversions' }
        ],
        limit: limit
      }

      filter = build_ga4_filter(hostname: hostname, site_only: site_only)
      body[:dimensionFilter] = filter if filter

      @client.post(endpoint, body)
    end

    # Google Analytics 4 Geographic Cities Report
    def query_ga4_cities(property_id, days: 30, limit: 10, hostname: nil, site_only: false)
      clean_id = property_id.to_s.sub(%r{^properties/}, '')
      endpoint = "https://analyticsdata.googleapis.com/v1beta/properties/#{clean_id}:runReport"

      body = {
        dateRanges: [{ startDate: "#{days}daysAgo", endDate: 'yesterday' }],
        dimensions: [{ name: 'city' }, { name: 'country' }],
        metrics: [
          { name: 'sessions' },
          { name: 'bounceRate' },
          { name: 'averageSessionDuration' }
        ],
        orderBys: [{ metric: { metricName: 'sessions' }, desc: true }],
        limit: limit
      }

      filter = build_ga4_filter(hostname: hostname, site_only: site_only)
      body[:dimensionFilter] = filter if filter

      @client.post(endpoint, body)
    end
  end
end

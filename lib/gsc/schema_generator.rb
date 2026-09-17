# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'uri'
require 'net/http'
require 'time'

module GSC
  class SchemaGenerator
    attr_reader :options

    def initialize(options = {})
      @options = options
    end

    # 1. Generate schema programmatically from input options
    def generate(type, params = {})
      normalized_type = type.to_s.downcase.gsub(/[^a-z]/, '')

      schema = case normalized_type
               when 'product'
                 build_product(params)
               when 'faq', 'faqpage'
                 build_faq(params)
               when 'howto', 'how-to'
                 build_howto(params)
               when 'article', 'blog', 'blogposting', 'newsarticle'
                 build_article(params)
               when 'software', 'softwareapplication', 'app', 'webapplication', 'mobileapplication'
                 build_software(params)
               when 'localbusiness', 'store', 'restaurant', 'business'
                 build_local_business(params)
               when 'organization', 'org', 'corp'
                 build_organization(params)
               when 'breadcrumb', 'breadcrumbs', 'breadcrumblist'
                 build_breadcrumbs(params)
               when 'course'
                 build_course(params)
               when 'job', 'jobposting', 'careers'
                 build_job_posting(params)
               when 'event'
                 build_event(params)
               when 'video', 'videoobject'
                 build_video(params)
               when 'recipe'
                 build_recipe(params)
               else
                 build_article(params)
               end

      validation = validate_schema(schema)

      {
        schema: schema,
        type: schema['@type'],
        validation: validation,
        snippets: format_snippets(schema)
      }
    end

    # 2. Extract content from a live URL or raw HTML and auto-synthesize optimal Schema
    def extract_from_url(url, explicit_type = nil)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 8
      http.read_timeout = 10

      res = http.request(req)
      html = res.body.to_s.force_encoding('UTF-8').scrub

      extract_from_html(html, url, explicit_type)
    rescue => e
      path_slug = URI.parse(url).path.split('/').reject(&:empty?).last || 'home' rescue 'home'
      headline = path_slug.gsub(/[-_]/, ' ').split.map(&:capitalize).join(' ')
      type_to_use = explicit_type || options[:type] || 'article'
      generate(type_to_use, {
        headline: headline,
        name: headline,
        url: url,
        description: "Comprehensive guide and overview for #{headline}."
      })
    end

    def extract_from_html(html, url = nil, explicit_type = nil)
      title = extract_tag_content(html, 'title') || extract_meta_content(html, 'og:title') || 'Untitled Page'
      desc = extract_meta_content(html, 'description') || extract_meta_content(html, 'og:description') || ''
      image = extract_meta_content(html, 'og:image') || extract_first_image(html, url)
      h1 = extract_first_h1(html)
      primary_name = (h1 && !h1.empty?) ? h1 : title

      # Price extraction heuristic
      price_match = html.match(/(?:\$|USD|EUR|GBP|\u00A3|\u20AC)\s*([0-9]+(?:\.[0-9]{2})?)/i) ||
                    html.match(/"price"\s*:\s*"?([0-9]+(?:\.[0-9]{2})?)"?/i) ||
                    html.match(/itemprop=["']price["'][^>]*content=["']([0-9.]+)["']/i)

      # FAQ extraction heuristic
      q_matches = html.scan(/<(?:h[234]|summary|dt)[^>]*>([^<]*\?[\s\S]*?)<\/(?:h[234]|summary|dt)>/i).flatten.map { |q| strip_html(q) }.reject(&:empty?)

      # Breadcrumb extraction heuristic
      bc_matches = html.scan(/<(?:a|span)[^>]*class=["'][^"']*(?:breadcrumb|crumb)[^"']*["'][^>]*>(.*?)<\/(?:a|span)>/i).flatten.map { |b| strip_html(b) }.reject(&:empty?)

      auto_detected = if price_match || html =~ /class=["'][^"']*(?:product|ecommerce|price|add-to-cart)/i
                        'product'
                      elsif q_matches.size >= 2
                        'faq'
                      elsif html =~ /class=["'][^"']*(?:software|app|download|pricing-table)/i
                        'software'
                      elsif bc_matches.size >= 2
                        'breadcrumb'
                      else
                        'article'
                      end

      target_type = explicit_type || options[:type] || auto_detected
      brand_extracted = URI.parse(url).host.to_s.sub(/^www\./, '').split('.').first.capitalize rescue 'Brand'

      params = {
        url: options[:url] || url,
        name: options[:name] || primary_name,
        headline: options[:headline] || options[:name] || primary_name,
        description: options[:description] || (desc.empty? ? "#{primary_name} overview and details." : desc),
        image: options[:image] || image,
        brand: options[:brand] || brand_extracted,
        price: options[:price] || (price_match ? price_match[1].to_f : 0.0),
        currency: options[:currency] || 'USD',
        rating: options[:rating],
        reviews: options[:reviews],
        author: options[:author],
        operating_system: options[:os] || options[:operating_system] || 'Web, macOS, Windows, iOS, Android',
        category: options[:category] || 'UtilitiesApplication'
      }

      if q_matches.size >= 2
        params[:questions] = q_matches.first(5).map do |clean_q|
          { q: clean_q, a: "Detailed answer and explanation regarding #{clean_q.sub(/\?*$/, '')}." }
        end
      end

      if bc_matches.size >= 2
        params[:breadcrumbs] = bc_matches.map { |b| { name: b, url: url } }
      end

      existing_schemas = extract_existing_schemas(html)
      result = generate(target_type, params)

      target_class = result[:schema]['@type'].to_s.downcase
      matching_existing = existing_schemas.find do |s|
        s_type = s['@type'].to_s.downcase
        s_type == target_class ||
          (target_class == 'softwareapplication' && s_type =~ /software|app/) ||
          (target_class == 'faqpage' && s_type =~ /faq/) ||
          (target_class == 'article' && s_type =~ /article|blog/)
      end

      existing_types = existing_schemas.map { |s| s['@type'] }.compact.uniq

      result[:existing_analysis] = {
        existing_count: existing_schemas.size,
        existing_types: existing_types,
        duplicate_detected: !matching_existing.nil?,
        matching_type: matching_existing ? matching_existing['@type'] : nil,
        matching_schema: matching_existing
      }

      result
    end

    def extract_existing_schemas(html)
      schemas = []
      return schemas if html.nil? || html.empty?

      html.scan(%r{<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>}im) do |match|
        json_str = match[0].to_s.strip
        next if json_str.empty?

        begin
          parsed = JSON.parse(json_str)
          schemas.concat(flatten_existing(parsed))
        rescue JSON::ParserError
          # skip corrupted
        end
      end
      schemas
    end

    def flatten_existing(data)
      case data
      when Array
        data.flat_map { |item| flatten_existing(item) }
      when Hash
        if data['@graph'].is_a?(Array)
          data['@graph'].flat_map { |item| flatten_existing(item) }
        else
          [data]
        end
      else
        []
      end
    end

    # 3. Validation against Google Rich Result Guidelines
    def validate_schema(schema)
      if schema.is_a?(Hash) && schema['@graph'].is_a?(Array)
        aggregated_errors = []
        aggregated_warnings = []
        schema['@graph'].each do |item|
          sub_val = validate_schema(item)
          aggregated_errors.concat(sub_val[:errors])
          aggregated_warnings.concat(sub_val[:warnings])
        end
        return {
          valid: aggregated_errors.empty?,
          errors: aggregated_errors,
          warnings: aggregated_warnings
        }
      end

      type = schema['@type']
      errors = []
      warnings = []

      case type
      when 'Product'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        errors << 'Missing "offers" or "aggregateRating"' unless schema['offers'] || schema['aggregateRating']
        warnings << 'Missing "image" (strongly recommended for Google Shopping rich results)' unless schema['image']
        warnings << 'Missing "brand"' unless schema['brand']

        if schema['offers']
          offers = schema['offers']
          errors << 'Offers missing "price"' unless offers['price']
          errors << 'Offers missing "priceCurrency"' unless offers['priceCurrency']
        end

      when 'FAQPage'
        main_entity = schema['mainEntity']
        if !main_entity.is_a?(Array) || main_entity.empty?
          errors << 'FAQPage must contain a non-empty "mainEntity" array'
        else
          main_entity.each_with_index do |q, idx|
            errors << "Question ##{idx + 1} missing 'name'" if q['name'].to_s.strip.empty?
            errors << "Question ##{idx + 1} missing 'acceptedAnswer'" unless q['acceptedAnswer'] && q['acceptedAnswer']['text']
          end
        end

      when 'HowTo'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        errors << 'Missing "step" array' unless schema['step'].is_a?(Array) && !schema['step'].empty?
        warnings << 'Missing "totalTime" or "estimatedCost"' unless schema['totalTime'] || schema['estimatedCost']

      when 'Article', 'BlogPosting', 'NewsArticle'
        errors << 'Missing "headline"' if schema['headline'].to_s.strip.empty?
        errors << 'Missing "author"' unless schema['author']
        warnings << 'Missing "datePublished"' unless schema['datePublished']
        warnings << 'Missing "image" (Google Top Stories requires image >= 1200px)' unless schema['image']

      when 'SoftwareApplication', 'WebApplication', 'MobileApplication'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        warnings << 'Missing "operatingSystem"' unless schema['operatingSystem']
        warnings << 'Missing "applicationCategory"' unless schema['applicationCategory']

      when 'LocalBusiness', 'Store', 'Restaurant'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        errors << 'Missing "address"' unless schema['address']
        warnings << 'Missing "telephone"' unless schema['telephone']
        warnings << 'Missing "openingHoursSpecification"' unless schema['openingHoursSpecification']

      when 'BreadcrumbList'
        items = schema['itemListElement']
        if !items.is_a?(Array) || items.empty?
          errors << 'BreadcrumbList must contain "itemListElement" array'
        else
          items.each_with_index do |it, idx|
            errors << "Breadcrumb ##{idx + 1} missing 'position'" unless it['position']
            errors << "Breadcrumb ##{idx + 1} missing 'name'" unless it['name']
            errors << "Breadcrumb ##{idx + 1} missing 'item'" unless it['item']
          end
        end

      when 'Course'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        errors << 'Missing "description"' if schema['description'].to_s.strip.empty?
        errors << 'Missing "provider"' unless schema['provider']

      when 'JobPosting'
        errors << 'Missing "title"' if schema['title'].to_s.strip.empty?
        errors << 'Missing "description"' if schema['description'].to_s.strip.empty?
        errors << 'Missing "datePosted"' unless schema['datePosted']
        errors << 'Missing "hiringOrganization"' unless schema['hiringOrganization']

      when 'Event'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        errors << 'Missing "startDate"' unless schema['startDate']
        errors << 'Missing "location"' unless schema['location']

      when 'VideoObject'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        errors << 'Missing "description"' if schema['description'].to_s.strip.empty?
        errors << 'Missing "thumbnailUrl"' unless schema['thumbnailUrl']
        errors << 'Missing "uploadDate"' unless schema['uploadDate']

      when 'Recipe'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        errors << 'Missing "image"' unless schema['image']
        errors << 'Missing "recipeIngredient"' unless schema['recipeIngredient']
        errors << 'Missing "recipeInstructions"' unless schema['recipeInstructions']

      when 'Organization'
        errors << 'Missing "name"' if schema['name'].to_s.strip.empty?
        warnings << 'Missing "url"' unless schema['url']
        warnings << 'Missing "logo"' unless schema['logo']
      end

      {
        valid: errors.empty?,
        errors: errors,
        warnings: warnings,
        score: calculate_schema_score(errors, warnings)
      }
    end

    def format_snippets(schema)
      json_str = JSON.pretty_generate(schema)

      html_script = "<script type=\"application/ld+json\">\n#{json_str}\n</script>"

      nextjs_script = "<script\n  type=\"application/ld+json\"\n  dangerouslySetInnerHTML={{ __html: JSON.stringify(#{json_str.lines.map { |l| '  ' + l }.join.strip}) }}\n/>"

      shopify_snippet = "{% comment %} Schema.org #{schema['@type']} JSON-LD (Generated by gsc-cli) {% endcomment %}\n<script type=\"application/ld+json\">\n#{json_str}\n</script>"

      {
        html: html_script,
        nextjs: nextjs_script,
        shopify: shopify_snippet,
        raw_json: json_str
      }
    end

    def strip_html(str)
      return '' unless str
      s = str.to_s.dup
      s = s.gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/im, '')
      s = s.gsub(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/im, '')
      s = s.gsub(/<br\s*\/?>/i, ' ')
      s = s.gsub(/<[^>]+>/, ' ')
      s = s.gsub(/&nbsp;/i, ' ')
           .gsub(/&amp;/i, '&')
           .gsub(/&quot;/i, '"')
           .gsub(/&#39;/i, "'")
           .gsub(/&lt;/i, '<')
           .gsub(/&gt;/i, '>')
      s.gsub(/\s+/, ' ').strip
    end

    private

    def build_product(p)
      name = p[:name] || p['name'] || 'Featured Product'
      desc = p[:description] || p['description'] || "#{name} description."
      price = (p[:price] || p['price']) ? (p[:price] || p['price']).to_f.round(2) : nil
      currency = p[:currency] || p['currency'] || 'USD'
      image = p[:image] || p['image']
      brand_name = p[:brand] || p['brand'] || 'Brand'
      sku = p[:sku] || p['sku']
      rating_val = (p[:rating] || p['rating']) ? (p[:rating] || p['rating']).to_f.round(1) : nil
      review_count = (p[:reviews] || p['reviews']) ? (p[:reviews] || p['reviews']).to_i : nil

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'Product',
        'name' => name,
        'description' => desc,
        'brand' => {
          '@type' => 'Brand',
          'name' => brand_name
        }
      }

      schema['image'] = [image] if image
      schema['sku'] = sku if sku

      if price
        schema['offers'] = {
          '@type' => 'Offer',
          'url' => p[:url] || p['url'] || '',
          'priceCurrency' => currency,
          'price' => price.to_s,
          'priceValidUntil' => (Time.now + (365 * 24 * 3600)).strftime('%Y-%m-%d'),
          'itemCondition' => 'https://schema.org/NewCondition',
          'availability' => 'https://schema.org/InStock'
        }
      end

      if rating_val && review_count
        schema['aggregateRating'] = {
          '@type' => 'AggregateRating',
          'ratingValue' => rating_val.to_s,
          'reviewCount' => review_count.to_s
        }
      end

      schema
    end

    def build_faq(p)
      questions = p[:questions] || p['questions'] || []
      if questions.empty?
        # Fallback default questions
        q_text = p[:q] || p['q'] || p[:question] || p['question'] || 'How does this work?'
        a_text = p[:a] || p['a'] || p[:answer] || p['answer'] || 'It operates automatically using advanced heuristics.'
        questions = [{ q: q_text, a: a_text }]
      end

      entities = questions.map do |item|
        q_str = item[:q] || item['q'] || item[:question] || item['question'] || 'Frequently Asked Question'
        a_str = item[:a] || item['a'] || item[:answer] || item['answer'] || 'Answer description.'
        {
          '@type' => 'Question',
          'name' => q_str,
          'acceptedAnswer' => {
            '@type' => 'Answer',
            'text' => a_str
          }
        }
      end

      {
        '@context' => 'https://schema.org',
        '@type' => 'FAQPage',
        'mainEntity' => entities
      }
    end

    def build_howto(p)
      name = p[:name] || p['name'] || p[:headline] || 'How to Optimize Performance'
      desc = p[:description] || p['description'] || "Step-by-step actionable guide for #{name}."
      steps = p[:steps] || p['steps'] || [
        { name: 'Initial Assessment', text: 'Audit current baseline metrics and identify bottlenecks.' },
        { name: 'Implementation', text: 'Deploy high-impact optimizations across key components.' },
        { name: 'Verification', text: 'Validate performance gains and ensure zero regressions.' }
      ]

      step_entities = steps.each_with_index.map do |s, idx|
        {
          '@type' => 'HowToStep',
          'position' => (idx + 1).to_s,
          'name' => s[:name] || s['name'] || "Step #{idx + 1}",
          'text' => s[:text] || s['text'] || s.to_s
        }
      end

      {
        '@context' => 'https://schema.org',
        '@type' => 'HowTo',
        'name' => name,
        'description' => desc,
        'totalTime' => p[:time] || p['time'] || 'PT15M',
        'step' => step_entities
      }
    end

    def build_article(p)
      headline = p[:headline] || p['headline'] || p[:name] || 'Comprehensive Guide'
      desc = p[:description] || p['description'] || "#{headline}: In-depth analysis and expert insights."
      author_name = p[:author] || p['author'] || 'Editorial Team'
      publisher_name = p[:publisher] || p['publisher'] || 'Publisher'
      url = p[:url] || p['url'] || ''
      image = p[:image] || p['image']
      published = p[:date_published] || p['date_published'] || Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'Article',
        'headline' => headline,
        'description' => desc,
        'datePublished' => published,
        'dateModified' => Time.now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'author' => {
          '@type' => 'Person',
          'name' => author_name
        },
        'publisher' => {
          '@type' => 'Organization',
          'name' => publisher_name
        }
      }

      schema['image'] = [image] if image
      schema['publisher']['logo'] = { '@type' => 'ImageObject', 'url' => p[:logo] || p['logo'] } if (p[:logo] || p['logo'])
      schema['mainEntityOfPage'] = { '@type' => 'WebPage', '@id' => url } unless url.empty?

      schema
    end

    def build_software(p)
      name = p[:name] || p['name'] || 'Software Application'
      desc = p[:description] || p['description'] || "#{name} application."
      os = p[:os] || p['os'] || p[:operating_system] || 'Web, macOS, Windows, Linux'
      category = p[:category] || p['category'] || 'BusinessApplication'
      price = (p[:price] || p['price'] || 0.0).to_f.round(2)
      rating_val = (p[:rating] || p['rating']) ? (p[:rating] || p['rating']).to_f.round(1) : nil
      review_count = (p[:reviews] || p['reviews']) ? (p[:reviews] || p['reviews']).to_i : nil

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'SoftwareApplication',
        'name' => name,
        'operatingSystem' => os,
        'applicationCategory' => category,
        'description' => desc,
        'offers' => {
          '@type' => 'Offer',
          'price' => price.to_s,
          'priceCurrency' => p[:currency] || p['currency'] || 'USD'
        }
      }

      if rating_val && review_count
        schema['aggregateRating'] = {
          '@type' => 'AggregateRating',
          'ratingValue' => rating_val.to_s,
          'reviewCount' => review_count.to_s
        }
      end

      schema
    end

    def build_local_business(p)
      name = p[:name] || p['name'] || 'Local Business'
      url = p[:url] || p['url'] || ''

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'LocalBusiness',
        'name' => name,
        'telephone' => p[:telephone] || '+1-555-0199',
        'address' => {
          '@type' => 'PostalAddress',
          'streetAddress' => p[:street] || '123 Market Street',
          'addressLocality' => p[:city] || 'San Francisco',
          'addressRegion' => p[:state] || 'CA',
          'postalCode' => p[:zip] || '94103',
          'addressCountry' => 'US'
        },
        'openingHoursSpecification' => [
          {
            '@type' => 'OpeningHoursSpecification',
            'dayOfWeek' => %w[Monday Tuesday Wednesday Thursday Friday],
            'opens' => '09:00',
            'closes' => '18:00'
          }
        ]
      }

      schema['url'] = url unless url.empty?
      schema['image'] = [p[:image]] if p[:image]
      schema
    end

    def build_breadcrumbs(p)
      items = p[:breadcrumbs] || p['breadcrumbs'] || []
      if items.empty?
        base_url = p[:url] || 'https://example.com'
        items = [
          { name: 'Home', url: base_url },
          { name: p[:name] || 'Current Page', url: "#{base_url}/current" }
        ]
      end

      item_list = items.each_with_index.map do |it, idx|
        {
          '@type' => 'ListItem',
          'position' => idx + 1,
          'name' => it[:name] || it['name'] || "Item #{idx + 1}",
          'item' => it[:url] || it['url'] || "#{p[:url]}/step-#{idx + 1}"
        }
      end

      {
        '@context' => 'https://schema.org',
        '@type' => 'BreadcrumbList',
        'itemListElement' => item_list
      }
    end

    def build_course(p)
      name = p[:name] || p['name'] || p[:headline] || 'Comprehensive Online Course'
      desc = p[:description] || p['description'] || "Complete course on #{name}."
      provider = p[:brand] || p[:provider] || 'Academy'

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'Course',
        'name' => name,
        'description' => desc,
        'provider' => {
          '@type' => 'Organization',
          'name' => provider,
          'sameAs' => p[:url] || ''
        }
      }

      if p[:price]
        schema['offers'] = {
          '@type' => 'Offer',
          'category' => 'Paid',
          'price' => (p[:price] || 0.0).to_f.round(2).to_s,
          'priceCurrency' => p[:currency] || 'USD'
        }
      end

      schema
    end

    def build_job_posting(p)
      title = p[:title] || p[:name] || 'Technical Specialist'
      desc = p[:description] || "Exciting opportunity for #{title}."
      hiring_org = p[:brand] || p[:hiring_organization] || 'Company'
      date_posted = p[:date_posted] || Time.now.strftime('%Y-%m-%d')
      valid_through = (Time.now + (90 * 24 * 3600)).strftime('%Y-%m-%d')

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'JobPosting',
        'title' => title,
        'description' => desc,
        'datePosted' => date_posted,
        'validThrough' => valid_through,
        'employmentType' => p[:employment_type] || 'FULL_TIME',
        'hiringOrganization' => {
          '@type' => 'Organization',
          'name' => hiring_org,
          'sameAs' => p[:url] || ''
        },
        'jobLocation' => {
          '@type' => 'Place',
          'address' => {
            '@type' => 'PostalAddress',
            'addressCountry' => 'US'
          }
        }
      }

      if p[:price] || p[:salary]
        schema['baseSalary'] = {
          '@type' => 'MonetaryAmount',
          'currency' => p[:currency] || 'USD',
          'value' => {
            '@type' => 'QuantitativeValue',
            'value' => (p[:price] || p[:salary]).to_f,
            'unitText' => 'YEAR'
          }
        }
      end

      schema
    end

    def build_event(p)
      name = p[:name] || p['name'] || 'Featured Event & Workshop'
      desc = p[:description] || p['description'] || "#{name} overview."
      start_date = p[:start_date] || (Time.now + (14 * 24 * 3600)).strftime('%Y-%m-%dT09:00:00Z')
      end_date = p[:end_date] || (Time.now + (14 * 24 * 3600) + 28800).strftime('%Y-%m-%dT17:00:00Z')

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'Event',
        'name' => name,
        'description' => desc,
        'startDate' => start_date,
        'endDate' => end_date,
        'eventAttendanceMode' => 'https://schema.org/OnlineEventAttendanceMode',
        'eventStatus' => 'https://schema.org/EventScheduled',
        'location' => {
          '@type' => 'VirtualLocation',
          'url' => p[:url] || 'https://example.com/webinar'
        },
        'organizer' => {
          '@type' => 'Organization',
          'name' => p[:brand] || 'Event Organizer',
          'url' => p[:url] || ''
        }
      }

      if p[:price]
        schema['offers'] = {
          '@type' => 'Offer',
          'url' => p[:url] || '',
          'price' => (p[:price] || 0.0).to_f.round(2).to_s,
          'priceCurrency' => p[:currency] || 'USD',
          'availability' => 'https://schema.org/InStock'
        }
      end

      schema
    end

    def build_video(p)
      name = p[:name] || p['name'] || p[:headline] || 'Product Demo & Walkthrough'
      desc = p[:description] || p['description'] || "#{name} video overview."
      thumb = p[:image] || p[:thumbnail] || 'https://example.com/thumbnail.jpg'

      {
        '@context' => 'https://schema.org',
        '@type' => 'VideoObject',
        'name' => name,
        'description' => desc,
        'thumbnailUrl' => [thumb],
        'uploadDate' => p[:upload_date] || Time.now.strftime('%Y-%m-%d'),
        'contentUrl' => p[:url] || 'https://example.com/video.mp4'
      }
    end

    def build_recipe(p)
      name = p[:name] || p['name'] || 'Classic Recipe'
      desc = p[:description] || p['description'] || "#{name} step-by-step recipe."
      image = p[:image] || 'https://example.com/recipe.jpg'

      {
        '@context' => 'https://schema.org',
        '@type' => 'Recipe',
        'name' => name,
        'description' => desc,
        'image' => [image],
        'recipeIngredient' => p[:ingredients] || ['1 cup ingredient A', '2 tbsp ingredient B'],
        'recipeInstructions' => [
          { '@type' => 'HowToStep', 'text' => 'Mix ingredients in a large bowl.' },
          { '@type' => 'HowToStep', 'text' => 'Cook for 15 minutes until golden brown.' }
        ]
      }
    end

    def build_organization(p)
      name = p[:name] || p['name'] || 'Organization Name'
      url = p[:url] || p['url'] || ''
      logo = p[:logo] || p['logo'] || (!url.empty? ? "#{url}/logo.png" : nil)

      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'Organization',
        'name' => name,
        'sameAs' => p[:same_as] || p['same_as'] || []
      }

      schema['url'] = url unless url.empty?
      schema['logo'] = logo if logo

      schema
    end

    def calculate_schema_score(errors, warnings)
      score = 100
      score -= (errors.size * 35)
      score -= (warnings.size * 10)
      [0, score].max
    end

    def extract_tag_content(html, tag)
      match = html.match(/<#{tag}[^>]*>(.*?)<\/#{tag}>/im)
      match ? strip_html(match[1]) : nil
    end

    def extract_meta_content(html, name_or_prop)
      pattern = /<meta[^>]+(?:name|property)=["']#{Regexp.escape(name_or_prop)}["'][^>]+content=["']([^"']*)["']/i
      alt_pattern = /<meta[^>]+content=["']([^"']*)["'][^>]+(?:name|property)=["']#{Regexp.escape(name_or_prop)}["']/i
      m = html.match(pattern) || html.match(alt_pattern)
      m ? strip_html(m[1]) : nil
    end

    def extract_first_h1(html)
      extract_tag_content(html, 'h1')
    end

    def extract_first_image(html, base_url)
      m = html.match(/<img[^>]+src=["']([^"']+)["']/i)
      return nil unless m
      src = m[1].strip
      return src if src =~ %r{^https?://}
      URI.join(base_url, src).to_s rescue src
    end
  end
end

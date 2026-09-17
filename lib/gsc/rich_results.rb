# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module GSC
  class RichResults
    attr_reader :options, :url, :content, :schemas

    def initialize(options = {})
      @options = options
    end

    def self.audit(target, options = {})
      new(options).audit(target)
    end

    def audit(target)
      @url, @content = load_content(target)
      @schemas = extract_schemas(@content)
      results = @schemas.map.with_index { |s, idx| validate_schema(s, idx) }
      synthesize_report(results)
    end

    private

    def load_content(target)
      target_str = target.to_s.strip
      if target_str.match?(%r{^https?://})
        uri = URI.parse(target_str)
        req = Net::HTTP::Get.new(uri)
        req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) gsc-cli/2.1'
        req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 8, read_timeout: 10) do |http|
          http.request(req)
        end
        [target_str, res.body.to_s.dup.force_encoding('UTF-8').scrub]
      elsif File.exist?(target_str)
        [target_str, File.read(target_str, encoding: 'UTF-8')]
      else
        [target_str.start_with?('http') ? target_str : 'direct-input', target_str]
      end
    rescue StandardError => e
      [target.to_s, "<!-- fetch error: #{e.message} -->"]
    end

    def extract_schemas(html_or_json)
      schemas = []

      # Case 1: Raw JSON input
      trimmed = html_or_json.strip
      if trimmed.start_with?('{', '[')
        begin
          parsed = JSON.parse(trimmed)
          return flatten_schemas(parsed)
        rescue JSON::ParserError
          # Fallback to HTML regex extraction
        end
      end

      # Case 2: Extract from <script type="application/ld+json">
      html_or_json.scan(%r{<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>}im) do |match|
        json_str = match[0].to_s.strip
        next if json_str.empty?

        begin
          parsed = JSON.parse(json_str)
          schemas.concat(flatten_schemas(parsed))
        rescue JSON::ParserError => e
          schemas << {
            '@type' => 'CorruptedJSONLD',
            '_parse_error' => e.message,
            '_raw' => json_str
          }
        end
      end

      schemas
    end

    def flatten_schemas(data)
      case data
      when Array
        data.flat_map { |item| flatten_schemas(item) }
      when Hash
        if data['@graph'].is_a?(Array)
          data['@graph'].flat_map { |item| flatten_schemas(item) }
        else
          [data]
        end
      else
        []
      end
    end

    def validate_schema(schema, idx)
      type = schema['@type'] || 'Unknown'
      errors = []
      warnings = []
      feature_name = nil

      if schema['_parse_error']
        return {
          index: idx + 1,
          type: 'SyntaxError',
          feature: 'Malformed JSON-LD',
          eligible: false,
          errors: ["JSON Syntax Error: #{schema['_parse_error']}"],
          warnings: [],
          raw: schema['_raw'],
          patch: nil
        }
      end

      case type
      when 'Product'
        feature_name = 'Merchant Product Rich Card'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "image"' unless schema['image']

        has_pricing = schema['offers'] || schema['review'] || schema['aggregateRating']
        errors << 'Must provide at least one of "offers", "review", or "aggregateRating"' unless has_pricing

        if schema['offers']
          offers = schema['offers'].is_a?(Array) ? schema['offers'].first : schema['offers']
          errors << 'Missing "offers.price" or "offers.lowPrice"' unless offers['price'] || offers['lowPrice']
          errors << 'Missing "offers.priceCurrency"' unless offers['priceCurrency']
          warnings << 'Missing "offers.availability" (e.g. InStock)' unless offers['availability']
          warnings << 'Missing "offers.priceValidUntil"' unless offers['priceValidUntil']
        end

        if schema['aggregateRating']
          ar = schema['aggregateRating']
          errors << 'Missing "aggregateRating.ratingValue"' unless ar['ratingValue']
          errors << 'Missing "aggregateRating.ratingCount" or "aggregateRating.reviewCount"' unless ar['ratingCount'] || ar['reviewCount']
        end

      when 'FAQPage'
        feature_name = 'Interactive FAQ Accordion'
        entities = schema['mainEntity']
        if !entities.is_a?(Array) || entities.empty?
          errors << 'FAQPage must contain a non-empty "mainEntity" array of Question objects'
        else
          entities.each_with_index do |q, q_idx|
            q_num = q_idx + 1
            errors << "Question ##{q_num} missing 'name'" unless q['name']
            if !q['acceptedAnswer'] || !q['acceptedAnswer']['text']
              errors << "Question ##{q_num} missing 'acceptedAnswer.text'"
            end
          end
        end

      when 'HowTo'
        feature_name = 'Step-by-Step Guided HowTo Carousel'
        errors << 'Missing "name"' unless schema['name']
        steps = schema['step']
        if !steps.is_a?(Array) || steps.empty?
          errors << 'HowTo must contain a non-empty "step" array'
        else
          steps.each_with_index do |s, s_idx|
            s_num = s_idx + 1
            errors << "Step ##{s_num} missing 'text' or 'name'" unless s['text'] || s['name']
          end
        end
        warnings << 'Missing "totalTime"' unless schema['totalTime']
        warnings << 'Missing "image"' unless schema['image']

      when 'Article', 'NewsArticle', 'BlogPosting'
        feature_name = 'Top Stories Carousel & Author Card'
        errors << 'Missing "headline"' unless schema['headline']
        errors << 'Missing "image"' unless schema['image']
        errors << 'Missing "datePublished"' unless schema['datePublished']
        errors << 'Missing "author"' unless schema['author']

        if schema['author']
          authors = schema['author'].is_a?(Array) ? schema['author'] : [schema['author']]
          authors.each do |a|
            if a.is_a?(Hash)
              warnings << 'Author missing "url" (E-E-A-T profile link)' unless a['url']
            end
          end
        end
        warnings << 'Missing "dateModified"' unless schema['dateModified']
        warnings << 'Missing "publisher" with logo' unless schema['publisher']

      when 'SoftwareApplication', 'WebApplication', 'MobileApplication'
        feature_name = 'Software Application Rich Snippet'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "operatingSystem"' unless schema['operatingSystem']
        errors << 'Missing "applicationCategory"' unless schema['applicationCategory']
        errors << 'Missing "offers"' unless schema['offers']
        warnings << 'Missing "aggregateRating"' unless schema['aggregateRating']

      when 'LocalBusiness', 'Store', 'Restaurant', 'MedicalBusiness'
        feature_name = 'Local 3-Pack & Knowledge Graph Card'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "address"' unless schema['address']
        errors << 'Missing "telephone"' unless schema['telephone']
        warnings << 'Missing "openingHoursSpecification"' unless schema['openingHoursSpecification'] || schema['openingHours']
        warnings << 'Missing "geo" coordinates (latitude/longitude)' unless schema['geo']

      when 'BreadcrumbList'
        feature_name = 'Interactive Breadcrumb Path'
        items = schema['itemListElement']
        if !items.is_a?(Array) || items.empty?
          errors << 'BreadcrumbList must contain "itemListElement" array'
        else
          items.each_with_index do |it, i_idx|
            errors << "Breadcrumb ##{i_idx + 1} missing 'position'" unless it['position']
            errors << "Breadcrumb ##{i_idx + 1} missing 'name'" unless it['name']
            errors << "Breadcrumb ##{i_idx + 1} missing 'item'" unless it['item']
          end
        end

      when 'Recipe'
        feature_name = 'Recipe Rich Card with Cooking Specs'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "image"' unless schema['image']
        errors << 'Missing "recipeIngredient"' unless schema['recipeIngredient']
        errors << 'Missing "recipeInstructions"' unless schema['recipeInstructions']
        warnings << 'Missing "cookTime"' unless schema['cookTime']
        warnings << 'Missing "aggregateRating"' unless schema['aggregateRating']

      when 'VideoObject'
        feature_name = 'Video SERP Thumbnail & Key Moments'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "description"' unless schema['description']
        errors << 'Missing "thumbnailUrl"' unless schema['thumbnailUrl']
        errors << 'Missing "uploadDate"' unless schema['uploadDate']

      when 'Course'
        feature_name = 'Course Listing Rich Carousel'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "description"' unless schema['description']
        errors << 'Missing "provider"' unless schema['provider']

      when 'JobPosting'
        feature_name = 'Google for Jobs Interactive Listing'
        errors << 'Missing "title"' unless schema['title']
        errors << 'Missing "description"' unless schema['description']
        errors << 'Missing "datePosted"' unless schema['datePosted']
        errors << 'Missing "hiringOrganization"' unless schema['hiringOrganization']

      when 'Event'
        feature_name = 'Event SERP Listing & Tickets'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "startDate"' unless schema['startDate']
        errors << 'Missing "location"' unless schema['location']

      when 'Review', 'AggregateRating'
        feature_name = 'Star Rating Snippet'
        errors << 'Missing "ratingValue"' unless schema['ratingValue']
        warnings << 'Missing "bestRating" (defaults to 5)' unless schema['bestRating']

      else
        feature_name = "Schema.org #{type}"
        warnings << "Generic schema type '#{type}' does not trigger a dedicated Google Rich Result"
      end

      eligible = errors.empty? && !feature_name.start_with?('Schema.org')

      patch = generate_patch(schema, errors, warnings)

      {
        index: idx + 1,
        type: type,
        feature: feature_name,
        eligible: eligible,
        errors: errors,
        warnings: warnings,
        raw: schema,
        patch: patch
      }
    end

    def generate_patch(schema, errors, warnings)
      return nil if errors.empty? && warnings.empty?

      patched = schema.dup
      type = patched['@type']

      case type
      when 'Product'
        product_url = @url.to_s.start_with?('http') ? @url : nil
        patched['image'] ||= [product_url ? "#{product_url.sub(%r{/$}, '')}/product.jpg" : 'https://schema.org/ProductImage']
        if !patched['offers'] && !patched['aggregateRating']
          patched['offers'] = {
            '@type' => 'Offer',
            'price' => '49.99',
            'priceCurrency' => 'USD',
            'priceValidUntil' => (Time.now + (365 * 86400)).strftime('%Y-%m-%d'),
            'availability' => 'https://schema.org/InStock',
            'url' => product_url || ''
          }
        end
        if patched['offers'].is_a?(Hash)
          patched['offers']['priceValidUntil'] ||= (Time.now + (365 * 86400)).strftime('%Y-%m-%d')
          patched['offers']['availability'] ||= 'https://schema.org/InStock'
        end

      when 'Article', 'BlogPosting'
        base_url = @url.to_s.start_with?('http') ? @url : nil
        patched['datePublished'] ||= Time.now.strftime('%Y-%m-%dT%H:%M:%S%:z')
        patched['dateModified']  ||= Time.now.strftime('%Y-%m-%dT%H:%M:%S%:z')
        patched['image'] ||= [base_url ? "#{base_url.sub(%r{/$}, '')}/featured.jpg" : 'https://schema.org/ArticleImage']
        if !patched['author']
          author_url = base_url ? "#{base_url.sub(%r{/$}, '')}/author" : ''
          patched['author'] = {
            '@type' => 'Person',
            'name' => 'Author',
            'url' => author_url
          }
        end

      when 'FAQPage'
        if !patched['mainEntity'].is_a?(Array) || patched['mainEntity'].empty?
          patched['mainEntity'] = [
            {
              '@type' => 'Question',
              'name' => 'Question?',
              'acceptedAnswer' => {
                '@type' => 'Answer',
                'text' => 'Answer.'
              }
            }
          ]
        end
      end

      patched
    end

    def synthesize_report(results)
      total = results.size
      eligible_count = results.count { |r| r[:eligible] }
      total_errors = results.sum { |r| r[:errors].size }
      total_warnings = results.sum { |r| r[:warnings].size }

      # Duplicate detection across same entity types
      types = results.map { |r| r[:type] }
      duplicates = types.select { |t| types.count(t) > 1 }.uniq
      if duplicates.any?
        duplicates.each do |dup_type|
          results.each do |r|
            if r[:type] == dup_type
              r[:warnings] << "Duplicate '#{dup_type}' schema detected on page. Google advises consolidating duplicate entities into a single JSON-LD block."
            end
          end
        end
        total_warnings = results.sum { |r| r[:warnings].size }
      end

      # Score calculation
      score = if total == 0
                0
              else
                raw = (eligible_count.to_f / total) * 70 + [30 - (total_errors * 10) - (total_warnings * 2), 0].max
                [[raw.round, 100].min, 0].max
              end

      grade = case score
              when 95..100 then 'A+'
              when 85..94  then 'A'
              when 70..84  then 'B'
              when 50..69  then 'C'
              else 'F'
              end

      eligible_features = results.select { |r| r[:eligible] }.map { |r| r[:feature] }.uniq

      {
        url: @url,
        total_schemas_detected: total,
        eligible_for_rich_results: eligible_count > 0,
        eligible_features: eligible_features,
        score: score,
        grade: grade,
        critical_errors_count: total_errors,
        warnings_count: total_warnings,
        duplicate_types: duplicates,
        schemas: results
      }
    end
  end
end

# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'schema_generator'

module GSC
  class SchemaValidator
    attr_reader :url, :schemas, :validation_results

    AVAILABLE_TEMPLATES = [
      { type: 'faq',           name: 'FAQPage',             feature: 'Interactive FAQ Accordion Drop-down' },
      { type: 'product',       name: 'Product',             feature: 'Merchant Rich Card, Star Ratings & Prices' },
      { type: 'software',      name: 'SoftwareApplication', feature: 'App Card, OS Badge, Pricing & Rating' },
      { type: 'breadcrumb',    name: 'BreadcrumbList',      feature: 'Hierarchical SERP Navigation Path' },
      { type: 'article',       name: 'Article',             feature: 'Google Top Stories Carousel & Author E-E-A-T' },
      { type: 'howto',         name: 'HowTo',               feature: 'Step-by-Step Guided Instructions' },
      { type: 'course',        name: 'Course',              feature: 'Course Carousel & Provider Card' },
      { type: 'job',           name: 'JobPosting',          feature: 'Google for Jobs Interactive Listing' },
      { type: 'event',         name: 'Event',               feature: 'Event Schedule, Venue & Ticket Offers' },
      { type: 'localbusiness', name: 'LocalBusiness',       feature: 'Google Maps & Local 3-Pack with Hours/Phone' },
      { type: 'video',         name: 'VideoObject',         feature: 'Video SERP Thumbnail & Key Moments' },
      { type: 'recipe',        name: 'Recipe',              feature: 'Recipe Card with Cook Time & Nutrition' },
      { type: 'organization',  name: 'Organization',        feature: 'Brand Knowledge Graph Panel & Logo' }
    ].freeze

    def initialize(url)
      @url = url.to_s.strip
    end

    def audit
      pa = GSC::PageAnalyzer.new(@url)
      data = pa.fetch_and_analyze
      raw_schemas = data[:schema] || data.dig(:structured_data, :schemas) || []
      @schemas = self.class.flatten_schemas(raw_schemas)

      results = []
      @schemas.each_with_index do |schema, idx|
        results << validate_single_schema(schema, idx)
      end

      {
        url: @url,
        total_schemas: @schemas.length,
        schemas: results
      }
    end

    def self.flatten_schemas(items)
      return [] unless items.is_a?(Array)
      items.flat_map do |item|
        target = item.is_a?(Hash) && (item[:data] || item['data']) ? (item[:data] || item['data']) : item
        if target.is_a?(Hash) && target['@graph'].is_a?(Array)
          flatten_schemas(target['@graph'])
        elsif target.is_a?(Array)
          flatten_schemas(target)
        elsif target.is_a?(Hash)
          [target]
        else
          []
        end
      end
    end

    def validate_single_schema(schema, idx)
      type = schema['@type'] || 'Unknown'
      errors = []
      warnings = []

      case type
      when 'SoftwareApplication', 'WebApplication'
        errors << 'Missing "name"' unless schema['name']
        warnings << 'Missing "operatingSystem"' unless schema['operatingSystem']
        warnings << 'Missing "applicationCategory"' unless schema['applicationCategory']
        warnings << 'Missing "offers"' unless schema['offers']
        warnings << 'Missing "aggregateRating"' unless schema['aggregateRating']

      when 'FAQPage'
        main_entity = schema['mainEntity']
        if !main_entity || !main_entity.is_a?(Array) || main_entity.empty?
          errors << 'FAQPage must contain a non-empty "mainEntity" array'
        else
          main_entity.each_with_index do |q, q_idx|
            errors << "Question ##{q_idx + 1} missing name" unless q['name']
            errors << "Question ##{q_idx + 1} missing acceptedAnswer" unless q['acceptedAnswer']
          end
        end

      when 'Product'
        errors << 'Missing "name"' unless schema['name']
        warnings << 'Missing "image"' unless schema['image']
        warnings << 'Missing "offers"' unless schema['offers']

      when 'Article', 'BlogPosting'
        errors << 'Missing "headline"' unless schema['headline']
        errors << 'Missing "author"' unless schema['author']
        warnings << 'Missing "datePublished"' unless schema['datePublished']
        warnings << 'Missing "image"' unless schema['image']

      when 'Organization', 'LocalBusiness'
        errors << 'Missing "name"' unless schema['name']
        errors << 'Missing "url"' unless schema['url']
        warnings << 'Missing "logo"' unless schema['logo']
      end

      {
        index: idx,
        type: type,
        valid: errors.empty?,
        errors: errors,
        warnings: warnings,
        raw: schema
      }
    end

    def self.generate_template(type, params = {})
      GSC::SchemaGenerator.new.generate(type, params)[:schema]
    end
  end
end

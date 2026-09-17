# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module GSC
  class EntityAuditor
    ENTITY_TYPES = %w[
      Organization Brand Corporation SoftwareApplication WebApplication
      Person LocalBusiness MedicalOrganization EducationalOrganization WebSite
    ].freeze

    HIGH_AUTHORITY_SAMEAS = {
      wikidata: /wikidata\.org\/wiki\/Q\d+/i,
      wikipedia: /wikipedia\.org\/wiki\//i,
      crunchbase: /crunchbase\.com\/(organization|person)\//i,
      linkedin: /linkedin\.com\/(company|in|school)\//i,
      github: /github\.com\//i,
      twitter: /(twitter|x)\.com\//i,
      youtube: /youtube\.com\/(channel|@)/i,
      trustpilot: /trustpilot\.com\/review\//i,
      google_knowledge_graph: /google\.com\/search\?.*kgmid/i
    }.freeze

    def self.audit(url, custom_html: nil)
      html = custom_html || fetch_html(url)
      return { error: 'Failed to retrieve HTML', score: 0 } unless html

      schemas = extract_json_ld(html)
      entities = find_entities(schemas)

      score = 0
      findings = []
      recommendations = []
      same_as_urls = []
      authoritative_links = {}

      if entities.empty?
        recommendations << 'Add an @type: Organization or Brand JSON-LD schema block to anchor your entity in LLM knowledge graphs.'
      else
        score += 25
        findings << "Detected #{entities.size} Knowledge Graph entity node(s): #{entities.map { |e| e['@type'] }.uniq.join(', ')}"

        # Analyze primary entity
        primary = entities.find { |e| %w[Organization Corporation Brand SoftwareApplication].include?(e['@type']) } || entities.first

        # Name check
        if primary['name'] || primary['legalName']
          score += 15
          findings << "Entity Name: \"#{primary['name'] || primary['legalName']}\""
        else
          recommendations << 'Specify explicit "name" and "legalName" in Organization schema.'
        end

        # URL check
        if primary['url']
          score += 10
          findings << "Canonical URL: #{primary['url']}"
        else
          recommendations << 'Add canonical "url" to Organization schema.'
        end

        # Logo / Image check
        if primary['logo'] || primary['image']
          score += 10
          findings << 'Branding asset (logo/image) is defined.'
        else
          recommendations << 'Add "logo" URL to enhance visual entity search and AI overview previews.'
        end

        # Description
        if primary['description'] && primary['description'].to_s.length >= 20
          score += 10
          findings << 'Entity description is defined (>= 20 characters).'
        else
          recommendations << 'Add a detailed "description" (40-80 words) summarizing core business category and value prop.'
        end

        # sameAs Analysis (Crucial for AI / LLM disambiguation)
        raw_same_as = Array(primary['sameAs']).map(&:to_s).reject(&:empty?)
        same_as_urls = raw_same_as

        if raw_same_as.empty?
          recommendations << 'CRITICAL FOR AI: Add "sameAs" array linking your Wikidata, Wikipedia, LinkedIn, Crunchbase, and official social profiles.'
        else
          score += 15
          findings << "Found #{raw_same_as.size} sameAs identity URL(s)."

          HIGH_AUTHORITY_SAMEAS.each do |source, pattern|
            match = raw_same_as.find { |u| u =~ pattern }
            if match
              authoritative_links[source] = match
            end
          end

          if authoritative_links[:wikidata] || authoritative_links[:wikipedia]
            score += 15
            findings << "Strong Entity Anchor: Verified Wikipedia/Wikidata link (#{authoritative_links[:wikidata] || authoritative_links[:wikipedia]})."
          else
            recommendations << 'Add Wikidata or Wikipedia link to sameAs for definitive Google Knowledge Graph & LLM disambiguation.'
          end

          if authoritative_links[:linkedin] || authoritative_links[:crunchbase]
            findings << "Corporate Validation: Linked #{authoritative_links.keys.map(&:to_s).join(', ')}."
          end
        end

        # knowsAbout / topic authority
        if primary['knowsAbout']
          score += 5
          findings << "Topic authority defined via knowsAbout: #{Array(primary['knowsAbout']).first(3).join(', ')}"
        end
      end

      score = [score, 100].min

      grade = case score
              when 90..100 then 'A'
              when 75..89  then 'B'
              when 50..74  then 'C'
              when 30..49  then 'D'
              else 'F'
              end

      recommended_schema = generate_template(url, entities.first)

      {
        url: url,
        score: score,
        grade: grade,
        entities_found: entities.size,
        entities: entities,
        same_as_urls: same_as_urls,
        authoritative_links: authoritative_links,
        findings: findings,
        recommendations: recommendations,
        recommended_json_ld: recommended_schema
      }
    end

    def self.extract_json_ld(html)
      schemas = []
      html.scan(/<script[^>]*type=["']application\/ld\+json["'][^>]*>(.*?)<\/script>/m) do |match|
        content = match[0].to_s.strip
        parsed = JSON.parse(content) rescue nil
        if parsed.is_a?(Array)
          schemas.concat(parsed)
        elsif parsed.is_a?(Hash)
          if parsed['@graph'].is_a?(Array)
            schemas.concat(parsed['@graph'])
          else
            schemas << parsed
          end
        end
      end
      schemas
    end

    def self.find_entities(schemas)
      entities = []
      schemas.each do |s|
        next unless s.is_a?(Hash)

        type = s['@type']
        if type.is_a?(Array)
          entities << s if (type & ENTITY_TYPES).any?
        elsif ENTITY_TYPES.include?(type.to_s)
          entities << s
        end

        # Check nested entity attributes
        %w[publisher author brand organization].each do |k|
          nested = s[k]
          if nested.is_a?(Hash) && ENTITY_TYPES.include?(nested['@type'].to_s)
            entities << nested
          end
        end
      end
      entities.uniq { |e| "#{e['@type']}_#{e['name']}" }
    end

    def self.generate_template(url, existing = nil)
      uri = URI.parse(url) rescue nil
      host = uri&.host ? uri.host.sub(/^www\./, '') : url.to_s.sub(%r{^https?://}, '').sub(%r{/.*$}, '')
      host = 'organization' if host.empty?
      name = existing && existing['name'] ? existing['name'] : host.split('.').first.capitalize

      {
        '@context' => 'https://schema.org',
        '@type' => 'Organization',
        'name' => name,
        'url' => uri ? "#{uri.scheme}://#{uri.host}" : "https://#{host}",
        'logo' => uri ? "#{uri.scheme}://#{uri.host}/logo.png" : "https://#{host}/logo.png",
        'description' => "#{name} official organization entity.",
        'sameAs' => [
          "https://www.linkedin.com/company/#{name.downcase}",
          "https://twitter.com/#{name.downcase}",
          "https://github.com/#{name.downcase}",
          "https://www.crunchbase.com/organization/#{name.downcase}"
        ]
      }
    end

    def self.fetch_html(url)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = 'Mozilla/5.0 (compatible; GSC-CLI-EntityAuditor/2.1.1; +https://github.com)'
      req['Accept'] = 'text/html,application/xhtml+xml'

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 8
      http.read_timeout = 10

      res = http.request(req)
      return nil unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)

      if res.is_a?(Net::HTTPRedirection) && res['location']
        new_url = URI.join(url, res['location']).to_s
        return fetch_html(new_url)
      end

      res.body.to_s.dup.force_encoding('UTF-8').scrub
    rescue StandardError
      nil
    end
  end
end

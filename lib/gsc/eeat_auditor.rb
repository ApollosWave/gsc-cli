# encoding: utf-8
# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'time'

module GSC
  class EeatAuditor
    CREDENTIAL_PATTERNS = %r{\b(?:MD|PhD|DO|PharmD|RN|CPA|Esq|JD|MBA|MS|MA|BSc|PE|PMP|CTO|CEO|Founder|Lead Architect|Senior Editor|Staff Writer|Medical Director|Specialist|Fellow)\b}i
    REVIEWER_PATTERNS   = %r{\b(?:reviewed by|medically reviewed by|fact-checked by|fact checked by|edited by|scientifically verified by|legal review by)\b}i
    DISCLOSURE_PATTERNS = %r{\b(?:editorial guidelines|editorial policy|conflict of interest|affiliate disclosure|corrections policy|code of ethics)\b}i

    attr_reader :options, :url, :html

    def initialize(options = {})
      @options = options
    end

    def self.audit(target, options = {})
      new(options).audit(target)
    end

    def audit(target)
      @url, @html = load_content(target)
      signals = extract_signals(@html, @url)
      evaluate_health(signals)
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
        [target_str.start_with?('http') ? target_str : 'local-document', target_str]
      end
    rescue StandardError => e
      [target_str.to_s, "<html><body><!-- Error: #{e.message} --></body></html>"]
    end

    def extract_signals(html_str, base_url)
      json_ld_schemas = extract_json_ld(html_str)
      article_schema = find_article_schema(json_ld_schemas)
      person_schema  = find_person_schema(json_ld_schemas, article_schema)

      # 1. Author Identification
      dom_author = extract_dom_author(html_str)
      author_name = person_schema&.dig('name') || dom_author[:name]
      has_author_byline = !author_name.nil? && !author_name.strip.empty?
      has_author_url = !person_schema&.dig('url').nil? || dom_author[:url]

      # 2. Author Bio & Credentials
      bio_snippet = person_schema&.dig('description') || dom_author[:bio]
      credentials = []
      credentials += author_name.scan(CREDENTIAL_PATTERNS).flatten if author_name
      credentials += bio_snippet.scan(CREDENTIAL_PATTERNS).flatten if bio_snippet
      credentials += person_schema['jobTitle'].scan(CREDENTIAL_PATTERNS).flatten if person_schema && person_schema['jobTitle']
      credentials.uniq!

      # 3. Entity Disambiguation & Social Profiles (sameAs)
      same_as = Array(person_schema&.dig('sameAs'))
      dom_social_links = extract_author_social_links(html_str)
      all_social_links = (same_as + dom_social_links).uniq

      has_linkedin = all_social_links.any? { |l| l.include?('linkedin.com') }
      has_twitter  = all_social_links.any? { |l| l.include?('twitter.com') || l.include?('x.com') }
      has_wiki     = all_social_links.any? { |l| l.include?('wikipedia.org') || l.include?('wikidata.org') }
      has_scholar  = all_social_links.any? { |l| l.include?('scholar.google.com') || l.include?('orcid.org') }

      # 4. Editorial Review Signals
      reviewed_by = article_schema&.dig('reviewedBy')
      reviewer_name = if reviewed_by.is_a?(Hash)
                        reviewed_by['name']
                      elsif reviewed_by.is_a?(String)
                        reviewed_by
                      else
                        extract_dom_reviewer(html_str)
                      end
      has_reviewer = !reviewer_name.nil? && !reviewer_name.strip.empty?

      # 5. Temporal Freshness Dates
      date_published = article_schema&.dig('datePublished') || extract_dom_meta(html_str, 'article:published_time')
      date_modified  = article_schema&.dig('dateModified')  || extract_dom_meta(html_str, 'article:modified_time')

      # 6. Authoritative Outbound Sources (.gov, .edu, doi.org, PubMed)
      authoritative_citations = extract_authoritative_citations(html_str)

      # 7. Editorial Transparency & Disclosures
      has_disclosure = html_str.match?(DISCLOSURE_PATTERNS)

      {
        author_name: author_name,
        has_author_byline: has_author_byline,
        has_author_url: has_author_url,
        bio_snippet: bio_snippet,
        credentials: credentials,
        person_schema: person_schema,
        article_schema: article_schema,
        social_profiles: all_social_links,
        has_linkedin: has_linkedin,
        has_twitter: has_twitter,
        has_wiki: has_wiki,
        has_scholar: has_scholar,
        reviewer_name: reviewer_name,
        has_reviewer: has_reviewer,
        date_published: date_published,
        date_modified: date_modified,
        citations: authoritative_citations,
        has_disclosure: has_disclosure
      }
    end

    def extract_json_ld(html_str)
      schemas = []
      html_str.scan(/<script\b[^>]*?type=["']application\/ld\+json["'][^>]*?>(.*?)<\/script>/im) do |match|
        content = match.first.strip
        begin
          parsed = JSON.parse(content)
          if parsed.is_a?(Array)
            schemas.concat(parsed)
          elsif parsed.is_a?(Hash)
            if parsed['@graph'].is_a?(Array)
              schemas.concat(parsed['@graph'])
            else
              schemas << parsed
            end
          end
        rescue StandardError
          # Non-JSON or malformed
        end
      end
      schemas
    end

    def find_article_schema(schemas)
      article_types = %w[Article NewsArticle BlogPosting TechArticle ScholarlyArticle MedicalWebPage WebPage]
      schemas.find do |s|
        type = s['@type']
        if type.is_a?(Array)
          (type & article_types).any?
        else
          article_types.include?(type)
        end
      end
    end

    def find_person_schema(schemas, article_schema)
      if article_schema && article_schema['author']
        auth = article_schema['author']
        return auth if auth.is_a?(Hash) && auth['@type'] == 'Person'
        return auth.first if auth.is_a?(Array) && auth.first.is_a?(Hash)
      end

      schemas.find { |s| s['@type'] == 'Person' || s['@type'] == 'ProfilePage' }
    end

    def extract_dom_author(html_str)
      name = nil
      url = nil
      bio = nil

      # Meta tag author
      if html_str =~ /<meta\b[^>]*?name=["']author["'][^>]*?content=["'](.*?)["']/im
        name = $1.strip
      elsif html_str =~ /<meta\b[^>]*?property=["']article:author["'][^>]*?content=["'](.*?)["']/im
        name = $1.strip
      end

      # DOM rel="author" link
      if html_str =~ /<a\b[^>]*?rel=["'][^"']*?\bauthor\b[^"']*?["'][^>]*?href=["'](.*?)["'][^>]*?>(.*?)<\/a>/im
        url = $1.strip
        name ||= strip_tags($2).strip
      end

      # Author bio container check
      if html_str =~ /<div\b[^>]*?(?:class|id)=["'][^"']*?(?:author-bio|author-description|biography|about-author)[^"']*?["'][^>]*?>(.*?)<\/div>/im
        bio = strip_tags($1).strip
      end

      { name: name, url: url, bio: bio }
    end

    def extract_dom_reviewer(html_str)
      if html_str =~ REVIEWER_PATTERNS
        match_idx = $~.end(0)
        snippet = html_str[match_idx, 120]
        if snippet =~ /^\s*<(?:a|span|strong|b)[^>]*?>(.*?)<\/(?:a|span|strong|b)>/im
          return strip_tags($1).strip
        elsif snippet =~ /^\s*([^<\n\r]+)/im
          clean = strip_tags($1).strip.sub(/[,.]+$/, '')
          return clean unless clean.empty?
        end
      end
      nil
    end

    def extract_dom_meta(html_str, prop_name)
      if html_str =~ /<meta\b[^>]*?(?:property|name)=["']#{prop_name}["'][^>]*?content=["'](.*?)["']/im
        $1.strip
      else
        nil
      end
    end

    def extract_author_social_links(html_str)
      links = []
      patterns = [
        %r{https?://(?:www\.)?linkedin\.com/in/[a-zA-Z0-9_-]+},
        %r{https?://(?:www\.)?(?:twitter|x)\.com/[a-zA-Z0-9_]+},
        %r{https?://(?:en\.)?wikipedia\.org/wiki/[a-zA-Z0-9_%-]+},
        %r{https?://scholar\.google\.com/citations\?[a-zA-Z0-9_=&-]+},
        %r{https?://orcid\.org/[0-9-]+}
      ]

      patterns.each do |pat|
        html_str.scan(pat) { |m| links << m }
      end

      links.uniq
    end

    def extract_authoritative_citations(html_str)
      cites = []
      html_str.scan(/<a\b[^>]*?href=["'](https?:\/\/[^"']+)["'][^>]*?>/im) do |match|
        href = match.first
        if href =~ %r{https?://[^/]*?\.(?:gov|edu)(?:/|$)}i ||
           href =~ %r{https?://(?:www\.)?(?:doi\.org|ncbi\.nlm\.nih\.gov|pubmed\.ncbi\.nlm\.nih\.gov|nature\.com|sciencedirect\.com|wikipedia\.org)}i
          cites << href
        end
      end
      cites.uniq
    end

    def evaluate_health(s)
      score = 0.0
      issues = []

      # 1. Author Identification (20 pts)
      if s[:has_author_byline]
        score += 15.0
        score += 5.0 if s[:has_author_url]
      else
        issues << :missing_author_byline
      end

      # 2. Schema.org Person & Article Markup (20 pts)
      if s[:person_schema]
        score += 10.0
        score += 5.0 if s[:person_schema]['jobTitle']
        score += 5.0 if Array(s[:person_schema]['sameAs']).any?
      else
        issues << :missing_person_schema
      end

      # 3. Credentials & Expertise Proof (15 pts)
      if s[:credentials].any?
        score += 15.0
      elsif s[:bio_snippet] && s[:bio_snippet].length > 60
        score += 10.0
      else
        issues << :missing_credentials_or_bio
      end

      # 4. Social & External Entity Disambiguation (15 pts)
      if s[:has_linkedin] || s[:has_wiki] || s[:has_scholar]
        score += 15.0
      elsif s[:has_twitter]
        score += 10.0
      else
        issues << :missing_social_proof
      end

      # 5. Editorial Review / Fact-Check Verification (10 pts)
      if s[:has_reviewer]
        score += 10.0
      else
        issues << :missing_editorial_review
      end

      # 6. Temporal Freshness / Dates (10 pts)
      if s[:date_published] && s[:date_modified]
        score += 10.0
      elsif s[:date_published] || s[:date_modified]
        score += 5.0
        issues << :missing_date_modified
      else
        issues << :missing_dates
      end

      # 7. Authoritative External Citations (5 pts)
      if s[:citations].any?
        score += 5.0
      else
        issues << :no_authoritative_citations
      end

      # 8. Editorial Policy & Disclosures (5 pts)
      if s[:has_disclosure]
        score += 5.0
      else
        issues << :missing_editorial_disclosure
      end

      score = [[score.round(1), 100.0].min, 0.0].max
      grade = compute_grade(score)

      prescriptions = generate_prescriptions(s, issues)
      snippet = generate_eeat_schema(s, @url)

      {
        url: @url,
        health_score: score,
        grade: grade,
        author_name: s[:author_name],
        credentials: s[:credentials],
        reviewer_name: s[:reviewer_name],
        date_published: s[:date_published],
        date_modified: s[:date_modified],
        social_profiles: s[:social_profiles],
        citations_count: s[:citations].size,
        issues: issues,
        prescriptions: prescriptions,
        schema_fix_snippet: snippet
      }
    end

    def generate_prescriptions(s, issues)
      recs = []

      if issues.include?(:missing_author_byline)
        recs << "Add an explicit author byline and biographical link to attribute content to a named human subject matter expert."
      end

      if issues.include?(:missing_person_schema)
        recs << "Inject Schema.org Person JSON-LD into the page <head> specifying author name, jobTitle, worksFor, and sameAs profiles."
      end

      if issues.include?(:missing_credentials_or_bio)
        recs << "State the author's verifiable professional credentials (e.g., MD, CPA, Lead Architect, PhD) and practical industry experience in an author bio box."
      end

      if issues.include?(:missing_social_proof)
        recs << "Add outgoing links to the author's authoritative profiles (LinkedIn, Wikipedia, or Google Scholar) to establish entity authority in Google's Knowledge Graph."
      end

      if issues.include?(:missing_editorial_review)
        recs << "Include a secondary reviewer or fact-checker byline (and schema 'reviewedBy') to fulfill Google's YMYL (Your Money or Your Life) standards."
      end

      if issues.include?(:missing_dates) || issues.include?(:missing_date_modified)
        recs << "Expose clear datePublished and dateModified timestamps in both DOM and schema to signal content freshness."
      end

      if issues.include?(:no_authoritative_citations)
        recs << "Add 1–3 outbound citations to peer-reviewed studies, government (.gov), or academic (.edu) sources to anchor factual assertions."
      end

      recs
    end

    def generate_eeat_schema(s, page_url)
      auth_name = s[:author_name] || "Expert Author"
      job_title = s[:credentials].first ? "#{s[:credentials].first} & Subject Matter Expert" : "Subject Matter Expert"
      same_as_json = s[:social_profiles].any? ? JSON.generate(s[:social_profiles]) : "[\"https://www.linkedin.com/in/author-profile\"]"

      pub_date = s[:date_published] || Time.now.strftime("%Y-%m-%d")
      mod_date = s[:date_modified]  || Time.now.strftime("%Y-%m-%d")

      reviewer_block = if s[:reviewer_name]
                         <<~JSON.strip
                           ,
                           "reviewedBy": {
                             "@type": "Person",
                             "name": "#{s[:reviewer_name]}",
                             "jobTitle": "Editorial & Fact-Checking Lead"
                           }
                         JSON
                       else
                         ""
                       end

      <<~JSON.strip
        {
          "@context": "https://schema.org",
          "@type": "Article",
          "mainEntityOfPage": "#{page_url}",
          "headline": "Article Headline Here",
          "datePublished": "#{pub_date}",
          "dateModified": "#{mod_date}",
          "author": {
            "@type": "Person",
            "name": "#{auth_name}",
            "jobTitle": "#{job_title}",
            "sameAs": #{same_as_json}
          }#{reviewer_block}
        }
      JSON
    end

    def compute_grade(score)
      case score
      when 90.0..100.0 then 'A+'
      when 80.0...90.0 then 'A'
      when 70.0...80.0 then 'B'
      when 55.0...70.0 then 'C'
      when 40.0...55.0 then 'D'
      else 'F'
      end
    end

    def strip_tags(html)
      html.gsub(/<[^>]*>/, '').strip
    end
  end
end

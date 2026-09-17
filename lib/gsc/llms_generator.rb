# encoding: utf-8
# frozen_string_literal: true

require 'uri'
require 'net/http'
require 'time'
require 'fileutils'
require_relative 'sitemap_loader'
require_relative 'page_analyzer'

module GSC
  class LlmsGenerator
    attr_reader :base_url, :options

    def initialize(base_url, options = {})
      @base_url = base_url.to_s.strip
      @base_url = "https://#{@base_url}" unless @base_url =~ %r{^https?://}
      @options = options || {}
    end

    # Generate standard /llms.txt index file per specification
    def generate_llms_txt(title: nil, summary: nil, limit: 25)
      pages_meta = collect_pages_metadata(limit: limit)

      site_title = title || URI.parse(@base_url).host.sub(/^www\./, '').capitalize
      site_summary = summary || "Official developer documentation, guides, and knowledge base for #{site_title}."

      out = []
      out << "# #{site_title}"
      out << ""
      out << "> #{site_summary}"
      out << ""
      out << "## Core Documentation"
      out << ""

      core_pages = pages_meta.first(12)
      core_pages.each do |pm|
        out << "- [#{pm[:title]}](#{pm[:url]}): #{pm[:description]}"
      end

      optional_pages = pages_meta[12..-1] || []
      if optional_pages.any?
        out << ""
        out << "## Extended Guides & Articles"
        out << ""
        optional_pages.each do |pm|
          out << "- [#{pm[:title]}](#{pm[:url]}): #{pm[:description]}"
        end
      end

      out << ""
      out << "## Optional"
      out << ""
      out << "- [Full Consolidated Knowledge Base](#{@base_url}/llms-full.txt): Complete multi-page markdown knowledge bundle for LLM context ingestion."
      out << ""

      out.join("\n")
    end

    # Generate complete /llms-full.txt multi-page consolidated knowledge bundle
    def generate_llms_full_txt(title: nil, summary: nil, limit: 25, gsc_rows: nil)
      pages_meta = collect_pages_metadata(limit: limit)
      site_title = title || URI.parse(@base_url).host.sub(/^www\./, '').capitalize
      site_summary = summary || "Comprehensive knowledge base and technical specifications for #{site_title}."

      toc = []
      docs_content = []

      pages_meta.each_with_index do |pm, idx|
        section_id = "section-#{idx + 1}"
        toc << "#{idx + 1}. [#{pm[:title]}](##{section_id})"

        html = fetch_html(pm[:url])
        md_body = html_to_clean_markdown(html, pm[:url])

        # FAQ injection from GSC queries if available
        faq_block = generate_gsc_faq_block(pm[:url], gsc_rows)

        doc_section = []
        doc_section << "<a name=\"#{section_id}\"></a>"
        doc_section << "# #{pm[:title]}"
        doc_section << ""
        doc_section << "**Source URL**: #{pm[:url]}"
        doc_section << "**Description**: #{pm[:description]}"
        doc_section << ""
        doc_section << md_body
        doc_section << ""
        doc_section << faq_block if faq_block
        doc_section << ""
        doc_section << "---"
        doc_section << ""

        docs_content << doc_section.join("\n")
      end

      out = []
      out << "# #{site_title} — Full Knowledge Base (`/llms-full.txt`)"
      out << ""
      out << "> #{site_summary}"
      out << "> Generated automatically by Google Search Console CLI (`gsc llms --full`) on #{Time.now.strftime('%Y-%m-%d')}."
      out << ""
      out << "## Table of Contents"
      out << ""
      out << toc.join("\n")
      out << ""
      out << "---"
      out << ""
      out << docs_content.join("\n")

      out.join("\n")
    end

    # Package complete bundle (both llms.txt and llms-full.txt) with token analytics
    def package_agent_bundle(output_dir: nil, limit: 25, gsc_rows: nil)
      llms_txt = generate_llms_txt(limit: limit)
      llms_full_txt = generate_llms_full_txt(limit: limit, gsc_rows: gsc_rows)

      # Token estimation (standard 4 chars per token)
      txt_tokens = (llms_txt.length / 4.0).ceil
      full_tokens = (llms_full_txt.length / 4.0).ceil

      saved_files = []
      if output_dir
        FileUtils.mkdir_p(output_dir)
        txt_path = File.join(output_dir, "llms.txt")
        full_path = File.join(output_dir, "llms-full.txt")

        File.write(txt_path, llms_txt, encoding: 'UTF-8')
        File.write(full_path, llms_full_txt, encoding: 'UTF-8')

        saved_files << { path: txt_path, size_bytes: File.size(txt_path) }
        saved_files << { path: full_path, size_bytes: File.size(full_path) }
      end

      context_windows = {
        claude_3_5_sonnet_200k: (full_tokens <= 200_000),
        gpt_4o_128k: (full_tokens <= 128_000),
        gemini_1_5_pro_1m: (full_tokens <= 1_000_000)
      }

      {
        base_url: @base_url,
        total_pages_packaged: limit,
        llms_txt: {
          chars: llms_txt.length,
          tokens: txt_tokens,
          content: llms_txt
        },
        llms_full_txt: {
          chars: llms_full_txt.length,
          tokens: full_tokens,
          content: llms_full_txt
        },
        context_window_fit: context_windows,
        saved_files: saved_files
      }
    end

    # HTML to Clean Markdown Converter (Zero Gem Dependencies)
    def html_to_clean_markdown(html, base_url = '')
      return "" if html.nil? || html.empty?

      # 1. Strip comments, scripts, styles, nav, footer, header, svg, noscript
      clean = html.to_s.dup.force_encoding('UTF-8').scrub
      clean.gsub!(/<!--.*?-->/m, '')
      clean.gsub!(/<script\b[^>]*>.*?<\/script>/mi, '')
      clean.gsub!(/<style\b[^>]*>.*?<\/style>/mi, '')
      clean.gsub!(/<noscript\b[^>]*>.*?<\/noscript>/mi, '')
      clean.gsub!(/<svg\b[^>]*>.*?<\/svg>/mi, '')
      clean.gsub!(/<iframe\b[^>]*>.*?<\/iframe>/mi, '')
      clean.gsub!(/<nav\b[^>]*>.*?<\/nav>/mi, '')
      clean.gsub!(/<footer\b[^>]*>.*?<\/footer>/mi, '')
      clean.gsub!(/<header\b[^>]*>.*?<\/header>/mi, '')
      clean.gsub!(/<aside\b[^>]*>.*?<\/aside>/mi, '')

      # 2. Convert Headings (h1 - h6)
      (1..6).each do |level|
        clean.gsub!(/<h#{level}\b[^>]*>(.*?)<\/h#{level}>/mi) do
          heading_text = strip_tags($1).strip
          "\n\n#{'#' * level} #{heading_text}\n\n"
        end
      end

      # 3. Convert Tables to GFM Markdown
      clean.gsub!(/<table\b[^>]*>(.*?)<\/table>/mi) do
        table_html = $1
        convert_table_to_markdown(table_html)
      end

      # 4. Convert Lists
      clean.gsub!(/<li\b[^>]*>(.*?)<\/li>/mi) do
        li_text = strip_tags($1).strip
        "\n- #{li_text}"
      end
      clean.gsub!(/<\/?(ul|ol)\b[^>]*>/mi, "\n")

      # 5. Convert Code blocks
      clean.gsub!(/<pre\b[^>]*><code\b[^>]*>(.*?)<\/code><\/pre>/mi) do
        code = decode_html_entities($1).strip
        "\n```\n#{code}\n```\n"
      end
      clean.gsub!(/<code\b[^>]*>(.*?)<\/code>/mi) do
        code = decode_html_entities($1).strip
        "`#{code}`"
      end

      # 6. Convert Bold and Italic
      clean.gsub!(/<(b|strong)\b[^>]*>(.*?)<\/\1>/mi) { "**#{strip_tags($2).strip}**" }
      clean.gsub!(/<(i|em)\b[^>]*>(.*?)<\/\1>/mi) { "*#{strip_tags($2).strip}*" }

      # 7. Convert Links
      clean.gsub!(/<a\b[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/mi) do
        href = $1.strip
        text = strip_tags($2).strip
        next text if text.empty?
        resolved_href = URI.join(base_url, href).to_s rescue href
        safe_text = text.gsub('[', '\[').gsub(']', '\]')
        "[#{safe_text}](#{resolved_href})"
      end

      # 8. Convert Paragraphs and line breaks
      clean.gsub!(/<br\s*\/?>/mi, "  \n")
      clean.gsub!(/<p\b[^>]*>(.*?)<\/p>/mi) { "\n\n#{strip_tags($1).strip}\n\n" }

      # 9. Strip any remaining HTML tags
      clean = strip_tags(clean)

      # 10. Decode HTML Entities
      clean = decode_html_entities(clean)

      # 11. Normalize excessive whitespace
      clean.gsub!(/\r\n/, "\n")
      clean.gsub!(/\n{3,}/, "\n\n")
      clean.strip
    end

    def audit_ai_readability(url)
      pa = GSC::PageAnalyzer.new(url)
      data = pa.fetch_and_analyze

      html = pa.html || ''
      has_tables = html.include?('<table')
      has_lists = html.include?('<ul') || html.include?('<ol')
      schemas = data.dig(:structured_data, :schemas) || []
      h1_count = (data.dig(:headings, :h1) || []).length

      score = 100
      issues = []

      if h1_count != 1
        score -= 20
        issues << "H1 count is #{h1_count} (Must be exactly 1 for clean LLM hierarchy)"
      end

      unless has_tables
        score -= 15
        issues << "No <table> found (tables increase LLM citation and fact extraction by 3x)"
      end

      unless has_lists
        score -= 15
        issues << "No bullet lists (<ul> or <ol>) found for quick entity consumption"
      end

      if schemas.empty?
        score -= 20
        issues << "No JSON-LD schemas detected (structured data accelerates AI knowledge graph inclusion)"
      end

      {
        url: url,
        ai_readability_score: [score, 0].max,
        grade: score >= 80 ? 'A (Excellent)' : (score >= 60 ? 'B (Acceptable)' : 'C (Needs Work)'),
        issues: issues,
        features: {
          has_tables: has_tables,
          has_lists: has_lists,
          schemas_found: schemas.length,
          h1_count: h1_count
        }
      }
    end

    private

    def collect_pages_metadata(limit: 25)
      sitemap_target = "#{@base_url.chomp('/')}/sitemap.xml"
      urls = (GSC::SitemapLoader.resolve_urls(sitemap_target, @base_url, quiet: true) rescue [@base_url]) || [@base_url]
      urls = [@base_url] if urls.empty?

      # Also add standard routes if sitemap is small
      default_routes = ["/about", "/features", "/pricing", "/faq", "/docs", "/contact"].map do |r|
        URI.join(@base_url, r).to_s rescue nil
      end.compact

      candidate_urls = (urls + default_routes).uniq.first(limit)
      metadata = []

      candidate_urls.each do |url|
        html = fetch_html(url)
        next unless html && !html.empty?

        title = extract_title(html) || url
        desc = extract_description(html) || "Guide and specifications for #{title}."

        metadata << {
          url: url,
          title: title,
          description: desc
        }
      end

      metadata.empty? ? [{ url: @base_url, title: "Home", description: "Home page" }] : metadata
    end

    def fetch_html(url)
      uri = URI.parse(url) rescue nil
      return "" unless uri && uri.host

      begin
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: (uri.scheme == 'https'), open_timeout: 5, read_timeout: 8) do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) gsc-cli/2.1'
          req['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
          res = http.request(req)
          res.body.to_s[0..60_000] if res.body
        end
      rescue StandardError
        ""
      end
    end

    def extract_title(html)
      if html =~ /<title\b[^>]*>(.*?)<\/title>/mi
        strip_tags(decode_html_entities($1)).strip
      end
    end

    def extract_description(html)
      if html =~ /<meta\b[^>]*name=["']description["'][^>]*content=["']([^"']+)["']/mi
        strip_tags(decode_html_entities($1)).strip
      elsif html =~ /<meta\b[^>]*content=["']([^"']+)["'][^>]*name=["']description["']/mi
        strip_tags(decode_html_entities($1)).strip
      end
    end

    def convert_table_to_markdown(table_html)
      rows = []
      table_html.scan(/<tr\b[^>]*>(.*?)<\/tr>/mi).each do |tr_match|
        row_content = tr_match.first
        cells = []
        row_content.scan(/<(th|td)\b[^>]*>(.*?)<\/\1>/mi).each do |_tag, content|
          cells << strip_tags(content).gsub('|', '\\|').strip
        end
        rows << cells unless cells.empty?
      end

      return "" if rows.empty?

      col_count = rows.map(&:size).max
      rows.each { |r| r.fill('', r.size...col_count) }

      md = []
      # Header
      header = rows.first
      md << "| #{header.join(' | ')} |"
      md << "| #{Array.new(col_count, '---').join(' | ')} |"

      # Body
      rows[1..-1].each do |r|
        md << "| #{r.join(' | ')} |"
      end

      "\n\n" + md.join("\n") + "\n\n"
    end

    def generate_gsc_faq_block(url, gsc_rows)
      return nil unless gsc_rows && gsc_rows.is_a?(Array)

      clean_target = url.downcase.sub(%r{/$}, '')
      matching_queries = []

      gsc_rows.each do |r|
        keys = r['keys'] || []
        page = keys.find { |k| k =~ %r{^https?://} }
        next unless page && page.downcase.sub(%r{/$}, '') == clean_target

        q = keys.find { |k| k !~ %r{^https?://} }
        clicks = (r['clicks'] || 0).to_i
        matching_queries << { query: q, clicks: clicks } if q
      end

      return nil if matching_queries.empty?

      top_q = matching_queries.sort_by { |item| -item[:clicks] }.first(5)
      faq = []
      faq << "### Search Questions & High-Intent Queries (Verified from Google Search Console)"
      faq << ""
      top_q.each do |item|
        faq << "- **Q: How does #{item[:query]} work?**"
        faq << "  *A: Detailed in the core specifications above.*"
      end
      faq.join("\n")
    end

    def strip_tags(text)
      text.to_s.gsub(/<[^>]+>/, ' ')
    end

    def decode_html_entities(text)
      t = text.to_s.dup
      t.gsub!('&amp;', '&')
      t.gsub!('&quot;', '"')
      t.gsub!('&#39;', "'")
      t.gsub!('&apos;', "'")
      t.gsub!('&lt;', '<')
      t.gsub!('&gt;', '>')
      t.gsub!('&nbsp;', ' ')
      t.gsub!('&#8217;', "'")
      t.gsub!('&#8220;', '"')
      t.gsub!('&#8221;', '"')
      t
    end
  end
end

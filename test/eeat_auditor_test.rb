# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/eeat_auditor'

class EeatAuditorTest < Minitest::Test
  def setup
    @html_high_eeat = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Cardiovascular Health Guidelines</title>
        <meta name="author" content="Dr. Sarah Jenkins, MD, PhD" />
        <meta property="article:published_time" content="2026-01-15T08:00:00Z" />
        <meta property="article:modified_time" content="2026-03-01T12:00:00Z" />
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Article",
          "headline": "Cardiovascular Health Guidelines",
          "datePublished": "2026-01-15",
          "dateModified": "2026-03-01",
          "author": {
            "@type": "Person",
            "name": "Dr. Sarah Jenkins",
            "jobTitle": "Cardiologist & Clinical Researcher, MD, PhD",
            "sameAs": [
              "https://www.linkedin.com/in/sarah-jenkins-md",
              "https://scholar.google.com/citations?user=xyz"
            ]
          },
          "reviewedBy": {
            "@type": "Person",
            "name": "Dr. Robert Chen, MD"
          }
        }
        </script>
      </head>
      <body>
        <p class="byline">By <a rel="author" href="/author/sarah-jenkins">Dr. Sarah Jenkins, MD</a></p>
        <p class="review">Medically reviewed by Dr. Robert Chen, MD</p>
        <div class="author-bio">
          Dr. Sarah Jenkins, MD, PhD is a board-certified cardiologist with over 15 years of clinical practice.
        </div>
        <p>Refer to the official study published on <a href="https://www.ncbi.nlm.nih.gov/pubmed/123456">NIH PubMed</a> and guidelines from <a href="https://cdc.gov/heartdisease">CDC.gov</a>.</p>
        <footer>
          <p>Read our <a href="/editorial-policy">Editorial Policy and Conflict of Interest Disclosures</a>.</p>
        </footer>
      </body>
      </html>
    HTML

    @html_low_eeat = <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Best Crypto Investments</title></head>
      <body>
        <h1>Make Money Fast With Crypto</h1>
        <p>Here are 5 coins you must buy right now.</p>
      </body>
      </html>
    HTML
  end

  def test_high_eeat_audit
    res = GSC::EeatAuditor.audit(@html_high_eeat)

    assert_equal 100.0, res[:health_score]
    assert_equal 'A+', res[:grade]
    assert_equal 'Dr. Sarah Jenkins', res[:author_name]
    assert_includes res[:credentials], 'MD'
    assert_includes res[:credentials], 'PhD'
    assert_equal 'Dr. Robert Chen, MD', res[:reviewer_name]
    assert_equal '2026-01-15', res[:date_published]
    assert_equal '2026-03-01', res[:date_modified]
    assert res[:citations_count] >= 2
    assert_empty res[:issues]

    # Verify JSON-LD snippet generation
    snippet = res[:schema_fix_snippet]
    assert_includes snippet, 'https://schema.org'
    assert_includes snippet, 'Dr. Sarah Jenkins'
    assert_includes snippet, 'reviewedBy'
  end

  def test_low_eeat_audit
    res = GSC::EeatAuditor.audit(@html_low_eeat)

    assert res[:health_score] < 30.0
    assert_equal 'F', res[:grade]
    assert_nil res[:author_name]
    assert_empty res[:credentials]
    assert_nil res[:reviewer_name]
    assert_equal 0, res[:citations_count]

    assert_includes res[:issues], :missing_author_byline
    assert_includes res[:issues], :missing_person_schema
    assert_includes res[:issues], :missing_credentials_or_bio
    assert_includes res[:issues], :missing_social_proof
    assert_includes res[:issues], :missing_editorial_review
    assert_includes res[:issues], :missing_dates
    assert_includes res[:issues], :no_authoritative_citations

    # Verify prescriptions
    refute_empty res[:prescriptions]
    assert res[:prescriptions].any? { |p| p.include?('author byline') }
    assert res[:prescriptions].any? { |p| p.include?('Schema.org Person') }
    assert res[:prescriptions].any? { |p| p.include?('LinkedIn') }
    assert res[:prescriptions].any? { |p| p.include?('YMYL') }
  end

  def test_dom_fallback_extraction
    html_fallback = <<~HTML
      <html>
      <head>
        <meta name="author" content="Alex Rivera, CPA" />
        <meta property="article:published_time" content="2026-02-10" />
      </head>
      <body>
        <p>Fact-checked by Jane Doe, Esq</p>
        <p>Follow on <a href="https://linkedin.com/in/alex-rivera-cpa">LinkedIn</a></p>
      </body>
      </html>
    HTML

    res = GSC::EeatAuditor.audit(html_fallback)
    assert_equal 'Alex Rivera, CPA', res[:author_name]
    assert_includes res[:credentials], 'CPA'
    assert_equal 'Jane Doe, Esq', res[:reviewer_name]
    assert_equal '2026-02-10', res[:date_published]
    assert res[:health_score] > 40.0
  end
end

# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/gsc/schema_generator'

class SchemaGeneratorTest < Minitest::Test
  def setup
    @generator = GSC::SchemaGenerator.new
  end

  def test_generates_valid_product_schema
    res = @generator.generate('product', {
      name: 'Wireless Noise-Canceling Headphones',
      price: 199.99,
      currency: 'USD',
      brand: 'AudioTech',
      rating: 4.8,
      reviews: 150,
      image: 'https://example.com/headphones.jpg'
    })

    assert_equal 'Product', res[:type]
    assert res[:validation][:valid]
    assert_empty res[:validation][:errors]
    assert_equal 100, res[:validation][:score]
    assert_equal 'Wireless Noise-Canceling Headphones', res[:schema]['name']
    assert_equal '199.99', res[:schema]['offers']['price']
    assert_includes res[:snippets][:html], '<script type="application/ld+json">'
    assert_includes res[:snippets][:nextjs], 'dangerouslySetInnerHTML'
  end

  def test_generates_valid_faq_schema
    questions = [
      { q: 'What is the refund policy?', a: 'We offer a 30-day money back guarantee.' },
      { q: 'How do I install the app?', a: 'Download from the App Store and click install.' }
    ]

    res = @generator.generate('faq', { questions: questions })

    assert_equal 'FAQPage', res[:type]
    assert res[:validation][:valid]
    assert_equal 2, res[:schema]['mainEntity'].size
    assert_equal 'What is the refund policy?', res[:schema]['mainEntity'][0]['name']
    assert_equal 'We offer a 30-day money back guarantee.', res[:schema]['mainEntity'][0]['acceptedAnswer']['text']
  end

  def test_generates_valid_howto_schema
    res = @generator.generate('howto', {
      name: 'How to Install Google Search Console',
      description: 'Step-by-step tutorial on installing your custom tracking verification.'
    })

    assert_equal 'HowTo', res[:type]
    assert res[:validation][:valid]
    assert res[:schema]['step'].is_a?(Array)
    assert res[:schema]['step'].size >= 3
  end

  def test_generates_valid_article_schema
    res = @generator.generate('article', {
      headline: 'Next-Gen Technical SEO in 2026',
      author: 'Jane Doe',
      image: 'https://example.com/seo.jpg'
    })

    assert_equal 'Article', res[:type]
    assert res[:validation][:valid]
    assert_equal 'Next-Gen Technical SEO in 2026', res[:schema]['headline']
    assert_equal 'Jane Doe', res[:schema]['author']['name']
  end

  def test_generates_valid_software_application_schema
    res = @generator.generate('software', {
      name: 'SpeedBoost App',
      price: 29.00,
      os: 'Web, macOS'
    })

    assert_equal 'SoftwareApplication', res[:type]
    assert res[:validation][:valid]
    assert_equal 'SpeedBoost App', res[:schema]['name']
    assert_equal '29.0', res[:schema]['offers']['price']
  end

  def test_extract_and_generate_from_html
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Ergonomic Office Chair - Store</title>
        <meta name="description" content="Best ergonomic chair with lumbar support.">
        <meta property="og:image" content="https://store.com/chair.jpg">
      </head>
      <body>
        <h1>Ergonomic Office Chair</h1>
        <div class="product-price">$349.00</div>
      </body>
      </html>
    HTML

    res = @generator.extract_from_html(html, 'https://store.com/products/chair')

    assert_equal 'Product', res[:type]
    assert_equal 'Ergonomic Office Chair', res[:schema]['name']
    assert_equal '349.0', res[:schema]['offers']['price']
    assert res[:validation][:valid]
  end

  def test_flags_schema_validation_errors
    invalid_schema = {
      '@context' => 'https://schema.org',
      '@type' => 'Product',
      'name' => '' # Missing name
      # Missing offers or aggregateRating
    }

    val = @generator.validate_schema(invalid_schema)
    refute val[:valid]
    assert val[:errors].size >= 2
    assert val[:score] < 50
  end

  def test_strips_html_tags_from_scraped_content
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>Test App &amp; Tools</title></head>
      <body>
        <h1>Stop losing things<br class="hidden sm:block"/> <span class="text-ink-soft">on moving day</span></h1>
      </body>
      </html>
    HTML

    res = @generator.extract_from_html(html, 'https://example.com')
    assert_equal 'Stop losing things on moving day', res[:schema]['headline']
    refute_includes res[:schema]['headline'], '<br'
    refute_includes res[:schema]['headline'], '<span'
  end

  def test_honors_explicit_type_on_url_extraction
    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>App Suite</title></head>
      <body>
        <h1>Fast App</h1>
        <div class="product-price">$0.00</div>
      </body>
      </html>
    HTML

    res = @generator.extract_from_html(html, 'https://example.com', 'SoftwareApplication')
    assert_equal 'SoftwareApplication', res[:type]
    assert_equal 'Fast App', res[:schema]['name']
    assert res[:validation][:valid]
  end

  def test_generates_valid_breadcrumb_schema
    res = @generator.generate('breadcrumb', {
      url: 'https://example.com',
      breadcrumbs: [
        { name: 'Home', url: 'https://example.com' },
        { name: 'Docs', url: 'https://example.com/docs' },
        { name: 'CLI', url: 'https://example.com/docs/cli' }
      ]
    })

    assert_equal 'BreadcrumbList', res[:type]
    assert res[:validation][:valid]
    assert_equal 3, res[:schema]['itemListElement'].size
    assert_equal 2, res[:schema]['itemListElement'][1]['position']
    assert_equal 'Docs', res[:schema]['itemListElement'][1]['name']
  end

  def test_generates_valid_course_and_job_posting_schema
    course = @generator.generate('course', {
      name: 'Advanced SEO Architecture',
      description: 'Master technical SEO and schema engineering.',
      brand: 'Search Institute'
    })
    assert_equal 'Course', course[:type]
    assert course[:validation][:valid]

    job = @generator.generate('job', {
      title: 'Senior SEO Architect',
      description: 'Lead enterprise Search Console optimization.',
      brand: 'Acme Corp'
    })
    assert_equal 'JobPosting', job[:type]
    assert job[:validation][:valid]
  end
end


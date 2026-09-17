# frozen_string_literal: true

require_relative 'test_helper'

class AdvancedFeaturesTest < Minitest::Test
  def test_google_suggest_instance
    sug = GSC::GoogleSuggest.new('seo audit')
    assert_equal 'seo audit', sug.query
  end

  def test_open_page_rank_clean_domain
    opr = GSC::OpenPageRank.new('dummy_key')
    assert_equal 'example.com', opr.clean_domain('https://www.example.com/some/path')
  end

  def test_schema_generator
    faq = GSC::SchemaValidator.generate_template('faq', question: 'Test Q?', answer: 'Test A.')
    assert_equal 'FAQPage', faq['@type']
    assert_equal 'Test Q?', faq['mainEntity'].first['name']

    app = GSC::SchemaValidator.generate_template('app', name: 'SuperApp')
    assert_equal 'SoftwareApplication', app['@type']
    assert_equal 'SuperApp', app['name']
  end

  def test_content_gap_clean_text
    gap = GSC::ContentGap.new('https://example.com/1', 'https://example.com/2')
    # private method testing via send
    clean = gap.send(:extract_clean_text, '<html><body><h1>Hello World</h1><script>alert(1)</script></body></html>')
    assert_equal 'Hello World', clean
  end

  def test_backlinks_manager_data_structure
    bm = GSC::BacklinksManager.new('testdomain.com')
    assert_equal 'testdomain.com', bm.domain
    data = bm.load_data
    assert data.key?('sources')
    assert data.key?('targets')
  end

  def test_indexnow_key_generation
    key = GSC::IndexNow.generate_key
    assert_equal 32, key.length
    assert_match(/^[a-f0-9]{32}$/, key)
  end

  def test_serp_preview_calculation
    sp = GSC::SerpPreview.new('https://example.com/flat-feet', title: 'Best Running Shoes for Flat Feet', desc: 'Find top-rated running shoes.')
    res = sp.generate
    assert_equal 'Best Running Shoes for Flat Feet', res[:title]
    assert res[:metrics][:title_pixel_est] > 0
    refute res[:metrics][:title_truncated]
  end
end

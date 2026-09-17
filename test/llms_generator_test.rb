# encoding: utf-8
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/gsc/llms_generator'

class LlmsGeneratorTest < Minitest::Test
  def setup
    @gen = GSC::LlmsGenerator.new("https://example.com")
  end

  def with_stubbed_method(obj, method_name, fake_proc)
    orig = obj.method(method_name)
    obj.define_singleton_method(method_name) { |*args, **kwargs, &blk| fake_proc.call(*args, **kwargs, &blk) }
    yield
  ensure
    obj.define_singleton_method(method_name, orig)
  end

  def test_html_to_clean_markdown_strips_unwanted_tags
    html = <<~HTML
      <html>
        <head><title>Test Page</title></head>
        <body>
          <nav><a href="/">Home</a></nav>
          <header><h1>Site Header</h1></header>
          <script>console.log("drop me");</script>
          <style>body { color: red; }</style>
          <p>Main genuine content paragraph.</p>
          <footer>Copyright 2026</footer>
        </body>
      </html>
    HTML

    md = @gen.html_to_clean_markdown(html)

    refute_includes md, "console.log"
    refute_includes md, "body { color: red; }"
    refute_includes md, "Site Header"
    refute_includes md, "Copyright 2026"
    assert_includes md, "Main genuine content paragraph."
  end

  def test_html_to_clean_markdown_converts_elements
    html = <<~HTML
      <div>
        <h1>Top Feature</h1>
        <p>This is <b>bold</b> and <i>italic</i> with a <a href="https://example.com/learn">link</a>.</p>
        <ul>
          <li>Point Alpha</li>
          <li>Point Beta</li>
        </ul>
      </div>
    HTML

    md = @gen.html_to_clean_markdown(html, "https://example.com")

    assert_includes md, "# Top Feature"
    assert_includes md, "**bold**"
    assert_includes md, "*italic*"
    assert_includes md, "[link](https://example.com/learn)"
    assert_includes md, "- Point Alpha"
    assert_includes md, "- Point Beta"
  end

  def test_html_to_clean_markdown_converts_tables
    html = <<~HTML
      <table>
        <thead>
          <tr><th>Feature</th><th>Speed</th></tr>
        </thead>
        <tbody>
          <tr><td>CLI Engine</td><td>Sub-10ms</td></tr>
          <tr><td>Ahrefs Web</td><td>1200ms</td></tr>
        </tbody>
      </table>
    HTML

    md = @gen.html_to_clean_markdown(html)

    assert_includes md, "| Feature | Speed |"
    assert_includes md, "| --- | --- |"
    assert_includes md, "| CLI Engine | Sub-10ms |"
    assert_includes md, "| Ahrefs Web | 1200ms |"
  end

  def test_html_to_clean_markdown_code_blocks
    html = <<~HTML
      <div>
        <p>Run the command: <code>gsc llms --full</code></p>
        <pre><code>
        def calculate
          42
        end
        </code></pre>
      </div>
    HTML

    md = @gen.html_to_clean_markdown(html)

    assert_includes md, "`gsc llms --full`"
    assert_includes md, "```"
    assert_includes md, "def calculate"
  end

  def test_generate_llms_txt_structure
    fake_metadata = [
      { url: "https://example.com/docs/intro", title: "Introduction", description: "Getting started guide." },
      { url: "https://example.com/docs/api", title: "API Reference", description: "Complete endpoints." }
    ]

    with_stubbed_method(@gen, :collect_pages_metadata, ->(**kw) { fake_metadata }) do
      txt = @gen.generate_llms_txt(title: "Acme Cloud", summary: "The API platform for agents.")

      assert_includes txt, "# Acme Cloud"
      assert_includes txt, "> The API platform for agents."
      assert_includes txt, "## Core Documentation"
      assert_includes txt, "- [Introduction](https://example.com/docs/intro): Getting started guide."
      assert_includes txt, "- [API Reference](https://example.com/docs/api): Complete endpoints."
      assert_includes txt, "## Optional"
      assert_includes txt, "- [Full Consolidated Knowledge Base](https://example.com/llms-full.txt)"
    end
  end

  def test_generate_llms_full_txt_with_faq_injection
    fake_metadata = [
      { url: "https://example.com/shipping", title: "Shipping Rates", description: "Global delivery times." }
    ]

    fake_html = "<h1>Shipping Rates</h1><p>We deliver worldwide in 2-3 business days.</p>"
    gsc_rows = [
      { "keys" => ["https://example.com/shipping", "shipping time to us"], "clicks" => 40 }
    ]

    with_stubbed_method(@gen, :collect_pages_metadata, ->(**kw) { fake_metadata }) do
      with_stubbed_method(@gen, :fetch_html, ->(u) { fake_html }) do
        full_txt = @gen.generate_llms_full_txt(gsc_rows: gsc_rows)

        assert_includes full_txt, "Full Knowledge Base (`/llms-full.txt`)"
        assert_includes full_txt, "## Table of Contents"
        assert_includes full_txt, "1. [Shipping Rates](#section-1)"
        assert_includes full_txt, "**Source URL**: https://example.com/shipping"
        assert_includes full_txt, "We deliver worldwide in 2-3 business days."
        assert_includes full_txt, "Search Questions & High-Intent Queries (Verified from Google Search Console)"
        assert_includes full_txt, "shipping time to us"
      end
    end
  end

  def test_package_agent_bundle_and_disk_export
    Dir.mktmpdir do |dir|
      fake_metadata = [
        { url: "https://example.com/guide", title: "Quickstart Guide", description: "5-minute setup." }
      ]
      fake_html = "<h1>Quickstart</h1><p>Step 1: Install. Step 2: Run.</p>"

      with_stubbed_method(@gen, :collect_pages_metadata, ->(**kw) { fake_metadata }) do
        with_stubbed_method(@gen, :fetch_html, ->(u) { fake_html }) do
          bundle = @gen.package_agent_bundle(output_dir: dir)

          assert bundle[:llms_txt][:tokens] > 0
          assert bundle[:llms_full_txt][:tokens] > 0
          assert_equal true, bundle.dig(:context_window_fit, :claude_3_5_sonnet_200k)
          assert_equal true, bundle.dig(:context_window_fit, :gpt_4o_128k)
          assert_equal 2, bundle[:saved_files].size

          assert File.exist?(File.join(dir, "llms.txt"))
          assert File.exist?(File.join(dir, "llms-full.txt"))
          assert File.size(File.join(dir, "llms-full.txt")) > 50
        end
      end
    end
  end
end

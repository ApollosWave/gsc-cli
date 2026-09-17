# frozen_string_literal: true

module GSC
  class Prompts
    PLAYBOOKS = [
# Master 360° Multi-Horizon Audit
{
  id: 0,
  category: 'master',
  category_name: '👑 Master 360° Multi-Horizon Audits',
  title: 'The 360° Multi-Horizon Master SEO & Universal Keyword Audit',
  impact: 'Maximum Impact (Exhaustive 30d, 90d, 180d audit & action plan)',
  cli_command: 'gsc performance --days 180 --json',
  template: "Perform an exhaustive 360° SEO, Universal Keyword, and Crawl Health Audit for {{domain}} across 30d, 90d, and 180d horizons.\n\nExecute the following commands with --json and save the final report to docs/seo/master_audit_report.md (and as an agent artifact if your environment supports artifacts):\n\n1. Macro Multi-Horizon Performance & Trends:\n   - `gsc performance --days 30 --json`\n   - `gsc performance --days 90 --json`\n   - `gsc performance --days 180 --json`\n   - `gsc decay --compare 28 --json`\n\n2. Universal Keyword Intelligence (Saved & Unsaved):\n   - Check all saved snapshots: `gsc saved check 1 --json`\n   - Unsaved live search queries: `gsc top-queries --days 180 --limit 500 -s imp --json`\n   - Page 2 striking distance: `gsc opportunities --min-imp 5 --limit 100 --json`\n   - CTR underperformers: `gsc underperformers --limit 50 --json`\n   - Keyword cannibalization conflicts: `gsc cannibalization --json`\n\n3. Google Trends & Autocomplete Velocity:\n   - `gsc trends \"{{seed}}\" --time 12m --json`\n   - `gsc planner \"{{seed}}\" --json`\n\n4. Landing Pages, Post-Click GA4 Behavior & Crawl Budget:\n   - Top traffic landing pages: `gsc top-pages --days 90 --limit 100 --json`\n   - Organic bounce & engagement: `gsc ga4 --organic --days 30 --limit 100 --json`\n   - SERP vs Bounce correlation: `gsc correlation --organic --json`\n   - Sitemap crawl waste: `gsc zombies public/sitemap.xml --json`\n\nGenerate a Master Executive Report containing:\n1. Executive Growth Scorecard (Macro comparison: 30d vs 90d vs 180d clicks, impressions, CTR, pos).\n2. The Universal Keyword Opportunity Matrix (Ranking, Striking Distance, Untargeted Saved Keywords).\n3. Google Trends Seasonal Velocity & Rising Breakouts (+5000% queries).\n4. CTR Optimization Matrix (Title & meta rewrites for low-CTR pages).\n5. Post-Click Leak Audit (High organic impressions with high GA4 bounce).\n6. Technical & Zombie Crawl Waste cleanup plan.\n7. Prioritized 30-Day Sprint (P0, P1, P2 with exact file paths and code edits)."
},

      # Category: Growth & Striking Distance Opportunities
      {
        id: 1,
        category: 'growth',
        category_name: '🚀 Growth & Striking Distance',
        title: 'The Page 2 Striking Distance Leap',
        impact: 'High Impact (Push Page 2 keywords to Top 3)',
        cli_command: 'gsc opportunities --min-imp 20 --json',
        template: 'Run `gsc opportunities --min-imp 20 --json` for {{domain}}. Find the top 3 striking-distance queries (positions 8–18 with high impressions). For each query, locate its ranking page in our codebase, identify what content is missing compared to top SERP competitors, expand the page with a targeted FAQ and comparison table, and ping Google Indexing API via `gsc index <url>`.'
      },
      {
        id: 2,
        category: 'growth',
        category_name: '🚀 Growth & Striking Distance',
        title: 'The Untargeted Keyword Goldmine',
        impact: 'High Impact (Create high-intent new landing pages)',
        cli_command: 'gsc saved check 1 --json',
        template: 'Inspect our saved keyword research with `gsc saved check 1 --json`. Identify the top 5 keywords with Opportunity Score > 65 that are currently flagged as 🚀 Untargeted. For each keyword, propose a dedicated landing page route, draft high-intent metadata, and generate a semantic content outline.'
      },
      {
        id: 3,
        category: 'growth',
        category_name: '🚀 Growth & Striking Distance',
        title: '5-Year Google Trends Seasonal Surf',
        impact: 'Medium Impact (Catch seasonal breakout demand)',
        cli_command: 'gsc trends "{{seed}}" --time 5y --json',
        template: 'Run `gsc trends "{{seed}}" --time 5y --json`. Identify the historical peak search months, extract all rising breakout queries (+5000%), and update our landing page headings and marketing banners to capture the upcoming seasonal search surge.'
      },
      {
        id: 4,
        category: 'growth',
        category_name: '🚀 Growth & Striking Distance',
        title: 'Long-Tail Autocomplete Multiplier',
        impact: 'Medium Impact (Target long-tail customer questions)',
        cli_command: 'gsc planner "{{seed}}" --limit 50 --json',
        template: 'Run `gsc planner "{{seed}}" --limit 50 --json`. Group all discovered long-tail queries by search intent (Transactional vs Informational), and generate an interactive FAQ accordion component in our template addressing the top 5 customer questions.'
      },

      # Category: Conversion & Click-Through Rate (CTR)
      {
        id: 5,
        category: 'ctr',
        category_name: '🎯 Conversion & CTR Multipliers',
        title: 'The CTR Underperformer Double',
        impact: 'High Impact (Double organic clicks with 0 rank changes)',
        cli_command: 'gsc underperformers --limit 5 --json',
        template: 'Run `gsc underperformers --limit 5 --json` for {{domain}}. For the page with the highest impressions but lowest CTR (<2%), read its current <title> and meta description in our codebase. Rewrite them applying the 50–60 character high-CTR formula (front-loading the exact query, adding bracketed hooks like [2026 Free Tool], and appending brand). Update the file and ping `gsc index <url>`.'
      },
      {
        id: 6,
        category: 'ctr',
        category_name: '🎯 Conversion & CTR Multipliers',
        title: 'Review & FAQ Rich Snippet Enabler',
        impact: 'High Impact (Win star ratings and expandable FAQs in SERP)',
        cli_command: 'gsc snippets --json',
        template: 'Run `gsc snippets --json` on {{domain}} to check active search appearances. Then inspect our top traffic pages from `gsc top-pages --json` and inject valid Schema.org JSON-LD structured data (FAQPage or Product) so our Google SERP listings display star ratings and expandable FAQs.'
      },
      {
        id: 7,
        category: 'ctr',
        category_name: '🎯 Conversion & CTR Multipliers',
        title: 'Headline & H1 Alignment Overhaul',
        impact: 'Medium Impact (Increase on-page conversion rate)',
        cli_command: 'gsc top-queries --limit 10 --json',
        template: 'Find our top 3 visited landing pages using `gsc ga4 --organic --json`. Audit their <h1> display headings against our copywriting rules (ensure zero trailing periods, strong benefit promise, and strict alignment with high-volume search queries from `gsc top-queries`).'
      },
      {
        id: 8,
        category: 'ctr',
        category_name: '🎯 Conversion & CTR Multipliers',
        title: 'Keyword Cannibalization Consolidator',
        impact: 'High Impact (Stop competing against your own pages)',
        cli_command: 'gsc cannibalization --json',
        template: 'Run `gsc cannibalization --json` on {{domain}}. Detect any search queries where 2 or more of our URLs are competing against each other and splitting Google impressions. Recommend which URL should be the authoritative canonical, and add cross-linking or 301 redirects to consolidate ranking power.'
      },

      # Category: GA4 Behavioral, Ads & Conversion Analytics
      {
        id: 9,
        category: 'analytics',
        category_name: '📊 GA4 Behavioral & Ad Synergy',
        title: 'High-Bounce Traffic Leak Plugger',
        impact: 'High Impact (Rescue lost visitors who bounce in <10s)',
        cli_command: 'gsc correlation --json',
        template: 'Run `gsc correlation --json`. Correlate high-impression GSC search queries against GA4 bounce rates. Find search queries driving visitors who bounce in under 10 seconds. Audit the page\'s above-the-fold hero section and align the primary value proposition directly to user search intent.'
      },
      {
        id: 10,
        category: 'analytics',
        category_name: '📊 GA4 Behavioral & Ad Synergy',
        title: 'Real-Time Traffic Wave Monitor',
        impact: 'Medium Impact (Live visitor diagnostic & health check)',
        cli_command: 'gsc realtime --json',
        template: 'Run `gsc realtime --json`. Check how many live visitors are currently on {{domain}}, which landing pages they are viewing, and verify that our conversion tracking and call-to-actions on those active pages are operating smoothly.'
      },
      {
        id: 11,
        category: 'analytics',
        category_name: '📊 GA4 Behavioral & Ad Synergy',
        title: 'Google Ads & Organic Synergy Optimizer',
        impact: 'High Impact (Cut wasted ad spend where you rank #1 organically)',
        cli_command: 'gsc ads --json',
        template: 'Run `gsc ads --json` and `gsc top-queries --json`. Identify expensive Google Ads keywords (high CPC) where our site already ranks in Top 3 organically, and suggest pausing those paid ads to save ad spend while doubling down on organic CTR.'
      },
      {
        id: 12,
        category: 'analytics',
        category_name: '📊 GA4 Behavioral & Ad Synergy',
        title: 'Omni-Channel Attribution & Engagement Audit',
        impact: 'Medium Impact (Identify top converting traffic channels)',
        cli_command: 'gsc channels --days 30 --json',
        template: 'Run `gsc channels --days 30 --json`. Compare organic search conversion rates against paid and direct traffic. Highlight which traffic channel has the highest customer engagement rate and recommend channel-specific landing page optimizations.'
      },

      # Category: Technical SEO, Crawl Health & Indexing
      {
        id: 13,
        category: 'technical',
        category_name: '🛠️ Technical Health & Crawl Optimization',
        title: 'The 90-Day Zombie Page Purge',
        impact: 'High Impact (Reclaim crawl budget and prune dead weight)',
        cli_command: 'gsc zombies --json',
        template: 'Run `gsc zombies --json` on our sitemap. Identify all low-quality or obsolete pages that have received 0 impressions in the last 90 days. Recommend whether to update them with fresh content or retire them with `gsc remove <url>` to protect crawl budget.'
      },
      {
        id: 14,
        category: 'technical',
        category_name: '🛠️ Technical Health & Crawl Optimization',
        title: 'Sitemap Coverage & Rapid Indexing Blitz',
        impact: 'High Impact (Force Googlebot to index queued pages)',
        cli_command: 'gsc inspect-sitemap https://{{domain}}/sitemap.xml --json',
        template: 'Run `gsc inspect-sitemap https://{{domain}}/sitemap.xml --json`. Identify all URLs marked as "Discovered - currently not indexed" or "Crawled - currently not indexed". For any unindexed URL, batch ping Google Indexing API via `gsc index <url>` to accelerate indexing.'
      },
      {
        id: 15,
        category: 'technical',
        category_name: '🛠️ Technical Health & Crawl Optimization',
        title: 'Ranking Decay Early Warning Detection',
        impact: 'High Impact (Arrest traffic loss before it accelerates)',
        cli_command: 'gsc decay --days 28 --json',
        template: 'Run `gsc decay --days 28 --json`. Identify queries or pages experiencing period-over-period click or impression drops (>20%). Propose immediate content freshness updates and internal link boosts to reverse the decay.'
      },
      {
        id: 16,
        category: 'technical',
        category_name: '🛠️ Technical Health & Crawl Optimization',
        title: 'Lost Query Resuscitation',
        impact: 'Medium Impact (Recover queries that fell out of Google)',
        cli_command: 'gsc decay --json',
        template: 'Run `gsc decay --json` and filter by "lost". Find high-volume keywords that generated traffic last month but completely dropped off this month. Inspect the previous URL and restore missing topical sections.'
      },

      # Category: Programmatic SEO & Scalable Architecture
      {
        id: 17,
        category: 'programmatic',
        category_name: '⚡ Programmatic SEO & Directory Scaling',
        title: 'Programmatic Landing Page Generator',
        impact: 'High Impact (Build 50+ data-driven landing pages)',
        cli_command: 'gsc saved check 1 --json',
        template: 'Run `gsc saved check 1 --json`. Extract the top 10 untargeted city or feature keywords. Generate a reusable programmatic template that renders unique, value-dense content for each variation without creating duplicate content.'
      },
      {
        id: 18,
        category: 'programmatic',
        category_name: '⚡ Programmatic SEO & Directory Scaling',
        title: 'Competitor Gap Exploitation via Import',
        impact: 'High Impact (Steal competitor high-volume terms)',
        cli_command: 'gsc import clip --json',
        template: 'Run `gsc import clip --json` using our latest competitor export from clipboard. Compare their highest volume keywords against our `gsc top-queries --json`. Identify the 5 most profitable keywords where our competitor ranks but we have zero presence.'
      },
      {
        id: 19,
        category: 'programmatic',
        category_name: '⚡ Programmatic SEO & Directory Scaling',
        title: 'Zero-Click Search & AI Overview Winning Strategy',
        impact: 'High Impact (Win citations in Google AI Overviews)',
        cli_command: 'gsc top-queries -s imp --limit 20 --json',
        template: 'Run `gsc top-queries -s imp --limit 20 --json`. Identify informational queries where Google shows AI Overviews or direct answer boxes. Structure our content with concise 40-word definitions, numbered steps, and comparison tables to win the AI Overview citation.'
      },
      {
        id: 20,
        category: 'programmatic',
        category_name: '⚡ Programmatic SEO & Directory Scaling',
        title: 'Mobile vs Desktop SERP Parity Audit',
        impact: 'Medium Impact (Fix mobile ranking discrepancies)',
        cli_command: 'gsc devices --json',
        template: 'Run `gsc devices --json`. Compare Mobile CTR vs Desktop CTR for {{domain}}. If mobile CTR lags by more than 30%, inspect our mobile viewport layouts, tap target sizes, and above-the-fold content density.'
      },

      # Category: Executive Briefings & Daily Standups
      {
        id: 21,
        category: 'executive',
        category_name: '📋 Executive Briefings & Standups',
        title: '360° Executive SEO Health Briefing',
        impact: 'High Impact (Complete C-Suite progress report)',
        cli_command: 'gsc performance --days 30 --json',
        template: 'Run `gsc performance --days 30 --json`, `gsc decay --json`, and `gsc opportunities --json`. Generate a markdown briefing summarizing: Total Clicks & Growth % MoM, Top 3 Emerging Keywords, Top 3 Striking-Distance Opportunities, and 3 Critical Action Items for this sprint.'
      },
      {
        id: 22,
        category: 'executive',
        category_name: '📋 Executive Briefings & Standups',
        title: 'New Feature Launch Indexing Blitz',
        impact: 'High Impact (Index new releases within hours)',
        cli_command: 'gsc index {{url}} --json',
        template: 'Inspect the metadata, verify Schema markup, confirm robots.txt accessibility, and immediately submit our newly launched page at {{url}} to Google Indexing API via `gsc index {{url}}`.'
      },
      {
        id: 23,
        category: 'executive',
        category_name: '📋 Executive Briefings & Standups',
        title: 'Geographic Market Expansion Diagnostic',
        impact: 'Medium Impact (Find international expansion markets)',
        cli_command: 'gsc countries --limit 20 --json',
        template: 'Run `gsc countries --limit 20 --json` and `gsc cities --limit 20 --json`. Identify our top 3 international or regional markets outside our primary country. Check if localized currency, language, or shipping details are needed on those landing pages.'
      },
      {
        id: 24,
        category: 'executive',
        category_name: '📋 Executive Briefings & Standups',
        title: 'Title Tag Pixel Width & Truncation Audit',
        impact: 'Medium Impact (Prevent Google ... truncation on all pages)',
        cli_command: 'gsc top-pages --limit 25 --json',
        template: 'Crawl our sitemap via `gsc inspect-sitemap --json`, extract all page <title> tags from our repository, and flag any titles under 40 characters (too short) or over 60 characters (truncated by Google with ...). Propose rewritten versions for all flagged titles.'
      },
      {
        id: 25,
        category: 'executive',
        category_name: '📋 Executive Briefings & Standups',
        title: 'The Daily 5-Minute SEO Standup',
        impact: 'High Impact (Daily check of pulses, wins, and anomalies)',
        cli_command: 'gsc realtime --json',
        template: 'Run `gsc realtime --json`, `gsc top-queries --limit 5 --json`, and `gsc decay --json`. Give me a 3-bullet standup: (1) Live visitors right now, (2) Yesterday\'s top performing search query, and (3) Any query that saw an unexpected drop requiring attention.'
      },
      {
        id: 26,
        category: 'growth',
        category_name: '🚀 Growth & Striking Distance',
        title: 'The Adaptive Question Engine & AI Overview Citation Radar',
        impact: 'Maximum Impact (480d PAA harvest, AI Overview radar, answer synthesis & FAQ injection)',
        cli_command: 'gsc questions-harvest -d {{domain}} --days 480 --synthesize --json',
        template: "Execute an end-to-end autonomous Question Mining, AI Overview Citation Radar, and FAQ Schema Domination workflow for {{domain}}.\n\nStrip all hardcoded brand or niche assumptions—this playbook is 100% adaptive based on the live findings from {{domain}} and previous command outputs.\n\nExecute the following phased workflow step-by-step:\n\n### Phase 1: Deep Retrospective Search Console Harvest (480 Days)\n1. Run `gsc questions-harvest -d {{domain}} --days 480 --json` to uncover every question-intent query that {{domain}} has logged search impressions for across all historical search queries.\n2. Run `gsc strike -d {{domain}} --limit 15 --json` to detect high-impression striking distance queries ranking on Page 2 (Positions 4–20).\n3. From the harvested queries and striking distance results, identify:\n   - The Top 3 High-Opportunity Questions (Positions 4–20, prime for rich snippets).\n   - Any SERP Defense Questions (Positions 1–3, featured snippet holders).\n   - The primary Landing Pages associated with these questions.\n\n### Phase 2: Adaptive Topic & Seed Extraction\n1. Analyze the keywords and questions identified in Phase 1 to dynamically extract the 2–3 core topical entities/themes representing the domain's primary products, services, or features.\n   - For example: If queries mention pricing or api integration or security, extract \"pricing\", \"api integration\", etc. Do not assume or hardcode any topic.\n\n### Phase 3: Proactive Live Market Question Mining (People Also Ask & Suggest)\n1. For each core topical entity extracted in Phase 2, run:\n   - `gsc questions \"<extracted_seed>\" --limit 20 --json`\n2. Classify discovered market queries into 4 conversion archetypes:\n   - How-To / Implementation: Practical questions searchers ask when solving a problem.\n   - Commercial Comparison: \"Best\", \"Vs\", \"Alternatives\" searches comparing solutions.\n   - Policies & Rules: Compliance, eligibility, and configuration questions.\n   - Cost & ROI: Pricing, \"worth it\", and value justification queries.\n\n### Phase 4: Google AI Overview (AIO) Citation Radar\n1. For the top 2 highest-impression queries from Phase 1 and Phase 3, run:\n   - `gsc aio-hunter \"<target_query>\" --json`\n2. Analyze the radar telemetry:\n   - Is Google displaying an AI Overview (AIO)?\n   - What competitor domains does Google cite in the AIO carousel?\n   - What specific information-gain statistics or factual bullets are missing from our content that Google is citing from others?\n\n### Phase 5: High-Citability Answer Synthesis & FAQ Schema\n1. Run `gsc questions-harvest -d {{domain}} --days 480 --synthesize --json` to automatically synthesize authoritative, 40–60 word Featured Snippet answers and schema.org FAQPage JSON-LD for our target pages.\n2. For any crucial PAA question discovered in Phase 3 not yet in our GSC logs, run:\n   - `gsc answer \"<question>\" --brand {{domain}}`\n   to synthesize a high-citability direct answer block with targeted information gain.\n\n### Phase 6: Codebase Integration & Instant Indexing\n1. Locate the source files in our local repository corresponding to the target landing page URLs (e.g. Markdown, HTML, Liquid, JSX/TSX, or Astro/Svelte templates).\n2. Insert an H2/H3 FAQ section containing the synthesized questions and authoritative answers.\n3. Embed the generated `<script type=\"application/ld+json\">` FAQPage schema into the page <head> or body.\n4. Notify Googlebot immediately of the enriched content by triggering:\n   - `gsc index <target_url>`\n\nDeliver the final executive summary including:\n- Total questions harvested and new market questions discovered.\n- AI Overview radar assessment (AIO presence, cited competitors, citation strategy).\n- Exact file paths modified and diff of FAQ / schema additions.\n- Google Indexing API submission confirmations."
      }
    ].freeze

    def self.all
      PLAYBOOKS
    end

    def self.find(id)
      PLAYBOOKS.find { |p| p[:id] == id.to_i }
    end

    def self.by_category(cat)
      PLAYBOOKS.select { |p| p[:category] == cat.to_s.downcase }
    end

    def self.categories
      PLAYBOOKS.map { |p| { id: p[:category], name: p[:category_name] } }.uniq { |c| c[:id] }
    end

    def self.render_prompt(id, domain: nil, seed: nil, url: nil)
      item = find(id)
      return nil unless item

      dom = domain || Config.default_domain || '<your-domain.com>'
      s = seed || '<target-keyword>'
      u = url || (dom == '<your-domain.com>' ? '<target-url>' : "https://#{dom}")

      item[:template]
        .gsub('{{domain}}', dom)
        .gsub('{{seed}}', s)
        .gsub('{{url}}', u)
    end
  end
end

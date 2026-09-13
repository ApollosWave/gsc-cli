# frozen_string_literal: true

module GSC
  module CommandRegistry
COMMAND_REGISTRY = [
  {
    category: "Google Trends & Keyword Demand",
    commands: [
{ name: "ke <seed|file>", shortcut: "ke", desc: "Keywords Everywhere: Exact monthly volume, CPC, competition & GSC correlation", flags: ["--country", "--limit", "--json"] },
{ name: "ke-credits", shortcut: "ke-credits", desc: "Check remaining Keywords Everywhere account API credits", flags: ["--json"] },
{ name: "connect ke [key]", shortcut: "connect ke", desc: "Connect Keywords Everywhere API key and save to config.json", flags: [] },
      { name: "trends <query>", shortcut: "tr", desc: "Live Google Trends: 5yr/1yr demand trajectory, velocity & breakout queries", flags: ["--geo", "--time", "--json"] },
      { name: "planner <seed>", shortcut: "kp", desc: "Free keyword planner: intent expansion & GSC ranking correlation", flags: ["--country", "--limit", "--json"] },
      { name: "planner-import <file>", shortcut: "pi", desc: "Import Google Ads CSV or Markdown table to score & rank opportunities", flags: ["--limit", "--json"] }
    ]
  },
  {
    category: "Search Console Intelligence",
    commands: [
      { name: "performance", shortcut: "p", desc: "Executive dashboard: Clicks, Impressions, CTR, Position", flags: ["--days", "--limit", "--csv"] },
      { name: "top-queries", shortcut: "t", desc: "Top search queries, rankings, and CTR", flags: ["--days", "--limit", "-s", "--order", "--csv"] },
      { name: "top-pages", shortcut: nil, desc: "Top landing pages driving organic search clicks", flags: ["--days", "--limit", "-s", "--order", "--csv"] },
      { name: "opportunities", shortcut: "o", desc: "Striking-distance queries (Pos 7-20) to push to Top 3", flags: ["--days", "--min-imp", "--min-pos", "--max-pos"] },
      { name: "underperformers", shortcut: "u", desc: "High-ranking queries (Top 10) with low CTR (title tag wins)", flags: ["--days", "--min-imp"] },
      { name: "cannibalization", shortcut: "c", desc: "Detect internal URLs competing for the same keywords", flags: ["--days", "--min-imp"] },
      { name: "decay", shortcut: "d", desc: "Period-over-period decay detection (decaying vs surging)", flags: ["--compare"] },
      { name: "trends", shortcut: nil, desc: "Compare current vs prior period search trends", flags: ["--compare"] },
      { name: "devices", shortcut: nil, desc: "Desktop vs Mobile vs Tablet search traffic share", flags: ["--days"] },
      { name: "countries", shortcut: nil, desc: "Geographic search demand by country", flags: ["--days", "--limit"] },
      { name: "cities", shortcut: nil, desc: "Top visitor cities and retention via GA4", flags: ["--days", "--limit"] },
      { name: "snippets", shortcut: nil, desc: "Search appearance and rich snippet results (Reviews, Products, FAQs)", flags: ["--days"] }
    ]
  },
  {
    category: "Google Analytics 4 (GA4)",
    commands: [
      { name: "realtime", shortcut: "r", desc: "Stream live active visitors and active page paths", flags: ["--watch"] },
      { name: "pages", shortcut: nil, desc: "Top pages with views, users, and average engagement time", flags: ["--days", "--limit"] },
      { name: "sources", shortcut: nil, desc: "Traffic acquisition channels (Organic, Direct, Social, Paid)", flags: ["--days"] },
      { name: "geo", shortcut: nil, desc: "Country visitor distribution from GA4", flags: ["--days", "--limit"] },
      { name: "tech", shortcut: nil, desc: "Device category breakdown (Mobile, Desktop, Tablet)", flags: ["--days"] },
      { name: "conversions", shortcut: nil, desc: "Key event / conversion goal performance", flags: ["--days"] },
      { name: "search-terms", shortcut: nil, desc: "Internal site search query tracking", flags: ["--days"] },
      { name: "ga4", shortcut: nil, desc: "Landing page bounce rates, sessions, duration", flags: ["--organic", "--site-only", "--all-hosts"] },
      { name: "correlation", shortcut: nil, desc: "Merge GSC keyword rankings with GA4 bounce rates", flags: ["--organic", "--site-only", "--all-hosts"] },
      { name: "ads", shortcut: nil, desc: "Google Ads campaign performance (Clicks, Cost, CPC, Conversions)", flags: ["--days"] },
      { name: "ga4-properties", shortcut: nil, desc: "Discover all GA4 properties accessible by service account", flags: [] }
    ]
  },
  {
    category: "Google Indexing API & Sitemaps",
    commands: [
      { name: "inspect <url>", shortcut: nil, desc: "Live Google index check (coverage, canonical, date, robots.txt)", flags: ["-d"] },
      { name: "index <url>", shortcut: nil, desc: "Notify Googlebot to crawl/index URL immediately (URL_UPDATED)", flags: ["--dry-run"] },
      { name: "remove <url>", shortcut: nil, desc: "Notify Googlebot a page has been deleted (URL_DELETED)", flags: ["--dry-run"] },
      { name: "status <url>", shortcut: nil, desc: "Check Google Indexing API notification metadata", flags: [] },
      { name: "sitemaps-list", shortcut: nil, desc: "List registered XML sitemaps in Search Console", flags: ["-d"] },
      { name: "sitemaps-submit <url>", shortcut: nil, desc: "Submit/register XML sitemap with Search Console", flags: ["-d"] },
      { name: "index-sitemap <file/url>", shortcut: nil, desc: "Batch notify Googlebot to index all sitemap URLs", flags: ["--delay", "--dry-run"] },
      { name: "inspect-sitemap <file/url>", shortcut: nil, desc: "Bulk inspect indexation status for all sitemap URLs", flags: ["--delay"] },
      { name: "indexnow <url>", shortcut: "in", desc: "Instant indexing via IndexNow protocol (Bing, Yandex, Seznam, Naver)", flags: ["--key", "--json"] },
      { name: "indexnow-sitemap <sitemap>", shortcut: "ins", desc: "Batch submit all sitemap URLs to IndexNow", flags: ["--key", "--limit", "--json"] },
      { name: "connect indexnow [key]", shortcut: nil, desc: "Configure IndexNow API key and display verification file details", flags: [] }
    ]
  },
  {
    category: "Health, Diagnostics & Setup",
    commands: [
      { name: "serp [url|title]", shortcut: "preview", desc: "Google SERP & Title Pixel Width Simulator (Desktop & Mobile)", flags: ["--title", "--desc", "--url", "--json"] },
      { name: "page <url|file>", shortcut: "pg", desc: "Detailed On-Page DOM + Off-Page GSC Performance Audit", flags: ["--check-links", "--json"] },
      { name: "site-audit [sitemap]", shortcut: "crl", desc: "Full site crawl, broken links (404/500), image alts & AI report", flags: ["--check-links", "--report", "--json"] },
      { name: "audit", shortcut: "a", desc: "360-degree Comprehensive SEO & GA4 health audit", flags: ["--days", "-d"] },
      { name: "zombies <sitemap>", shortcut: nil, desc: "Find zero-impression crawl waste pages over 90 days", flags: [] },
      { name: "use <domain or 1-9>", shortcut: nil, desc: "Switch active default domain", flags: [] },
      { name: "domains", shortcut: nil, desc: "List verified domains and GA4 property links", flags: [] },
      { name: "where", shortcut: nil, desc: "Inspect installation path, active key, and config file", flags: [] },
      { name: "connect", shortcut: nil, desc: "1-Click Setup Wizard: auto-detects key or drag & drop", flags: [] },
      { name: "connect-ga4", shortcut: nil, desc: "Interactive GA4 linking wizard", flags: [] },
      { name: "open", shortcut: nil, desc: "Reveal configuration directory (~/.config/gsc) in Finder", flags: [] },
      { name: "prompts [id]", shortcut: "pb", desc: "25 Autonomous AI SEO Playbooks & ready-to-paste prompts", flags: ["--copy", "--json"] },
      { name: "skills [install|show]", shortcut: nil, desc: "Inspect or auto-install AI Agent Skill", flags: [] },
      { name: "commands", shortcut: nil, desc: "List all commands (human-readable or JSON with --json)", flags: ["--json"] }
    ]
  }
].freeze

    SKILL_MD_CONTENT = <<~SKILL
      ---
      name: gsc
      description: Automates Google Search Console, Google Indexing API, live URL index inspection, sitemap batch submission, and search ranking analytics (queries, impressions, positions, CTR). Trigger whenever checking SEO rankings, inspecting Google indexing status, analyzing search impressions/clicks, or notifying Googlebot of new/updated pages.
      ---
      
      # Google Search Console & Indexing API (GSC CLI) Agent Skill
      
      This skill allows AI agents (Google Antigravity, Claude Code, Cursor, Codex, etc.) to programmatically interact with Google Search Console and the Google Indexing API using the `gsc` CLI tool.
      
      ## Key Capabilities
      - **Search Analytics**: Query real keyword rankings, impressions, clicks, CTR, and average SERP positions.
      - **Growth Intelligence**: Uncover striking-distance Page 2 opportunities, CTR underperformers, and keyword cannibalization conflicts.
      - **Trend & Decay Analysis**: 28-day period-over-period decay detection (decaying, surging, new, lost).
      - **Crawl Optimization**: Scan sitemaps for 90-day zero-impression zombie pages wasting crawl budget.
      - **Instant Googlebot Indexing**: Ping Google's Indexing API with `URL_UPDATED` or `URL_DELETED` to trigger immediate crawling.
      - **Live URL Inspection**: Query Search Console API for actual index status (`PASS`, coverage state, canonical assigned by Google, crawl date).
      - **Bulk Sitemap Audit**: Inspect entire XML sitemaps to identify indexed vs queued URLs.
      - **GA4 Behavioral & Realtime**: Live visitor streaming, post-click bounce rates, engagement rates, and Google Ads ROI.
      - **Multi-domain Management**: Easily view or switch active domains across projects.
      
      ---
      
      ## Agent Rule: Always Use `--json` Flag
      When running `gsc` commands from agent tools (`run_command`), **always append `--json`** to receive clean, machine-readable JSON output instead of ANSI terminal formatting:
      
      ```bash
      gsc top-queries --json
      gsc opportunities --json
      gsc inspect https://example.com/page --json
      gsc performance --days 30 --json
      gsc realtime --json
      gsc ads --json
      gsc channels --json
      ```
      
      ---
      
      ## Common Agent Workflows
      
      ### 1. Analyzing Keyword Rankings & Opportunities
      When the user asks about traffic, rankings, or keyword performance:
      ```bash
      # Get top 20 queries for the active domain (sorted by impressions)
      gsc top-queries -s imp --limit 20 --json
      
      # Find highest-ranking queries (page 1 rankings, pos ascending)
      gsc top-queries -s pos --limit 20 --json
      
      # Find striking-distance opportunities (Page 2 keywords to push to Top 3)
      gsc opportunities --min-imp 10 --json
      
      # Find Top 10 queries with low CTR (easy title tag rewrites)
      gsc underperformers --json
      
      # Detect multiple URLs competing for the same search query
      gsc cannibalization --json
      
      # Detect traffic drops and ranking decay
      gsc decay --json
      ```
      **Interpretation Advice**:
      - Sort queries by impressions to find high-volume search terms.
      - Striking-distance keywords (position 7–20 with high impressions) are prime candidates for on-page content expansion to push them into Top 3.
      - CTR underperformers already rank on Page 1—simply rewrite their `<title>` and meta description with emotional hooks or benefit promises to double traffic.
      
      ### 2. Multi-Dimensional Performance & Geographic Analytics
      When the user asks for high-level performance, devices, country breakdown, or search appearances:
      ```bash
      # Full 360° executive dashboard (Totals, Devices, Countries, Snippets, Queries, Pages, Cities)
      gsc performance --days 30 --json
      
      # Device breakdown (Desktop vs Mobile vs Tablet clicks share)
      gsc devices --json
      
      # Top countries driving organic search impressions & clicks
      gsc countries --limit 20 --json
      
      # Top visitor cities and on-site engagement (via GA4)
      gsc cities --limit 20 --json
      
      # Search appearance & rich snippets (Review stars, Product snippets, FAQ rich results)
      gsc snippets --json
      ```
      
      ### 3. Inspecting Page Index Status
      When the user asks if a specific URL is indexed or why it's not showing up on Google:
      ```bash
      gsc inspect https://example.com/features/new-feature --json
      ```
      **Interpreting the JSON Response**:
      - `verdict: "PASS"`: The page is successfully indexed and eligible for search results.
      - `coverageState: "Crawled - currently not indexed"`: Google crawled the page but decided not to index it (often due to thin content, duplicate canonical, or low internal linking).
      - `coverageState: "Discovered - currently not indexed"`: Google knows about the URL (via sitemap or link) but has not yet crawled it. You can trigger `gsc index <url>` to accelerate crawling.
      - `robotsTxtState: "DISALLOWED"`: The page is blocked by `robots.txt`.
      
      ### 3. Pinging Googlebot After Creating/Updating Content
      Whenever you generate a new blog post, landing page, or programmatic SEO route, notify Googlebot immediately:
      ```bash
      gsc index https://example.com/blog/new-post --json
      ```
      *(If a page was permanently deleted, use `gsc remove <url> --json` to protect store crawl health).*
      
      ### 4. Auditing Sitemaps
      To bulk check whether all URLs in a sitemap are actually indexed:
      ```bash
      gsc inspect-sitemap https://example.com/sitemap.xml --delay 300 --json
      ```
      
      ### 5. Managing Active Domains & Credentials
      ```bash
      # Check current environment & key
      gsc where --json
      
      # List all verified domain properties accessible by key
      gsc domains --json
      
      # Set or switch active domain globally
      gsc use example.com --json
      ```
      
      ### 6. GA4 Behavioral, Realtime & Google Ads Analytics
      ```bash
      # Stream live active visitors on site right now
      gsc realtime --json
      
      # Top landing pages with bounce rates, duration, and engagement
      gsc ga4 --organic --json
      
      # Correlate pre-click GSC search queries with post-click GA4 bounce rates
      gsc correlation --json
      
      # Google Ads campaign performance (clicks, cost, CPC, conversions, CPA)
      gsc ads --json
      
      # Omnichannel traffic sources breakdown (Organic, Paid, Direct, Referral)
      gsc channels --json
      ```
      
      ---
      
      ### 7. Working with Saved Domain Keyword Libraries & Research
      GSC CLI maintains persistent, domain-scoped keyword research libraries in `~/.config/gsc/domains/<domain>/keywords/`. AI agents can use these archives to track target keywords over time and measure ranking progress:
      
      ```bash
      # List all saved research snapshots for the active domain
      gsc saved --json
      
      # Inspect keyword metrics (Volume, CPC, Competition Tier, Opportunity Score, 12m trends)
      gsc saved view 1 --json
      
      # Re-check an archived research snapshot against live Google Search Console rankings
      gsc saved check 1 --json
      ```
      
      **Agent Strategy for Saved Keywords**:
      - When the user asks *"What keywords should we target next?"* or *"How are our target keywords performing?"*, run `gsc saved --json` and inspect recent archives with `gsc saved check 1 --json`.
      - Identify keywords flagged as `🚀 Untargeted` (keywords with high search volume and high opportunity score where your domain currently has 0 impressions): these are prime candidates for **new landing pages, programmatic SEO templates, or blog posts**.
      - Identify keywords in `🎯 Page 2 Striking Distance` (positions 7–20): these are prime candidates for **on-page content expansion, internal link additions, and title tag rewrites**.
      
      ---
      
      ### 8. Autonomous Title & Meta Description Optimization Loop
      AI agents can execute a full, closed-loop title and CTR optimization cycle:
      
      ```
      [1. Identify Opportunities] ➔ [2. Inspect Current Code] ➔ [3. Rewrite Title & Meta] ➔ [4. Ping Googlebot]
      ```
      
      #### Step 1: Discover CTR Underperformers & Striking-Distance Keywords
      ```bash
      # Find Page 1 queries with high impressions but below-average CTR
      gsc underperformers --json
      
      # Find striking-distance queries (positions 7-20) with high impressions
      gsc opportunities --min-imp 20 --json
      ```
      
      #### Step 2: Locate the Page in Codebase
      Locate the corresponding template or page in the application repository (e.g. Rails views, Svelte pages, Next.js routes, or HTML templates).
      
      #### Step 3: Apply the High-CTR Title & Description Formula
      Rewrite `<title>` and `<meta name="description">` according to these strict rules:
      1. **Front-Load the Exact Query**: Place the highest-impression search query in the first 30 characters of `<title>`.
      2. **Optimal Length**: Keep `<title>` between **50 and 60 characters** (maximum 580px width) so Google does not truncate with `...`.
      3. **Emotional Hook / CTR Multiplier**: Include brackets `[Free Calculator]`, actionable numbers (`10 Best`, `2026 Checklist`), or primary value props.
      4. **Brand Suffix**: Always append ` | BrandName` at the end.
      5. **Meta Description**: 130–155 characters summarizing the page benefit with a clear call-to-action (e.g. *"Calculate exact moving box counts by room, size, and weight. Free instant estimator."*).
      6. **Heading Polish**: Ensure `<h1>` matches search intent and **never ends with a period (`.`)**.
      
      #### Step 4: Immediately Trigger Googlebot Indexing
      ```bash
      # Push the updated URL to Google Indexing API for rapid re-crawl within hours
      gsc index https://example.com/optimized-page --json
      ```
      
      ---
      
      ### 9. Google Trends & Universal Keyword Ingestion
      When researching new topics or expanding keyword coverage:
      ```bash
      # Real-time search demand curve, rising breakout queries, and seasonal interest
      gsc trends "moving checklist" --json
      
      # Universal import from Keywords Everywhere CSV/TSV or Google Keyword Planner export
      gsc import path/to/keywords.csv --json
      
      # Ingest copied table directly from clipboard (from 500 free daily web lookups)
      gsc import clip --json
      ```
      
      ---
      
      ---
      
      ### 10. AI SEO Playbook Catalog & Ready-to-Run Prompts (`gsc prompts`)
      GSC CLI includes a curated registry of **25 battle-tested, high-impact AI SEO Playbooks** with dynamically rendered prompts and underlying CLI commands:
      
      ```bash
      # Query all 25 intelligent SEO playbooks in structured JSON
      gsc prompts --json
      
      # Query a specific playbook by ID
      gsc prompt 5 --json
      ```
      
      #### The 6 Strategic Playbook Categories:
      1. **🚀 Growth & Striking Distance (Playbooks 1–4)**: Page 2 leaps (positions 8–18), untargeted keyword goldmines, Google Trends seasonal surges, and long-tail autocomplete multipliers.
      2. **🎯 Conversion & CTR Multipliers (Playbooks 5–8)**: CTR underperformer doubles (<2% CTR on Page 1), Review/FAQ rich snippet enablers, <h1> headline alignment, and keyword cannibalization consolidation.
      3. **📊 GA4 Behavioral & Ad Synergy (Playbooks 9–12)**: High-bounce traffic leak pluggers, real-time traffic wave riders, Google Ads vs Organic synergy (cut wasted ad spend), and omni-channel attribution audits.
      4. **🛠️ Technical Health & Crawl Optimization (Playbooks 13–16)**: 90-day zombie page crawl purges, sitemap coverage & indexing blitzes, ranking decay early warning alerts, and lost query resuscitation.
      5. **⚡ Programmatic SEO & Scaling (Playbooks 17–20)**: Programmatic landing page generators from saved keyword archives, competitor gap exploitation, zero-click search/AI Overview winning strategies, and mobile vs desktop SERP parity.
      6. **📋 Executive Briefings & Daily Standups (Playbooks 21–25)**: 360° C-Suite monthly health briefings, new feature launch indexing blitzes, international market expansion diagnostics, and 5-minute daily SEO standups.
      
      **Agent Playbook Execution Protocol**:
      When the user asks open-ended questions like *"How can we grow traffic this week?"* or *"What SEO tasks should we work on?"*:
      1. Run `gsc prompts --json` to load the playbook library.
      2. Run `gsc performance --days 30 --json` and `gsc saved check 1 --json` to diagnose site opportunities.
      3. Select the 2–3 highest-impact playbooks for the site's current state and present them clearly to the user, offering to execute them immediately.
      
      ## Error Handling & Onboarding
      - If `gsc` returns an error about missing credentials: Direct the user to run `gsc connect` in their terminal (which automatically scans `~/Downloads` for service account JSON keys or accepts a drag-and-drop), or run `gsc open` to reveal `~/.config/gsc/` in Finder.
      - If `gsc` returns an error about permission restricted in Search Console: Ensure the service account email is added as an **Owner** in Google Search Console Settings -> Users and permissions.
      - If `gsc` returns a 403 error for Google Analytics: Open Google Analytics (Admin > Account Access Management or Property Access Management), click '+', paste the service account email, and assign the **Viewer** role.
      - If `gsc ke` returns `402 Insufficient Credits`: Inform the user that the REST API requires purchased credits, but they can perform 500 free daily lookups on `keywordseverywhere.com/tools/bulk-keywords-data`, click **Copy**, and run `gsc import clip` to ingest the data with full opportunity scoring and sparklines for free!
      

    SKILL
  end

  COMMAND_REGISTRY = CommandRegistry::COMMAND_REGISTRY
  SKILL_MD_CONTENT = CommandRegistry::SKILL_MD_CONTENT
end

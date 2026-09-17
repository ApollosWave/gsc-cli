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

## High-Performance Networking & Gzip Compression
GSC CLI automatically requests and handles **gzip compression** (`Accept-Encoding: gzip`, `User-Agent: gsc-cli (gzip)`) on all Search Console endpoints using pure Ruby standard library `zlib`, achieving **up to 80% bandwidth reduction** on high-volume queries and sitemap audits.

## Complete Data Ingestion (`--all` Pagination)
By default, query commands return up to `--limit <n>` rows (default: 50). To retrieve **100% of all search queries or pages** without truncation, append `--all`:
```bash
# Fetch every single search query via automated startRow pagination
gsc top-queries --all --json

# Fetch every indexed landing page via automated startRow pagination
gsc top-pages --all --json
```

## Agent Rule: Optimize Token Consumption (`--compact`, `--ndjson`, `--csv`)

When running `gsc` commands from agent tools (`run_command`), **always append machine-readable flags** to receive clean, deterministic output instead of ANSI terminal formatting:

- **`--compact` (Recommended for AI Agents)**: Single-line minified JSON. Saves **35–45% LLM tokens**, allowing you to ingest 2x more search performance data within identical context windows.
- **`--ndjson`**: Newline-delimited JSON streaming. Ideal for line-by-line streaming, grep, or subagent tasks.
- **`--csv`**: Ultra-compact tabular data. Saves **65–75% LLM tokens** on high-volume keyword and landing page queries.
- **`--json`**: Standard 2-space indented JSON.

```bash
# Recommended for lowest LLM token usage:
gsc top-queries --limit 20 --compact
gsc opportunities --min-imp 20 --compact
gsc strike --limit 15 --compact
gsc inspect https://example.com/page --compact
gsc performance --days 30 --compact
gsc realtime --compact
gsc ads --compact
gsc channels --compact
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

### 8. Detailed On-Page & Off-Page SEO Merger (`gsc page`)
Analyze any live URL or local HTML/template file (`.html`, `.svelte`, `.erb`) with the DOM inspection engine inspired by Detailed SEO Extension, merged with real Google Search Console 90-day search queries:
```bash
# 360° On-Page DOM + Real Search Console Rankings & CTR
gsc page https://example.com/ --compact

# Deep verification: test HTTP response codes (200, 404, 500) for all internal links
gsc page https://example.com/ --check-links

# Local file auditing before deployment
gsc page src/routes/+page.svelte
```
**Metrics Extracted & Audited**:
- **Title Tag**: Character count, SERP pixel estimation (flags > 568px truncation risk).
- **Meta Description**: Optimal 70–155 character compliance.
- **Canonical URL**: Self-referencing verification vs external canonicals.
- **Headings Hierarchy**: Indented H1–H6 visual tree, flags missing or duplicate `<h1>`.
- **Images & Accessibility**: Total images, missing `alt` attributes count & image URLs.
- **Link Architecture**: Internal vs external link count, nofollow count, broken link status codes.
- **Structured Data**: Application/ld+json schemas (SoftwareApplication, Offer, FAQ, etc.).
- **Social Graph**: Open Graph (`og:*`) and Twitter Card tags.
- **GSC Search Synergy**: Merges page-specific clicks, impressions, CTR, average position, and top 5 ranking queries directly from Search Console API.

---

### 9. Autonomous Site Crawler & Broken Link Repair (`gsc site-audit`)
Crawl all pages in a sitemap (or discover from domain), audit DOM defects, check for dead links (404/500), and generate an AI-actionable Markdown fix sprint:
```bash
# Crawl entire sitemap and emit actionable repair sprint
gsc site-audit https://example.com/sitemap.xml --report docs/seo/site_audit_issues.md

# Verify all links across first 20 pages with dead link testing
gsc site-audit example.com --limit 20 --check-links --report docs/seo/site_audit_issues.md

# Machine-readable JSON output for automated agent remediation
gsc site-audit https://example.com/sitemap.xml --limit 10 --compact
```
**Actionable Fix Report Includes**:
1. **Executive Health Scorecard**: Total pages, critical crawl errors, broken links, missing alts, and heading flaws.
2. **Broken Link Table**: Dead source URL, broken target link, anchor text, and HTTP status code.
3. **Missing Alt Attributes**: Exact image URLs and template fix recommendations.
4. **H1 & Heading Flaws**: Zero or multiple `<h1>` occurrences.
5. **SERP Truncation Flaws**: Titles > 60 chars or < 30 chars, meta descriptions > 155 chars.
6. **Prioritized AI Fix Sprint**: Step-by-step instructions for AI coding agents to edit templates and trigger immediate re-indexing (`gsc index <url>`).

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
5. **Meta Description**: 130–155 characters summarizing the page benefit with a clear call-to-action (e.g. *"Inspect technical SEO health, Core Web Vitals, and index coverage instantly. Free diagnostic audit."*).
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
GSC CLI includes a curated registry of **26 battle-tested, high-impact AI SEO Playbooks (including Playbook #0: Master 360° Multi-Horizon Audit)** with dynamically rendered prompts and underlying CLI commands:

```bash
# Query all 25 intelligent SEO playbooks in structured JSON
gsc prompts --json

# Query a specific playbook by ID
gsc prompt 5 --json
```

#### 👑 Master 360° Multi-Horizon Audit (Playbook 0):
- **Playbook #0: The 360° Multi-Horizon Master SEO & Universal Keyword Audit**: Exhaustive multi-horizon audit (30d, 90d, 180d) across all keywords (saved & unsaved), Google Trends demand, post-click GA4 engagement, crawl budget, and programmatic opportunity gaps.

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


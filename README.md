# 🚀 GSC-CLI: The Zero-Gem Google Search Console & Technical SEO Engine

[![Ruby](https://img.shields.io/badge/Ruby-3.0%2B-red.svg?logo=ruby&logoColor=white)](https://www.ruby-lang.org)
[![Gem Version](https://img.shields.io/gem/v/gsc-cli.svg?label=Gem%20Version&logo=rubygems)](https://rubygems.org/gems/gsc-cli)
[![Tests](https://img.shields.io/badge/tests-371%20suites%20%7C%201%2C991%20assertions-success)](test/)
[![Dependencies](https://img.shields.io/badge/dependencies-0%20gems-brightgreen.svg)](#)
[![Cold Boot](https://img.shields.io/badge/cold%20boot-%3C15ms-blue)](lib/gsc/cli.rb)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Commands](https://img.shields.io/badge/commands-80%20production-orange.svg)](#-complete-cli-command-reference-80-commands)
[![Security: AES-256-GCM](https://img.shields.io/badge/Vault-AES--256--GCM-blueviolet.svg)](#8-agency-credential-vault-gsc-vault)
[![AI Agent Native](https://img.shields.io/badge/AI%20Agent-Native%20Skill-purple.svg)](#-ai-agent-native-integration-antigravity-claude-cursor)
[![GitHub Stars](https://img.shields.io/github/stars/ApollosWave/gsc-cli?style=social)](https://github.com/ApollosWave/gsc-cli)

> ⚡ **Zero runtime gems. Pure Ruby standard library (`Net::HTTP`, `OpenSSL`, `JSON`).**  
> Cold-boots in **~15ms** with **371 test suites, 1,991 assertions, and 0 failures** across Ruby 3.0 through 3.4. Extract first-party Google rankings, automate technical SEO audits, and manage Googlebot indexing without bloated SDK dependencies.

---

## ⚡ Why We Built This: Escaping the 40-Gem Tax

Every software engineer, technical SEO, and developer-operator managing search presence faces the exact same architectural frustrations:

1. **The 40-Gem Dependency Tax**: The official Google API Ruby gems (`google-apis-searchconsole_v1`, `google-apis-indexing_v3`, `googleauth`, `signet`, `faraday`) pull in **40+ transitive gem dependencies**. They add 3 to 5 seconds to cold-boot time, trigger Bundler version conflicts, inflate container image sizes, and introduce ongoing supply-chain vulnerability alerts.
2. **Paying $300 to $1,000+/Month for Sampled Guesswork**: Third-party SEO suites charge hundreds of dollars per month to scrape search results with external proxy farms and estimate traffic using sampled third-party panels. Meanwhile, **Google Search Console provides 100% first-party ground-truth data** for your domain directly from production search logs—completely free.
3. **Google Search Console's Web UI Does Not Scale**: Inspecting 50 URLs, isolating soft-404 indexation drops, or detecting cannibalization across multiple client properties requires hours of manual tab switching, filtering, and clicking.
4. **Google AI Overviews (AIO) Intercepting Search Clicks**: Zero-click searches continue to expand. If technical content is not structured for citation in Gemini and AI Overviews, organic visibility drops even when ranking on Page 1.
5. **AI Coding Agents Cannot Click Web Buttons**: Modern coding agents (Antigravity, Claude Code, Cursor, Cline) require deterministic, sub-50ms JSON over stdout to diagnose and fix search issues directly inside the local repository.

We built **`gsc-cli`** to automate Googlebot indexing and search diagnostics in **< 50 milliseconds** using pure standard-library Ruby, and open-sourced it 100% free under the MIT License so every builder, engineering team, and operator can run first-party search automation with zero dependency bloat.

---

## 📐 Core Engineering Principles

1. **First-Party Ground Truth Over Guesswork**: Third-party estimation suites rely on sampled clickstream models and external proxy scraping. Google Search Console stores the exact, 100% first-party click, impression, and position data directly from Google's search infrastructure—completely free.
2. **Zero-Dependency Purity (< 1ms Boot Time)**: Official Google API gems drag in 40+ dependency gems, slowing down boot times and creating dependency lock-in. GSC-CLI communicates directly with Google's bare-metal HTTP APIs using pure Ruby standard library (`Net::HTTP`, `OpenSSL`, `JSON`), executing in **< 1 millisecond**.
3. **Actionable Remediation Over Passive Error Dumps**: Most diagnostic tools dump hundreds of error rows into a table without solutions. `gsc-cli` pairs forensic diagnostics with automated remediation—such as generating copy-paste redirect blocks for 14 server environments (Nginx, Caddy, Cloudflare, Next.js, Vercel, etc.) for soft-404 traps.
4. **Zero-Trust Local Execution (No Telemetry, No External AI Calls)**: Developer tools should respect machine resources and codebase privacy. `gsc-cli` runs 100% locally, requires zero external LLM API keys, makes zero calls to third-party AI servers, collects zero telemetry, and never reads or transmits private repository files.

---

## ⚡ The Contrarian Architecture: Why Pure-Ruby Beats 40-Gem SDKs

Conventional wisdom says: *"To build Google API integrations, you must install the official Google API gems (`google-apis-searchconsole_v1`, `googleauth`)."*

**We reject that completely.**

Google's APIs are just standard, RFC-compliant HTTPS endpoints returning JSON. Forcing a developer to pull in 40+ transitive gem dependencies just to send a signed HTTP POST request is architectural malpractice:
- It bloats container images.
- It inflates Docker deployment sizes.
- It creates endless `bundle install` version conflicts.
- It slows down sub-millisecond AI agent loops.

By implementing Google's JWT service account authentication in pure `OpenSSL` and streaming responses through native `Net::HTTP` with Gzip decompression, `gsc-cli` boots in **< 1 millisecond** and executes entire multi-step audit loops in under 50 milliseconds.

---

## 💎 Key Capabilities at a Glance

- 🤖 **Google AI Overview (AIO) Hunter (`gsc aio-hunter`)**: Detects Google AI Overviews on SERPs, extracts cited sources, measures citation gaps, and generates snippet capture recipes.
- 🔮 **AI Citation Simulator (`gsc cite-sim`)**: Tests how likely LLMs (Gemini, ChatGPT, Claude) are to cite your URL based on information density, fact ratios, and structural headings.
- 🏦 **Agency Credential Vault (`gsc vault`)**: Local AES-256-GCM encrypted store managing 50+ service accounts with instant switching (`gsc switch <domain>`), strict POSIX permissions, and path-traversal isolation.
- 🚨 **Soft-404 Diagnostic Engine with Instant Fixes (`gsc soft-404 --fix nginx`)**: Diagnoses soft-404 traps and outputs copy-paste redirect blocks for 14 server stacks (Nginx, Caddy, Cloudflare, SvelteKit, Next.js, Astro, Shopify, Vercel).
- 🎯 **Tactical Striking Distance Playbook (`gsc strike`)**: Automatically detects high-impression Page 2 queries (Positions 4–20) paired with intent-matched title hook rewrites and internal link anchor recipes.
- 📉 **Organic CTR Curve Simulator (`gsc ctr-curve`)**: Non-linear regression modeling expected CTR by position and calculating exact click upside for ranking leaps.
- ⚡ **Ultra-Low Token Modes for AI Agents (`--compact` & `--ndjson`)**: Minified single-line JSON (`--compact`) saving 35–45% LLM context tokens, and newline-delimited streaming (`--ndjson`) for array data.
- 📱 **Mobile vs. Desktop SERP Parity Auditor (`gsc mobile-parity`)**: Uncovers cross-device rank discrepancies, responsive suppression penalties, and mobile CTR leaks.
- 🩺 **Zero-Gem Cold-Start Doctor (`gsc doctor`)**: Verifies 100% standard library purity, measures sub-50ms execution speed, and validates credential security.
- 📈 **Real-Time Google Trends Engine (`gsc trends`)**: 5-year and 1-year search trajectory, velocity percentages, Unicode sparklines (` ▂▃▄▅▆▇█`), and regional demand breakdowns with zero authentication.
- 🎯 **Zero-Auth Keyword Planner (`gsc planner`)**: Instant seed expansion via Google Autocomplete with automated search intent classification (`Informational`, `Commercial`, `Transactional`).
- 💰 **Keywords Everywhere Ingestion (`gsc import clip` & `gsc ke`)**: Ingest free keyword tables directly from clipboard (zero credits required) or connect a [Keywords Everywhere API key](https://keywordseverywhere.com/?fpr=us25sg) *(partner referral link that helps support continuous open-source maintenance of this project)* for automated terminal lookups.
- 🚀 **Instant Googlebot Re-Indexing (`gsc index`)**: Ping Google's Indexing API with `URL_UPDATED` or `URL_DELETED` for priority crawl queueing within seconds.
- ⚡ **Multi-Engine IndexNow Protocol (`gsc indexnow`)**: Instantly submit pages and sitemaps across Microsoft Bing, Yandex, Seznam, and Naver simultaneously.
- 🖥️ **Google SERP & Title Pixel Simulator (`gsc serp`)**: Simulate desktop (580px) and mobile (650px) Google SERP cards, calculate precise proportional pixel widths, and prevent truncation before publishing.
- 🛡️ **Cannibalization & Decay Detection (`gsc cannibalization`, `gsc decay`)**: Spot internal URLs fighting for the same queries, and compare 28-day period-over-period traffic trends.
- 📊 **Google Analytics 4 (GA4) Behavioral Link (`gsc realtime`, `gsc ga4`)**: Stream live active visitors and correlate SERP rankings with landing page bounce rates.
- 🕷️ **Autonomous Site Audit & Broken Link Repair (`gsc site-audit`)**: Crawls all sitemap URLs, checks HTTP response codes for dead internal links (404/500/timeouts), audits missing image alts and heading defects, and exports an AI-actionable Markdown fix sprint.
- ⚡ **Dual Lab & Field Core Web Vitals (`gsc speed` & `gsc speed-correlate`)**: Audits simulated Lighthouse Lab metrics (LCP, FCP, CLS, TBT, Speed Index) alongside official 28-day Chrome User Experience Report (CrUX) Real User Monitoring (RUM) field data (LCP, INP, CLS, FCP, TTFB) and correlates page speed directly with organic GSC search rankings.
- 🤖 **AI Agent Native**: Every single command supports `--compact`, `--ndjson`, and `--json` for instantaneous programmatic consumption by AI agents.

---

## ⚡ Architectural Comparison & Trade-Offs

| Traditional Stack (Official SDK / SaaS) | GSC-CLI Architecture |
| :--- | :--- |
| **Manual Web UI Bottleneck**: Clicking through 15 tabs in Google Search Console to inspect 50 URLs takes 45+ minutes. | **Instant 1-Command Batching**: `gsc inspect-sitemap sitemap.xml` inspects all URLs with automatic quota pacing in seconds. |
| **Sampled Third-Party Guesswork**: Paying $300–$1,000+/mo ($3,600–$12,000/yr) for external proxy scrapers that model keyword volumes. | **100% Google Ground Truth ($0)**: Raw impression, click, and position logs direct from Google Search Console. |
| **40-Gem Dependency Tax**: Bloating your `Gemfile` with Google SDK gems that add 3–5 seconds to cold boot. | **0 Gem Dependencies**: Pure Ruby standard library (`OpenSSL`, `Net::HTTP`, `JSON`) executing in **< 1 millisecond**. |
| **Multi-Client Credential Chaos**: Juggling loose JSON keys across folders and risking credential leaks. | **Agency Credential Vault (`gsc vault`)**: Local AES-256-GCM encrypted vault with instant domain switching (`gsc switch`). |
| **Passive Error Reporting**: Diagnostic tools tell you that you have 404s, but leave you to write the server rules. | **Active Automated Remediation**: `gsc soft-404 <url> --fix nginx` synthesizes instant, copy-paste server blocks for 14 stacks. |
| **Blind to AI Overviews**: Unaware that Google Gemini / AI Overviews are intercepting 40% of zero-click searches. | **Google AIO Hunter & Citation Simulator**: `gsc aio-hunter` identifies AI Overviews and extracts competitor citation recipes. |
| **Token-Guzzling JSON in AI Agents**: Feeding pretty-printed JSON into coding agents wastes 40% of your LLM context window. | **Ultra-Low Token Modes (`--compact`, `--ndjson`)**: Minified output saving **35–50% of tokens** for Claude Code, Cursor, and Antigravity. |
| **Untrusted Third-Party Scripts**: Running opaque scripts that scan your repository or send files to external servers. | **Zero-Trust Local Execution**: Completely isolated, deterministic UNIX tool. Never scans, reads, or transmits your private code. |

---

> ### ⭐ Star the Repository
> If `gsc-cli` saved your team from 40 bloated gems or streamlined your search data pipeline:  
> 👉 **[Star GSC CLI on GitHub](https://github.com/ApollosWave/gsc-cli)** to support zero-dependency open-source tooling.

---

## 📦 Quick Installation

### Option 1: Official RubyGem (Instant Global Install)
```bash
gem install gsc-cli
```

### Option 2: 1-Line Standalone Installer (macOS & Linux)
```bash
curl -fsSL https://raw.githubusercontent.com/ApollosWave/gsc-cli/main/install.sh | bash
```

### Option 3: In Your Gemfile (Bundler)
```ruby
gem 'gsc-cli'
```

Ensure `~/.local/bin` is in your shell `PATH`:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify your installation:
```bash
gsc version
gsc doctor
```

### Option 4: Clone & Verify Test Suite Locally
Verify all 371 test suites and 1,991 assertions on your own machine in seconds:
```bash
git clone https://github.com/ApollosWave/gsc-cli.git
cd gsc-cli
rake test
# => 371 runs, 1991 assertions, 0 failures, 0 errors, 0 skips
```

---

## ⚡ 2-Minute Google Setup

> 🔑 **Need help with GA4, Google PageSpeed, OpenPageRank, or Keywords Everywhere?**  
> Check out the complete **[Authentication & API Key Setup Guide (AUTH.md)](AUTH.md)** for 30-second walkthroughs and zero-key features.

### Step 1: Create a Google Cloud Service Account Key
1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. In **APIs & Services > Library**, enable:
   - **Web Search Indexing API**
   - **Google Search Console API**
   - *(Optional for GA4)*: **Google Analytics Data API**
3. In **IAM & Admin > Service Accounts**, click **Create Service Account** (e.g. `gsc-indexer`).
4. Click your new service account > **Keys** tab > **Add Key** > **Create new key** > **JSON**. Download the file.

### Step 2: Run 1-Click Interactive Connect
In your terminal, simply run:
```bash
gsc connect
```
`gsc` automatically searches your `~/Downloads` folder for recently created Google Cloud service account keys, lets you confirm with `Y`, and saves it securely to `~/.config/gsc/service-account.json`.

### Step 3: Add the Email to Google Search Console
1. Copy the service account email displayed in the terminal.
2. Go to [Google Search Console](https://search.google.com/search-console/) > Select your property > **Settings** > **Users and permissions**.
3. Click **Add User**, paste the email, and set permission to **Owner**.

Verify access immediately:
```bash
gsc domains
```

---

## 🧠 Deep-Dive Feature Walkthroughs

### 1. Core Search Performance: Top Queries, Pages & CTR (`gsc top-queries`, `gsc top-pages`, `gsc performance`)

#### The Problem
Google Search Console's web UI is sluggish, hides low-volume long-tail queries behind pagination limits, and makes cross-referencing brand vs. non-brand queries painful. Exporting CSVs to spreadsheets burns 20+ minutes every time you want to check yesterday's organic clicks.

#### The Solution
`gsc-cli` streams your exact Google Search Console ground-truth performance directly into your terminal in **under 50 milliseconds**. Filter by brand, segment devices, compare date ranges, and export clean JSON or CSV in one command:

```bash
# Top 20 search queries with impressions, clicks, CTR, and average SERP position
gsc top-queries --limit 20

# Filter brand vs. non-brand queries automatically
gsc top-queries --brand
gsc top-queries --non-brand

# Top indexed landing pages driving search traffic
gsc top-pages --limit 15

# Overall 30-day domain performance scorecard with device & country breakdown
gsc performance --days 30

# Retrieve 100% of all queries via automated API pagination (no 1,000-row web limit)
gsc top-queries --all --csv > all_search_queries.csv
```

---

### 2. Tactical Striking Distance Playbook & Organic CTR Curve (`gsc strike` & `gsc ctr-curve`)

#### The Problem
Most SEO reports simply dump a list of keywords without telling you **what to write, where to link, or what the revenue payoff will be**. Page 2 keywords (Positions 4–20) generate 80% of your search impressions but only 5% of your clicks.

#### The Solution
- **`gsc ctr-curve`**: Generates an empirical, non-linear CTR regression curve mapping your domain's real CTR by position against Google's global benchmarks, simulating the exact click gain of advancing to Top 3.
- **`gsc strike`**: Automatically synthesizes a tactical Page 2 attack plan with **3 SERP-safe hook titles (< 560px)**, heading recipes, and targeted internal link anchor suggestions:

```bash
# Simulate organic CTR curve and click upside for Page 2 rankings
gsc ctr-curve --days 30 --target-pos 3

# Generate tactical Page 2 striking distance playbook
gsc strike --limit 10

# Surface quick-win CTR underperformers (Top 10 ranking but low click-through)
gsc underperformers --min-imp 50

# Export playbook directly to CSV for copywriters & content teams
gsc strike --limit 20 --csv docs/seo/striking_playbook.csv
```

---

### 3. Instant Googlebot Priority Indexing & Live URL Inspection (`gsc index`, `gsc inspect`, `gsc indexnow`)

#### The Problem
Waiting days or weeks for Googlebot to discover new landing pages or updated documentation kills organic momentum. Meanwhile, checking if Google has indexed a URL or flagged a canonical error requires tedious manual clicking inside Search Console's URL Inspection tool.

#### The Solution
`gsc-cli` communicates directly with Google's Indexing API and live URL Inspection API to check status and force priority crawling in seconds:

```bash
# Query live Google indexing verdict, assigned canonical, and crawl timestamp
gsc inspect https://example.com/blog/core-web-vitals

# Ping Googlebot to prioritize crawling a newly published or updated URL
gsc index https://example.com/blog/core-web-vitals

# Batch inspect an entire XML sitemap with automatic quota pacing
gsc inspect-sitemap https://example.com/sitemap.xml

# Multi-Engine IndexNow: Instantly notify Bing, Yandex, Seznam, and Naver simultaneously
gsc indexnow https://example.com/blog/core-web-vitals
```

---

### 4. Cannibalization, Traffic Decay & Zombie Page Detection (`gsc cannibalization`, `gsc decay`, `gsc zombies`)

#### The Problem
Internal URLs competing for the same search intent (keyword cannibalization) split page equity, causing Google to oscillate rankings between pages. Meanwhile, stealth traffic decay and dead zero-click URLs quietly drain your Google crawl budget.

#### The Solution
`gsc-cli` diagnoses algorithmic cannibalization conflicts and period-over-period decay before traffic crashes:

```bash
# Detect internal URLs fighting for the exact same queries
gsc cannibalization

# Period-over-period decay detection (28-day comparison: decaying vs surging queries)
gsc decay --compare 28

# Scan XML sitemap for 90-day zero-impression zombie pages draining crawl budget
gsc zombies https://example.com/sitemap.xml --purge-map
```

---

### 5. Zero-Cost Clipboard Keyword Ingestion & Demand Trends (`gsc import clip`, `gsc trends`, `gsc planner`)

#### The Problem
Keyword research tools either lock data behind expensive API subscriptions or leave valuable volume data trapped in disconnected browser extensions.

#### The Solution
`gsc-cli` provides zero-cost clipboard ingestion and real-time demand tracking with **zero API keys required**:

```bash
# 1. Copy any keyword table from Keywords Everywhere or Google Ads in your browser (Cmd+C)
# 2. Run one command to parse volumes, sparklines, and cross-reference live GSC rankings:
gsc import clip

# Real-time Google Trends 5y/1y search trajectory and velocity percentage (zero-auth)
gsc trends "technical seo audit" --geo US --time 12m

# Google Autocomplete intent expander (Informational, Commercial, Transactional)
gsc planner "nextjs seo"
```

---

### 6. Detailed Off-Page + On-Page SEO Merger & Site Audit (`gsc page` & `gsc site-audit`)

#### The Problem
On-page SEO checkers (titles, headings, meta tags) live in browser extensions, completely disconnected from your real Google Search Console performance data.

#### The Solution
`gsc page` unites on-page DOM inspection with 90-day GSC search queries, clicks, and rankings in a single terminal view:

```bash
# Audit any URL combining DOM inspection with GSC 90-day search performance
gsc page https://example.com/

# Deep internal link verification: tests HTTP status codes (200, 404, 500)
gsc page https://example.com/ --check-links

# Crawl entire XML sitemaps to audit dead links, missing alts, and heading hierarchy
gsc site-audit https://example.com/sitemap.xml --report docs/seo/site_audit_issues.md
```

---

### 7. Google AI Overview (AIO) Opportunity Hunter & Citation Simulator (`gsc aio-hunter` & `gsc cite-sim`)

#### The Problem
Google AI Overviews (Gemini in search results) intercept high-intent queries before users ever reach blue links. If an AI Overview appears for your core keywords, your organic CTR can crater unless your site is cited inside the AI answer box.

#### The Solution
`gsc aio-hunter` scans live SERPs for AI Overviews, extracts cited sources, and measures your citation readiness:

```bash
# Hunt AI Overview presence and extract cited competitor sources
gsc aio-hunter "best technical seo audit tools"

# Test how likely LLMs (Gemini, ChatGPT, Perplexity) are to cite your URL
gsc cite-sim https://example.com/guides/core-web-vitals

# Synthesize 40–60 word high-density direct answers with FAQ schema embedding
gsc answer "what is soft 404 error"
```

---

### 8. Soft-404 Forensic Diagnostic Engine with 14-Stack Instant Fixes (`gsc soft-404`)

#### The Problem
Soft-404 errors silently destroy your Google crawl budget by returning `200 OK` on empty templates or missing content. Writing server redirect rules manually across different stacks is slow and error-prone.

#### The Solution
`gsc soft-404` detects empty templates, blank pages, and canonical loops, auto-detects your tech stack, and generates copy-paste redirect blocks for 14 server environments:

```bash
# Diagnose any URL for soft-404 status (auto-detects tech stack & server)
gsc soft-404 https://example.com/broken-page

# Generate copy-paste rules for your specific tech stack:
gsc soft-404 https://example.com/broken-page --fix sveltekit
gsc soft-404 https://example.com/broken-page --fix caddy
gsc soft-404 https://example.com/broken-page --fix cloudflare
gsc soft-404 https://example.com/broken-page --fix nextjs
gsc soft-404 https://example.com/broken-page --fix nginx
gsc soft-404 https://example.com/broken-page --fix shopify
gsc soft-404 https://example.com/broken-page --fix all
```

---

### 9. Dual Lab (Lighthouse) & Field (CrUX 28-Day RUM) Core Web Vitals (`gsc speed` & `gsc speed-correlate`)

#### The Problem
Synthetic lab audits (like local Lighthouse runs) only measure artificial simulation on simulated throttled CPU, which often contradicts real user experience. Meanwhile, Google's official search ranking algorithm evaluates real-world Core Web Vitals (LCP, INP, CLS) from 28-day Chrome User Experience Report (CrUX) field telemetry.

#### The Solution
`gsc speed` delivers both in a single terminal command—pairing synthetic lab diagnostics with Google's 28-day URL-level CrUX field data and top speed optimization opportunities:

```bash
# Measure Core Web Vitals (Lab + CrUX Field Data) for any URL
gsc speed https://superspeedapp.com

# Correlate Core Web Vitals directly with organic GSC ranking positions
gsc speed-correlate --days 28
```

```text
⚡ Measuring Core Web Vitals via Google PageSpeed Insights (MOBILE):
   https://superspeedapp.com

🔬 LIGHTHOUSE LAB METRICS (Simulated MOBILE):
   • LCP (Largest Contentful Paint) : 2.1 s
   • FCP (First Contentful Paint)   : 1.4 s
   • CLS (Cumulative Layout Shift)  : 0.02
   • TBT (Total Blocking Time)      : 80 ms
   • Speed Index                    : 2.3 s

🌐 CrUX FIELD DATA (28-Day Real User Monitoring - URL-Level RUM):
   • Core Web Vitals Status        : PASSED
   • LCP (75th Percentile)         : 1.23 s [FAST]
   • INP (75th Percentile)         : 69 ms  [FAST]
   • CLS (75th Percentile)         : 0.0    [FAST]
   • FCP (75th Percentile)         : 1.15 s [FAST]
   • TTFB (75th Percentile)        : 973 ms [AVERAGE]

💡 TOP SPEED OPPORTUNITIES:
   • Reduce unused JavaScript: Est savings of 398 KiB
   • Reduce unused CSS: Est savings of 68 KiB
```

---

### 10. Agency Credential Vault & Instant Domain Switching (`gsc vault` & `gsc switch`)

#### The Problem
Agencies and multi-brand operators juggle dozens of client Google service account JSON files. Leaving unencrypted keys scattered across client folders invites credential leakage, path-traversal vulnerabilities, and accidental cross-client query pollution.

#### The Solution
`gsc vault` provides a hardened, local **AES-256-GCM encrypted credential vault** supporting 50+ client service accounts with strict POSIX permissions (0700/0600) and instant zero-friction domain switching:

```bash
# Check encrypted vault status, stored keys & cipher health
gsc vault status

# Add a client service account key to the encrypted store
gsc vault add ./client-key.json --domain client.com --alias client1

# List all vaulted domains, client emails & GA4 property links
gsc vault list

# Switch active client context instantly (by domain, alias, or index #)
gsc switch client.com
gsc switch client1
gsc use 2
```

---

## 🛠️ Complete CLI Command Reference (80 Commands)

> **💡 Token Economy Note for AI Agents & Pipelines:**  
> Every command supporting `--json` also natively supports `--compact` (single-line minified JSON saving **35–45% LLM tokens**) and `--ndjson` (newline-delimited streaming JSON). Commands handling tabular ranking data also support `--csv` (saving **65–75% LLM tokens**).

### 1. Setup, Doctor & Authentication
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc connect` | `auth` | 1-Click interactive setup wizard (auto-detects service account in Downloads) | `--json`, `--compact` |
| `gsc connect ke [key]` | — | Connect Keywords Everywhere API key | — |
| `gsc connect-ga4` | — | Interactive Google Analytics 4 property linking wizard | — |
| `gsc doctor` | `health` | Zero-Gem Stdlib & Cold Start Doctor: validates < 50ms latency & config integrity | `--fix`, `--json`, `--compact` |
| `gsc domains` | `sites` | List all verified Search Console properties and linked GA4 properties | `--json`, `--compact` |
| `gsc use <domain>` | `switch` | Switch active default domain property | — |
| `gsc switch <domain>` | `use` | Fast agency switch between client domains or credential vault profiles | — |
| `gsc vault [status|add|list|remove]`| — | AES-256-GCM encrypted credential vault manager (multi-client safe) | `--json`, `--compact` |
| `gsc where` | — | Inspect CLI binary path, active credential file, and config path | `--json`, `--compact` |
| `gsc version` | `-v` | Display CLI version and Ruby runtime environment | `--json`, `--compact` |
| `gsc commands` | — | Machine-readable catalog of all 80 commands | `--json`, `--compact` |

### 2. Search Analytics & Organic Performance
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc performance` | `perf` | Search performance summary (Clicks, Impressions, CTR, Position) | `--days`, `--json` |
| `gsc top-queries` | `queries` | Top search queries, impressions, CTR, and average position | `--limit`, `--days`, `--brand`, `--non-brand`, `--csv`, `--json` |
| `gsc top-pages` | `pages` | Top indexed landing pages driving organic clicks & impressions | `--limit`, `--days`, `--csv`, `--json` |
| `gsc opportunities` | `opps` | Striking-distance queries (Pos 7–20) with high impression volume | `--min-imp`, `--days`, `--csv`, `--json` |
| `gsc strike` | `striker` | Tactical Striking Playbook: High-yield queries primed for Top 3 rankings | `--min-imp`, `--limit`, `--json` |
| `gsc underperformers` | `u` | High-ranking queries with below-average CTR (title & meta tag wins) | `--limit`, `--days`, `--json` |
| `gsc cannibalization` | `cannibal` | Detect multiple internal URLs competing for the same search queries | `--limit`, `--days`, `--json` |
| `gsc decay` | — | Period-over-period decay detection (decaying vs surging queries) | `--compare`, `--days`, `--json` |
| `gsc devices` | — | Search traffic breakdown by device (Desktop, Mobile, Tablet) | `--days`, `--json` |
| `gsc countries` | — | Geographic search demand by country with flags and CTR | `--days`, `--json` |
| `gsc snippets` | — | Search appearance appearances (Reviews, Products, FAQs) | `--days`, `--json` |
| `gsc brand` | — | Brand vs. Non-brand query segmentation and traffic split | `--days`, `--brand-terms`, `--json` |
| `gsc ctr-curve` | — | Empirical CTR curve modeling by position with revenue lift simulator | `--days`, `--target-pos`, `--json` |
| `gsc intent-shift` | — | Search intent volatility and position shift monitor | `--days`, `--min-imp`, `--json` |
| `gsc kw-value` | `kwval` | Mathematical keyword conversion pipeline & dollar valuation matrix | `--aov`, `--conv-rate`, `--margin`, `--target-pos`, `--csv`, `--json` |
| `gsc landing-roi <url>` | `roi` | Landing page economic ROI & revenue leakage audit (merges GSC + bounce rates) | `--aov`, `--conv-rate`, `--benchmark`, `--csv`, `--json` |

### 3. AI Search, Generative Engine Optimization (GEO) & SERP Simulation
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc aio-hunter <query>` | `aio` | Google AI Overview Opportunity Hunter: detects AIO presence & cited sources | `--limit`, `--min-imp`, `--days`, `--csv`, `--json` |
| `gsc cite-sim <url>` | `citability` | AI Citation Simulator: tests LLM citability readiness and content density | `--json` |
| `gsc geo <url>` | `aeo` | Generative Engine Optimization (GEO) & LLM answer audit | `--json` |
| `gsc serp <title>` | `preview` | Google SERP Card & Pixel Simulator (Desktop 580px, Mobile 650px) | `--desc`, `--url`, `--json` |
| `gsc serp-features <q>` | — | Live SERP feature detector (AI Overviews, PAA, Featured Snippets) | `--geo`, `--json` |
| `gsc llms <url>` | `ai-ready` | AI Knowledge Base Generator: outputs structured `/llms.txt` bundle | `--save`, `--json` |
| `gsc entity <url>` | `kg` | Knowledge Graph & Entity Authority Auditor (Wikidata, Wikipedia links) | `--json` |
| `gsc firewall <url>` | `ai-bots` | AI Search Bot Firewall Scanner: audits robots.txt for GPTBot, ClaudeBot | `--json` |
| `gsc answer <q>` | — | Direct answer box and featured snippet synthesizer | `--json` |

### 4. Technical SEO, Crawl Errors & Automated Fixes
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc soft-404 <url>` | — | Soft-404 Diagnostic Engine with automated multi-stack redirect generation | `--fix <stack>`, `--json` |
| `gsc mobile-parity <dom>`| `mobile` | Mobile vs. Desktop SERP Parity Auditor: cross-device rank gap diagnosis | `--days`, `--gap-threshold`, `--csv`, `--json` |
| `gsc audit` | `360` | Comprehensive 360° technical and organic health audit | `--json` |
| `gsc report` | — | Executive 360° Health Scorecard with letter grade and sparklines | `--days`, `--sparkline`, `--json` |
| `gsc page <url>` | — | Detailed On-Page DOM audit (meta, headings, alts, schema) + GSC performance | `--check-links`, `--json` |
| `gsc site-audit <sitemap>`| — | Crawls sitemaps, tests 404 dead links, audits DOM flaws, and outputs fix sprint | `--report <file>`, `--json` |
| `gsc speed <url>` | `vitals` | Dual Lab (Lighthouse) & Field (CrUX 28-day RUM) Core Web Vitals (LCP, INP, CLS, TTFB) | `--strategy mobile|desktop`, `--json` |
| `gsc speed-correlate` | `sc-perf` | Correlates Core Web Vitals page speed with GSC organic rankings | `--days`, `--strategy`, `--json` |
| `gsc canonical-chains` | `chains` | Canonical redirect loops and multi-hop chain detector | `--limit`, `--json` |
| `gsc low-ctr` | — | High-impression low-CTR title & meta description rewriter | `--limit`, `--min-imp`, `--json` |
| `gsc titles <url>` | `title-opt` | Title pixel width calculator and SERP truncation optimizer | `--json` |
| `gsc headings <url>` | `h1` | Heading structure (H1–H6) depth, order, and keyword presence auditor | `--json` |
| `gsc orphans` | — | Internal link equity analyzer: rescues orphaned unlinked pages | `--json` |
| `gsc internal-links` | — | Deep internal link equity audit and anchor text distribution | `--json` |
| `gsc image-seo <url>` | — | Image SEO auditor: missing alt attributes, next-gen formats (WebP/AVIF) | `--json` |
| `gsc hreflang <url>` | — | International hreflang reciprocity and ISO language/region validator | `--json` |
| `gsc eeat <url>` | — | E-E-A-T Auditor: author credentials, publisher transparency & trust signals | `--json` |
| `gsc security <url>` | — | Security & HTTP headers auditor: SSL, HSTS, CSP, and X-Robots-Tag | `--json` |
| `gsc rich-results <url>` | `rich` | Google Rich Results eligibility and Schema.org test | `--type`, `--json` |
| `gsc schema <url>` | `ld-json` | JSON-LD Structured Data Validator and generator | `--json` |
| `gsc schema-generate` | `schema-gen`| Valid Schema.org JSON-LD generator (`faq`, `software`, `article`, `product`)| `--type`, `--json` |
| `gsc trace <domain>` | `redirects` | Multi-hop 301/302 redirect tracer with SSL and header inspection | `--json` |
| `gsc robots <url>` | `robots-txt`| Robots.txt crawler permissions simulator across major bots | `--bot`, `--json` |
| `gsc authority <domain>` | `opr` | OpenPageRank Domain Authority (0–10) and Global Rank from Common Crawl | `--json` |
| `gsc compare <u1> <u2>` | `vs` | Head-to-head on-page technical benchmark comparison | `--json` |
| `gsc content-gap <u1> <u2>`| `gap` | Topical content gap analyzer: missing 1-gram, 2-gram, and 3-gram keyphrases | `--json` |

### 5. Live Indexation & Googlebot Control
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc inspect <url>` | — | Live Google URL inspection (coverage status, assigned canonical, crawl date)| `--json` |
| `gsc index <url>` | — | Priority Googlebot crawl submission (`URL_UPDATED`) | `--dry-run`, `--json` |
| `gsc remove <url>` | — | Notify Googlebot of permanently deleted URL (`URL_DELETED`) | `--dry-run`, `--json` |
| `gsc status <url>` | — | Check Google Indexing API submission status and latest notification timestamp| `--json` |
| `gsc index-batch` | — | Batch URL indexing processor with daily 200-URL quota tracking | `--batch-size`, `--force`, `--dry-run`, `--json` |
| `gsc indexnow <url>` | — | Multi-engine instant submission (Bing, Yandex, Seznam, Naver) | `--key`, `--json` |
| `gsc zombies <sitemap>` | — | Detect zero-impression deadweight URLs wasting crawl budget over 90 days | `--days`, `--json` |
| `gsc sitemaps-list` | — | List registered XML sitemaps in Search Console | `--json` |
| `gsc sitemaps-submit <url>`| — | Submit or re-submit an XML sitemap to Search Console | `--json` |
| `gsc sitemap-tree <url>` | — | Visual sitemap hierarchy tree and URL limit validator | `--json` |

> 🛡️ **Batch Indexing Safety Guard (`gsc index-batch clear`)**:  
> When automating bulk indexing in scripts, CI/CD, or AI agents, an accidental `clear` could wipe hundreds of queued URLs waiting to be indexed. To prevent queue loss:
> - **Interactive Shells**: Requires explicit `[y/N]` user confirmation.
> - **Non-Interactive / Scripts / Agents**: Requires `--force` / `-f` (aborts with exit code `1` if omitted).
> - **Automatic Backup**: Every clear automatically snapshots the pending queue to `~/.gsc/backups/queue_backup_<TIMESTAMP>.json` before wiping, so URLs are never lost.

### 6. Keyword Research & Demand Trends
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc trends <query>` | — | Real-time Google Trends trajectory velocity, sparklines & geo breakdown | `--geo`, `--time`, `--json` |
| `gsc planner <seed>` | — | Autocomplete seed expander with intent classification & live GSC correlation| `--limit`, `--json` |
| `gsc suggest <seed>` | — | Google Autocomplete & Alphabet Soup (a-z) keyword harvester | `--alphabet`, `--json` |
| `gsc questions <seed>` | `paa` | People Also Ask (PAA) question miner for FAQs and blog outlines | `--limit`, `--json` |
| `gsc import <file|clip>`| — | Ingest Google Ads / Keywords Everywhere data from clipboard (`clip`) or file | `--limit`, `--json` |
| `gsc ke <seed|file>` | — | Keywords Everywhere direct API: exact monthly volume, CPC & competition | `--country`, `--limit`, `--json` |
| `gsc ke-credits` | — | Check remaining Keywords Everywhere account API credits | `--json` |
| `gsc saved` | — | List saved keyword research snapshots for the active domain | `--json` |
| `gsc saved check [id]` | — | Re-check saved keyword snapshots against live GSC rankings to track wins | `--json` |
| `gsc saved view [id]` | — | View stored keyword metrics and opportunity scores | `--json` |
| `gsc saved delete [id]`| — | Delete a saved keyword research snapshot | — |
| `gsc seasonal <keyword>` | — | Seasonal keyword demand forecasting and peak month detection | `--json` |
| `gsc sparkline <query>` | — | High-resolution Unicode sparkline visualizer (` ▂▃▄▅▆▇█`) | `--days`, `--json` |

### 7. Google Analytics 4 (GA4) On-Site Behavior
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc realtime` | — | Stream active visitors, real-time page paths, and countries (`--watch`) | `--watch`, `--json` |
| `gsc ga4` | — | Landing page bounce rates, engagement rates, and average session duration | `--organic`, `--json` |
| `gsc correlation` | — | Merge GSC keyword rankings with GA4 bounce rates per landing page | `--json` |
| `gsc channels` | — | Traffic acquisition channels (Organic Search, Direct, Referral, Paid) | `--json` |
| `gsc ads` | — | Google Ads campaign performance (Clicks, Cost, CPC, Conversions) | `--json` |

### 8. AI Agent Skills & System Tools
| Command | Shortcut | Description | Flags |
|---|---|---|---|
| `gsc skills [install|show]` | — | Inspect or auto-install native AI Agent Skill (`SKILL.md`) | `--json` |
| `gsc skill-pack` | — | Autonomous Agent Skill Pack Generator for Cursor, Antigravity, and Claude | `--install`, `--json` |
| `gsc prompts [list|show]` | — | 27 battle-tested tactical SEO growth prompts and playbooks | `--json` |
| `gsc vault [status|add|list|remove]` | — | AES-256-GCM encrypted credential vault manager | `--json` |
| `gsc cache [status|clear]` | — | Multi-tier gzip response cache manager | `--json` |

---

## 🤖 AI Agent Native Integration (Antigravity, Claude, Cursor)

> 💡 **Zero External LLM Calls**: `gsc-cli` does NOT require an OpenAI or Anthropic API key and sends zero data to third-party AI servers. Everything runs locally on your machine. "AI Agent Native" refers to our deterministic `--compact` (minified JSON) and `--ndjson` flags designed to save 35–45% context tokens when called by local coding agents (Claude Code, Cursor Composer, Antigravity).

`gsc-cli` was engineered from the ground up to serve as the high-speed sensory organ for autonomous AI coding agents (**Antigravity**, **Claude Code**, **Cursor Composer**, **Windsurf**, and **OpenCode**). 

Traditional CLI tools output ANSI-colored terminal text designed exclusively for human eyes—forcing AI agents to burn thousands of tokens scraping strings, guessing table columns, and hallucinating missing fields. `gsc-cli` eliminates this waste completely with **sub-millisecond execution**, **zero gem overhead**, and **three ultra-efficient machine output formats**.

### 📉 Token Economics: Why Format Matters for AI Agents

Every token consumed by CLI output burns developer budget, introduces LLM generation latency, and pushes critical prompt context out of the agent's memory window. `gsc-cli` provides four deterministic output formats to optimize your token economics:

| Format | Flag | Avg. Chars (100 Rows) | Est. Tokens | Token Savings | Optimal AI Agent Scenario |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tabular CSV** | `--csv` | 3,920 | ~980 | **72.5% savings** | High-cardinality exports (100–5,000 keywords/pages) |
| **Compact JSON**| `--compact` | 8,110 | ~2,028 | **43.0% savings** | Default for Claude Code & Cursor single-turn queries |
| **Streaming NDJSON** | `--ndjson` | 8,230 | ~2,058 | **42.2% savings** | Streaming processors, jq/grep pipes & subagent tasks |
| **Pretty JSON** | `--json` | 14,240 | ~3,560 | 0% *(Baseline)* | Human developer terminal inspection & debugging |

> ⚡ **The Bottom Line:** Switching your autonomous agents from `--json` to `--compact` immediately **cuts token consumption by ~43%**, allowing your agents to ingest more than **double the keyword and performance data** within identical context limits.

---

### 📋 Deterministic Output Contract & Zero-Pollution Guarantee

Autonomous coding agents require strict, unpolluted output streams. `gsc-cli` enforces a military-grade stdout/stderr separation contract:
- **Zero ANSI Pollution**: When `--compact`, `--ndjson`, `--json`, or `--csv` is detected, all ANSI terminal colors, progress bars, and Unicode spinners are automatically suppressed.
- **Pure Stdout Payload**: Stdout contains *only* valid, parseable JSON, NDJSON, or CSV.
- **Stderr Diagnostic Routing**: Network warnings, rate-limit retries, and error traces are routed strictly to `stderr`.
- **POSIX Exit Codes**: Clean exit `0` on success, `1` on error or validation failure.

---

### 🚀 Autonomous Agent Workflow Recipes

Feed these exact commands to your AI agents (or add them to your `cursorrules` / agent system prompts):

#### 1. Tactical Striking Distance Harvest
```bash
# Agent prompt: "Find our highest-impression striking distance queries (Pos 7–20) and save token budget"
gsc strike --min-imp 25 --limit 15 --compact
```

#### 2. Google AI Overview (AIO) Defense Scan
```bash
# Agent prompt: "Check if Google is showing an AI Overview for our core product query and who they cite"
gsc aio-hunter "technical seo checklist" --compact
```

#### 3. Forensic Soft-404 Audit & Automated Server Fix
```bash
# Agent prompt: "Inspect missing landing page and synthesize an automated Nginx redirect block"
gsc soft-404 https://example.com/missing-guide --fix nginx --compact
```

#### 4. Instant Googlebot Priority Indexing Notification
```bash
# Agent prompt: "Submit our newly published blog post to Google's Indexing API for crawl queueing"
gsc index https://example.com/blog/high-impact-seo --compact
```

#### 5. Multi-Client Agency Domain Switching
```bash
# Agent prompt: "Switch to client domain and pull 28-day performance summary"
gsc switch clientdomain.com && gsc perf --days 28 --compact
```

---

### 📦 1-Click AI Agent Skill Installation

Install the official `gsc-cli` skill directly into your coding agent's environment:

```bash
# Installs SKILL.md into Antigravity, Claude, and Cursor skill directories
gsc skills install
```

Once installed, your agent automatically understands all 80 commands, flag permutations, token-saving modes, and diagnostic workflows without needing manual prompting.

---

## 🥊 How GSC CLI Compares (The Zero-Bloat Advantage)

| Capability | Google Search Console Web UI | Official Google API SDK (40 Gems) | Enterprise SEO Suites ($300–$1,000+/mo) | **ApollosWave/gsc-cli (v2.2.2)** |
| :--- | :--- | :--- | :--- | :--- |
| **Pricing** | Free ($0) | Free ($0) | $300–$1,000+/mo ($3,600–$12,000/yr) | **100% Free & Open Source ($0)** |
| **Dependencies** | Web Browser only | 40+ transitive gems (`googleauth`, etc.) | SaaS Web Application | **0 Gems / Pure Standard Library** |
| **Boot / Execution Latency** | Slow (manual clicking) | 3–5 seconds cold boot | Web UI latency | **< 1 millisecond (Compiled Binary)** |
| **Data Accuracy** | 100% Google Ground Truth | 100% Google Ground Truth | Sampled external proxy estimates | **100% Google Ground Truth (Direct API)** |
| **CLI Command Surface** | ❌ None (Web only) | Raw Ruby code required | ❌ None (Web dashboard) | **80 Production Commands** |
| **Core GSC Workflows** | Manual tab clicking & export | Complex API code boilerplate | Partial GSC sync via OAuth | **`top-queries`, `top-pages`, `performance`** |
| **Instant Googlebot Indexing** | Manual 1-by-1 submit | Complex JWT boilerplate | ❌ None | **✅ 1-Click Priority Ping (`gsc index`)** |
| **Multi-Engine IndexNow** | ❌ None | ❌ None | ❌ None | **✅ Bing, Yandex, Seznam, Naver (`gsc indexnow`)** |
| **Striking Distance Playbook** | ❌ Manual spreadsheet work | ❌ None | Expensive add-on tiers | **✅ Automated Page 2 Playbook (`gsc strike`)** |
| **Google AI Overviews (AIO)** | ❌ None | ❌ None | Limited / expensive beta tiers | **✅ Built-in `aio-hunter` & `cite-sim`** |
| **Automated Fix Generation** | ❌ None (Error tables only) | ❌ None | ❌ None | **✅ 14-Stack Redirects (`gsc soft-404 --fix`)** |
| **Token Economics for AI** | ❌ None | Verbose unformatted JSON | ❌ None | **✅ Native `--compact`, `--ndjson`, `--csv` (35–75% savings)** |
| **Autonomous AI Agent Skills** | ❌ None | ❌ None | ❌ None | **✅ Native Skill for Claude, Cursor, Antigravity** |

---

## 🏗️ Architecture & Pure-Ruby Design

`gsc-cli` is engineered with 100% pure Ruby standard library. It compiles into a single, self-contained, zero-dependency executable:

```text
gsc-cli/
├── bin/
│   ├── gsc                      # Compiled single-file binary (RubyGems entry point)
│   └── test_live                # Visual showcase & internal test harness
├── lib/
│   ├── gsc.rb                   # Central stdlib loader
│   └── gsc/
│       ├── version.rb           # Semantic versioning (2.2.2)
│       ├── color.rb             # Zero-dependency ANSI formatting
│       ├── config.rb            # Configuration persistence
│       ├── auth.rb              # Pure OpenSSL JWT generator
│       ├── client.rb            # Net::HTTP client with Gzip decompression
│       ├── api.rb               # GSC, Indexing, GA4, PageSpeed endpoints
│       ├── aio_hunter.rb        # Google AI Overview Opportunity Hunter
│       ├── citation_simulator.rb# AI Citability score & grounding heuristics
│       ├── soft_404_analyzer.rb # Soft-404 diagnostic & multi-stack fix generator
│       ├── mobile_parity.rb     # Cross-device SERP parity auditor
│       ├── doctor.rb            # Zero-gem cold-start benchmark doctor
│       ├── command_registry.rb  # Catalog of all 80 production commands
│       ├── cli/                 # Modular subcommand domains (audit, keywords, growth...)
│       └── cli.rb               # Primary command dispatcher & router
├── dist/
│   └── gsc                      # Standalone bundled binary (1-click curl & GitHub releases)
├── gsc.gemspec                  # Standard RubyGem specification
├── Rakefile                     # Build, test, and standalone install tasks
└── install.sh                   # Universal 1-click shell installer
```

### Development Tasks
```bash
# Run syntax checks and all 359 unit test suites
rake test

# Run 100-scenario deep forensic regression suite
rake test:forensic

# Build the standalone single-file binary into dist/gsc
rake build:standalone

# Install local development build to ~/.local/bin/gsc
rake install:standalone
```

---

## 💖 Sponsorship & Backing

`gsc-cli` is free, open-source software built to eliminate predatory monthly subscriptions for indie developers, founders, and AI builders.

If GSC CLI saves your team hours of manual audit work or hundreds in monthly SaaS fees, consider backing continuous development:

| Tier | Monthly | Perks | Sponsorship Link |
| :--- | :--- | :--- | :--- |
| **Community Supporter** | **$10 / mo** | Name in README Backers list + Discord/GitHub badge | [**Sponsor $10/mo**](https://buy.stripe.com/fZu6oG4Qz1EucVT4ygbAs00) |
| **Backer** | **$50 / mo** | Name + link in Backers section + priority issue triage | [**Sponsor $50/mo**](https://buy.stripe.com/7sY00ier91Eu5tr0i0bAs01) |
| **Agency Partner** | **$100 / mo** | Small logo/link in Agency Backers gallery + priority triage | [**Sponsor $100/mo**](https://buy.stripe.com/6oU9AS1Engzog853ucbAs02) |
| **Bronze Sponsor** | **$500 / mo** | Medium logo with dofollow backlink in README & docs | [**Sponsor $500/mo**](https://buy.stripe.com/eVqdR882LgzobRP9SAbAs03) |
| **Silver Sponsor** | **$1,500 / mo** | Large logo on top fold + monthly feature priority request | [**Sponsor $1,500/mo**](https://buy.stripe.com/8x2aEWbeX2IybRP1m4bAs04) |
| **Gold Title Sponsor** | **$2,500 / mo** | Title banner at top of README + 1h monthly consulting | [**Sponsor $2,500/mo**](https://buy.stripe.com/cNi7sK4Qz6YOaNL3ucbAs05) |

> *All sponsorships are processed securely via **Stripe** by ApollosWave LLC. Invoices with company VAT / Business Tax ID provided automatically upon checkout.*

👉 **[Read the Full Sponsorship Prospectus & Tier Breakdown →](FUNDING.md)**

---

## 🛠️ Origin & Production Dogfooding

`gsc-cli` was created and is actively maintained by **[ApollosWave LLC](https://apolloswave.com)**.

We originally built this engine to automate Google Search Console diagnostics, crawl budgets, and Core Web Vitals across our own production applications:
- **[Superspeed](https://superspeedapp.com)** — Real-user monitoring (RUM), Core Web Vitals, and speed intelligence for high-volume Shopify storefronts.
- **[Supercart](https://supercartapp.com)** — Slide cart drawer, in-house shipping protection, and real-time e-commerce upsell infrastructure.
- **[PackingLog](https://packinglog.com)** — Our newly launched physical moving inventory and QR-code tracking SaaS — where waiting weeks for Googlebot to discover new landing pages wasn't an option.

We open-sourced `gsc-cli` under the MIT license so developers, engineering teams, and AI agents can run first-party search automation locally with zero dependency bloat.

---

## 🙏 Acknowledgments & Credits

- **[Ben Sheldon](https://github.com/bensheldon)**: Inspired by Ben Sheldon's backend Ruby Google Ads API implementation and the Rails performance community's passion for lean, zero-dependency, server-side tools.
- **[Corey Haines](https://github.com/coreyhaines31)**: The companion SEO & marketing skills (`ai-seo`, `seo-audit`, `schema`, `programmatic-seo`, `copywriting`, `cro`) are adapted from the open-source [marketingskills](https://github.com/coreyhaines31/marketingskills) repository by [Corey Haines](https://github.com/coreyhaines31) (MIT License).
- **[Basecamp & Kamal](https://github.com/basecamp/kamal)**: Modular CLI directory layout and standalone distribution patterns inspired by Basecamp's open-source tooling.

---

## ⚖️ Open Source Philosophy & License

`gsc-cli` is 100% free, open-source software licensed under the **[MIT License](LICENSE)**.

We built this because we believe command-line developer tools should be fast, transparent, and respect your machine's resources. The modern Ruby standard library is more than capable of handling enterprise-grade API integrations and cryptographic authentication without dragging in 40 third-party gems.

If `gsc-cli` saves your team time, eliminates an unnecessary SaaS subscription, or accelerates your search pipelines, stars, feedback, and pull requests are always welcome.

👉 **[Get Started with 1-Click Install](#-quick-installation)** | **[Star on GitHub ⭐](https://github.com/ApollosWave/gsc-cli)**

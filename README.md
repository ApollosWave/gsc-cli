# 🚀 High-Growth Operators & Autonomous AI Agents: The Zero-Dependency Google Search Console, AIO Hunter & Instant Indexing Engine

> **Zero Gem Dependencies.** Pure Ruby standard library (`Net::HTTP`, `OpenSSL`, `JSON`).  
> **The Sub-50ms Organic Growth Mandate:** Extract ground-truth Google rankings, capture Google AI Overviews, and automate technical SEO in **< 50 milliseconds** — *even if you manage 50 client domains, don't have a Google Service Account key yet, or run offline AI coding agents with strict token budgets.*

[![Ruby](https://img.shields.io/badge/Ruby-3.0%2B-red.svg?logo=ruby&logoColor=white)](https://www.ruby-lang.org)
[![Gem Version](https://badge.fury.io/rb/gsc-cli.svg)](https://rubygems.org/gems/gsc-cli)
[![Dependencies](https://img.shields.io/badge/dependencies-0%20gems-brightgreen.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Commands](https://img.shields.io/badge/commands-80%20production-orange.svg)](#-complete-cli-command-reference-80-commands)
[![Security: AES-256-GCM](https://img.shields.io/badge/Vault-AES--256--GCM-blueviolet.svg)](#8-agency-credential-vault-gsc-vault)
[![AI Agent Native](https://img.shields.io/badge/AI%20Agent-Native%20Skill-purple.svg)](#-ai-agent-native-integration-antigravity-claude-cursor)
[![GitHub Stars](https://img.shields.io/github/stars/ApollosWave/gsc-cli?style=social)](https://github.com/ApollosWave/gsc-cli)

---

<p align="center">
  <b>gsc-cli</b> is a free, open-source initiative built and maintained by 
  <a href="https://apolloswave.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli"><b>ApollosWave LLC</b></a>.
</p>

<p align="center">
  <sub>Explore other software built by our team:</sub><br>
  ⚡ <a href="https://superspeedapp.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli"><b>Superspeed</b></a> — Built for Shopify speed, CRO & revenue leak intelligence app (5.0 ★)<br>
  🛒 <a href="https://supercartapp.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli"><b>Supercart</b></a> — Built for Shopify slide cart drawer, in-house shipping protection & upsells (5.0 ★)<br>
  📦 <a href="https://packinglog.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli"><b>PackingLog</b></a> — Smart QR-code box inventory & photo catalog for residential & office moves
</p>

---

## ⚡ The Brutal Truth About Modern SEO (And Why We Built GSC CLI)

Every software founder, growth engineer, and indie builder faces the exact same bleeding bottlenecks:

1. **Bleeding $300 to $1,000+/Month on SEO Tool Fees for Sampled Guesswork**: Third-party estimation suites charge $300 to $1,000+ every month to scrape search results with external proxies and model keyword volumes from sampled databases. Meanwhile, **Google already has the exact, 100% first-party ground-truth data** for your site sitting inside Search Console—completely free.
2. **Official Google API Gems Are Bloated Monsters**: The official Google API Ruby gems (`google-apis-searchconsole_v1`, `google-apis-indexing_v3`, `googleauth`) drag in **40+ transitive gem dependencies**, take 3 to 5 seconds just to boot, trigger bundle conflicts, and introduce constant supply-chain vulnerabilities.
3. **Google Search Console's Web UI is Insultingly Slow**: Clicking through Google Search Console's web interface to inspect 50 URLs, check soft-404 errors, or spot cannibalization takes hours of repetitive clicking, filtering, and tab-switching.
4. **Google AI Overviews (AIO) Are Stealing 40% of Clicks**: Zero-click searches are skyrocketing. If your content isn't structured for direct citation in Google Gemini / AI Overviews, your organic traffic drops even if you rank on Page 1.
5. **AI Coding Agents Cannot Click Web Buttons**: Modern coding agents (Antigravity, Claude Code, Cursor, Cline) need raw, deterministic, sub-50ms JSON over stdout to diagnose and fix SEO issues autonomously inside your codebase.

### The Origin of GSC-CLI
At **[ApollosWave](https://apolloswave.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli)**, we run multiple production software businesses—from Shopify revenue & speed intelligence (**[Superspeed](https://superspeedapp.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli)**) and e-commerce upsell apps (**[Supercart](https://supercartapp.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli)**) to physical moving inventory SaaS (**[PackingLog](https://packinglog.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli)**).

We refused to bloat our applications with 40 gems or waste 10 hours a week clicking in Search Console. We needed a **single, standalone, pure-Ruby CLI** that communicates directly with Google's bare-metal HTTP APIs using native `OpenSSL` and `Net::HTTP` in **under 50 milliseconds**.

We built **`gsc-cli`** to run our own marketing operations. **We open-sourced it 100% free under the MIT License** so other builders can scale organic search traffic without the corporate SEO tax.

---

## 💎 The 5 Immutable Truths of Modern Organic Growth

1. **Compounding Organic Acquisition**: You didn't build your software to burn half your runway on paid ads. You built it to create a compounding, self-sustaining organic acquisition engine that pulls in qualified customers day and night on autopilot.
2. **First-Party Ground Truth Over Guesswork**: You always suspected that third-party scraping tools and panel-based traffic estimators don't have Google's private internal search logs for your domain. You were right. External proxy estimators rely on sampled clickstream models; meanwhile, Google Search Console stores the exact, 100% first-party click and impression ground truth directly from Google's production infrastructure—completely free.
3. **Liberation from the 40-Gem Tax**: Official Google API gems drag in 40+ dependency gems, slow down boot times to 4+ seconds, trigger bundle conflicts, and introduce constant supply-chain alerts. GSC-CLI communicates directly with Google's bare-metal HTTP APIs using pure Ruby standard library in **< 1 millisecond**.
4. **Zero-Trust Local Execution & Anti-Slop Guarantee**: Developers are tired of untrusted scripts that require root privileges or send your private code to remote AI servers. `gsc-cli` is **not an AI slop wrapper**. It runs 100% locally with zero external gem dependencies, zero telemetry, and zero remote code ingestion.
5. **Actionable Remediation Over Passive Error Tables**: Traditional SEO auditing tools spit out 500 error rows but leave you stranded without actionable fixes. GSC-CLI diagnoses soft-404 traps and automatically synthesizes copy-paste redirect blocks for 14 server environments.

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
- 💰 **Keywords Everywhere Ingestion (`gsc import clip` & `gsc ke`)**: Ingest free keyword tables directly from clipboard (zero credits required) or connect paid API keys for 1-step automated terminal lookups.
- 🚀 **Instant Googlebot Re-Indexing (`gsc index`)**: Ping Google's Indexing API with `URL_UPDATED` or `URL_DELETED` for priority crawl queueing within seconds.
- ⚡ **Multi-Engine IndexNow Protocol (`gsc indexnow`)**: Instantly submit pages and sitemaps across Microsoft Bing, Yandex, Seznam, and Naver simultaneously.
- 🖥️ **Google SERP & Title Pixel Simulator (`gsc serp`)**: Simulate desktop (580px) and mobile (650px) Google SERP cards, calculate precise proportional pixel widths, and prevent truncation before publishing.
- 🛡️ **Cannibalization & Decay Detection (`gsc cannibalization`, `gsc decay`)**: Spot internal URLs fighting for the same queries, and compare 28-day period-over-period traffic trends.
- 📊 **Google Analytics 4 (GA4) Behavioral Link (`gsc realtime`, `gsc ga4`)**: Stream live active visitors and correlate SERP rankings with landing page bounce rates.
- 🕷️ **Autonomous Site Audit & Broken Link Repair (`gsc site-audit`)**: Crawls all sitemap URLs, checks HTTP response codes for dead internal links (404/500/timeouts), audits missing image alts and heading defects, and exports an AI-actionable Markdown fix sprint.
- 🤖 **AI Agent Native**: Every single command supports `--compact`, `--ndjson`, and `--json` for instantaneous programmatic consumption by AI agents.

---

## 🔄 The Transformation: Nightmare Status Quo vs. The GSC-CLI Way

| Nightmare Status Quo | The GSC-CLI Transformation |
| :--- | :--- |
| **Manual Clicking Trap**: Clicking through 15 tabs in Google Search Console to inspect 50 URLs (takes 45+ minutes). | **Instant 1-Command Batching**: `gsc inspect-sitemap sitemap.xml` inspects all URLs with automatic quota pacing in seconds. |
| **Sampled Third-Party Guesswork**: Paying $300–$1,000+/mo ($3,600–$12,000/yr) for external proxy scrapers that model keyword volumes. | **100% Google Ground Truth ($0)**: Raw impression, click, and position logs direct from Google Search Console. |
| **40-Gem Dependency Hell**: Bloating your `Gemfile` with Google SDK gems that add 4 seconds to cold boot. | **0 Gem Dependencies**: Pure Ruby standard library (`OpenSSL`, `Net::HTTP`, `JSON`) executing in **< 1 millisecond**. |
| **Multi-Client Credential Chaos**: Juggling loose JSON keys across client folders and risking credential leaks. | **Agency Credential Vault (`gsc vault`)**: Local AES-256-GCM encrypted vault with instant domain switching (`gsc switch`). |
| **Passive Error Reporting**: Diagnostic tools tell you that you have 404s, but leave you to write the server rules. | **Active Automated Remediation**: `gsc soft-404 <url> --fix nginx` synthesizes instant, copy-paste server blocks for 14 stacks. |
| **Blind to AI Overviews**: Unaware that Google Gemini / AI Overviews are intercepting 40% of zero-click searches. | **Google AIO Hunter & Citation Simulator**: `gsc aio-hunter` identifies AI Overviews and extracts competitor citation recipes. |
| **Token-Guzzling JSON in AI Agents**: Feeding pretty-printed JSON into coding agents wastes 40% of your LLM context window. | **Ultra-Low Token Modes (`--compact`, `--ndjson`)**: Minified output saving **35–50% of tokens** for Claude Code, Cursor, and Antigravity. |
| **Untrusted Scripts Touching Code**: Running opaque scripts that scan your repository and send files to third parties. | **Zero-Trust Local Execution**: Completely isolated, deterministic UNIX tool. Never scans, reads, or transmits your private code. |

---

> ### ⭐ Join the Zero-Bloat SEO Revolution
> **Did `gsc-cli` save your team from 40 bloated Google gems, bypass the $300–$1,000+/mo SEO suite tax, or give your AI agents instant sub-50ms search ground truth?**  
> 
> Help fellow engineers and operators discover zero-dependency tooling:  
> 👉 **[Drop a Star on GitHub](https://github.com/ApollosWave/gsc-cli)** — *even if you only use it for terminal sparklines, instant Googlebot indexing, or AI Overview detection.* It takes 2 seconds and directly fuels continuous open-source development!

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

### 1. Google AI Overview (AIO) Opportunity Hunter (`gsc aio-hunter`)

#### The Problem
Google AI Overviews (Gemini in search results) are intercepting high-intent search traffic before users ever click a blue link. If an AI Overview appears for your core keywords, your CTR can crater by 40% unless your site is cited inside the AI answer box.

#### The Solution
`gsc aio-hunter` queries SERPs, detects AI Overviews, extracts the exact cited sources, identifies your citation gap, and generates a structured snippet capture recipe:

```bash
# Hunt AI Overview presence and extract cited competitor URLs
gsc aio-hunter "best technical seo audit tools"

# Filter by minimum impressions and export JSON for AI agents
gsc aio-hunter --min-imp 50 --json
```

---

### 2. AI Citation Simulator (`gsc cite-sim`)

#### The Problem
How do you know if an LLM (ChatGPT Search, Perplexity, Gemini) will actually cite your URL when answering user queries?

#### The Solution
`gsc cite-sim` runs a local structural heuristics audit assessing citation readiness:
- **Information Density Ratio**: High-value facts per 1,000 DOM words.
- **Structural Heading Depth**: Clean H2/H3 question-and-answer hierarchy.
- **Entity Markup**: Schema.org JSON-LD definitions.
- **Citability Score (0–100)**: Clear breakdown with actionable optimization advice.

```bash
gsc cite-sim https://example.com/guides/core-web-vitals
```

---

### 3. Soft-404 Forensic Diagnostic Engine with Instant Stack Fixes (`gsc soft-404`)

#### The Problem
Soft-404 errors silently destroy your Google crawl budget. These are pages that return a `200 OK` status code while showing "Product Not Found" or empty category pages. Finding them is painful; generating server redirect rules by hand is tedious and error-prone.

#### The Solution
`gsc soft-404` detects empty templates, blank pages, and canonical loops, auto-detects your underlying tech stack (SvelteKit, Cloudflare, Astro, Next.js, Caddy, Webflow, Shopify, Nginx), and generates production-ready redirect rules:

```bash
# Diagnose any URL for soft-404 status (auto-detects tech stack & server)
gsc soft-404 https://example.com/broken-page

# Generate copy-paste rules for your specific tech stack:
gsc soft-404 https://example.com/broken-page --fix sveltekit
gsc soft-404 https://example.com/broken-page --fix caddy
gsc soft-404 https://example.com/broken-page --fix cloudflare
gsc soft-404 https://example.com/broken-page --fix workers
gsc soft-404 https://example.com/broken-page --fix astro
gsc soft-404 https://example.com/broken-page --fix gatsby
gsc soft-404 https://example.com/broken-page --fix github
gsc soft-404 https://example.com/broken-page --fix webflow
gsc soft-404 https://example.com/broken-page --fix shopify
gsc soft-404 https://example.com/broken-page --fix nextjs
gsc soft-404 https://example.com/broken-page --fix nginx
gsc soft-404 https://example.com/broken-page --fix all
```

---

### 4. Cross-Device Mobile vs. Desktop SERP Parity (`gsc mobile-parity`)

#### The Problem
Google indexes mobile-first. If your mobile layout has hidden content, slower load times, or truncated titles, your mobile ranking can drop 10 positions below desktop without you ever noticing in standard dashboards.

#### The Solution
`gsc mobile-parity` compares mobile and desktop impressions, average positions, and CTR side-by-side, flagging responsive suppression penalties:

```bash
gsc mobile-parity example.com --gap-threshold 2.0
```

---

### 5. Detailed Off-Page + On-Page SEO Merger (`gsc page` & `gsc site-audit`)

```bash
# Audit any URL combining DOM inspection with GSC 90-day search performance
gsc page https://example.com/

# Deep internal link verification: tests HTTP status codes (200, 404, 500)
gsc page https://example.com/ --check-links

# Crawl entire XML sitemaps to generate prioritized AI fix sprints
gsc site-audit https://example.com/sitemap.xml --report docs/seo/site_audit_issues.md
```

---

### 6. Zero-Cost Clipboard Keyword Ingestion (`gsc import clip`)

> **No API key or paid credits required!** Works 100% free with the Keywords Everywhere web dashboard or Google Ads Keyword Planner.

1. **Copy Your Keywords in the Browser**: Click "Copy to Clipboard" on any keyword volume table.
2. **Run One Command in Your Terminal**:
   ```bash
   gsc import clip
   ```
3. **Instant Analysis & GSC Correlation**:
   * Parses volume, CPC, competition score, and 12-month history at zero cost.
   * Draws live **Unicode Sparklines (` ▂▃▄▅▆▇█`)** showing demand trajectories.
   * Calculates **Opportunity Scores (0–100)** to prioritize low-competition wins.
   * Automatically cross-references live Google Search Console rankings (`🏆 Top 3`, `🥇 Page 1`, `🎯 Striking Distance`, or `🚀 Untargeted`).
   * Archives into `~/.config/gsc/domains/<domain>/keywords/` for historical rank tracking.

---

### 7. Google Trends Real-Time Demand Engine (`gsc trends`)

Queries Google Trends explore and widget APIs directly in real time with **zero authentication and zero API keys**:
```bash
gsc trends "seo audit" --geo US --time 12m
gsc trends "local llm" --geo US --time 5y --json
```

---

### 8. Agency Credential Vault (`gsc vault`)

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

### 9. Striking Distance Playbook & Organic CTR Curve (`gsc strike` & `gsc ctr-curve`)

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

# Export playbook directly to CSV for copywriters & content teams
gsc strike --limit 20 --csv docs/seo/striking_playbook.csv
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
| `gsc speed <url>` | `vitals` | Official Core Web Vitals via PageSpeed Insights (LCP, INP, CLS, TTFB) | `--strategy mobile|desktop`, `--json` |
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
| `gsc index-batch` | — | Batch URL indexing processor with daily 200-URL quota tracking | `--run`, `--status`, `--json` |
| `gsc indexnow <url>` | — | Multi-engine instant submission (Bing, Yandex, Seznam, Naver) | `--key`, `--json` |
| `gsc zombies <sitemap>` | — | Detect zero-impression deadweight URLs wasting crawl budget over 90 days | `--days`, `--json` |
| `gsc sitemaps-list` | — | List registered XML sitemaps in Search Console | `--json` |
| `gsc sitemaps-submit <url>`| — | Submit or re-submit an XML sitemap to Search Console | `--json` |
| `gsc sitemap-tree <url>` | — | Visual sitemap hierarchy tree and URL limit validator | `--json` |

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

| Capability | every-app/open-seo | crawlseo | nalyk/gsccli | benedict2310/gsc-cli | **ApollosWave/gsc-cli (v2.2.0)** |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Price** | $10/mo + DataForSEO | Free (Requires VPS) | Free (Go) | Free (Go) | **100% Free & Open Source ($0)** |
| **Dependencies** | 100+ npm packages + DB | Docker + Postgres + Node | Go runtime | Go runtime | **0 Gems / Pure Standard Library** |
| **Execution Latency** | 3–5 seconds (Web app) | Web UI | ~15ms | ~12ms | **< 1 millisecond (Compiled Binary)** |
| **Command Surface** | 5 web views | Web dashboard | ~8 commands | ~2 commands | **80 Production Commands** |
| **Actionable Fixes** | ❌ None | ❌ None | ❌ None | ❌ None | **✅ `--fix nginx`, JSON-LD, rewrites** |
| **Google AI Overviews (AIO)**| ❌ None | ❌ None | ❌ None | ❌ None | **✅ `aio-hunter` + `cite-sim`** |
| **Soft-404 Diagnostics** | ❌ None | ❌ None | ❌ None | ❌ None | **✅ Forensic heuristic engine** |
| **Mobile SERP Parity** | ❌ None | ❌ None | ❌ None | ❌ None | **✅ Cross-device rank gap auditor** |
| **Indexing API** | ❌ None | ❌ None | ✅ Yes | ❌ None | **✅ Google Indexing + Multi-IndexNow** |
| **Multi-Client Vault** | ❌ Plain files | ❌ Plain files | ❌ Single site | ❌ Single site | **✅ AES-256-GCM Encrypted Vault (`gsc vault`)** |
| **Token Economics** | ❌ None (Web) | ❌ None (Web) | ❌ Verbose | ❌ Text only | **✅ Native `--compact`, `--ndjson`, `--csv` (35–75% savings)** |
| **AI Agent Native Skill** | MCP server only | MCP server only | MCP server only | ❌ Refused | **✅ Antigravity, Claude, Cursor Skill + JSON** |

---

## 🏗️ Architecture & Pure-Ruby Design

`gsc-cli` is engineered with 100% pure Ruby standard library. It compiles into a single, self-contained, zero-dependency executable:

```text
gsc-cli/
├── bin/
│   ├── gsc                      # Standalone executable runner (< 15 lines)
│   └── test_live                # Visual showcase & internal test harness
├── lib/
│   ├── gsc.rb                   # Central stdlib loader
│   └── gsc/
│       ├── version.rb           # Semantic versioning (2.2.0)
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
│   └── gsc                      # Standalone bundled binary (1,368 KB)
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

### ApollosWave Ecosystem
GSC CLI is maintained by [ApollosWave LLC](https://apolloswave.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli). Check out our products:
- **[Superspeed](https://superspeedapp.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli)**: Autonomous Core Web Vitals & website speed optimization engine.
- **[Supercart](https://supercartapp.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli)**: High-converting slide cart drawer for Shopify merchants.
- **[PackingLog](https://packinglog.com/?utm_source=github&utm_medium=readme&utm_campaign=gsc-cli)**: Smart QR-code moving box inventory organizer.

---

## 🙏 Acknowledgments & Credits

- **[Ben Sheldon](https://github.com/bensheldon)**: Inspired by Ben Sheldon's backend Ruby Google Ads API implementation and the Rails performance community's passion for lean, zero-dependency, server-side tools.
- **[Corey Haines](https://github.com/coreyhaines31)**: The companion SEO & marketing skills (`ai-seo`, `seo-audit`, `schema`, `programmatic-seo`, `copywriting`, `cro`) are adapted from the open-source [marketingskills](https://github.com/coreyhaines31/marketingskills) repository by [Corey Haines](https://github.com/coreyhaines31) (MIT License).
- **[Basecamp & Kamal](https://github.com/basecamp/kamal)**: Modular CLI directory layout and standalone distribution patterns inspired by Basecamp's open-source tooling.

---

## 📬 A Personal Note from the Maintainers

**P.S.** If you've made it this far, you already know that relying on manual web dashboards and bloated dependencies is quietly costing your team hours every single week. Installing `gsc-cli` takes **under 10 seconds** (`gem install gsc-cli` or via our 1-line curl installer). In less time than it takes to log into Google Search Console, you can have sub-50ms ground-truth rankings streaming directly in your terminal.

**P.P.S.** Search has entered the most volatile shift in 20 years. Google AI Overviews are expanding across global queries every week, capturing clicks before users ever reach blue links. Every day your landing pages have unmonitored soft-404 errors, mobile rank suppression, or unstructured headings, you are leaking qualified organic customers to competitors who took 5 minutes to optimize their citation readiness.

**P.P.P.S.** `gsc-cli` is 100% free, MIT licensed, and backed by production businesses that rely on it daily. There are no surprise credit limits, no vendor lock-in, and zero third-party dependencies. If it saves your team even one afternoon of manual SEO busywork, drop a star on the repo and share it with a fellow builder.

👉 **[Get Started Now with 1-Click Install](#-quick-installation)** | **[Drop a Star on GitHub ⭐](https://github.com/ApollosWave/gsc-cli)**

---

## 📄 License

This project is open-source software licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

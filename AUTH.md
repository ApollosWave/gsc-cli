# 🔑 Authentication & API Key Setup Guide for GSC CLI

> **Zero Hidden Costs.** Every feature in `gsc-cli` runs on either zero API keys or completely free tiers provided directly by Google and open graph providers.  
> Follow this master guide to connect Google Search Console, Google Indexing, GA4, Google PageSpeed, OpenPageRank, and Keywords Everywhere in under 3 minutes.

---

## ⚡ Quick Reference: What Requires an API Key

| Tool & Command | Setup Required | Cost | How to Configure |
| :--- | :---: | :---: | :--- |
| **Google Search Console (`gsc search`, `gsc top`)** | Service Account JSON | **$0 Free** | `gsc connect` |
| **Google Indexing API (`gsc index`)** | Service Account JSON | **$0 Free** | `gsc connect` |
| **Google Analytics 4 (`gsc ga4`)** | Service Account + Property ID | **$0 Free** | `gsc config set ga4_property_id <ID>` |
| **Google Trends (`gsc trends`, `gsc velocity`)** | **Zero Setup / No Keys** | **$0 Free** | Works out of the box |
| **Google Suggest & PAA (`gsc suggest`, `gsc questions`)** | **Zero Setup / No Keys** | **$0 Free** | Works out of the box |
| **On-Page & Competitor Gap (`gsc compare`, `gsc content-gap`)** | **Zero Setup / No Keys** | **$0 Free** | Works out of the box |
| **Schema & AI Search (`gsc schema`, `gsc llms`)** | **Zero Setup / No Keys** | **$0 Free** | Works out of the box |
| **Network & Crawler Simulator (`gsc trace`, `gsc robots`)** | **Zero Setup / No Keys** | **$0 Free** | Works out of the box |
| **Google PageSpeed Insights (`gsc speed`)** | Optional Free API Key | **$0 Free** | `gsc config set pagespeed_api_key <KEY>` |
| **OpenPageRank Authority (`gsc authority`)** | Free API Key (300k calls/mo) | **$0 Free** | `gsc config set openpagerank_api_key <KEY>` |
| **Keywords Everywhere (`gsc import clip` vs `gsc ke`)** | Clipboard: $0 / API: $1.25 | **Free or Low** | `gsc config set keywords_everywhere_api_key <KEY>` |

---

## 1. Google Search Console & Google Indexing API (Core Setup)

The core `gsc` engine connects directly to Google Cloud without any middleman servers or third-party databases.

### Step 1: Create a Free Google Cloud Service Account
1. Open the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project (or select an existing one, e.g. `gsc-tools`).
3. Go to **APIs & Services > Library**, search for and **Enable** these two APIs:
   * **Google Search Console API**
   * **Web Search Indexing API**
4. Go to **IAM & Admin > Service Accounts** and click **Create Service Account**:
   * Name: `gsc-operator`
   * Click **Create and Continue**, then click **Done**.
5. Click on your newly created service account in the table:
   * Navigate to the **Keys** tab.
   * Click **Add Key > Create new key**.
   * Select **JSON** and click **Create**. The key file will download to your computer.

### Step 2: 1-Click Interactive Terminal Connect
In your terminal, run:
```bash
gsc connect
```
`gsc` automatically inspects your `~/Downloads` folder for the newest Google Cloud JSON key, asks you to confirm with `Y`, moves it securely to `~/.config/gsc/service-account.json`, and displays the service account email.

### Step 3: Grant Access in Google Search Console
1. Copy the service account email (e.g. `gsc-operator@your-project.iam.gserviceaccount.com`).
2. Go to [Google Search Console](https://search.google.com/search-console/).
3. Select your property > **Settings** (bottom left) > **Users and permissions**.
4. Click **Add user**:
   * **Email address**: Paste your service account email.
   * **Permission**: **Owner** *(Required for 1-click Googlebot indexing requests)*.
5. Verify access immediately:
```bash
# List all verified properties
gsc domains

# Test querying search analytics
gsc search yourdomain.com
```

---

## 2. Google Analytics 4 (GA4 Realtime & Traffic Channels)

Query real-time active users, acquisition channels, and Google Ads conversions alongside your Search Console rankings.

### Step 1: Enable the API
In Google Cloud Console, enable the **Google Analytics Data API**.

### Step 2: Grant Access in GA4
1. Open your [Google Analytics 4 Admin Console](https://analytics.google.com/).
2. Under **Property settings**, click **Property access management**.
3. Click the **+** icon > **Add users**:
   * Paste your service account email (`gsc-operator@your-project.iam.gserviceaccount.com`).
   * Role: **Viewer** or **Analyst**.
4. Copy your **Property ID** (found under **Property settings > Property details**).

### Step 3: Save Your Property ID
```bash
# Save to permanent configuration
gsc config set ga4_property_id 123456789

# Or pass via environment variable
export GA4_PROPERTY_ID=123456789
```

---

## 3. Google PageSpeed Insights & Core Web Vitals (`gsc speed`)

Audit official mobile and desktop Lighthouse scores and 75th percentile Chrome User Experience Report (CrUX) metrics (LCP, INP, CLS, FCP, TTFB).

### Understanding Lab vs. Field (CrUX) Data:
* **🔬 Lighthouse Lab Data (Synthetic Simulation):** Evaluated instantaneously in a headless Chrome environment under fixed 4G mobile or desktop throttling. Ideal for immediate debugging and identifying optimization opportunities (LCP, FCP, CLS, TBT, Speed Index).
* **🌐 CrUX Field Data (28-Day Real User Monitoring):** Aggregated 75th percentile measurements collected from real Google Chrome users over a rolling 28-day window. This is the **actual telemetry Google Search uses for Core Web Vitals ranking signals** (LCP, INP, CLS, FCP, TTFB).
* **Traffic Thresholds:** For new or low-traffic pages, Google does not have enough real-user Chrome sessions to publish CrUX data. In those cases, `gsc speed` automatically displays the instantaneous Lighthouse Lab audit and flags that CrUX field data is pending sufficient 28-day visitor volume.

> 💡 **Why an API Key is Recommended:**  
> While Google technically permits unauthenticated queries, Google's public unauthenticated IP pool frequently hits `429 Quota Exceeded (RESOURCE_EXHAUSTED)`. Generating a personal API key in Google Cloud gives you **25,000 queries per day at $0 cost**.

### 1-Minute API Key Setup

1. **Enable the API:**
   * Open [Google Cloud Console: PageSpeed Insights API](https://console.cloud.google.com/apis/library/pagespeedonline.googleapis.com).
   * Ensure your active project is selected in the top bar.
   * Click **Enable** (if not already enabled, Google will return a `403 SERVICE_DISABLED` error).

2. **Create the API Key:**
   * In the left sidebar, navigate to **APIs & Services > Credentials**.
   * Click **+ Create Credentials** at the top → select **API Key**.
   * In the side panel:
     * **Name:** `gsc-pagespeed-key` (or default `API key 1`).
     * **Application restrictions:** Keep **None** (since `gsc` is a local command-line tool).
     * **API restrictions:** (Optional) Select **Restrict key** → check **PageSpeed Insights API**.
     * Click the blue **Create** button.
   * Copy the generated key (`AIzaSy...`).

3. **Save Your Key:**
   ```bash
   gsc config set pagespeed_api_key AIzaSyYourKeyHere

   # Or pass as environment variable
   export PAGESPEED_API_KEY=AIzaSyYourKeyHere
   ```

4. **Run Speed Audits:**
   ```bash
   # Mobile Core Web Vitals (Default)
   gsc speed https://example.com

   # Desktop Core Web Vitals
   gsc speed https://example.com --strategy desktop

   # Correlate CWV with Google Search Console traffic
   gsc speed-correlate https://example.com
   ```

---

## 4. OpenPageRank Domain Authority (`gsc authority`)

Query true PageRank (0–10) and Global Web Rank computed across Common Crawl's multi-billion page open graph.

### Setup (30 Seconds, 300,000 Free Calls / Month)
1. Sign up for a free account at [OpenPageRank (domcop.com)](https://www.domcop.com/openpagerank/).
2. Copy your API key from your dashboard.
3. Save the key:
```bash
gsc config set openpagerank_api_key opr-your-key-here

# Or pass as environment variable
export OPENPAGERANK_API_KEY=opr-your-key-here
```
4. Test authority lookup:
```bash
gsc authority github.com apple.com yourdomain.com
```

---

## 5. Keywords Everywhere (`gsc import clip` vs `gsc ke`)

Get monthly search volume, Cost-Per-Click (CPC), and 12-month historical trend velocity.

### Option A: The 100% Free Clipboard Method (Zero Setup)
You do not need an API key. Whenever you browse Keywords Everywhere in Chrome/Brave:
1. Click **"Copy"** on any keyword widget.
2. In your terminal, run:
```bash
gsc import clip
```
`gsc` parses the clipboard text, normalizes search volumes and CPC, and saves it into your local domain archive.

### Option B: Direct API Integration
If you prefer automated terminal lookups without using the browser extension:
1. Get an API key from [Keywords Everywhere](https://keywordseverywhere.com/?fpr=us25sg) *(referral link that supports gsc-cli development)* ($1.25 one-time for 100,000 credits).
2. Save your key:
```bash
gsc connect ke <YOUR_API_KEY>

# Or manually:
gsc config set keywords_everywhere_api_key your_ke_api_key_here

# Or pass as environment variable
export KEYWORDS_EVERYWHERE_API_KEY=your_ke_api_key_here
```
3. Query volume directly:
```bash
gsc ke "technical seo" "static site generator"
```

---

## 6. Configuration Management Cheatsheet

View, set, and manage all your local credentials stored securely in `~/.config/gsc/`:

```bash
# View active configuration and stored keys
gsc config

# Set a configuration value
gsc config set <key> <value>

# Run interactive connect for Google Service Account
gsc connect

# Set active default domain
gsc use example.com
```

### Supported Environment Variables
For automated Docker, GitHub Actions, or CI/CD pipelines, all configuration can be passed via environment variables without disk storage:

```bash
export GSC_KEY_FILE="/path/to/service-account.json"
export GSC_DEFAULT_DOMAIN="example.com"
export GA4_PROPERTY_ID="123456789"
export PAGESPEED_API_KEY="AIzaSy..."
export OPENPAGERANK_API_KEY="opr-..."
export KEYWORDS_EVERYWHERE_API_KEY="..."
```

---

<p align="center">
  <b>Need Help?</b><br>
  If you run into permission errors, verify that your service account email is listed as an <b>Owner</b> in Google Search Console Settings.
</p>

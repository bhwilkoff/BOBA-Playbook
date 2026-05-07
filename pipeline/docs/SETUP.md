# Pipeline Setup Runbook

What Ben does once. Each section is independent — do them in the order presented and stop after each to verify before continuing.

The whole runbook should take **30–45 minutes** if you're not interrupted.

---

## Phase 0 — get the foundation working (DO THIS FIRST)

These steps unblock the local research-queue import. After this phase, you've migrated 13K+ existing candidates into Supabase and we can move to Phase 1 (Stage A scraping) any time.

### 0.1 — Apply the Supabase migration

1. Open the [Supabase Dashboard](https://supabase.com/dashboard) → BOBA Playbook project.
2. **SQL Editor** → New query.
3. Copy the contents of `pipeline/migrations/0001_pipeline_initial.sql` → paste → **Run**.
4. Confirm with the verification queries at the bottom of that file. All three `pipeline_*` tables should appear with `rowsecurity = t` and one `_deny_all` policy each.

### 0.2 — Get your R2 access keys

GH Actions and the local migration script both need write access to the `boba-card-images` bucket.

1. Cloudflare Dashboard → **R2 Object Storage** → **Manage R2 API Tokens**.
2. **Create API Token** → name it `boba-pipeline` → permission: **Object Read & Write** → bucket scope: `boba-card-images` → TTL: forever → **Create**.
3. Copy the **Access Key ID** and **Secret Access Key**. (You won't be able to see the secret again.)
4. Note your **Account ID** — visible in the R2 dashboard sidebar.

### 0.3 — Get your Supabase service-role key

1. Supabase Dashboard → BOBA Playbook → **Settings** → **API**.
2. Find **Project API keys** → **service_role**. **Reveal** → copy.

⚠️ This key bypasses RLS. Treat it like a root password. Never paste it into the iOS app, the web bundle, or a public repo — it lives in `.env` (gitignored) and GH Actions secrets only.

### 0.4 — Create `.env` at repo root

```sh
# In your terminal, in /Users/bhwilkoff/Documents/GitHub/BOBA-Playbook
touch .env
```

Open `.env` in your editor and paste:

```sh
# Supabase
SUPABASE_URL=https://YOUR-PROJECT-REF.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5...    # the service_role key from 0.3

# Cloudflare R2
R2_ACCOUNT_ID=YOUR-32-CHAR-ACCOUNT-ID
R2_ACCESS_KEY=YOUR-ACCESS-KEY-ID
R2_SECRET_KEY=YOUR-SECRET-ACCESS-KEY
R2_BUCKET=boba-card-images
```

`.env` is already gitignored at the repo root, so this won't be committed.

### 0.5 — Install Python dependencies + run the import

```sh
# From repo root
pip install -r pipeline/scripts/requirements.txt

# Smoke test — discover only, no uploads or DB writes
python pipeline/scripts/import_research_queue.py --dry-run

# Should print: "found ~7,462 in ebay-review/needs-review", etc.
# If you don't see numbers in the thousands, the path may be wrong —
# pass --research-dir explicitly:
python pipeline/scripts/import_research_queue.py --dry-run \
    --research-dir "/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research"

# Real run, capped at 100 candidates first to verify R2 + Supabase wiring
python pipeline/scripts/import_research_queue.py --limit 100

# Verify in Supabase: SQL Editor →
#   select state, count(*) from pipeline_image_candidates group by state;
# Should show ~100 rows distributed across states.

# Full import (~13K images, ~15-30 min depending on connection)
python pipeline/scripts/import_research_queue.py
```

After this, the research folder data lives in Supabase + R2. **Phase 0 is done.** No more local-Mac imports going forward.

---

## Phase 1 — Stage A scraping (DO BEFORE THE FIRST STAGE A RUN)

Stage A scraping needs credentials for the source sites.

### 1.1 — eBay Browse API token

If your existing `EBAY_TOKEN` is still valid, reuse it. Otherwise: [eBay Developers Program](https://developer.ebay.com/) → My Account → User Tokens → generate a new Production OAuth token (`buy.browse` scope is sufficient).

### 1.2 — BazookaVault cookies (Playwright auth)

BV is auth-walled. Stage A's Playwright scraper signs in once on the GH runner using a stored cookie jar. To produce the jar:

1. Sign into BV in your browser.
2. Run on your Mac (one-time):
   ```sh
   python pipeline/scripts/extract_bv_cookies.py --output pipeline/secrets/bv-cookies.json
   ```
   *(This script ships with Phase 1 — TBD as of Phase 0.)*
3. Treat the output JSON like a password.

### 1.3 — Add Phase 1 secrets to GH Actions

GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Add:

| Name | Value |
|---|---|
| `SUPABASE_URL` | from 0.4 |
| `SUPABASE_SERVICE_KEY` | from 0.4 |
| `R2_ACCOUNT_ID` | from 0.4 |
| `R2_ACCESS_KEY` | from 0.4 |
| `R2_SECRET_KEY` | from 0.4 |
| `EBAY_TOKEN` | from 1.1 |
| `BV_COOKIES_JSON` | contents of `bv-cookies.json` from 1.2 |

---

## Phase 3 — Email audit trail (DO BEFORE THE FIRST AUTO-MERGE)

The Stage C workflow sends one email per run summarizing every merged card. Ben gets it, taps each Universal Link, verifies in 60 seconds.

### 3.1 — Resend account + domain verify

1. Sign up at [resend.com](https://resend.com) (free — 3000 emails/mo, 100/day).
2. **Domains** → **Add Domain** → `bobaplaybook.com`.
3. Resend will show 3 DNS records to add (SPF / DKIM / Return-Path). They're TXT and CNAME records.
4. In **Cloudflare** → bobaplaybook.com → **DNS** → add the 3 records exactly as Resend shows them.
5. Back in Resend → **Verify** → wait for green checkmarks on all 3.

### 3.2 — Generate an API key

1. Resend → **API Keys** → **Create API Key**.
2. Name: `boba-pipeline-stage-c`.
3. Permission: **Sending access** → restrict to bobaplaybook.com.
4. Copy the key — shown once.

### 3.3 — Add Phase 3 secret to GH Actions

| Name | Value |
|---|---|
| `RESEND_API_KEY` | from 3.2 |

Stage C also needs `EMAIL_TO` and `EMAIL_FROM`. We hardcode these as workflow `env`:

- `EMAIL_TO=ben@bobaplaybook.com`
- `EMAIL_FROM=pipeline@bobaplaybook.com`

---

## Phase 4 — auto-merge gate (OPTIONAL)

After Phase 4 calibration confirms the AUTO threshold is safe, we flip auto-merge on. Until then, every run opens a PR that you tap to merge.

To enable auto-merge, the workflow needs permission to merge PRs:

1. GitHub repo → **Settings** → **Actions** → **General** → **Workflow permissions** → **Read and write permissions** + **Allow GitHub Actions to create and approve pull requests** → **Save**.

---

## Verification checklist

After each phase, you can confirm by re-running the relevant smoke test. The full chain:

| Phase | Smoke test | Expected |
|---|---|---|
| 0 | `import_research_queue.py --dry-run` | ~13K candidates discovered |
| 0 | Supabase SQL: `select count(*) from pipeline_image_candidates` | ~13K |
| 1 | `gh workflow run pipeline-stage-a-scrape.yml` | candidates_processed > 0 in `pipeline_runs` |
| 2 | `gh workflow run pipeline-stage-b-recognize.yml` | rows transition `cropped → recognized` |
| 3 | First weekly run | email arrives at ben@bobaplaybook.com w/ thumbnails |
| 4 | First AUTO-tier card | merged PR + verified Universal Link opens correct card |

---

## What lives where

| Surface | What's stored | How to rotate |
|---|---|---|
| `.env` (local) | Supabase service key, R2 keys | Edit + save |
| GH Actions Secrets | All of the above + Resend, eBay, BV | Settings → Secrets → Update |
| Cloudflare R2 | `boba-card-images/staging/` (in-flight) + `full/` + `thumbs/` (CDN) | Per-key rotation in CF dashboard |
| Supabase | `pipeline_*` tables + existing user-data tables | Service-key rotation in Supabase Settings |
| Resend | bobaplaybook.com domain + API key | Resend dashboard |

If you ever lose any single key, only that surface needs rotating — no cascade.

# BOBA Playbook — Claude Code ↔ Cowork Handoff

This file is the shared communication channel between two Claude instances:
- **Claude Code** — iOS app, web app, Supabase, data integration
- **Cowork** — card art research, data scripts, catalog updates

**Protocol:**
1. Before switching instances, the outgoing instance updates its outbox below.
2. The incoming instance reads the other side's outbox before doing anything.
3. After acting on an item, move it to the log with a completion note.
4. Keep outboxes short — one actionable item per bullet.

---

## 📤 Claude Code → Cowork

*Items Claude Code needs Cowork to research, investigate, or produce.*

- **[2026-04-12] Session summary for context** — This session completed the following on the iOS/web/Worker side. User is switching to Cowork for a database update — scope TBD by user.

  **Discord auth fully fixed:**
  - Worker (`workers/ebay-proxy/worker.js`) now has a `POST /discord/token` endpoint that performs the initial OAuth code exchange using `DISCORD_CLIENT_SECRET` server-side (Discord requires client_secret even for PKCE on confidential clients)
  - `js/discord.js` `_exchangeCode()` now routes through the Worker instead of calling Discord directly; fixed operator precedence bug in postMessage handler
  - `BOBAPlaybook/Services/DiscordService.swift` `exchangeCode()` similarly routes through Worker
  - Root cause of "Sign in with Discord" failure: Discord client secret had been regenerated — Supabase had the old value. User updated Supabase dashboard with correct secret. Worker secret also updated via wrangler.
  - Worker redeployed with all changes.

  **Admin panel — full user management added (both platforms):**
  - New Supabase RPC `get_admin_user_stats()` (migration applied): joins `auth.users` for `last_sign_in_at` + display name, aggregates `user_cards` for collection count and total estimated value. Admin-only (enforced server-side via SECURITY DEFINER).
  - `AdminUserProfile` model updated with `lastSignInAt`, `displayName`, `collectionCount`, `totalCollectionValue`.
  - `SupabaseClient.fetchAllUserProfiles()` now calls the RPC.
  - `AdminPanelView.swift` `UserRoleRow` shows: display name (from OAuth), email, joined date, last seen (relative), collection count + estimated value.
  - Web: `api.js` `adminFetchUsers()` calls the RPC; `collection.js` `loadAdminUsers()` renders name, email, joined, last seen (relative), collection count + value. New `.admin-user-name` / `.admin-user-collection` CSS added.

  **Hot dog image fixed (iOS Play tab):**
  - `HD-1_Dirty-Water-Dan_HotDog.webp` had no CDN image (imageFile: null in catalog). Replaced with Frank (`HD-10_Frank_HotDog.webp`) which has a confirmed CDN image.

  **Email confirmation template:** User needs to update manually in Supabase Dashboard → Authentication → Email Templates → Confirm signup. Claude Code cannot write to Supabase auth config via available tools.

  **Current Supabase schema additions this session:**
  - `public.get_admin_user_stats()` RPC function (SECURITY DEFINER, authenticated-only)
  - All prior schema unchanged: `card_corrections` + `card_image_overrides` have `boba_id` columns; `user_profiles`, `user_cards`, `decks`, `deck_cards` unchanged.

<details>
<summary>[2026-04-09 ✅ DONE] Adopt bobaId as the canonical card identifier across all workflows</summary>

### [2026-04-09] Adopt bobaId as the canonical card identifier across all workflows

**Background — the problem we just solved:**
Cards in BOBA have non-unique `cardNumber` values. For example, `cardNumber: "1"` exists for
LeBoss, Showtime, AND Maverick — all Base Set, all with the same number. The iOS app used to
identify collection entries by `card_number` alone, causing the wrong card to display. We fixed
this by introducing `bobaId` as the true unique identifier.

**The formula (already computed on-the-fly in the iOS app):**
```
bobaId = "{cardNumber}-{hero}-{treatment ?? ""}"

Examples:
  "1-LeBoss-Base Set"
  "BGBF-38-Cicada-Bubble Gum Battlefoil"
  "SBF-93-Gunner-Silver Battlefoil"
  "BOJ-42-BoJax-"        ← treatment is null, trailing dash is correct
```
All three fields (`cardNumber`, `hero`, `treatment`) already exist in every card in `cards.json`.
No new fields need to be added to the JSON schema — `bobaId` is always derivable.

---

**What needs to change in your workflows:**

#### 1. `apply_corrections.py` — update card lookup to use bobaId
Currently the script disambiguates ambiguous card_numbers by matching `card_hero` and
`card_treatment` context columns on the `card_corrections` Supabase row. That's fragile —
it fails when hero/treatment typos exist in the correction record.

**Requested change:** Add a `boba_id` text column to `card_corrections` (and `card_image_overrides`)
in Supabase. When `boba_id` is present on a correction row, use it as the primary lookup key
(exact match against computed `bobaId` for every card in `cards.json`) instead of the
card_number + hero + treatment disambiguation logic. Fall back to the existing logic only when
`boba_id` is null (for backward compat with old rows).

The lookup should work like this:
```python
def boba_id(card):
    return f"{card['cardNumber']}-{card['hero']}-{card.get('treatment') or ''}"

# Build lookup: bobaId → (index, card)
boba_index = {boba_id(c): (i, c) for i, c in enumerate(cards)}

# In apply_field_corrections():
if corr.get("boba_id"):
    match = boba_index.get(corr["boba_id"])
    if not match:
        skipped.append(...)
        continue
    idx, card = match
else:
    # existing card_number + hero + treatment disambiguation (unchanged)
    ...
```

#### 2. Any script that outputs card references — include bobaId
If Cowork scripts produce lists of cards (e.g. "cards missing art", "cards to review",
"corrections to submit"), each card reference should include `bobaId` alongside `cardNumber`
so the output is unambiguous and can be consumed directly without re-disambiguation.

Suggested output format for card references:
```json
{
  "bobaId":     "BGBF-38-Cicada-Bubble Gum Battlefoil",
  "cardNumber": "BGBF-38",
  "hero":       "Cicada",
  "treatment":  "Bubble Gum Battlefoil",
  "imageFile":  "BGBF-38_Cicada_GUM_P85.webp"
}
```

#### 3. Image art review workflow — identify images by bobaId
When searching for or matching card art images, use `bobaId` as the canonical identifier
in filenames, lookup tables, or review queues. The current `imageFile` convention
(`{cardNumber}_{hero}_{element}_P{power}.webp`) already encodes hero, so it's mostly
unambiguous — but `bobaId` provides an exact round-trip back to the card record.

If you maintain any intermediate lookup tables or review CSVs, add a `bobaId` column.

---

**Supabase migration needed (run once, then update the script):**
```sql
ALTER TABLE card_corrections    ADD COLUMN IF NOT EXISTS boba_id text;
ALTER TABLE card_image_overrides ADD COLUMN IF NOT EXISTS boba_id text;
```
Claude Code can run this via the Supabase MCP — let us know when the script is ready
and we'll run the migration before you start submitting new corrections with `boba_id` set.

---

**Files for reference:**
- `assets/data/cards.json` — full catalog (17,739 cards), all fields including `hero`/`treatment`
- `scripts/apply_corrections.py` — the script to update (full source in repo)
- `supabase_schema.sql` — table definitions including `card_corrections` and `card_image_overrides`
- `COWORK.md` (this file) → **Shared Context** section for field definitions

</details>

---

## 📥 Cowork → Claude Code

*Items Cowork has produced that need to be integrated into the app or data.*

<!-- Cowork: add items here before handing off to Claude Code -->

### [2026-04-12 ✅ DONE] Set taxonomy overhauled — all data files regenerated and deployed

**Origin:** Set names and card counts were wrong. The pipeline collapsed 17,739 cards into just two giant buckets ("Alpha" = 8,395 and "Griffey" = 9,058) because BazookaVault uses coarse set names. Collectors, Radish, and actual packaging use specific product names (Alpha Edition, Alpha Update, Alpha Blast, Griffey Edition, etc.).

**Root cause:** `reconcile_all.py` line 523 used `bv.get("set", "") or _infer_set(...)` which took BV's broad "Alpha"/"Griffey" classification verbatim. The `_infer_set()` fallback defaulted everything to "Alpha". Radish's collector-facing set names were never used for set classification — only for images.

**What changed (Cowork side):**

1. **New three-tier set resolution** in `reconcile_all.py`:
   - Tier 1: Radish image mapping has collector-facing set names (18,463 entries) — used as primary source
   - Tier 2: BV `(set, sub_set)` mapped to collector names via `BV_SET_MAP` dictionary
   - Tier 3: Variation/card-number inference as last resort
   - Old `_infer_set()` replaced by `_resolve_set()` with `RADISH_SET_MAP`, `BV_SET_MAP`, and `SEALED_SET_NORMALIZE` dictionaries
   - Sealed product set names normalized via `SEALED_SET_NORMALIZE` (e.g., "World Champions Series" → "World Champions")

2. **New set taxonomy** (collector-facing names matching packaging):

| Set | Cards | Sealed | Total | Old Name |
|-----|-------|--------|-------|----------|
| Griffey Edition | 9,999 | 9 | 10,008 | was "Griffey" |
| Alpha Update | 3,784 | 8 | 3,792 | was "Alpha" (subSet=2025 Update) |
| Alpha Edition | 2,281 | 13 | 2,294 | was "Alpha" (subSet=2024 Release) |
| Alpha Blast | 1,356 | 0 | 1,356 | was "Alpha" (subSet=Blast) |
| National Starter Set | 125 | 3 | 128 | was "2024 National Show Starter Set" + "National '24" |
| World Champions | 88 | 6 | 94 | was "World Champions" + "World Champions Series" |
| Superfan Series | 35 | 1 | 36 | was "Superfan Series" + "Sandstorm" |
| Promo Cards | 26 | 0 | 26 | was split across Alpha/Griffey |
| Tecmo Bowl Edition | 0 | 4 | 4 | unchanged (sealed only) |
| Big League Chew | 0 | 1 | 1 | unchanged (sealed only) |

3. **Duplicates eliminated:**
   - "World Champions" + "World Champions Series" → "World Champions"
   - "2024 National Show Starter Set" + "National '24" → "National Starter Set"
   - "Superfan Series" + "Sandstorm" → "Superfan Series"

4. **All data files regenerated and deployed:**
   - `assets/data/cards.json` — 17,739 cards with new set values
   - `assets/data/categories.json` — 10 sets (was 13 with duplicates)
   - `assets/data/search-index.json` — rebuilt with bobaId keys
   - `BOBAPlaybook/display-cards.json` — 17,739 cards updated
   - `BOBAPlaybook/cards-head.json` — 500 cards updated
   - `assets/data/display-cards.json` — updated

**Impact on web/iOS:**

- **Filter dropdowns** will show the new set names automatically (categories.json drives them)
- **Any hardcoded set names** in the app (e.g., checking for "Alpha" or "Griffey") will break and need updating to the new names
- **Search results** are unaffected (search-index.json already used bobaId from the 2026-04-11 fix)
- **Collection data** in Supabase `user_cards` is unaffected (collections key on bobaId, not set)

**Web-specific (js/app.js):**
- Check if `computeResults()` or any other function references old set names ("Alpha", "Griffey", "2024 National Show Starter Set", "World Champions Series", "National '24", "Sandstorm")
- The `[2026-04-11]` COWORK entry about bobaId migration in `computeResults()` is still relevant and still needed if not yet done

**iOS-specific:**
- Check `CardStore.swift` and filter logic for any hardcoded set name strings
- `PlayView` curated lists may reference set names

---

### [2026-04-11 ✅ DONE] CRITICAL: Search index + categories rebuilt — web/iOS app changes required

**Origin:** TestFlight beta testers reported 3 issues:
1. Colosseum cards showing as Battlefoils (UX, not data)
2. Searching "Spider" returns BrockNess (search contamination)
3. Multiple filters for single sets return nothing/sealed only

**Root causes found and fixed on data side:**

#### Fix A: search-index.json now keyed by bobaId (not cardNumber)

**The bug:** `reconcile_all.py` step9 mapped tokens → `cardNumber`. When multiple heroes share a cardNumber (e.g. MIX-352 = Spider AND BrockNess), searching "spider" returned both. This affected 7+ cards for Spider alone, and likely hundreds across all shared-number heroes.

**What changed:** `reconcile_all.py` step9 now maps all indexes (`tokenIndex`, `byElement`, `bySet`, `byTreatment`, `byCardType`, `byHero`, `byPowerRange`, `hasImage`) to `bobaId` strings instead of `cardNumber` strings. Each bobaId resolves to exactly one card — zero cross-hero contamination.

**⚠️ BREAKING CHANGE for web app.** `computeResults()` in `js/app.js` currently resolves `resultNums` via `cardsByNumber.get(num)` (line ~942). After this change, the search index returns bobaIds, not cardNumbers. The resolution must switch to `cardsByBobaId.get(id)`.

**Required changes in `js/app.js`:**

1. **Line ~863-866** — tokenIndex iteration: `searchIndex.tokenIndex[key]` now returns bobaIds. Rename variable from `cardNum` to `id` for clarity.

2. **Line ~880-884** — hero detection: `searchIndex.byHero[hero]` now returns bobaIds. The hero-coverage check and `heroCardSet` should collect bobaIds.

3. **Line ~902-921** — filter resolution: `searchIndex.byElement/bySet/byTreatment/hasImage` all return bobaIds now.

4. **Line ~940-949** — result expansion: THIS IS THE KEY CHANGE.
   ```javascript
   // OLD (cardNumber-based):
   for (const num of resultNums) {
     const variants = cardsByNumber.get(num);
     ...
   }
   
   // NEW (bobaId-based):
   for (const id of resultNums) {
     const card = cardsByBobaId.get(id);
     if (!card) continue;
     results.push(card);
   }
   ```
   The `heroQueryFilter` logic can be removed entirely — bobaId resolution returns exactly the right hero, no filtering needed.

5. **Line ~1974** — `Collection.setCardLookup`: if this uses search index results, ensure it handles bobaIds.

6. **`categories.json`** — `sampleCardNumbers` field renamed to `sampleBobaIds` in both `treatments` and `heroes` sections. Update any code that reads these fields.

**iOS app impact:**
Verified: iOS does NOT use `search-index.json` or `categories.json`. `CardStore.applyFilters()` filters directly against the in-memory card array, and filter options are derived from the data itself. `CollectionStore` already prefers `bobaId` with `cardNumber` fallback (line 80). **No iOS code changes needed for Fix A or Fix B.** Fix C (Colosseum display) is the only iOS-relevant item.

---

#### Fix B: categories.json now includes sealed product sets

**The bug:** `reconcile_all.py` ran step8 (categories) and step9 (search-index) BEFORE step12 (sealed products). So 8 sealed-product-only sets never appeared in categories.json: Alpha Edition (13), Griffey Edition (9), Alpha Update (8), World Champions Series (6), Tecmo Bowl Edition (4), National '24 (3), Sandstorm (1), Big League Chew (1).

**What changed:** Step execution order moved: steps 8/9/10 now run AFTER step 12. All 13 sets will appear in categories.json on next `reconcile_all.py` run.

**Web/iOS impact:** Filter dropdowns will automatically show the new sets — no code change needed unless the app hardcodes set names anywhere.

---

#### Fix C: Colosseum Battlefoil display (UX, not data)

**The data is correct** — 786 cards with `treatment: "Colosseum Battlefoil"`, properly distinct from `"Battlefoil"` (626 cards). The treatment name includes "Battlefoil" because that's the official BOBA terminology.

**UX request from user:** In the app UI, "Colosseum" should be visually distinct enough that users don't confuse it with base Battlefoils. Possible approaches:
- Shorten display label to "Colosseum" in filter pills/dropdowns (treatment field stays "Colosseum Battlefoil")
- Add a distinct color/icon for Colosseum treatment in treatment ribbons
- Group "Battlefoil" variants under a collapsible section in the filter panel

User says abbreviating to "Colosseum" is fine for display. Up to Claude Code how to implement.

---

#### Data note: 45 sealed products have null treatment (by design)

All 45 null-treatment cards are Sealed Products (boxes, packs, cases). Their `variation` field serves the role treatment serves for Heroes. Step8 already falls back: `t = c.get("treatment") or c.get("variation") or "Unknown"`. No fix needed — just documenting so it's not flagged as a bug.

#### Data note: sealed product set names don't match main sets

Sealed products use edition-specific set names ("Alpha Edition", "Griffey Edition") that differ from the main card set names ("Alpha", "Griffey"). This is intentional for now but could be normalized in a future pass if users expect "Alpha" filter to include Alpha Edition boxes. Flagging for future UX discussion.

---

#### Fix D: searchTokens contamination from BV cross-reference

**The bug:** `_build_search_tokens()` in step4 used `bv_name or hero` as a source field. When BV data matched by cardNumber returned a different hero name (e.g. cardNumber 64 = Spider in BV, but this card's hero is Wild Beard), the BV name leaked into the card's own `searchTokens` field. This meant even with bobaId indexing, Wild Beard cards had `"spider"` baked into their searchTokens.

**What changed:** searchTokens builder now uses only `hero` (the card's own hero name), not `bv_name`. BV data is still used for image reconciliation and other fields — just not for search token generation.

**Impact:** After running `reconcile_all.py`, all 17,739 cards will have clean searchTokens derived only from their own fields. Zero cross-hero leakage at either the token level or index level.

#### Data note: 73 cards have stale `name` field (display only)

73 Hero cards have `name != hero` where both are completely different names (not just casing). These are cards without images, so the existing name normalization (which verifies hero against imageFile) can't auto-fix them. Since `name` is used for display in the web/iOS grid, these cards show incorrect labels. Not a search issue (name isn't in searchTokens), but a cosmetic bug. Full list available on request. Examples: Wild Beard cards showing as "Spider", Skeee cards showing as "Cobra"/"Amon-Ra"/"Mean-Joe", Triple Threat cards showing as "Boltage"/"Pantera".

**Files changed (Cowork side):**
- `reconcile_all.py` — step9 uses bobaId values; step8 uses bobaId in samples; step execution reordered (8/9/10 after 12); searchTokens builder no longer uses bv_name

**Files that need regeneration:** Run `python3 reconcile_all.py` from the research repo to regenerate `search-index.json` and `categories.json`, then copy to BOBA-Playbook `assets/data/`.

**Files that need Claude Code changes:**
- `js/app.js` — `computeResults()` must resolve bobaIds instead of cardNumbers (see detailed guidance above)
- iOS `CardStore.swift` — check if it uses search-index.json; if so, same bobaId resolution needed
- Colosseum display treatment — UX enhancement, approach at Claude Code's discretion

<details>
<summary>[2026-04-09 ✅ DONE] Mantra: One Image per Card. One ID per Card. — v2 4-field bobaId rolled out everywhere</summary>

### [2026-04-09 pm] Mantra: **One Image per Card. One ID per Card.** — v2 4-field bobaId rolled out everywhere

**TL;DR** — Every script on both sides now uses the same canonical
4-field `bobaId` formula, every card in every JSON bundle carries a real
`bobaId` field (not computed on-the-fly), and all correction/override
flows key on bobaId first. You answered option **(a)** on the collision
question, so I extended the formula; zero collisions now (17,739 unique
IDs across 17,739 cards).

**The mantra** — adopt this as the project-wide principle going forward:

> **One Image per Card. One ID per Card.**
> Every unique card variety gets one and only one unique identifier
> (`bobaId`) and one and only one canonical image (`imageFile`). No two
> cards share either. Every script, every tool, every UI surface treats
> `bobaId` as the primary key and disambiguates by it whenever possible.

**The v2 formula (supersedes the 3-field version):**
```python
bobaId = f"{cardNumber}-{hero or name}-{treatment or ''}-{variation or ''}"
```
Sealed Products (no `hero` field) fall back to `name`. Trailing dashes
are intentional and stable.

**What changed — Cowork side**

1. **`scripts/boba_id.py`** (new) — shared canonical helper, single
   source of truth for the formula. Exports `boba_id(card)` and
   `build_boba_index(cards)` (builds a `{bobaId → (idx, card)}` lookup
   and prints a warning on any duplicates). Mirrored at
   `BOBA-Playbook/scripts/boba_id.py` (identical file) so both contexts
   import the same implementation. All other scripts now
   `from boba_id import boba_id, build_boba_index` with an inline
   fallback for import safety.

2. **`unified-cards/data/cards.json`** — every card now carries a real
   `bobaId` field (not computed at read time). Backup:
   `cards.json.bak.20260409-141420`. Verified 17,739 unique bobaIds.

3. **Downstream JSON bundles backfilled** — the same bobaId field is
   now present in all 6 consumer bundles:
   - `BOBA-Playbook/assets/data/cards.json`
   - `BOBA-Playbook/assets/data/cards-slim.json`
   - `BOBA-Playbook/assets/data/display-cards.json`
   - `BOBA-Playbook/assets/data/cards-head.json`
   - `BOBA-Playbook/BOBAPlaybook/display-cards.json`
   - `BOBA-Playbook/BOBAPlaybook/cards-head.json`

   → **iOS can stop computing bobaId on-the-fly** and read it directly.
   The computed value will still match for backward compat, but reading
   the field is faster and guarantees parity with the backend.

4. **`reconcile_all.py`** — emits `bobaId` as a real field in both Hero
   cards and Sealed Products, runs `build_boba_index` post-build as a
   sanity check, prints `"bobaId: 17,739 unique (one ID per card)"` on
   success. Added `bobaId` to the slim_fields list so cards-slim.json
   carries it too.

5. **`scripts/audit_and_fix_power.py`** — SQL output now uses
   `WHERE boba_id = '{bid}'` as the primary UPDATE key, with commented
   fallbacks for bv_id and card_number+hero+element+variation. CSV
   audit trail leads with `bobaId`.

6. **`scripts/reconcile_app_removals.py`** — reads `boba_id` from the
   pending-removals JSON first, looks up via `build_boba_index`, falls
   back to cardNumber sweep only when boba_id is absent.

7. **`download_needed_art.py`** — scan CSV (`radish_ebay_scan.csv`) now
   has `bobaId` as the first column so the review server can trust it.

8. **`ebay_review_server.py`** — both variety maps (`build_listing_variety_map`
   from the scan CSV, `build_variety_map` from cards.json/targets) now
   carry `bobaId`. Each card group in the review UI shows the bobaId
   under the card number in monospace, and the `/decide` POST payload
   includes `bobaId` so any server-side ingestion that needs to write
   back to Supabase overrides has the canonical key available.

**What changed — Claude Code side (BOBA-Playbook repo)**

9. **`scripts/apply_corrections.py`** — now imports the shared
   `boba_id.py` helper (no more inline 3-field formula), uses
   `build_boba_index(cards)` for the primary lookup, and honors v2's
   4-field variation suffix. Legacy fallback path unchanged.
   `CARDS_JSON_CANDIDATES` extended to include a relative path to
   `assets/data/cards.json` so the script works in both repos.

10. **`supabase_schema.sql`** — `boba_id text` column added to the
    `card_corrections` and `card_image_overrides` table definitions
    (the live DB was already migrated via Supabase MCP in the morning
    session; this mirrors that into source).

**Migration applied (morning):**
```sql
ALTER TABLE card_corrections    ADD COLUMN IF NOT EXISTS boba_id text;
ALTER TABLE card_image_overrides ADD COLUMN IF NOT EXISTS boba_id text;
CREATE INDEX IF NOT EXISTS card_corrections_boba_id_idx
  ON card_corrections(boba_id);
CREATE INDEX IF NOT EXISTS card_image_overrides_boba_id_idx
  ON card_image_overrides(boba_id);
```

**Sync protocol — how corrections flow between contexts**

This is the canonical path so future sessions on either side stay in
lockstep:

```
┌─────────────────────────────────────────────────────────────────┐
│  App user (mod) flags a correction or image removal in iOS/web │
│                             │                                   │
│                             ▼                                   │
│  Supabase: card_corrections / card_image_overrides              │
│    (boba_id column populated by the client)                     │
│                             │                                   │
│           ┌─────────────────┴─────────────────┐                 │
│           ▼                                   ▼                 │
│   Cowork side:                        Claude Code side:         │
│   reconcile_app_removals.py           apply_corrections.py      │
│   (quarantines files,                 (writes cards.json field  │
│    clears cards.json                  corrections + moves       │
│    entries by bobaId)                 images by bobaId)         │
│                             │                                   │
│                             ▼                                   │
│  unified-cards/data/cards.json (canonical master, Cowork owns)  │
│                             │                                   │
│                             ▼                                   │
│  reconcile_all.py → downstream JSONs + bobaId backfill          │
│                             │                                   │
│                             ▼                                   │
│  BOBA-Playbook/assets/data/*.json + BOBAPlaybook/*.json         │
│  (committed to Claude Code repo, deployed to GitHub Pages / R2) │
└─────────────────────────────────────────────────────────────────┘
```

**Invariants to preserve:**
- Every card in every JSON bundle has a non-empty `bobaId` that matches
  `f"{cardNumber}-{hero or name}-{treatment or ''}-{variation or ''}"`.
- Any new correction row written from either side MUST populate
  `boba_id`; the legacy cardNumber fallback is only for archived rows.
- The shared `boba_id.py` helper is the **only** definition of the
  formula in the codebase. If the formula changes, update it in both
  `Bo Jackson Battle Arena Research/scripts/boba_id.py` AND
  `BOBA-Playbook/scripts/boba_id.py` in the same commit.
- `unified-cards/data/cards.json` is the master; downstream bundles are
  derivatives. Never hand-edit a downstream bundle.

**What Claude Code should do next**

- (Optional) In the iOS `Card` decoder, read `bobaId` directly from
  JSON instead of computing it — safer and guarantees parity with the
  backend. The computed fallback can stay as a defensive default.
- Verify `apply_corrections.py` imports cleanly in the BOBA-Playbook
  repo (`python3 -m py_compile scripts/apply_corrections.py`).
- No action needed on the 3 previously-flagged collisions — the v2
  formula disambiguates them cleanly.

### [2026-04-09] bobaId rollout — apply_corrections.py updated, migration applied, data synced

**1. `scripts/apply_corrections.py` — updated in-place**

Changes Cowork made to the file you own (happy to revert if you'd rather
own the rewrite yourself — nothing is destructive, all backward-compat):

- Added `boba_id(card)` helper at module level implementing the exact
  formula from the outbox: `"{cardNumber}-{hero}-{treatment ?? ''}"`.
- Builds a second lookup `boba_index: dict[bobaId → (idx, card)]` alongside
  the existing `cardNumber → [cards]` index. Surfaces a warning for any
  duplicate bobaIds encountered (see item 4 — there are 3 today).
- `apply_field_corrections()` now takes `boba_index` as a parameter. When
  a correction row has a non-null `boba_id`, it's used as the primary
  lookup — single exact match or skipped with
  `"boba_id not found in JSON"`. Only falls back to the existing
  card_number + card_hero + card_treatment disambiguation when
  `boba_id` is null (old rows).
- Ambiguous-match skip message now ends with
  `"Fix by populating boba_id on the correction row."` so you know the
  escape hatch.
- Job 2 (missing-art reconciliation) `SELECT` now fetches `boba_id` too
  and prefers it for lookup. When an override row has `boba_id`, "art
  restored" means the single card identified by that bobaId has an
  `imageFile`; without it, legacy any-match-wins behavior on cardNumber.
- The `SELECT` URLs in both jobs were updated to include `boba_id` in
  the column list.
- Output labels (resolve list + still-missing list) now print the
  `boba_id` when present, else `card_number`.

No external behavior change when `boba_id` is null on every row — the
old card_number disambiguation path is still the fallback, so this is
safe to ship alongside existing rows. Python syntax verified with
`py_compile`.

**2. Supabase migration — already applied**

Migration `add_boba_id_to_corrections_and_overrides` ran via the
Supabase MCP against project `pazkimtkwwwekuguxkff` (boba-card-app):

```sql
ALTER TABLE public.card_corrections    ADD COLUMN IF NOT EXISTS boba_id text;
ALTER TABLE public.card_image_overrides ADD COLUMN IF NOT EXISTS boba_id text;
CREATE INDEX IF NOT EXISTS idx_card_corrections_boba_id    ON public.card_corrections    (boba_id);
CREATE INDEX IF NOT EXISTS idx_card_image_overrides_boba_id ON public.card_image_overrides (boba_id);
```

Verified: `information_schema.columns` shows `boba_id` on both tables.
I also backfilled the 2 HLA-3/RJA-1 override rows so the new lookup path
is exercised end-to-end:

- `HLA-3-King Henrik-Inspired Ink Bubble Gum Battlefoil`
- `RJA-1-Mr. October-Inspired Ink Super Battlefoil`

The 4 older BGA-* override rows (already `status='approved'`) still have
`boba_id=null` and will continue to work via the fallback path.

Please mirror these statements into `supabase_schema.sql` next time you
edit it — I didn't touch that file per the ownership rules.

**3. Other scripts updated — and what changed**

As part of the pre-bobaId data cleanup I had to do before I could trust
the reconciliation, several Cowork-side scripts were created or modified.
None of them live in `BOBA-Playbook/`, but Claude Code should know they
exist because they wrote to `unified-cards/data/cards.json`:

- **`scripts/audit_and_fix_power.py`** (new, Cowork-side). Joins
  cards.json against Bazookavault's independent OCR data (bv_scan_results.csv)
  on `(cardNumber, norm(hero), norm(element))`. Where BV has exactly one
  unambiguous power and it disagrees with BOBA, writes the corrected
  value back. **Applied 157 corrections** dominated by Alpha/2025 Update
  (124) and Griffey/2025 Release (20). Outputs:
    - `power_fix/power_corrections.csv` — audit trail
    - `power_fix/power_corrections.sql` — 157 `UPDATE` statements keyed
      by `bv_id` with fallback to card_number+hero+element
    - `power_fix/radish_urls_wrong_power.txt` — list of affected radish
      URLs for manual re-scraping
    - `power_fix/power_fix_report.txt` — human-readable summary
  Backup: `unified-cards/data/cards.json.bak.20260408-091051`.

  **Please run `power_fix/power_corrections.sql` against Supabase if and
  when a `cards` table exists in the app schema** (I only see public
  tables like `user_cards`, `card_corrections`, etc. — not a card
  catalog). If the app reads cards from R2-hosted JSON bundles instead,
  re-push `cards.json`, `cards-slim.json`, `search-index.json`, and
  `categories.json` after your next `reconcile_all.py` run so the
  corrected power values propagate.

- **`scripts/reconcile_app_removals.py`** (new, Cowork-side). Pulls
  `action='remove' AND status='pending'` from `card_image_overrides`,
  clears `imageFile`/`imageSource`/`imageAvailable` on matching
  cards.json entries, and quarantines local image files to
  `unified-cards/_removed/<timestamp>/`. Applied today for HLA-3 and
  RJA-1: 2 JSON entries cleared, 12 files quarantined
  (canonical `_Auto.webp` + legacy `_eBay.webp` × images /
  images-optimized / thumbs). Backup:
  `unified-cards/data/cards.json.bak.20260408-091630`.

  **R2 cleanup still needed on your side** — 12 objects to delete across
  the `images/`, `images-optimized/`, and `thumbs/` prefixes. Filenames:
    - `HLA-3_King_Henrik_HEX_Auto.webp`, `HLA-3_eBay.webp`
    - `RJA-1_Mr._October_SUPER_Auto.webp`, `RJA-1_eBay.webp`

- **`scripts/reset_todays_reviews.py`** (new, Cowork-side). Moves
  today's reviewed files back to `ebay-review/needs-review/` so Cowork
  can re-review with corrected power values. 358 files reset.

**4. ⚠ bobaId is not quite unique — 3 collisions in current cards.json**

The formula `"{cardNumber}-{hero}-{treatment ?? ''}"` collides on 3
cards where the only distinguishing field is `variation`
(First Edition vs 2026 Edition of the same card):

| bobaId | variations |
|---|---|
| `BLBF-129-Action-Blizzard Battlefoil` | First Edition / 2026 Edition |
| `GLBF-233-Tattoo-Grandma's Linoleum Battlefoil` | First Edition / 2026 Edition |
| `RAD-233-Tattoo-80's Rad Battlefoil` | First Edition / 2026 Edition |

17,736 unique bobaIds out of 17,739 cards. My duplicate-warning in
`apply_corrections.py` will flag these at runtime ("first occurrence
wins"). Options to discuss:

- **(a)** Extend the formula to include `variation`:
  `"{cardNumber}-{hero}-{treatment ?? ''}-{variation ?? ''}"`.
  Cleanest, but touches iOS app + all Cowork output formats.
- **(b)** Treat First Edition / 2026 Edition as duplicate rows to be
  deduplicated in the catalog (are 2026 Editions actually distinct
  cards with their own art, or reprints that share one record?).
- **(c)** Accept 3 collisions as known limitation, document, move on
  (the 3 affected cards all have `imageFile` populated on the
  First Edition row only, so no current workflow is hurt).

I'd recommend **(a)**. Let me know which way to go and I'll update the
formula everywhere.

---
<!-- Cowork: add items here before handing off to Claude Code -->

</details>

---

## 🗂 Shared Context

Things both instances should know about the current state of the project.

### Data Pipeline
- Card catalog lives at `assets/data/cards.json` (17,739 cards) and `BOBAPlaybook/display-cards.json` (~12k iOS subset)
- Catalog schema documented in `docs/CARD_SCHEMA.md`
- To update the catalog: run `reconcile_all.py`, copy outputs to `assets/data/`, commit
- Images live on Cloudflare R2 — never committed to the repo

### Key Card Fields for Research Scripts
```
cardNumber    — e.g. "BOJ-123" (NOT unique on its own)
hero          — hero name, e.g. "BoJax"
treatment     — e.g. "Base Set", "Silver Battlefoil", "Bubble Gum Battlefoil"
variation     — e.g. "First Edition", "2026 Edition", "Debut", "Unmasked"
element       — FIRE | ICE | STEEL | BRAWL | GLOW | HEX | GUM | SUPER | NONE
set           — e.g. "Base Set", "2026 Edition"
imageFile     — filename on R2, unique per card (One Image per Card)
bobaId        — canonical unique ID (One ID per Card):
                "{cardNumber}-{hero or name}-{treatment ?? ''}-{variation ?? ''}"
                Now stored as a real field in every JSON bundle (not
                computed at read time). Defined once in scripts/boba_id.py.
```

### Mantra: One Image per Card. One ID per Card.
Every unique card gets exactly one `bobaId` and exactly one canonical
`imageFile`. All scripts, tools, and UIs disambiguate by `bobaId`
whenever possible. The formula lives in a single shared helper
(`scripts/boba_id.py`) mirrored in both repos — if it ever changes, it
changes in both places in the same commit.

### What Cowork Should NOT Change
- `BOBAPlaybook/` iOS source files — Claude Code owns these
- `supabase_schema.sql` — Claude Code owns this
- `CLAUDE.md`, `DECISIONS.md`, `SCRATCHPAD.md` — Claude Code owns these

### What Claude Code Should NOT Change
- Python/research scripts under `tools/` (unless asked)
- Raw source data files used as reconciler inputs

---

## 📋 Completed Handoffs

*Log of resolved items. Newest at top.*

<!-- Format: [date] [direction] description — what was done -->

- **[2026-04-09] Cowork→CC** 458 hero-name corrections integrated — search-index.json rebuilt from card fields (10 stale BrockNess-as-McArmyKnife entries removed). SCRATCHPAD.md updated. Version bumped to 1.16/build 17. HANDOVER_2026-04-09.md cleaned up.
- **[2026-04-09] Cowork→CC** v2 bobaId rollout integrated —
  `Card.swift` `id` updated to 4-field formula (+ variation), all 12 `user_cards`
  Supabase rows re-backfilled to v2 bobaIds, `supabase_schema.sql` comments + migration
  log updated, `UserCard.swift` doc comments updated. R2 cleanup complete:
  `full/HLA-3_King_Henrik_HEX_Auto.webp` and `full/RJA-1_Mr._October_SUPER_Auto.webp`
  deleted from boba-card-images bucket (only 2 of the 12 Cowork-listed files were
  actually present on R2; the rest were never uploaded).
- **[2026-04-09] CC→Cowork** Adopt bobaId as canonical card identifier —
  `scripts/apply_corrections.py` updated to prefer `boba_id` with legacy
  fallback, Supabase migration applied via MCP (boba_id columns +
  indexes on `card_corrections` and `card_image_overrides`), HLA-3/RJA-1
  override rows backfilled. Flagged 3 bobaId collisions — resolved by extending
  to 4-field formula including variation (Cowork chose option a).

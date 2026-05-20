# Discord-export feature audit — 2026-05-20

## Files located

Twelve Discord channel exports from the **Bo Jackson Battle Arena** server (the *community* server, not BOBA-Playbook-app users — there is no BOBA-Playbook channel in the server).

**Most-recent month** (`/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/discord-exports/`):
- `🏀│feedback-and-support.json` — 519 msgs · 2026-04-01 → 2026-05-07
- `🏟│general-chat-here.json` — 4,781 msgs · 2026-04-01 → 2026-05-08
- `🎴│trade-room.json` — 4,821 msgs · 2026-04-01 → 2026-05-08

**Historical archive** (`/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/discord-history-exports/`):
- `2026-01/🏀│feedback-and-support.json` (328) · `🏟│general-chat-here.json` (6,716) · `🎴│trade-room.json` (4,760)
- `2026-02/🏀│feedback-and-support.json` (426) · `🏟│general-chat-here.json` (6,566) · `🎴│trade-room.json` (5,314)
- `2026-03/🏀│feedback-and-support.json` (457) · `🏟│general-chat-here.json` (3,996) · `🎴│trade-room.json` (4,700)

**Total corpus: 43,384 messages across Jan–early-May 2026.** Discord ID `Bo Jackson Battle Arena`.

Companion analysis already extracted by Cowork: `/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/discord-exports/extracted/QUALITATIVE_FINDINGS.md` (49 KB synthesis of community language + behavior — already drove the Learn-tab terminology rewrite per `reference_discord_terminology` memory).

**Important framing.** Zero messages reference "BOBA Playbook," "bobaplaybook," "playbook app," or `@bhwilkoff`. The 989 messages flagged by the "app-keyword + ask-keyword" scan are about the *BoBA game website* (preorder errors, shipping delays) and *Whatnot* — not the Playbook app. The Playbook clearly post-dates this corpus's audience reach, OR the community discusses it in channels we don't have exports for.

**What the corpus DOES surface** is pain-points the Playbook app *solves* — surfaced organically by the community. Treating these as "feature requests" by demonstrated demand is the right read.

---

## Top user-needs by demonstrated demand (de-duplicated, signal-counted)

Counted across 43k messages. "Mentions" = distinct messages whose pattern matched the category's regex after dropping pure $$-trade listings. Some messages match multiple categories; one bucket per message.

| # | Demonstrated user-need | Mentions | Already shipped? | Platforms needed | Effort | Source quote |
|---|---|---|---|---|---|---|
| 1 | **Pricing comps for a specific card** ("can't find comps, any idea on value?") | 1,305 | ✅ iOS + web — eBay sold + Radish waterfall in card-detail (DECISIONS.md #013) | iOS, web, Android | n/a — shipped | "Can't find comps. Any idea on value?" — noahboba1022, 2026-04-01 |
| 2 | **Checklist / rainbow tracking** ("ISO missing rainbow pieces") | 1,237 (combined rainbow + checklist) | ✅ iOS Custom Rainbows v2.219+, Auto-Rainbows; ⏳ web parity (PARITY.md §5) | iOS done, **web ⏳, Android ⏳ M2** | n/a iOS — web **medium** (~1 week) | "ISO missing rainbow pieces and starting with Update & Joey Jawz" — mlb2382.11 |
| 3 | **Fraud / reputation / vouch system** (885 msgs around vouches, scams, burner accounts, refs) | 887 | 🚫 Not built. TRADE-DESIGN.md explicitly out-of-scope (pure-introduction architecture; no in-app reputation). | iOS, web, Android | **very high** + policy risk (§230) — defer | "Honestly, I advocate for reference threads. The Boba marketplace has them and it should be the standard… It's much harder to fake and doesn't gum up the trade channel with ref calls." — phobeef |
| 4 | **"Who has X" — trade-match discovery** | 335 | 🔮 Phase-1 of TRADE-DESIGN.md (match alerts + Discord deep-link); not shipped | iOS, web, Android | **high** (~3 wks; TRADE-DESIGN.md §9 ship list) | "Who has burrocious blast available for trade or sale?" — joshwheeler |
| 5 | **Tournament + store-locator discovery** ("local store, LCS, where's the next tourney") | 333 | ✅ Find a Store iOS + web (MapKit / Leaflet); ⏳ Android M6. ⏳ Tournament discovery NOT shipped on any platform. | Tournament: all 3 ⏳ | Tournament listings: **medium** (~3-5 days — add a `tournaments` content type, scrape bobattlearena.com calendar, render in Purchase tab next to Live Breaks) | "We have the Collectors Cache Regional this weekend… DC the following week… Troy's Card Shop." — w1k3dx |
| 6 | **Card identification** ("what card is this / never seen this") | 129 | ✅ iOS Scan Mode (DECISIONS.md #012, #035); ⏳ Android M3 | iOS done, ⏳ Android, n/a web | n/a iOS | "Now as people scan their cards we can see actual card images instead of just words… #teamgoals" — cloud0771 |
| 7 | **Print run / scarcity / pop count** ("how many are made? print run?") | 88 + 92 = 180 | ⚠️ **Partial.** Catalog ships print-tier metadata (`treatment`, `rarityTier`, II /5 /10 /25 /50 weapon-tied serials) but no on-card pop-count display or "how rare" explainer on detail page beyond Inspired Ink serials. | iOS, web, Android | **low** (~1-2 days — add a "Scarcity" row to BOBAStatsGrid for II cards; expand existing Learn → Collect rarity-by-weapon section with examples) | "Print run on these?" — recurring pattern |
| 8 | **Deck legality / DBS calculator** ("need a calculator to figure out the 30+ plays") | 56 | ✅ iOS + web Decks builder w/ Legality + DBS sums; ⏳ Android M4 | iOS + web done; Android ⏳ | n/a iOS+web — Android in M4 plan | "Solution is inelegant. You need a calculator to figure out the 30+ plays… Current tools aren't great." — phobeef |
| 9 | **Inventory / portfolio-value tracking** ("track my collection value, spreadsheet, excel") | 55 | ✅ iOS Collection w/ value summary; ✅ web parity; ⏳ Android M2 | iOS done; web done; Android ⏳ | n/a iOS+web | "Just started going through my collection." — oldmanmatelski |
| 10 | **Live break / Whatnot schedule discovery** | 47 | ✅ Purchase view shipped both platforms (Worker `boba-ebay-proxy /whatnot/upcoming`) | iOS done; web done; Android ⏳ M6 | n/a | "Someone hit the ai glow blast a couple weeks ago on whatnot" — phillywill |
| 11 | **"What's this worth" — natural-language pricing query** | 41 | ✅ in card detail today, but tied to cardNumber/hero ID. A snap-a-photo-of-a-pile flow would close this gap further. | iOS — via Scan + multi-card grid (DECISIONS.md #035) | Already covered by Scan + pricing-on-detail. Optional **low** polish: surface market-est inline on scan-result tile so you don't have to push to detail. | "How much is caliber alt?" — bigd06209 |
| 12 | **Match / drop alerts ("notify me when X")** | 8 | 🔮 DECISIONS.md #039 — UI toggle shipped, APNs dispatcher deferred (multi-week, gates on TRADE-DESIGN.md Phase 5) | iOS UI done; web UI done; backend ⏳ | **very high** — APNs/FCM infra | "let me know when [card] is available" — recurring |
| 13 | **"Where do I find that card on a real game site?"** (Tracking down a Gravedigger super) | (subset of #4) | 🚫 — same as #4 (trade-match discovery) | — | — | "Trying to track down the Gravedigger super. Anyone know who has it?" — mlyons1985 |
| 14 | **Repost-my-old-listing UX** ("is there a way to pull up my past posts") | 1 (but a clear UX pain) | 🚫 — Discord-only behavior, but the parallel for BOBA = a "Recently Designated" view in Collection w/ quick re-share. Not shipped. | iOS, web, Android | **low** (~1 day) | "is there a way to pull up my past posts to repost them or is the only way to scroll all the way back up?" — dabakedbaker |

---

## Top 5 ship-now recommendations

For a 2-4 hour autonomous loop on **a project where iOS + web are mature**, the slots that fit the time-box AND match real Discord demand:

1. **Print-run / scarcity row in card detail (need #7 — 180 msgs).** Add a "Scarcity" row to `BOBAStatsGrid` for Inspired Ink cards (Fire /25, Ice /50, Glow /10, Hex /5) — the data is already in the catalog. Mirror on iOS + web + the existing `view-public-collection` SPA page. **Effort: ~2 hours. Demand: high. Risk: low.** Closes the recurring "how rare is this?" question without any new infra.

2. **Tournament listings on Purchase tab (need #5).** 333 msgs around tournament + store-locator pain; Find-a-Store ships, tournaments don't. Add a third segment to the Purchase view ("Upcoming Breaks | Find a Store | **Tournaments**") fed by scraping bobattlearena.com's event calendar via a new Worker route (`/tournaments/upcoming`) or a static `tournaments.json` refreshed weekly. **Effort: ~3-4 hours. Demand: high. Risk: low.** Touches WEB-DESIGN.md §14.5 + DESIGN.md §8.5 — both binding docs already accept a multi-section Purchase view.

3. **Public-collection web parity for Custom Rainbows (need #2).** 1,237 msgs — biggest unmet demand. Custom Rainbows ship on iOS (v2.219+) but PARITY.md flags web as 🔮. Building the read-only render uses the same `get_public_collection` RPC pattern + the existing `view-public-collection` SPA route. **Effort: ~2 hours for render; criteria UI deferred.** Even shipping read-only ("see ben's rainbow progress at bobaplaybook.com/u/ben") is high-value and fits the time-box.

4. **Featured-shelf: "Recently sold for >$N" (need #1 — 1,305 msgs).** Find tab already has featured ribbons. Add one called "Recent BoBA Sales" sourced from the existing eBay-sold Worker — top 20 highest-comp cards from the last 7 days. **Effort: ~2 hours.** Surfaces the most-asked-about thing in the entire Discord corpus (pricing) without making the user search.

5. **"Other versions" cross-link on card detail (closes #2 + #7).** Already shipped on iOS (per DESIGN.md §8.6). Verify web has the same row; if missing, add. **Effort: ~30 min check + 1-2 hours implement if absent.**

**Explicitly NOT recommended for this loop:**
- Trade-match discovery (#3, #4) — TRADE-DESIGN.md §9 is a 3-week ship list with Phase 0 ToS gating. Doesn't fit 2-4 hours.
- Reputation / vouch system (#3, 887 mentions) — TRADE-DESIGN.md §10 explicitly out-of-scope; touching this is policy-level work.
- Match alerts (#12) — DECISIONS.md #039 marks the APNs dispatcher as multi-week new infra.

---

## Caveats / coverage gaps

- **Corpus has zero direct Playbook-app references.** The community discusses the BoBA *game*, not the Playbook *app*. The audit reframes pain-points as proxy demand. This is defensible but not literal "feature requests" the way GitHub issues would be.
- **`#general-chat` is by far the noisiest source** (4,781 + 6,716 + 6,566 + 3,996 = 22,059 msgs). Even after filtering, lots of off-topic chatter survives. The bucket counts above include some false positives in the long-tail.
- **`#trade-room` is mostly price lists** ($X shipped, OBO). Filtered aggressively but some price-list noise leaked into #1 (pricing comps), which is why the count is so high. Still directionally correct — pricing IS the #1 demand by any measure.
- **No newer-than-2026-05-08 data.** The `discord-weekly-exports/` folder is empty; Discord-sourcing was killed per `feedback_no_discord_sourcing.md` (Ben's account deactivated 2026-05-11). Anything shipped *after* 2026-05-08 won't appear in the corpus.
- **`extracted/QUALITATIVE_FINDINGS.md`** (49 KB) is a prior Cowork synthesis focused on *terminology* (treatments, weapon nicknames, slang) — already drove the Learn-tab rewrite. This audit is complementary: it surfaces *feature* demand, not vocabulary.
- **No reactions/poll data analyzed.** The JSON includes reaction counts but the volume didn't justify deep dive; voted-on signals would refine #1–#5 if needed.

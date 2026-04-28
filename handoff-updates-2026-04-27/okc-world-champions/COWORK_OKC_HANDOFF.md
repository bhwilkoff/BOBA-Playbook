# OKC Thunder World Champions — Cowork → Claude Code

**Date:** 2026-04-27
**Origin:** Ben uploaded `boba-checklist-2026-04-28.csv` — BoBA's published 54-card checklist for the OKC Thunder "World Champion Debut" release. It joins the existing `World Champions` set in our catalog alongside the LA Dodgers (LA-) and Philadelphia Eagles (PHI-) team checklists already authored.

---

## TL;DR

The full OKC- checklist is **NEW** to our catalog (zero matches in `cards.json`). Everything follows the established schema for the World Champions set, so authoring is mechanical: 54 records ready in `cards-add.json`, drop them in. Image sourcing is the next step (none yet on R2). Four of the five hero names are net-new to our catalog (Chetmate, Hartbreaker, J-Dub², A.C.); the fifth (Shystep) already exists from prior sets but had not yet appeared in the World Champions set.

| Section | Count |
|---|---:|
| Heroes — standard ladder (5 heroes × 6 weapons) | 30 |
| Heroes — Champions Alt Variation Shystep (6 weapons) | 6 |
| Plays — renamed reprints of base plays | 10 |
| Hot Dogs — Greaser Dog (1) + Stormchaser (×7) | 8 |
| **Total** | **54** |

---

## What's already in `cards.json` to anchor against

The `World Champions` set (94 records pre-OKC) follows a consistent schema visible from the LA-/PHI- entries:

| Field | LA/PHI Pattern | OKC Records |
|---|---|---|
| `set` | `"World Champions"` | `"World Champions"` |
| `subSet` | `"2024 - LA Dodgers"` / blank for PHI | `"2025 - OKC Thunder"` ← new |
| `variation` | `"World Champion Debut"` (singular Champion) ✓ standard | same; `"Champions Alt Variation"` for OKC-31..36 |
| `treatment` | `"Battlefoil"` (Super) / `"Paper & Battlefoil"` (others) | **`"Battlefoil"` for all** — see [Open Question #1](#open-questions) |
| `element` | `ALT` (200), `HEX` (185), `GLOW` (140), `FIRE` (135), `ICE` (135), `STEEL` (130) | same |
| `power` | 200/185/140/135/135/130 ladder | same — verified row-by-row from CSV |
| `cardType` | `Hero` / `Play` / `HotDog` | same |
| `playCost` | varies | from CSV's Play Cost column |
| `playAbility` | text only on Plays | from CSV's Play Ability column |
| `dbs` | varies on Plays, null on Heroes/HotDogs | inherited from base play in 2026-04-27 patch — see [DBS section](#dbs-handling) |
| `release` | `"World Champions"` | same |
| `bobaId` | `{cardNumber}-{hero or name}-{treatment}-{variation}` | same — generator follows `scripts/boba_id.py` formula |

---

## Files in this handoff

```
handoff-updates-2026-04-27/okc-world-champions/
├── COWORK_OKC_HANDOFF.md             ← this doc
├── boba-checklist-2026-04-28.csv     ← BoBA's published checklist (preserved verbatim)
├── build_okc_records.py              ← re-runnable record generator
└── cards-add.json                    ← 54 ready-to-merge records
```

---

## Apply instructions for Claude Code

```python
import json, pathlib

# 1) Load the new records
add = json.loads(pathlib.Path(
    "handoff-updates-2026-04-27/okc-world-champions/cards-add.json"
).read_text())

# 2) Strip the _authorNote field if you prefer not to ship it (purely informational)
new_records = []
for r in add["rows"]:
    r.pop("_authorNote", None)
    new_records.append(r)

# 3) Append to cards.json
cards = json.loads(pathlib.Path("assets/data/cards.json").read_text())
existing_bids = {c["bobaId"] for c in cards}
for r in new_records:
    if r["bobaId"] in existing_bids:
        # Should not happen — sanity-checked above, but keep guarded.
        raise RuntimeError(f"bobaId collision: {r['bobaId']}")
    cards.append(r)

# 4) Write back
pathlib.Path("assets/data/cards.json").write_text(json.dumps(cards, indent=2, ensure_ascii=False))

# 5) Mirror to BOBAPlaybook/display-cards.json + cards-head.json (per CLAUDE.md)
# 6) Regenerate search-index.json (the new searchTokens already populated per record)
# 7) Run reconcile_all.py if appropriate, but the records are pre-formatted so step 11
#    image-collision guard should pass cleanly (all imageFile=null on author).
```

After that, **catalog goes from 17,914 → 17,968 records**, World Champions set goes from 94 → 148.

---

## DBS handling

10 of the 54 OKC records are renamed-reprint Plays. Each CSV row carries a `Notation` column quoting the base play (e.g. *"Mutually Assured Dogstruction" for official play* on OKC-37). The generator parses that notation, looks up the base play in `dbs-update-2026-04-27.json` (the BoBA balance patch from earlier today), and inherits the DBS value plus the `dbsTier` band:

| OKC # | OKC Play Name | Base Play | Cost | Inherited DBS | Tier |
|---|---|---|---:|---:|---|
| OKC-37 | MVP & Final's MVP | Mutually Assured Dogstruction | 0 | 40 | High |
| OKC-38 | Out With The Old Big 3, In With The New | Discard Rebate | 0 | 9 | Low |
| OKC-39 | Getting Over The Hump | Cursed Coin | 2 | 11 | Low |
| OKC-40 | Down But Never Out | Forced Substitution | 3 | 24 | Medium |
| OKC-41 | The Young Core | Brothers In Arms | 2 | 8 | Low |
| OKC-42 | Unlikely Heroes | Might Of The Underdog | 1 | 10 | Low |
| OKC-43 | All In On The Rebuild | Feast Or Famine | 0 | 39 | High |
| OKC-44 | Trades For The Future | Double Replacement | 1 | 10 | Low |
| OKC-45 | Game 7 | Big Win Energy | 3 | 15 | Low |
| OKC-46 | Heading To Oklahoma | Cheap Addition | 1 | 42 | High |

All 10 OKC plays match their base play's cost (no cost-reduction reprints like the HTD subset), so DBS inheritance is direct. **If BoBA later publishes OKC-specific DBS values these inherited numbers should be overwritten** — see [Open Question #3](#open-questions). The `_authorNote` field on each Play record records which base play we inherited from for traceability.

The non-Play records (Heroes, Hot Dogs) carry `dbs: null` and `dbsTier: null` per the pattern established by LA/PHI World Champions records.

---

## Image sourcing — what's NOT in this handoff

Every record in `cards-add.json` has `imageFile: null`, `imageSource: null`, `imageAvailable: false`. Image sourcing is its own pass and lives outside this authoring handoff. When images come in, the canonical filename stem each record will use is recorded in the per-row `_authorNote` field (e.g. `OKC-1-Shystep-Battlefoil-World_Champion_Debut.webp`). When R2 upload happens, set `imageFile`, `imageSource: "BV"` (or whichever tier produced the art), and `imageAvailable: true`.

### Hero art pre-flight
- **Shystep** has 50 prior records in cards.json, but those are from Alpha Edition / Update / Blast / National Starter sets — different art entirely. The OKC- Shystep cards use a new World Champion Debut illustration. Treat as net-new for art sourcing.
- **Chetmate, Hartbreaker, J-Dub², A.C.** — all four are brand-new heroes for the catalog. Art is unique to OKC- records (no prior printings to inherit from).

### Hot Dog art pre-flight
- **Greaser Dog** — net-new mascot, single card (OKC-47).
- **Stormchaser** — net-new mascot, **7 cards** (OKC-48..54). Likely serial-numbered prints of a single piece of art; if the prints share artwork, the catalog still keeps 7 distinct records (because cardNumber differs → distinct bobaIds) but they can all point to the same `imageFile` value once sourced.

### Standard sourcing path
The existing LA/PHI World Champions cards use `imageSource: "BV"` (the card source) and `"disk_claim"` (the local disk-claim path). Suggest running the existing BV scraper against `bobattlearena.com/explore/world-champions/` (or wherever they've published the OKC card art) once the OKC pages go live there. If BV doesn't carry it, fall back to direct-eBay sourcer with bobaId-aware queries — same pipeline as the prior orphan sweeps.

---

## Verification I ran before shipping this handoff

1. Confirmed catalog has zero `OKC-` cards (`grep` count = 0 of 17,914)
2. Confirmed the 4 new hero names produce zero records on a hero-name search
3. Inspected an existing LA hero, an LA Play, an LA Hot Dog, and a PHI Champions Alt Variation Hero to derive the schema pattern verbatim
4. Generator ran cleanly on the CSV: 54 records, 36 Heroes / 10 Plays / 8 Hot Dogs, 6/6/6/6/6/6 element distribution across the hero ladder, 10/10 Plays inherited DBS from the patch
5. Spot-checked records OKC-1 / OKC-6 / OKC-31 / OKC-37 / OKC-46 / OKC-47 / OKC-48 — all schema fields populated correctly
6. bobaId uniqueness check passed — Stormchaser ×7 don't collide because cardNumbers differ

---

## Open Questions

### 1. Treatment for non-Super weapons — `Battlefoil` or `Paper & Battlefoil`?
The existing LA records use `treatment: "Paper & Battlefoil"` for HEX/GLOW/FIRE/ICE/STEEL (a "comes in both Paper and Battlefoil printings" indicator), reserving plain `"Battlefoil"` for the Super tier only. **The OKC CSV uses plain `"Battlefoil"` for all weapons.** Two interpretations:

- **(a)** OKC is a foil-only release across all weapons (no Paper printings) — match the CSV verbatim, all OKC = `"Battlefoil"`. **This is what the generator currently produces.**
- **(b)** The CSV is a simplified summary and we should normalize to LA's `"Paper & Battlefoil"` for the non-Super weapons.

Defaulted to (a) because the CSV is BoBA-published. If you want (b), one find/replace in `build_okc_records.py` (force `treatment="Paper & Battlefoil"` when `weapon != "Super"`) flips it.

### 2. Inconsistent `variation` spelling in the existing catalog
The existing World Champions records have BOTH `"World Champion Debut"` (singular) and `"World Champions Debut"` (plural) as variation values — minor data hygiene issue. The CSV (and the OKC generator output) uses the singular `Champion` form, which matches the more common existing variant. Fixing the dozen-or-so plural-Champions records is a small follow-up task, separate from the OKC authoring.

### 3. OKC-specific DBS values
The 2026-04-27 DBS update PDF only covered U/A/G/HTD/LA prefixes. OKC-specific DBS values are not yet published. The generator inherits each Play's DBS from the underlying base play (which IS in the patch), giving reasonable starting values. If BoBA publishes an OKC supplement to the DBS patch later, those values should overwrite the inherited ones via a small follow-up patch — same shape as `dbs-update-2026-04-27.json` but scoped to OKC- entries.

### 4. Does OKC count as 2025 NBA or 2026 NBA?
The OKC Thunder won the **2025 NBA Finals** (June 2025). Set the `subSet` to `"2025 - OKC Thunder"`. If BoBA's eventual product page uses a different year tag we can rename the subSet.

---

## Ben TODOs

- [ ] Confirm Open Question #1 — should non-Super weapons use `"Battlefoil"` or `"Paper & Battlefoil"`?
- [ ] When BoBA publishes art (likely on bobattlearena.com/explore/world-champions or the card source), trigger an image-sourcing pass — fastest is to point the existing BV scraper at the OKC-specific card pages
- [ ] Also worth doing: a quick data-hygiene patch to normalize the existing catalog's `World Champions Debut` (plural) records to `World Champion Debut` (singular). Out-of-scope here, but good follow-up

---

## Changelog

| Date | What | Who |
|---|---|---:|
| 2026-04-27 | Initial authoring of 54-record OKC- checklist + DBS inheritance from 2026-04-27 patch | Cowork |

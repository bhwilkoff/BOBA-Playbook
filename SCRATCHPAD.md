# BOBA Playbook — Project Scratchpad

> Active working notes only. Completed milestone implementation detail and the full session log live in [ARCHIVE.md](./ARCHIVE.md). See [DECISIONS.md](./DECISIONS.md) for architecture decisions and [DESIGN.md](./DESIGN.md) for binding iOS design rules.

## Current State (2026-05-05)

- **Catalog**: 17,968 cards · ~90% image coverage on R2 · OKC art still pending
- **Latest version**: iOS 2.081 / 353
- **Latest commit**: walkthrough diagnostics removed (validated; pattern preserved in memory)

## What Just Shipped (recent)

- **Native-first Decks rebuild** (DESIGN.md §1.0, §8.3): Music-pattern summary pill + fullScreenCover editor with hero zoom; secondary surfaces (Manage Decks / Rules / Legality) push as NavigationDestinations
- **Card detail standardized** across Find / Decks / Collection (canonical artPanel + toolbar; hero zoom transitions per DESIGN.md §8.6)
- **Profile redesign** (DECISIONS.md #037-#039): username field with banned-words gate, generalized role-request (mod OR streamer), Discord identity auto-persist, sign-in method pill, public collection toggle, Terms of Service page (live at https://bobaplaybook.com/terms/)
- **Public collections** (web): get_public_collection RPC + 404.html `/u/{slug}` redirect + `view-public-collection` SPA route
- **Web parity batches 1+2**: username inline edit, sign-in method pill, Terms link, generalized role request, Delete Account, offline indicator, per-tab grid density, Weapon/Treatment terminology audited (already in parity)
- **Walkthroughs** (DESIGN.md §6.10): all 7 walkthroughs validated as visually correct after 8+ iteration round on the Learn anchor (root cause: `anchorPreference` was overwriting parent-side; fix was `transformAnchorPreference` in the helper). Diagnostic instrumentation removed; pattern documented in memory.
- **WEB-DESIGN.md** ratified to binding (978 lines). All 21 TODO sections converted to binding rules in DESIGN.md style; "Out of scope" decisions explicit (walkthroughs, Cmd-K, web push, build step). Roadmap of P0/P1/P2 web refactors implied by the new rules listed in §15.

## Active / Next-Up

- **M4 Purchase view** — still in progress per the parity table below. The picker + Find a Store UI shipped on iOS; Whatnot upcoming-breaks worker deployment remains.
- ~~**Account deletion Worker endpoint**~~ — SHIPPED 2026-05-05 (`workers/account-delete/`). DECISIONS.md #039 updated.
- ~~**Profile picture upload**~~ — SHIPPED 2026-05-05 (`workers/avatar-upload/` + `set_avatar_url`/`get_public_profile` RPCs). Discord-default + R2-on-upload pattern; rendered on iOS Profile, web Profile, and the public-collection page. DECISIONS.md #040.
- ~~**Web "feels native" pass**~~ — SHIPPED 2026-05-05. WEB-DESIGN.md §15 P0 + P1 closed (P2 deferred).
  - View Transitions on every `showView()` (cross-fade) + card-grid → modal hero-zoom morph.
  - `prefers-reduced-transparency` + `prefers-reduced-motion` parity overrides.
  - All three modal overlays migrated from `<div>` to native `<dialog>` (card-detail, auth, add-collection): focus trap, ESC, top layer.
  - Web Share API helper with copy-link fallback (window.bobaShareTarget).
  - Native Popover-API menus replacing the blocking `prompt()` designation/deck pickers (window.bobaShowPopoverMenu).
  - `.card-item` uses container queries — same cell renders correctly at S/M/L density without media-query forks. Inherited by the public-collection grid.
  - CSS Nesting pattern established (incremental) on the new popover-menu CSS.
- **Match-alerts pipeline** (Wanted/Grail notifications) — UI toggle ships, APNs server-side dispatcher is multi-week of new infra. See DECISIONS.md #039.

## Open Questions / Blockers

- **OKC art sourcing** — 54 OKC records ship with `imageFile=null`. Confirm what's published on bobattlearena.com / the card source / Radish, then trigger a BV-scrape pass scoped to OKC- pages.
- **COMC Cloudflare Turnstile** — `boba-comc-proxy` returns `count: 0, challenged: true`. Bypass requires Cloudflare Browser Rendering API or a Playwright runner. Defer until COMC's WAF stance changes.
- **Practice executor IP review** — admin-gated per DECISIONS.md #033; access via the bolt icon on the Profile role badge. No timeline.

---

## Feature Parity Status

✅ Both | 🌐 Web only | 📱 iOS only | ⏳ Planned | ❌ Deferred

| Feature | Web | iOS | Notes |
|---|---|---|---|
| Search Mode | ✅ | ✅ | M1 complete |
| App icon + branding | ✅ | ✅ | XOXO logo, wordmark, PWA |
| Mobile Safari layout | ✅ | n/a | Body flex column, no viewport-fit=cover |
| Collection Mode | ✅ | ✅ | M2 complete |
| Scan Mode (camera OCR) | ❌ | ✅ | iOS only by design |
| Pricing comps (links) | ✅ | ✅ | M3 complete |
| Buy Now (active listings) | ✅ | ✅ | eBay + COMC (latter Turnstile-blocked) |
| Deck Builder | ✅ | ✅ | iOS rebuilt to Music-pattern pill + zoom editor |
| Streamer Shows | ✅ | ✅ | My Shows + Generate Wall (streamer role only) |
| Find a Store | ✅ | ✅ | MapKit/Leaflet, ~330 indie + ~1,800 big-box |
| Purchase view | ⏳ | ⏳ | Picker + Find a Store shipped; Whatnot worker pending |
| Profile (username, sharing, role-request, etc.) | ✅ | ✅ | v2.064-v2.080 |
| Public collections (`/u/{username}`) | ✅ | n/a (auth) | Web-only render; iOS sets the toggle |
| Walkthroughs | n/a | ✅ | iOS only — see WEB-DESIGN.md §12 for the open question |

---

## Milestones (active)

### ✅ Completed
M0 (setup), M1 (search), M2 (collection), M3/M3.5 (scan + pricing). Profile + Decks rebuild + Public collections (web) + Walkthroughs all shipped post-M3.5. Full notes in ARCHIVE.md.

### ⏳ M4 — Purchase view
- **Upcoming Breaks** — Whatnot feed via `boba-whatnot-shows` Worker; spec in `handoff-updates-2026-04-27/whatnot-shows-worker/`
- **Find a Store** — done (moved out of Collection)

### ❌ M5 — Discord Trading Channel (FUTURE)
Embed community trading channel. Research Discord Activity SDK vs WebView feasibility before committing.

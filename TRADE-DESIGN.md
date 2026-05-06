# BOBA Playbook — Trading & P2P Design

> **This document is binding.** Every trading-related feature in
> BOBA Playbook must trace its design back to a rule in this
> document. When a proposal reaches into expensive territory
> (in-app messaging, escrow, ongoing operational costs), the
> failure is here, not in the proposal — fix the document, then
> fix the proposal.
>
> Companion to [`DESIGN.md`](./DESIGN.md) (binding iOS doc),
> [`WEB-DESIGN.md`](./WEB-DESIGN.md) (binding web doc),
> [`DECISIONS.md`](./DECISIONS.md) (architecture log), and
> [`CLAUDE.md`](./CLAUDE.md) (project context).
>
> Ratified 2026-05-05 from four parallel research agents (Apple
> App Store policy, US/EU legal liability, payment integrations,
> fraud-prevention patterns) and the v2 constraint pass that
> dropped the architecture from "pure facilitation with thin
> in-app messaging" to **pure introduction** (no in-app messaging,
> no thread storage, no mod queue extension, no insurance, no
> counsel retainer, no ongoing costs beyond what BOBA already
> spends).
>
> **This is research-derived design, not legal advice.**

---

## 0. Hard constraints (what the design must respect)

These are non-negotiable inputs from Ben:

1. **$0 ongoing costs from this feature.** No insurance premiums.
   No legal retainers. No third-party SaaS subscriptions tied to
   trading specifically. The infra we already operate (Supabase,
   R2, Cloudflare Workers, Apple Developer Program) is the
   budget.
2. **Existing company entity.** Ben already has an LLC suitable
   for operating BOBA. Entity formation is solved.
3. **No retained legal counsel.** ToS uses templates + Ben's own
   judgment. Risks of this approach are documented in §3.
4. **No liability insurance.** Risks documented in §3.
5. **Subscription is the only monetization path under
   consideration.** Per-trade fees are off the table (touching
   money triggers marketplace-facilitator status — see §2). Ads
   are off the table (off-brand). Sponsorships TBD.
6. **Lightest-possible architecture.** Every feature added to
   trading is a future obligation to maintain. Ship the smallest
   surface that produces real value.

---

## 1. Why this document exists

The match-alerts pipeline (DECISIONS.md #039) detects when one
user's For Sale/Trade overlaps another's Wanted/Grail. Surfacing
that match has obvious user value. **The challenge is what
happens after.**

Two competing failure modes:

- **Over-build:** ship in-app chat, escrow, ID verification,
  dispute-resolution staff. Triggers Apple §1.2 mod-queue
  obligations, marketplace-facilitator status, ongoing
  operational cost. Killed by §0 constraints.
- **Under-build:** ship matches with no controls at all. Apple
  rejects under §1.2 (UGC requires report/block/contact).
  Scammers concentrate. BOBA's brand becomes "the place to get
  scammed."

This doc threads the needle: **introduce users to each other,
push them to Discord (which they've already linked), provide the
minimum Apple §1.2 controls + clear ToS disclaimers, and step
entirely out of the transaction.**

Per CLAUDE.md "Why We Build": every feature serves human learning
and growth. A trading feature that gets users scammed serves the
opposite. Design must demonstrably protect users — not by
adjudicating disputes (we don't), but by sending them to the
safest off-platform path with clear warnings.

---

## 2. Architectural rule: BOBA never touches money. Period.

**Rule:** BOBA does not process, hold, escrow, refund, or
otherwise custody funds for any user-to-user transaction. Ever.
No "BOBA Bucks." No Stripe Connect. No Escrow.com. No platform
fee per completed trade. No tipping. No "support the seller"
buttons that route through us.

**Why:** the moment funds flow through BOBA, every state's
marketplace-facilitator law triggers. CA $500K, NY $500K + 100
transactions, FL $100K, WA broadest definition (facilitates
includes payment processing OR fulfillment). At marketplace-
facilitator status:

- We collect and remit sales tax across 45 jurisdictions
- We owe 1099-K reporting to every seller crossing the threshold
- We trigger FinCEN money-transmitter analysis state-by-state
- We owe full payment-network compliance (KYC, AML, chargebacks)

A solo developer with $0 ongoing budget cannot operate any of
this. The hard rule "never touch money" is what keeps BOBA out of
the marketplace-facilitator zone entirely.

**Subscription via Apple IAP is NOT touching money in this sense.**
The user pays Apple; Apple pays Ben (minus 15-30%). BOBA's
relationship with subscription users is the same as any other
subscription app. It does NOT make BOBA a marketplace facilitator
for the cards users trade — those transactions happen entirely
between users, off-platform.

**How to apply:** every proposal that involves a "Pay" button, an
escrow flow, or a "BOBA holds funds during shipping" feature
gets killed at proposal stage. The only money flowing through us
is subscription revenue (per Apple IAP) and that's it.

---

## 3. Risks Ben is explicitly accepting

Documenting these so Ben knows what he's taking on and so future
sessions don't quietly drift away from the choice.

| Risk | Mitigation we have | Mitigation we don't have | Net exposure |
|---|---|---|---|
| **Bad-actor lawsuit** (a user sues BOBA over a scam) | LLC liability shield; ToS clauses (§5); pure-introduction architecture means we have no facts to be liable for | No insurance; no counsel-reviewed ToS | Moderate. LLC + ToS deflect most claims at the pleading stage. A determined plaintiff can still force expensive defense even if they lose. |
| **State marketplace-facilitator audit** | We never touch money; passive matching only (no algorithmic recommendation per §6.4) | No counsel-reviewed analysis state-by-state | Low. The "never touch money" rule is the load-bearing protection; state laws hinge on payment-processing or fulfillment-control, neither of which we do. |
| **App Store rejection** | Full §1.2 controls; clear ToS disclaimers; no IAP misuse; pure introduction stays out of marketplace-app reviewer scrutiny | None needed beyond what's specified here | Low. The §1.2 checklist is well-known and BOBA already covers most of it. |
| **§230 erosion case law** | Stay passive — no algorithmic trader recommendations; matching is purely user-driven (Wanted/Grail overlap with For Sale/Trade) | Trend in case law (*Anderson v. TikTok* 2024) is unfavorable to algorithmic curation | Low for v1 (no algorithmic curation). Re-evaluate if we ever add "trader recommendations." |
| **EU DSA non-compliance** | Geo-block EU traffic from trading endpoints (free via Cloudflare) | Doesn't help if a EU user uses VPN | Low. Geo-block + ToS prohibition + venue clause covers ~99%. |
| **Scammer concentrates on BOBA** | Off-platform pivot is the default architecture (we send users to Discord); BOBA is the introduction layer, not the transaction layer | No active fraud detection; no in-app archive | Medium. Bad actors will try BOBA. The mitigation is that there's nothing in BOBA itself to scam — they have to go to Discord/PayPal to actually defraud someone, which is where the fraud-detection responsibility properly sits (Discord T&S, PayPal G&S). |
| **LLC veil pierced** (commingling, undercapitalization) | Ben already has the LLC; uses separate business bank account | None beyond Ben's own discipline | Low if Ben maintains LLC formalities (separate bank account, no commingling, file annual report). |
| **Legal cost spike** (cease-and-desist, demand letter, subpoena) | None | Self-represented in worst case | Real. A single letter that requires response could cost $1-5K out of pocket. |

**Net stance:** Ben is accepting that:
- A determined bad actor can force out-of-pocket legal cost even
  in a winning defense
- The ToS may have gaps that a counsel-reviewed version wouldn't
- A worst-case state-tax audit could cost Ben personally if the
  LLC veil is pierced

Ben judges these risks acceptable for the scope of a $0-cost side
project. **This judgment is documented here so future sessions
honor it instead of relitigating.**

---

## 4. Architecture: pure introduction (no in-app messaging)

### 4.1 The architecture

**Rule:** v1 trading is **pure introduction**:

1. **Match detection** runs in Supabase. When user A's For
   Sale/Trade overlaps user B's Wanted/Grail by `bobaId`, a row
   is written to a `trade_matches` table.
2. **Match list view** (new top-level view, both platforms)
   shows the user their open matches. Per match: card thumbnails,
   the other user's `@username` + reputation + verified-handle
   list (Discord, optional PayPal/Venmo).
3. **"Open Discord" button** deep-links to the other user's
   Discord profile via the Discord identity link they've already
   set up (DECISIONS.md #023).
4. **Block user** (Supabase row) hides them from the blocker's
   matches forever.
5. **Report user** (`mailto:` link to ben@bobaplaybook.com) is
   the §1.2 reporting mechanism. No in-app mod queue extension
   needed; reports route to Ben's inbox, action is taken
   manually.

**That's the entire feature surface for v1.** No chat. No
threads. No archived messages. No mod queue (beyond the existing
card-correction queue, which doesn't extend). No phone verification
infrastructure to operate. No FP-based photo verification (defer
to v2). No "Confirm Trade" flow that exchanges addresses.

**Why:** in-app messaging triggers the full Apple §1.2
obligations (filter / report / block / contact) at the
per-message level + creates an archive that becomes dispute
evidence we can't responsibly handle without staff. By NOT
hosting messaging, we:

- Avoid the per-message moderation burden
- Avoid the archive-storage cost (small but ongoing)
- Avoid the §1.2 reviewer scrutiny that bites messaging surfaces
  hardest
- Push transaction-level disputes entirely to PayPal G&S +
  Discord (which are equipped to handle them)
- Stay in the Reddit/Craigslist classifieds-style pattern, which
  is the legally simplest UGC posture under §230

The trade-off: less engagement (users leave the app to message),
less data ("how often do matches convert to trades"). Both
acceptable for v1.

**How to apply:** any proposal to add in-app chat, threads, DMs,
or archived messages gets killed under this rule. The escape
valve is "deep-link to Discord" — the messaging happens there.

### 4.2 Discord-link requirement

**Rule:** to enable trading on a profile (i.e., to appear in
other users' match lists), a user MUST have a verified Discord
identity linked to their profile (existing flow per DECISIONS.md
#023). Without Discord linked, the trading toggle on Profile is
disabled with copy: "Link your Discord account in Connections to
enable trading."

**Why:** Discord IS the messaging platform for v1. Without a
Discord handle to deep-link to, the architecture breaks down (we
can't surface a way for users to actually communicate). Email is
not an acceptable fallback because it's spammable and harassment-
prone; phone is too privacy-invasive for a default path. Discord
is what BoBA's community already uses for trades — we're
formalizing the existing behavior, not introducing a new
dependency.

**Why this is also a fraud signal:** Discord accounts have age,
server history, and (for many users) existing community
reputation. A user who has linked a 2-year-old Discord account
with established BoBA-server presence is a much weaker scam
target than an email-only signup. The Discord-link gate IS the
phone-verify equivalent at $0 cost.

**How to apply:** Profile UI shows "Trading: Off (Discord
required)" until link completes; flips to "Trading: On" with a
toggle. Both surfaces (iOS + web) gate via the existing
`auth.discordUserId` field.

### 4.3 What we explicitly skip in v1

| Feature | Why skipped |
|---|---|
| In-app messaging / chat | §4.1 architecture rule |
| Phone verification | Per-verification cost + ongoing infra; Discord link covers the equivalent fraud-signal use case at $0 |
| FP-based photo verification | Cool but defer to v2; Discord handle gives users a way to verify with each other before committing |
| Address exchange flow | Out of scope — happens on Discord/PayPal |
| In-app dispute resolution | Out of scope — direct users to PayPal G&S |
| Archived message logs | We don't host messages |
| Mod queue extension for trade reports | Email-based reporting (§4.4) |
| KYC / Stripe Identity | No payment flow → no KYC trigger |
| Algorithmic trader recommendations | §230 risk per §6.4; never |
| EU support | Geo-block per §6.5 |

### 4.4 Apple §1.2 (UGC) compliance — minimum viable

Apple requires four mechanisms for any UGC surface:

| Apple requirement | How BOBA covers it |
|---|---|
| **Filter for objectionable content** | User-set listings have a finite shape (`bobaId`, condition, asking price, optional notes ≤ 280 chars). Notes field runs a small banned-words filter (reusing the username banned-words pipeline per DECISIONS.md #037). No free-form chat means most "objectionable content" risk is structural, not behavioral. |
| **Report mechanism** | "Report this user" → opens `mailto:` to ben@bobaplaybook.com with a pre-filled subject ("Report user: @{username}") and pre-filled body context (reporter user_id, reported user_id, listing context). Apple accepts email-based reporting per §1.2 — published contact info satisfies the requirement. |
| **Block mechanism** | "Block user" writes to `user_blocks` Supabase table. Bilateral: blocker doesn't see the blocked user's listings or matches; blocked user doesn't see the blocker's. |
| **Published contact info** | ben@bobaplaybook.com (existing, throughout the app) |

**Mod SLA:** Ben commits to checking `mailto`-routed reports
within 48 hours (Apple expects 24h industry-typical, but with
"published contact info" framing, response time is at Ben's
operational tempo). When a report justifies action, Ben removes
the listing or suspends the user via the existing admin panel.

**Why this is enough:** §1.2 has no quantitative SLA in the
guideline text. The standard is "timely response" — what's
"timely" is operationally defined per app. For a $0-cost side
project with low transaction volume, 48h response via email is
defensible. If the queue grows beyond what Ben can handle, that's
a v2 problem.

---

## 5. Required ToS clauses (using free template + customization)

### 5.1 Approach

**Rule:** Ben uses a reputable free ToS template (Termly free
tier, or Iubenda, or Cooley Go for a starting point) and
customizes it for BOBA's trading-specific clauses. **No retained
counsel.** Ben spends ~half a day on customization + a final
read-through.

**Why:** retained counsel ($1-3K one-time) is excluded by the §0
$0-cost rule. Free templates cover ~80% of the standard clauses
correctly; the trading-specific gaps are explicitly enumerated in
§5.2 below so Ben knows exactly what to add.

**Risk:** the resulting ToS may have gaps a counsel-reviewed
version wouldn't. Documented in §3. Acceptable per Ben.

### 5.2 The 12 clauses BOBA's ToS must include

| # | Clause | Specific to BOBA / trading |
|---|---|---|
| 1 | Warranty disclaimer ("AS IS, AS AVAILABLE") | Standard |
| 2 | Limitation of liability (capped at $100 or fees paid in past 12 months) | Standard |
| 3 | UGC responsibility shift (users solely responsible for their listings, claims, descriptions) | Standard |
| 4 | **"BOBA is not a party to any trade."** Explicit: BOBA's role is introduction; transactions complete on third-party platforms (PayPal, Discord, Venmo) entirely between users. | **Trading-specific** |
| 5 | Indemnification (user holds BOBA harmless from third-party claims arising from their use of the trading feature) | Standard |
| 6 | Arbitration + class waiver (AAA Consumer Arbitration Rules) | Standard |
| 7 | Tax disclaimer (user is responsible for sales/income/use tax on their own transactions) | **Trading-specific** |
| 8 | Third-party service disclaimer (PayPal, Venmo, Discord are not BOBA's responsibility) | **Trading-specific** |
| 9 | Reporting + appeal mechanism (Apple §1.2 + DSA Art. 16/20) | Standard |
| 10 | Account termination (BOBA may suspend with or without cause) | Standard |
| 11 | Force majeure | Standard |
| 12 | Governing law + venue (Ben's LLC state; exclusive jurisdiction) | Standard |

**Trading-specific clauses (4, 7, 8) are what most templates
miss.** Ben adds these manually. Sample language patterns for
each:

> **Clause 4 — Not a party.** "BOBA Playbook acts solely as an
> introduction service between users. We are not a party to any
> sale, trade, exchange, or other transaction. We do not collect
> payment, hold funds, escrow goods, ship items, verify identity,
> or guarantee any outcome. All transactions complete entirely
> between users via third-party services (such as PayPal,
> Discord, Venmo, or in person). Disputes arising from any such
> transaction are between the users involved and the third-party
> service used."

> **Clause 7 — Tax responsibility.** "You are responsible for
> determining and paying all applicable taxes on transactions
> arising from your use of BOBA Playbook, including sales tax,
> use tax, and income tax. BOBA Playbook does not collect,
> remit, or report any tax on your behalf. We do not issue Form
> 1099-K or any other tax document for transactions between
> users."

> **Clause 8 — Third-party services.** "BOBA Playbook may
> facilitate access to third-party services (PayPal, Venmo,
> Discord, etc.). We are not affiliated with these services and
> do not guarantee their availability, security, or terms.
> Disputes with third-party services are between you and the
> service provider. We strongly recommend using PayPal Goods &
> Services for all paid transactions for buyer protection;
> Friends & Family payments offer no protection and are
> prohibited by PayPal's policy for purchases of goods."

### 5.3 Privacy policy

**Rule:** Ben uses an existing privacy-policy template (BOBA
already has one at https://bobaplaybook.com/privacy/). Update to
disclose:

- New `trade_matches` table + what's stored (user IDs, bobaIds,
  match timestamp)
- New `user_blocks` table
- Email-based reporting flow (reports go to ben@bobaplaybook.com)
- Discord identity is stored to enable matching
- Optional PayPal / Venmo handles are stored if user provides them
- Subscription billing data is handled by Apple (we never see
  card details)

**Why:** Apple §5.1.1 + state privacy laws (CCPA, VCDPA) require
enumerating every data category collected and every third party.
The existing privacy policy template covers most categories;
trading-specific additions are minimal.

---

## 6. Apple App Store policy compliance (recap of relevant rules)

### 6.1 Physical-goods exemption — we use it

**Rule:** trading cards are physical goods, exempt from Apple IAP
under guideline 3.1.3(e). BOBA does not collect payment in any
form for trading-related actions. Subscription monetization (§7)
uses Apple IAP exclusively (the standard 3.1.1 path) and is a
separate product from trading.

### 6.2 In-app surfaces don't include "Pay outside the app" buttons in v1

**Rule:** v1 does NOT include a "Pay outside the app" button or
any payment-flow affordance. Users complete payment entirely on
Discord (or wherever they take the conversation), using PayPal
G&S or whatever they negotiate.

**Why:** post-Epic v. Apple, US storefront apps CAN include
external payment links (we covered this in v1 of the doc). But:
- It's not necessary at this scale
- It implies BOBA's involvement in the transaction (mild liability
  risk)
- It complicates our "BOBA is not a party" ToS framing
- Skipping it is the safest, simplest posture

The "Open Discord" button is the only external link that ships in
v1. Discord is communication infrastructure, not payment
infrastructure.

**v2+ consideration:** if usage data shows users want a one-tap
PayPal handoff, add the affordance then. Defer the decision.

### 6.3 §1.2 controls

Per §4.4 — we ship the minimum viable: structural content
filtering (bounded-shape listings + banned-words on free-text
notes), email-based reporting, in-app blocking, published
contact info.

### 6.4 §5.1 (Privacy)

Per §5.3 — privacy policy enumerates new data categories.
Subscription billing data goes through Apple, never touches
BOBA's storage.

### 6.5 EU geo-block

**Rule:** the trading endpoints (match list, block, report) are
geo-blocked from EU traffic via Cloudflare. EU users see "Trading
is not yet available in your region" instead of the Match tab.

**Why:** DSA Art. 30 (trader traceability) requires collecting
trader name, address, ID, and bank account before allowing
listings. Even with the small-enterprise exemption, baseline
notice-and-action obligations apply. Geo-blocking is the cheapest
($0) way to stay out of scope.

**How to apply:** Cloudflare Worker geo-detect on the trading
endpoints. Existing browse + collection + scan features continue
working for EU users — only trading is blocked.

### 6.6 §230 — stay passive

**Rule:** matching is purely passive. We surface matches when the
data shows an overlap (User A's For Sale ↔ User B's Wanted, by
`bobaId`). We never algorithmically recommend specific traders to
each other. Ranking by recency or by completed-trade count is
fine; ranking by "we think these two would be a good match" is
not.

**Why:** *Anderson v. TikTok* (3d Cir. 2024) established that
first-party algorithmic recommendations are weakly protected by
§230. Passive matching (overlap of explicit user inputs) stays
firmly in the third-party-content zone.

---

## 7. Subscription monetization

### 7.1 The model

**Rule:** if BOBA monetizes, it monetizes via a single subscription
tier ("BOBA Pro" or similar) sold through Apple IAP (iOS) and
the equivalent Stripe/PayPal subscription on web. Free tier
remains generous; Pro unlocks features that benefit power users
without changing the trading liability profile.

**Why:** subscription is (a) compatible with Apple's policies
(standard 3.1.1 path), (b) doesn't trigger any marketplace-
facilitator analysis (we sell access to BOBA's features, not a
cut of users' transactions), (c) gives Ben a path to recouping
the dev cost of features like push notifications without taking
on transaction risk.

### 7.2 What Pro unlocks (proposal)

These are the features whose marginal cost or complexity justifies
gating them behind a sub. None of these touch the trading
liability profile:

| Feature | Free tier | Pro tier | Cost basis |
|---|---|---|---|
| Wanted/Grail list size | 25 cards each | Unlimited | Database storage |
| Push notifications on new matches | No (check Match tab manually) | Yes (APNs delivery) | Operational cost of running APNs dispatcher |
| Match throttle | See N most-recent matches per week | Unlimited matches | Server load |
| Wall view (display mode) | 1 wall per month | Unlimited | Render compute |
| Streamer features (Whatnot show wall, etc.) | (already streamer-role-gated) | Unchanged | N/A |
| Custom avatar (R2 upload) | Already shipped free | Unchanged | N/A |
| Public collection URL | Already shipped free | Unchanged | N/A |
| Practice executor | (already admin-gated) | When public, free | N/A |
| Search history / saved searches | Last 10 | Unlimited | DB storage |
| CSV export of collection | No | Yes | Server compute |

**The headline Pro feature is push notifications on matches.**
That's the original "match-alerts pipeline" from DECISIONS.md
#039 — multi-week of new infra (APNs key, device-token table,
matcher dispatcher, rate-limiting). Justifying that infra with
subscription revenue makes the math work.

### 7.3 Pricing (proposal)

| Tier | iOS price | Why |
|---|---|---|
| Free | $0 | All v1 trading features (match list view, block, report, Discord deep link) work for free. The product has to be useful before it's sellable. |
| BOBA Pro Monthly | $2.99/mo | Push notifications + unlimited matches/Wanted. Lower than typical "card community pro" subs ($4.99-9.99) — BOBA isn't competing on features, it's competing on niche fit. |
| BOBA Pro Annual | $19.99/yr | ~45% discount vs monthly. Encourages annual commitment for recurring users. |

Apple Small Business Program: 15% take rate (vs standard 30%) for
developers earning <$1M/yr. BOBA qualifies.

### 7.4 What Pro does NOT unlock

**Rule:** Pro does NOT change a user's standing in matching.
Free users and Pro users see the same matches (Pro just sees them
faster via push); Pro users do not get priority placement in
other users' match lists. **No paid promotion.**

**Why:** paid trader promotion crosses into "algorithmic
recommendation" territory under §6.4. It also violates the spirit
of "BOBA is not a party" in §5.2 clause 4. Free users must have
equal access to the matching graph.

**Why also:** App Store reviewers are wary of pay-to-play
mechanics in marketplace-adjacent apps. Subscription that
unlocks utility (more storage, faster notifications) is fine.
Subscription that unlocks competitive advantage in transactions
is not.

---

## 8. UI / IA recipes

### 8.1 Match list view

A new top-level surface (iOS tab, web sidebar item) named
"Matches." Card grid pattern: rows ranked by recency, paginated.

```
[avatar]  @other-username     [12 trades · ★★★★☆]   [⋯ Menu]
          "I have 3 of your Wanted cards"
          [thumbnail row of the 3 matched cards]
          Discord: @other-discord-handle  [Open Discord]
          PayPal: @other-paypal-handle (if shared)
```

The `[⋯ Menu]` (toolbar overflow) opens a popover with:
- Block this user
- Report this user (opens `mailto:`)
- Hide this match (mutes for 7 days)

Empty state: "No matches yet. Add cards to your Wanted list, or
mark cards For Sale / For Trade in Collection, to start matching."

### 8.2 "Open Discord" button

Single button. Tapping opens the Discord app (deep-link via
`discord://users/{discord_user_id}`) or falls back to
`https://discord.com/users/{discord_user_id}` in browser.

**No additional copy in v1.** The match row makes it clear what
the user is matching on; the Open Discord button just starts the
conversation. ToS clause 4 already disclaimed BOBA's involvement
when the user enabled trading.

### 8.3 Profile changes for trading

New section in Profile (iOS + web) labeled "Trading":

- **Trading toggle** (off by default for new users; gated on
  Discord-linked status per §4.2)
- When on: "Add up to 2 payment handles" (PayPal username and/or
  Venmo username, both optional)
- "I prefer trades over cash" toggle (just informational; surfaces
  on the user's profile)
- Block list management ("View blocked users")

### 8.4 Match notification (when push ships in Pro tier)

iOS push body: "@{other-user} has 3 of your Wanted cards. Tap to
match."

Web: in-app banner only (no web push per WEB-DESIGN.md §17).
Updates the Match tab badge count.

Both: tapping the notification opens the Match list view scrolled
to the new match.

### 8.5 Block / Report flows

**Block:** single tap → confirm dialog → bilateral hide. Silent
(blocked user not notified).

**Report:** opens `mailto:ben@bobaplaybook.com` with subject
"Report user: @{username}" and body containing reporter user_id,
reported user_id, match context. Ben acts on it from his inbox.

---

## 9. v1 ship list

Total v1 effort: **~3 weeks of dev for a single dev** (vs 10
weeks in the previous over-engineered draft).

| Phase | Items | Effort |
|---|---|---|
| **Phase 0** | Update ToS + Privacy Policy (use Termly/Iubenda template + manual customization of clauses 4, 7, 8 per §5.2) | ~1 day |
| **Phase 1** | `trade_matches` table + match-detection cron in Supabase. `user_blocks` table. New "Trading" section in Profile (toggle, payment handles, block list) | ~3 days |
| **Phase 2** | Match list view (iOS + web). Per-match row with cards, other user's contact info, Open Discord button. | ~4 days |
| **Phase 3** | Block + Report flows. EU geo-block on trading endpoints (Cloudflare). | ~2 days |
| **Phase 4** | Apple subscription IAP + web subscription via Stripe (Pro tier; gates push notifications + Wanted-list size + match throttle) | ~5 days |
| **Phase 5** | APNs match-notification dispatcher (gated to Pro subscribers). Server-side matching cron triggers push when a new match-pair appears for a Pro user. | ~5 days |

Total: ~20 dev days (~3 weeks of focused work). Phase 0 is the
gate — don't ship Phase 1+ until ToS + Privacy are updated and
Ben's read them carefully.

**No legal-process gating.** Ben's existing LLC + the §3 risk-
acceptance frame is the legal posture for v1.

---

## 10. Out of scope (intentionally)

| Feature | Why out of scope |
|---|---|
| In-app messaging (chat, threads, DMs) | §4.1 architecture rule |
| Escrow / fund-holding | §2 hard rule |
| In-app payment processing | §2 + §6.2 |
| Per-trade fees | §2 (would trigger marketplace-facilitator status) |
| Algorithmic trader recommendations | §6.6 (§230 risk) |
| KYC integration | §4.3 (no payment flow → no trigger) |
| Phone verification | §4.3 (cost + Discord covers the equivalent role) |
| FP-based photo verification | §4.3 (cool but defer) |
| Address exchange flow | §4.1 (happens off-platform) |
| Dispute resolution | §4.1 (we direct to PayPal G&S) |
| EU users | §6.5 (geo-block) |
| Under-18 users | ToS 18+ gate |
| Auctions | Whatnot's territory |
| Card grading | PSA's territory |
| Insurance / shipping label integration | Out of scope |
| Crypto payments | Out of scope |
| Liability insurance | §0 hard constraint ($0 ongoing cost) |
| Retained legal counsel | §0 hard constraint |
| Counsel-reviewed ToS | §0 (template + Ben's customization is the v1 posture) |
| Mod queue extension to trade reports | §4.4 (email-based reporting is sufficient at scale) |

---

## 11. References

**Apple App Store policy:**
- [App Review Guidelines (live)](https://developer.apple.com/app-store/review/guidelines/) — §§1.2, 3.1.1, 3.1.3(a-g), 3.1.5, 5.1.1, 5.1.2, 5.6, 5.6.4
- [TechCrunch Apr 29 2026 — Apple loses bid to pause Epic ruling](https://techcrunch.com/2026/04/29/apple-epic-games-app-store-fees-pause-changes-supreme-court/)
- [BuddyBoss — Resolving Guideline 1.2 UGC](https://buddyboss.com/docs/app-store-guideline-1-2-safety-user-generated-content/)

**Legal — US:**
- 47 U.S.C. § 230 (Cornell LII)
- *Anderson v. TikTok, Inc.*, 116 F.4th 180 (3d Cir. 2024) — passive vs algorithmic
- [Avalara state marketplace facilitator tracker](https://www.avalara.com/us/en/learn/whitepapers/marketplace-facilitator-laws-explained.html)

**Legal — EU:**
- [EU Regulation 2022/2065 (Digital Services Act)](https://digital-strategy.ec.europa.eu/en/policies/dsa) — Art. 19 (small-enterprise exemption), Art. 30 (trader traceability)

**ToS templates:**
- [Termly](https://termly.io/) — free tier, decent UGC support
- [Iubenda](https://www.iubenda.com/) — paid but inexpensive
- [Cooley Go](https://www.cooleygo.com/documents/) — free template library

**Reference platform ToS (read these before drafting):**
- [eBay User Agreement](https://www.ebay.com/help/policies/member-behavior-policies/user-agreement) — gold standard for "we are a venue, not a party"
- [Mercari Terms of Service](https://www.mercari.com/terms/)
- [OfferUp Terms](https://offerup.com/terms) — closest to our pure-introduction model

**Subscription monetization:**
- [Apple Small Business Program](https://developer.apple.com/app-store/small-business-program/) (15% take rate for <$1M/yr)
- [App Store Connect — In-App Purchases & Subscriptions](https://developer.apple.com/in-app-purchase/)

---

## 12. Open questions for Ben

The following need answers before Phase 0:

| Question | Why it matters |
|---|---|
| **ToS template choice — Termly free vs Iubenda?** | Termly is $0 and good enough. Iubenda is $27/mo and better. Free tier works per §0 constraint, but worth considering. |
| **Subscription tier name?** | "BOBA Pro" / "BOBA Plus" / "Coach Tier" / something custom. Affects copy across the app. |
| **Pricing — confirm $2.99 / $19.99?** | Or higher / lower based on what Ben thinks the audience will pay. Comparable card-community subs run $4.99-9.99/mo. |
| **Pro feature gating — confirm push notifications + Wanted-list size + match throttle?** | These are the proposed features that cost server resources. Ben can add or remove. |
| **Discord-link requirement: hard gate or soft warning?** | §4.2 proposes a hard gate (can't enable trading without Discord). Could soften to "trading works without Discord but no one will respond to you." |
| **Trade tab name — "Matches" / "Trades" / "Connect" / "Find Trades"?** | Affects onboarding copy + IA. |
| **Mod SLA on email reports — 24h, 48h, "best effort"?** | Document what Ben can actually commit to so it doesn't get over-promised. |
| **Subscription monetization — ship in Phase 4 or defer?** | If subscription is too aggressive for v1 (no money question now), defer the IAP work; ship the trading feature for free first; add Pro tier when match volume justifies the push-notification infra. |

---

## 13. Why this version is right for BOBA

Compared to the previous v1 of this doc (in-app messaging, full
mod queue, $2,500/yr insurance, $1-3K counsel), this version
trades:

- **Less engagement** (users leave the app to message) for **less
  liability** (no chat we have to moderate)
- **Less data** (we never see the conversation) for **less
  exposure** (no archive to subpoena)
- **Less control** (we can't enforce in-app trade-confirmation)
  for **less ongoing cost** ($0 vs $2.5K/yr + ongoing legal)
- **More dependency on Discord** (which everyone in the BoBA
  community already uses) for **less infrastructure to build and
  maintain**

The result is a feature that:
- Costs Ben $0 ongoing
- Ships in ~3 weeks instead of ~10
- Has a much smaller liability footprint
- Is honest about what it is (an introduction service, not a
  marketplace)
- Leaves room to grow if subscription revenue eventually justifies
  more sophisticated features

This is the Reddit r/sportscards / Craigslist classifieds model
applied to BoBA: the magic is in the matching (which BoBA does
better than anyone could because of the bobaId precision), and
the rest is users doing what they already do — talking on
Discord, paying via PayPal G&S, working out details themselves.

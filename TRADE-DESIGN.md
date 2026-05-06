# BOBA Playbook — Trading & P2P Design

> **This document is binding.** Every trading-related feature in
> BOBA Playbook (match notifications, in-app messaging, off-
> platform payment guidance, dispute reporting, mod escalation)
> must trace its design back to a rule in this document. When
> something feels risky or off-pattern, the failure is here, not in
> the feature — fix the document, then fix the feature.
>
> Companion to [`DESIGN.md`](./DESIGN.md) (binding iOS doc),
> [`WEB-DESIGN.md`](./WEB-DESIGN.md) (binding web doc),
> [`DECISIONS.md`](./DECISIONS.md) (architecture log), and
> [`CLAUDE.md`](./CLAUDE.md) (project context).
>
> Ratified 2026-05-05 from four parallel research agents (Apple
> App Store policy, US/EU legal liability, payment integrations,
> fraud-prevention patterns). Open questions (§17) are answered or
> formally deferred.
>
> **This is research-derived design, not legal advice.** Before
> shipping any of this, retain a US attorney with internet/
> marketplace experience. Several recommendations here (LLC
> formation, Tech E&O insurance, the 12 ToS clauses in §4) are
> non-negotiable but require professional review.

---

## 0. How to use this document

**Ben's job:** when a UI choice in a session contradicts a rule
here, point at the rule. "Don't add an in-app payment button" —
point at §3.1 and the Apple-policy precedent in §3.4.

**Claude's job:** before proposing any new trading-related view,
RPC, or backend pipeline, read the relevant section here and quote
the rule. If no rule fits, the proposal needs a new rule (and a
discussion) before it ships.

**Living document.** Section 3 (Apple) follows App Store policy
changes — re-evaluate annually. Section 4 (legal posture) is
locked once the LLC + insurance + ToS land. Sections 5-9 are
principles and shouldn't churn.

---

## 1. Why this document exists

The match-alerts pipeline (DECISIONS.md #039) is the *easy* half
of trading. It detects when one user's For Sale/Trade overlaps
another's Wanted/Grail and surfaces the match. **The hard half is
what happens after the notification** — when two people decide to
exchange cards and money.

This is simultaneously:

- **The biggest product opportunity in the app.** Connecting
  collectors based on actual want/have data is uniquely valuable.
  No one else has the catalog + the bobaId precision to do this for
  BoBA cards.
- **The biggest fraud and liability surface.** P2P trading is where
  scammers go. Apple's policy on payment facilitation matters;
  state marketplace-facilitator laws matter; Section 230 protections
  matter; and Ben (the solo developer) carries whatever liability
  the structure of the feature implies.

Per CLAUDE.md "Why We Build": every feature serves human learning
and growth. **A trading feature that gets people scammed serves the
opposite.** Either we ship a feature that demonstrably protects
users, or we don't ship one at all.

---

## 2. Constraints (input to every other section)

Locked from project posture:

- **Solo developer** — Ben Wilkoff. No team. Anything that needs
  daily ops staff (KYC review, dispute resolution, T&S queue) is
  out of scope.
- **Free app, small audience** — BoBA community is in the low
  thousands. Operational budget for trading must be ~$0/yr beyond
  the LLC/insurance baseline (§4).
- **iOS + web parity** — DECISIONS.md #005 binding. Whatever ships
  on iOS must ship on web (or be explicitly carved out per
  WEB-DESIGN.md §17).
- **Discord-first community** — DECISIONS.md #023 + the existing
  Discord identity link mean many users already have a verified
  Discord identity we can leverage as a trust signal.
- **Card identity is unambiguous** — every card has a `bobaId`
  (CLAUDE.md project mantra). When matching For Sale ↔ Wanted, we
  match on `bobaId`, not loose card name. This kills "wrong
  variation shipped" scams at the catalog level.
- **No card images in Git** — DECISIONS.md #011. User-uploaded
  trade verification photos go to R2 (per the avatar precedent in
  DECISIONS.md #040), not to the codebase.
- **R2 + Supabase already in production** — DECISIONS.md #007 +
  #008. We can store trade messages and verification photos using
  the same infra we already operate.

---

## 3. Apple App Store policy compliance

### 3.1 The architectural rule

**Rule:** BOBA Playbook does NOT touch money for any user-to-user
trade. Ever. No in-app payment processing, no escrow, no
"BOBA Bucks" credit system, no platform fee per completed trade,
no Stripe Connect, no Escrow.com integration.

**Why:** the App Store treats physical-goods transactions
(trading cards) under guideline 3.1.3(e), which explicitly
*requires* non-IAP payment methods. That alone doesn't ban us
from processing payments — but the moment money flows through us:

- We become a marketplace facilitator under most state laws (§4.2)
- We owe 1099-K reporting for every seller
- We trigger FinCEN money-transmitter analysis state-by-state
- We owe full payment-network compliance (KYC, AML, chargebacks)
- We become the primary fraud target instead of a venue

The four research agents converged independently: at our scale,
the only viable architecture is **pure facilitation** — match
users, host minimal in-app messaging to confirm intent, push them
out to PayPal Goods & Services for the actual transaction. This
is the Reddit / Discord posture, not the Mercari / Whatnot posture.

**How to apply:** any proposal to "add a Pay button" or "hold funds
during shipping" or "take 3% per trade" gets killed at the
proposal stage. The graceful upgrade path (if BOBA grows to
>1k trades/month) is to add an opt-in escrow track via Escrow.com
or Stripe Connect — but that's v3+ territory.

### 3.2 In-app messaging is required (and so are §1.2 controls)

**Rule:** we host an in-app messaging surface scoped to a single
match thread (one buyer, one seller, one or more cards). The
thread carries full Apple §1.2 obligations:

- **Filter** for objectionable content (per-message keyword
  flagging routes to mod queue)
- **Report** button on every message and every user
- **Block** another user (mutual: blocked user can't see your
  listings, can't message, can't appear in your matches)
- **Mod response** within 24 hours of a report (existing mod role
  per DECISIONS.md #023 is reused)
- **Public contact** for users to reach Ben: ben@bobaplaybook.com

**Why:** the Apple-policy research agent's strongest finding was
that there's no successful "we host nothing, users transact in
PayPal" iOS app at scale. Pure introduction is hard to ship a
match-quality feature with — both users need a place to confirm
which card, what condition, what shipping. We host that
conversation, then push them out for the actual payment.

The §1.2 obligations are the cost of having ANY messaging
surface. They're not optional.

**How to apply:** the trade-thread view (§13.3) ships with all
four §1.2 mechanisms. The mod queue routes to the existing Mod
Panel (CollectionView's mod-edit overlay → admin panel hierarchy).

### 3.3 Apple-allowed external payment guidance

**Rule:** the trade thread surfaces a "**Pay outside the app**"
affordance that:

1. Generates a `paypal.me/{seller-username}/{amount}USD` deep link
   (PayPal's HTTPS Universal Link)
2. Shows clear, mandatory copy: *"Pay with PayPal Goods &
   Services — never Friends & Family. G&S protects you if the
   card doesn't arrive or doesn't match the listing. F&F has zero
   buyer protection and is a violation of PayPal's policy for
   purchases."*
3. Logs the timestamp + amount of the affordance use (for dispute
   evidence, even though we don't resolve disputes ourselves)
4. Does NOT include a confirm-payment button (that would imply
   we're tracking the transaction; we aren't)

**Why:** post-Epic v. Apple (April 2025 ruling, March 2026 appeal
rejected), US storefront apps can include external payment links
and CTAs without Apple commission. Apple's revised guideline
3.1.1(a) explicitly permits this in US storefront apps. Outside
the US, 3.1.3(e) (physical goods exemption) already covers us
because trading cards are physical.

**How to apply:** the affordance generates the link client-side;
no server roundtrip. The HTTPS Universal Link form is preferred
over `paypal://` custom scheme (works whether the PayPal app is
installed or not, no `LSApplicationQueriesSchemes` plist entry
needed, no `canOpenURL` gating).

### 3.4 Reference apps — what they do, what we don't

| App | Pattern | Why we don't copy it |
|---|---|---|
| **Mercari** | Holds funds, ships labels, escrow until buyer rates | Requires full-time T&S + sales-tax across 45 states + 1099-K |
| **eBay** | Managed Payments + Money Back Guarantee | Same; plus ~13.25% take rate that funds the operation |
| **OfferUp** | Optional in-app shipping; local cash-on-pickup default | Local pickup not viable for a national card community |
| **Whatnot** | Live-stream auctions + multi-day fund hold | Different product (live broadcasting); different team scale |
| **TCGPlayer** | Marketplace + dispute resolution | Solves a different problem (volume sellers) |
| **COMC** | Physical consignment — they hold the cards | We don't take physical custody of anything |
| **Reddit r/sportscards** | Pure community + flair-based rep | **THIS is closest to our model** — we add bobaId precision + structured matching + Discord-linked identity |
| **Discord trading servers** | Pure messaging + community vouches | We use Discord as the off-platform handoff destination |

**Pattern:** apps that take payment have explicit anti-off-platform
rules and full-time T&S teams. Apps that don't take payment
explicitly disclaim the transaction and lean on community trust.
**Nobody is in between** — there's no successful "we host the
chat but you pay each other off-platform" iOS app at scale,
because that's the worst-of-both-worlds zone for fraud liability.

We sit closest to **Reddit r/sportscards + Discord**, with
better matching (bobaId precision) and better identity (Discord
link verified at OAuth time).

### 3.5 Reviewer red flags to avoid

Top five rejection reasons for marketplace + UGC apps in 2026:

1. **Missing §1.2 controls** — no report / block / EULA / mod
   SLA. Mitigated by §3.2.
2. **Wrong IAP direction** — using IAP for physical goods, OR
   using non-IAP for digital. Mitigated by §3.1 (we never collect
   payment for ANYTHING in-app).
3. **Missing in-app account deletion** — already shipped per
   DECISIONS.md #039.
4. **Vague privacy policy** — must enumerate every data category
   collected and every third party. Mitigated by §11.
5. **Calls to action steering users to your website *for
   purchases* before the in-app option** — outside US, this is
   still 3.1.3-banned. Inside US, post-Epic, allowed. Our
   "**Pay outside the app**" affordance is post-conversation
   guidance for a physical-goods exchange, which is permitted in
   both jurisdictions under 3.1.3(e).

---

## 4. Legal posture

### 4.1 Business entity

**Rule:** Ben forms a single-member LLC in his home state before
the trading feature ships. Cost: ~$50–500 setup + $50–800/yr
depending on state.

**Why:** sole proprietorship leaves all personal assets exposed
to any judgment (eviction, foreclosure, garnishment). An LLC
creates a liability shield as long as it's properly maintained
(separate bank account, no commingling of funds, file the annual
report). For a trading feature where users may lose money via
scams that BOBA is then sued over, the LLC is non-negotiable.

**How to apply:** form the LLC, open a separate business bank
account, run all BOBA-related expenses (R2, Supabase, Cloudflare
Workers, Apple Developer Program) through that account. Don't
move BOBA funds through Ben's personal accounts.

### 4.2 State marketplace-facilitator law avoidance

**Rule:** BOBA does not become a marketplace facilitator in any
state, full stop. The trigger is "processing payment OR
contracting for delivery on behalf of the seller." Per §3.1, we
do neither.

**Why:** all 45 sales-tax states + DC have marketplace facilitator
laws as of 2024. Crossing the threshold means we collect and
remit sales tax across every jurisdiction we have economic nexus
in (CA $500K, NY $500K + 100 transactions, FL $100K, WA broadest
definition — facilitates includes payment processing OR
fulfillment). Solo dev cannot operate this.

**How to apply:** any proposal that even *looks* like we touch
funds (Stripe Connect, escrow, "BOBA Bucks") gets killed under
§3.1 + this rule.

### 4.3 Required ToS clauses

**Rule:** BOBA's Terms of Service includes the following 12
clauses, with no exceptions:

| # | Clause | Risk Mitigated |
|---|---|---|
| 1 | **Warranty disclaimer** — "AS IS, AS AVAILABLE" | Implied warranty claims |
| 2 | **Limitation of liability** — capped at $100 or fees paid in past 12 months (we charge no fees, so $100) | Money-damages exposure |
| 3 | **User-generated content shift** — users solely responsible for listings | §230 reinforcement |
| 4 | **Off-platform transactions** — "BOBA is not a party to any sale, trade, or exchange" | Disputes from off-platform completion |
| 5 | **Indemnification** — user holds BOBA harmless from third-party suits | User-caused liability |
| 6 | **Arbitration + class waiver** — AAA Consumer Arbitration Rules | Class-action exposure |
| 7 | **Tax disclaimer** — user is responsible for sales/income/use tax | Sales tax + 1099-K confusion |
| 8 | **Third-party service disclaimer** — PayPal/Venmo/Cash App are not BOBA's responsibility | Payment-processor failures |
| 9 | **Reporting + appeal mechanism** — DSA Art. 16/20 + Apple §1.2 compliance | Regulatory + reviewer requirement |
| 10 | **Account termination** — BOBA may suspend with or without cause | Discretion to remove bad actors |
| 11 | **Force majeure** — events beyond reasonable control | Infrastructure failures |
| 12 | **Governing law + venue** — Ben's state of residence; exclusive jurisdiction | Forum-shopping |

**Why:** these mirror the common pattern across eBay / Mercari /
Whatnot / OfferUp public ToS pages. The "we are a venue, not a
party to transactions" framing is what gives us §230 cover and
shifts user expectations.

**How to apply:** retained counsel reviews + customizes language
(~$1,000–3,000 one-time). Templates from Termly or Iubenda are a
starting point but not the final document. Ship clauses 1, 2, 3,
4, 5, 6, 7, 8, 10, 12 as non-negotiable; 9 and 11 are
recommended.

### 4.4 Insurance

**Rule:** Tech E&O + Cyber liability bundle, $1M / $2M limits.
Budget ~$2,500/yr.

**Why:** general liability does NOT cover software defects,
marketplace disputes, or data breaches. E&O covers professional
output (the marketplace itself). Cyber covers data-breach
response, regulatory fines (GDPR/CCPA), notification costs.
Carriers: Hiscox (most accessible to solo devs, online quote),
Embroker, Vouch, Coalition (cyber-focused).

**How to apply:** quote three carriers before launch. Renew
annually. The premium is the cheapest insurance Ben will ever
buy relative to the downside risk.

### 4.5 EU posture

**Rule:** BOBA Playbook geo-blocks EU traffic from the trading
feature on launch. The match-detection backend may run for EU
users, but the trade-thread + payment-guidance surfaces are
hidden until DSA compliance is justified.

**Why:** DSA went into full effect Feb 17, 2024. Article 30
(Traceability of traders) requires collecting trader name,
address, ID, and bank account before allowing them to offer
products. The micro/small-enterprise exemption under Art. 19
(BOBA qualifies — <50 employees, <€10M revenue) waives Art. 30
+ internal complaint-handling requirements, but the basic notice-
and-action mechanism still applies. Geo-blocking until we have EU
revenue justifying the compliance work is the cleanest posture.

**How to apply:** Cloudflare Worker geo-detect on the trading
endpoints; render an "Trading is not yet available in your
region" message instead of the trade-thread UI. Existing browse
+ collection + scan features continue working for EU users.

### 4.6 Section 230 posture — stay passive

**Rule:** BOBA never algorithmically recommends specific traders
to other users. All matching is **passive** — driven by user
search/filter and the catalog-derived overlap of bobaIds. Not by
any "this trader is recommended for you" signal.

**Why:** *Anderson v. TikTok* (3d Cir. 2024) narrowed §230
protection for first-party algorithmic recommendations. The trend
is: §230 still robust for hosting third-party content, weaker for
active curation. *Roommates.com* established that "material
contribution" to the unlawful content strips immunity. A trader-
recommendation feature ("we suggest you trade with @ben — he's
verified") is the canonical material-contribution risk.

**How to apply:** ranking matches by recency, by card-power
proximity, by "you both follow X hero" — fine. Ranking by trust
score IS fine because the score is user-generated rep + objective
signals (account age, completed trades). Generating *any* signal
that implies BOBA's endorsement of a specific trader is NOT fine.

---

## 5. Architecture decision

### 5.1 Pure facilitation, with thin in-app messaging

**Rule:** the v1 architecture is **pure facilitation with a thin
in-app messaging layer** that exists primarily to confirm intent
and surface the off-platform payment path.

**Anatomy:**
- **Match detection backend** — Supabase function runs nightly (or
  on demand), surfaces user-pair × bobaId triples where one user
  has the card in For Sale/Trade and another has it in Wanted/Grail
- **Match list view** — pull-to-refresh page showing my matches
  ("3 of your Wanted cards are listed by other users")
- **Trade-thread view** — single text-message thread per match,
  scoped to the buyer / seller / cards. Full §1.2 controls.
- **Pay-outside-the-app affordance** — generates PayPal G&S
  deep link with mandatory safety copy
- **Trade-complete confirmation** — both users tap "I shipped" /
  "I received" within a 7-day window; auto-confirms after 14 days.
  Zero financial flow; this is purely for reputation calculation.
- **Report + block** — per §3.2 + §12

**Why:** chosen because (per the four research agents) it is the
single architecture that:
- minimizes Apple-rejection risk (we never collect payment, so
  no IAP debate; full §1.2 controls handled)
- minimizes legal liability (no money flow → no marketplace-
  facilitator status → no 1099-K → no FinCEN money-transmitter
  analysis)
- maximizes engagement vs zero-touch alternatives (we do host the
  intent-confirming conversation)
- fits a single-developer ops budget (no dispute-resolution staff,
  no payment-network compliance)

**How to apply:** any proposal to add escrow, fund-holding, or
in-app payment buttons gets killed under §3.1 + this rule.

### 5.2 Explicit upgrade path (NOT v1 scope)

**Documented for completeness.** If BOBA grows past 1k confirmed
trades/month and the community demands escrow, the upgrade path
is **opt-in escrow via Escrow.com API as a separate "Verified
Trade" track** layered on the v1 architecture. Users who want
escrow pay the Escrow.com fee directly; BOBA never touches the
funds. Default trades stay on the v1 PayPal G&S guidance.

**Out of scope for v1.** Don't pre-build the upgrade path; the
research will be different in 12–24 months.

---

## 6. Payment integration

### 6.1 PayPal Goods & Services is the primary recommendation

**Rule:** the trade-thread's "Pay outside the app" affordance
generates a PayPal.Me URL with the amount pre-filled:
`https://paypal.me/{seller-username}/{amount}USD`. Mandatory
warning copy: *"Pay with Goods & Services — never Friends &
Family. G&S protects you if the card doesn't arrive."*

**Why:** PayPal G&S is the only sub-$100 payment method with real
buyer protection (180-day Item Not Received / Significantly Not
As Described disputes, full refund authority). Stripe Connect /
Escrow.com fees murder UX at our typical ticket size ($20–100).
Cash App and Zelle have effectively zero fraud protection and are
banned from our recommendation list.

**Limitation:** PayPal.Me URLs cannot force G&S — buyer toggles
on the PayPal side. Mandatory in-app copy + a "Why G&S, not F&F"
explainer dialog do the user-education work the URL parameter
can't.

**How to apply:** the affordance is a single button labeled
"Open PayPal" with a sub-label "Goods & Services only." Tapping
opens PayPal app on iOS via Universal Link. Long-press copies
the PayPal handle to clipboard for paste-into-other-app fallback.

### 6.2 Venmo as secondary

**Rule:** if the seller prefers Venmo, surface a Venmo deep link:
`venmo://paycharge?txn=pay&recipients={user}&amount={amt}&note={memo}`
(works in 2026, verified pattern). Same mandatory copy: "Tag as
Purchase for buyer protection — never as personal payment."

**Why:** Venmo shares PayPal's ownership and the same protection
split. Worth offering for users who prefer it; not a required
payment method.

**How to apply:** seller's profile carries up to two preferred
payment handles. Trade thread shows both as options. Buyer picks
the one they have an account with.

### 6.3 What we explicitly do NOT recommend

| Method | Why not |
|---|---|
| **PayPal Friends & Family** | Zero buyer protection. PayPal policy violation for purchases of goods. Banned from in-app warnings (we actively warn against it). |
| **Cash App personal payments** | Same as F&F — no protection. CFPB has been pursuing Cash App for fraud rates. |
| **Zelle** | Bank-to-bank, no fraud protection (treated as authorized push payment). Never recommend for stranger-to-stranger. |
| **Cryptocurrency** | Not a 2026-2027 surface for BOBA's audience. Adds reporting + regulatory exposure. |
| **Cashier's check / money order** | Fraud-prone (counterfeit cashier's checks are the most common scam vector for >$500 transactions). |

### 6.4 eBay / Whatnot referral when seller has a listing there

**Rule:** if a match'd seller has the same card already listed on
eBay or Whatnot (detected via the existing pricing pipeline per
DECISIONS.md #013), the trade-thread shows a "**View on eBay**" /
"**View on Whatnot**" link. This is the safest path for higher-
value transactions because eBay's Money Back Guarantee + Whatnot's
escrow are stronger than our PayPal G&S recommendation.

**Why:** we already query eBay sold + active listings for every
card. Surfacing a seller's existing eBay listing leverages
infrastructure we already trust.

**How to apply:** detection runs when the trade thread opens; if
matched, show the link as the primary CTA above the PayPal
affordance.

---

## 7. Identity + reputation

### 7.1 Required identity signals before listing

**Rule:** to list a card For Sale or For Trade, a user must have:

1. Verified email (already shipped — Supabase auth)
2. Phone verification (NEW — required before first listing)
3. **Discord identity link OR completed-trade history** (for
   trades >$25)

Trades ≤$25 only require email + phone. Trades >$25 require
either Discord link (existing infrastructure per DECISIONS.md #023)
OR ≥3 successfully completed lower-value trades.

**Why:** phone verification cuts burner accounts ~70% (Twilio
data). Discord link adds a portable identity signal that's hard
to fake at scale. Trade-history threshold gates higher-value
listings to users with reputation to lose.

**How to apply:** Twilio Verify API (~$0.05/verification) for
phone. Discord link uses existing OAuth. Trade-count tracking
already exists in match-confirmation flow (§5.1).

### 7.2 Reputation scoring

**Rule:** every confirmed completed trade adds +1 to the user's
reputation score. Disputes (reported by either party) freeze the
score until resolved by a moderator. The score is visible on every
user's profile + on every trade-thread view.

The score gates feature access:
- 0 trades → max listing $50, max 1 active listing
- 1–4 trades → max listing $100, max 3 active listings
- 5+ trades → max listing $500, max 10 active listings
- 10+ trades, 0 disputes → "Trusted Trader" badge + no listing cap

**Why:** reputation is hard to acquire (1 point per real trade,
not gameable), easy to lose (dispute freezes everything). Visible
everywhere the user appears. Same model as eBay feedback +
Mercari rating + Discord BST vouches.

**How to apply:** stored on `user_profiles.trade_count` and
`user_profiles.trade_disputes_open`. Score recomputes on each
trade-confirmation event. **Per §4.6 (passive only), the score is
displayed but BOBA never algorithmically promotes higher-rep
traders to other users.**

### 7.3 No KYC for v1

**Rule:** v1 does not integrate KYC providers (Persona, Stripe
Identity, Veriff). Government-ID verification is deferred until
v2+ when transaction values justify the friction.

**Why:** KYC adds 30–50% friction at the verification step
(Stripe Identity industry data). For sub-$100 transactions, the
fraud-prevention ROI doesn't justify the conversion loss. Phone
+ Discord + reputation cover ~95% of the threat model.

**How to apply:** if a future v2 raises the trade-value cap to
$500+, gate >$500 listings behind Stripe Identity (~$1.50/check).
Don't pre-build the integration.

---

## 8. In-app messaging policy

### 8.1 Messages are archived and visible to dispute participants

**Rule:** every in-app trade message is stored permanently
(server-side, in a Supabase `trade_messages` table). Users CANNOT
delete messages. The thread is visible to both parties always +
to moderators when a report is filed. Messages are NOT
end-to-end encrypted — the storage rationale is dispute evidence.

**Why:** archived messaging is the single biggest off-platform-
pivot deterrent (eBay/Mercari pattern). Users who know "this
conversation is logged" are less likely to attempt scams that
rely on later denying the conversation. Discord trade servers
that have no archive resolve every dispute as "he-said/she-said,"
which doesn't scale.

**How to apply:** every trade thread shows a small visible badge:
"Logged for dispute resolution." ToS clause #3 (UGC shift) +
#9 (reporting mechanism) cover the data-collection disclosure.

### 8.2 Off-platform pivot detection

**Rule:** when a chat message contains keywords associated with
common scam patterns, the app shows an interstitial warning to
both parties (sender on send, recipient on display). Keywords:
`venmo` / `cashapp` / `cash app` / `zelle` / `friends and family` /
`f&f` / `paypal f&f` / phone numbers / email addresses / "off
platform" / "outside the app".

The warning copy: *"This message mentions a payment method or
contact channel outside BOBA. **Friends & Family payments and
Zelle have NO buyer protection — you cannot get your money back
if scammed.** If you must trade off-platform, use PayPal Goods &
Services or insist on tracked + insured shipping."*

**Why:** ~40% of P2P scams in trading-card communities involve an
off-platform pivot to a payment method without buyer protection.
Detecting + warning at the moment of the pivot (not in
onboarding) is the most effective intervention pattern (PayPal's
own F&F warning UX validates this).

**How to apply:** keyword list lives in `js/chat-warnings.json` +
mirrored in iOS bundle. Warning is informational, not blocking —
users CAN proceed (they will anyway). The warning shifts liability
to the user: "we warned you, you proceeded."

### 8.3 No address / phone exchange in chat

**Rule:** the trade-thread does NOT prompt users to share shipping
address or phone in chat. Address sharing is gated behind a
"Confirm Trade" flow where both users tap "I'm ready to ship" —
at that point, BOTH users see the OTHER user's verified shipping
address and (optional) phone, surfaced from their profiles.

**Why:** unsolicited address requests in chat are a scam pattern
(seller asks for address pre-payment, then ghosts). Gating
address exchange behind mutual confirmation flips the protocol:
neither user reveals address until both have committed.

**How to apply:** the "Confirm Trade" button is a dialog with the
mutual-commit copy: "Tapping Confirm reveals your shipping
address to {other user}. Only do this when you're ready to ship
(seller) or pay (buyer)."

---

## 9. Fraud-prevention checklist (v1 ship list)

The v1 trading feature MUST ship with all of the following.
Ranked by ROI per dev hour:

| # | Feature | Effort | Reasoning |
|---|---|---|---|
| 1 | **Phone verification before listing** | ~3 days | Cuts burner accounts ~70% |
| 2 | **Discord link required for trades >$25** | ~1 day | Reuses existing OAuth infrastructure |
| 3 | **Off-platform keyword warnings in chat** (§8.2) | ~2 days | Deters most common scam pattern |
| 4 | **Account-age + trade-count gates** (§7.2) | ~2 days | New accounts can't list >$50 |
| 5 | **Required "today's date" photo for trades >$100** | ~2 days | Defeats photo theft scams |
| 6 | **FP card-ID verification of listing photo** | ~3 days | BOBA-unique advantage — reuses Scan FP infrastructure to verify photo matches listed bobaId |
| 7 | **Trade reputation score** (§7.2) | ~5 days | Visible everywhere; gates feature access |
| 8 | **In-app message archive + visible "logged" badge** (§8.1) | ~2 days | Single biggest scam deterrent |
| 9 | **24-hour trade-confirmation window** | ~3 days | Auto-confirms after 14 days; tracks "shipped" / "received" state |
| 10 | **Block + Report user** routing to mod queue (§12) | ~2 days | §1.2 requirement |
| 11 | **Dispute flow** — 7-day window, evidence upload, mod resolution (§10) | ~7 days | §1.2 requirement |
| 12 | **F&F warning interstitial** (§8.2) | ~1 day | Already covered above; called out for tracking |
| 13 | **Velocity limits** — max 5 listings/day for accounts <30 days | ~1 day | Anti-spam |
| 14 | **"Trusted Trader" badge** at 10 trades + 0 disputes | ~1 day | Social signal; per §4.6 not used for algorithmic recommendation |
| 15 | **PSA serial lookup for graded card listings** | ~2 days | Defeats grading-misrepresentation scams |

Total v1 effort: ~37 dev days. Realistic ship: 6-8 weeks of
focused work for a single dev.

---

## 10. Dispute resolution flow

### 10.1 We do not resolve transaction disputes — PayPal does

**Rule:** when a user reports "buyer didn't pay" / "seller didn't
ship" / "card not as described," BOBA does NOT adjudicate.
Instead:

1. The report routes to the mod queue (§12)
2. The other party is notified via the trade thread
3. **The reporter is directed to file a PayPal Goods & Services
   dispute** at https://www.paypal.com/disputes
4. BOBA's role is purely evidentiary: the chat archive (§8.1) is
   available to both parties as PDF export

**Why:** disputes over money are PayPal's job (their G&S
guarantee, their refund authority). Disputes over BOBA-internal
behavior (harassment, fraudulent listings, off-platform pivots)
are mod's job. The split protects Ben from being sued as the
adjudicator of any cash transaction.

**How to apply:** the in-app dispute filing UI has TWO paths:

- "Report this user / listing" → mod queue (BOBA's domain)
- "Open a PayPal dispute" → external link to PayPal disputes page
  (PayPal's domain)

The chat-archive PDF export is a single button on the trade
thread.

### 10.2 BOBA-side outcomes

**Rule:** mod-side resolutions can result in:
- User warning (logged on profile, not visible to others)
- Listing removal
- Temporary listing suspension (24h–30d)
- Permanent ban
- Reputation score adjustment (in extreme cases, reset to 0)

Decisions are recorded in a `mod_actions` Supabase table with
moderator name + reason. Users see a notification on the action.

**Why:** mods need real consequences to make reporting worthwhile.
The action log creates audit trail + appeals basis (§10.3).

### 10.3 Appeals

**Rule:** every mod action can be appealed once by emailing
ben@bobaplaybook.com. Ben (as admin) reviews + decides. Ben's
decision is final.

**Why:** DSA Art. 16/20 + Apple §1.2 require an appeal mechanism.
Email-based appeal is sufficient at our scale; doesn't require
a dedicated UI.

---

## 11. Required user-facing disclosures

The following banners / modals / acceptance gates MUST be present
before a user can complete their first trade action:

| When | What |
|---|---|
| **First "Browse Matches" tap** | One-time walkthrough (per DESIGN.md §6.10): "BOBA never holds your money" + "Pay with PayPal G&S only" + "Verify the card before paying" |
| **First "Make a Listing" tap** | Phone-verify gate + ToS re-acceptance with the trading-specific clauses highlighted |
| **First chat message in any thread** | Banner at top of chat: "Logged for dispute resolution" |
| **Chat message containing F&F / Cash App / Zelle keywords** | Interstitial warning (§8.2) |
| **"Confirm Trade" dialog** | "Tapping Confirm reveals your shipping address to {other user}" (§8.3) |
| **"Pay outside the app" tap** | "Open PayPal — Goods & Services only" with the explainer dialog one-tap-away |
| **Match notification** | Push body includes "Tap to match — BOBA never holds your money. Use PayPal G&S." |
| **Profile-level toggle** | "Enable Trading" (off by default for new users; opting in shows the full disclosure stack) |

**Why:** every disclosure is a liability shift. The user clicked
through the warning; they're on notice; ToS clauses 1+3+8
allocate responsibility.

**How to apply:** copy is reviewed by counsel before launch.
Disclosures use the canonical `BOBAHintBanner` (iOS) /
`.error-banner` (web) primitives — no one-off styling.

---

## 12. Reporting + moderation

### 12.1 Report mechanism

**Rule:** every user, every listing, and every chat message has a
"Report" affordance that opens a sheet with:
- Reason categories (Fraud / Harassment / Off-platform pivot /
  Inappropriate content / Other)
- Free-text detail (optional)
- "Submit"

Reports route to the existing mod queue (per DECISIONS.md #023).

**Why:** Apple §1.2 requires this. Reuse of existing mod
infrastructure is cheaper than a parallel queue.

**How to apply:** add `trade_reports` table on Supabase
(reporter_id, target_type, target_id, reason, detail, status,
mod_id, mod_action, resolved_at). The Mod Panel admin view
extends to show pending trade reports alongside card corrections.

### 12.2 Block mechanism

**Rule:** users can block other users. A blocked user:
- Cannot see the blocker's listings or profile
- Cannot initiate a match with the blocker
- Cannot send messages to the blocker
- Does not appear in the blocker's match list
- Block is bilateral: the blocker also can't see the blocked user

Blocks are silent (the blocked user is not notified).

**Why:** Apple §1.2 requirement. Bilateral blocking matches
industry pattern (Mercari, eBay, Whatnot).

**How to apply:** `user_blocks` table (blocker_id, blocked_id,
created_at). Match queries filter both directions.

### 12.3 Mod SLA

**Rule:** moderators respond to reports within 24 hours. If no
moderator is available (e.g., Ben is on vacation), the report
queue surfaces a "delayed response" notice to the reporter.

**Why:** §1.2 industry standard (BuddyBoss, Armia documentation).

**How to apply:** mod queue UI shows "open for X hours" badge.
Reports >24h trigger an admin alert email to ben@bobaplaybook.com.

---

## 13. UI / IA recipes

### 13.1 Match notification

**iOS:** push notification (APNs) + in-app banner per
DESIGN.md §6.10 hints. Body: "@{seller} has {N} of your Wanted
cards listed. Tap to message."

**Web:** in-app banner only (no web push per WEB-DESIGN.md §17
out-of-scope). Updates the Match tab badge count.

**Both:** mandatory disclosure copy in the notification body —
"BOBA never holds your money. Use PayPal G&S."

### 13.2 Match list view

A new top-level view (iOS tab, web sidebar item) labeled "Matches"
or "Trades" — final naming TBD. Rows:

```
[avatar] @seller-username     [3 cards, $45 total]   [PUBLIC]
         "I have 3 of your Wanted cards"
         [thumbnail row of the 3 cards]
         Last active: 2h ago · 12 completed trades · ★★★★☆
```

Tap a row → opens the trade-thread view (§13.3).

Empty state: "No matches yet. Add cards to your Wanted list to
start matching with sellers."

### 13.3 Trade-thread view

The core of the feature. Anatomy (top to bottom):

```
[ < Back ]                  [@seller — 12 trades — ★★★★☆]   [⋯]
                            [PUBLIC profile · Discord linked]

[Logged for dispute resolution badge — dismissible 1x per thread]

[Card context strip — thumbnail row of the matched cards
 with each card's bobaId + listed price]

[Chat history — text bubbles, timestamp + read receipt]

[Off-platform warning interstitial when triggered (§8.2)]

[Compose row: [text input] [send]]

[Action toolbar (always visible at bottom):
 [Pay outside the app] [Confirm Trade] [Report] [Block]]
```

Per WEB-DESIGN.md §6.5 cross-cutting capabilities: Profile, Share,
and Sign-In affordances live in the existing toolbar Menu (⋯),
not in the trade-thread chrome.

### 13.4 "Pay outside the app" sheet

When tapped:

```
[Avatar] @seller wants $45.00 USD for these 3 cards

  [Card thumb 1] [Card thumb 2] [Card thumb 3]

⚠️ Pay with Goods & Services only.
   F&F payments have no buyer protection.

[Open PayPal] (primary, opens paypal.me deep link)
[Open Venmo]  (if seller's profile lists Venmo)

[Why G&S, not F&F?] (link to in-app explainer)

[Cancel]
```

After tap (the deep link), no in-app confirmation is required.
The trade thread shows a system message: "{user} initiated PayPal
payment at {time}." This is purely for dispute-evidence.

### 13.5 "Confirm Trade" dialog

When the user taps "Confirm Trade" (after seller has shipped or
buyer has paid):

```
Confirm Trade

Tapping Confirm reveals your shipping address to @seller.
Only do this when you're ready to ship (seller) or pay (buyer).

[Cancel] [Confirm — share my address]
```

Both users must confirm before either's address is revealed.
After both confirm, addresses are shown in the chat as a system
message + on the action toolbar.

After 14 days from the second confirm, the trade auto-completes
and increments both users' reputation scores.

### 13.6 Report / Block flows

Standard sheet patterns per DESIGN.md §6.7 + WEB-DESIGN.md §10.
Block is one-tap (with confirm). Report opens the categorization
sheet (§12.1).

---

## 14. Roadmap — v1 ship order

Each item ships independently and is testable in isolation.

| Phase | Items | Duration |
|---|---|---|
| **Phase 0** | LLC formation, insurance quotes, ToS draft, retained counsel review | 4-6 weeks (parallel to dev) |
| **Phase 1** | Match-detection backend + match list view (read-only) | 1 week |
| **Phase 2** | Trade-thread view + in-app messaging + §1.2 controls (report, block, mod queue extension) | 2 weeks |
| **Phase 3** | Identity gates (phone verify, Discord-link enforcement) + reputation scoring | 1 week |
| **Phase 4** | Off-platform pivot warnings + payment-link affordance + disclosure stack | 1 week |
| **Phase 5** | Confirm-Trade flow + address exchange + reputation increment | 1 week |
| **Phase 6** | Dispute flow + PSA lookup + photo verification (FP card-ID) | 2 weeks |
| **Phase 7** | Push notifications (APNs server-side dispatcher — the original match-alerts pipeline from DECISIONS.md #039) | 2 weeks |

Total: ~10 weeks of dev + 4-6 weeks of legal in parallel. **Don't
ship Phase 1-7 without Phase 0 done first.** The legal posture
(LLC, insurance, ToS) is what makes the dev work shippable.

---

## 15. Out of scope (intentionally)

| Feature | Why out of scope |
|---|---|
| **Auctions** | Whatnot's territory; live-broadcast UX is a separate product |
| **Digital-only trades** | No card art changes hands in BoBA; not a thing |
| **Cross-border trading** | US-only for v1; international shipping fraud + customs adds complexity |
| **Card grading / authentication** | PSA / BGS territory; we surface PSA serial lookup but don't grade |
| **Insurance / shipping label integration** | USPS / FedEx APIs — too much surface for v1 |
| **Crypto / NFT-style ownership tokens** | Not 2026-2027 surface for trading cards |
| **In-app payment processing** | §3.1 hard rule — never |
| **Escrow** | §5.2 explicit upgrade path, not v1 |
| **Algorithmic trader recommendations** | §4.6 §230 risk — never |
| **EU users** | §4.5 geo-blocked until DSA compliance is justified |
| **Under-18 users** | COPPA-grade controls not in scope; gate at 18+ via ToS checkbox |

---

## 16. References

**Apple App Store policy:**
- [App Review Guidelines (live)](https://developer.apple.com/app-store/review/guidelines/) — §§1.2, 3.1.1, 3.1.3(a-g), 3.1.5, 5.1.1, 5.1.2, 5.6, 5.6.4
- [Apple Developer News Feb 2026 — UGC clarifications](https://developer.apple.com/news/?id=d75yllv4)
- [StoreKit External Purchase entitlement docs](https://developer.apple.com/documentation/storekit/external_purchase)
- [TechCrunch Apr 29 2026 — Apple loses bid to pause Epic ruling](https://techcrunch.com/2026/04/29/apple-epic-games-app-store-fees-pause-changes-supreme-court/)
- [BuddyBoss — Resolving Guideline 1.2 UGC](https://buddyboss.com/docs/app-store-guideline-1-2-safety-user-generated-content/)
- [RevenueCat — Ultimate guide to App Store rejections](https://www.revenuecat.com/blog/growth/the-ultimate-guide-to-app-store-rejections/)
- [Forge ASC — Top 10 App Store Rejection Reasons 2026](https://forgeasc.com/blog/app-store-rejection-reasons)

**Legal — US:**
- 47 U.S.C. § 230 (Cornell LII)
- *Fair Housing Council v. Roommates.com*, 521 F.3d 1157 (9th Cir. 2008)
- *Lemmon v. Snap, Inc.*, 995 F.3d 1085 (9th Cir. 2021)
- *Gonzalez v. Google LLC*, 598 U.S. 617 (2023)
- *Anderson v. TikTok, Inc.*, 116 F.4th 180 (3d Cir. 2024)
- *Heckman v. Live Nation Entertainment*, 120 F.4th 670 (9th Cir. 2024)
- IRS Notice 2024-85 (1099-K threshold delay)
- [Avalara state marketplace facilitator tracker](https://www.avalara.com/us/en/learn/whitepapers/marketplace-facilitator-laws-explained.html)
- State statutes: Cal. Rev. & Tax §6041; NY Tax Law §1101(e); Tex. Tax Code §151.0242; Fla. Stat. §212.05965; RCW 82.08.0531

**Legal — EU:**
- [EU Regulation 2022/2065 (Digital Services Act)](https://digital-strategy.ec.europa.eu/en/policies/dsa) — Art. 19, Art. 30

**Reference platform ToS:**
- [eBay User Agreement](https://www.ebay.com/help/policies/member-behavior-policies/user-agreement)
- [Mercari Terms of Service](https://www.mercari.com/terms/)
- [Whatnot Terms](https://www.whatnot.com/terms)
- [OfferUp Terms](https://offerup.com/terms)

**Payment integration:**
- [PayPal Developer docs](https://developer.paypal.com/) + User Agreement §11 (Purchase Protection)
- [Venmo Help Center — Purchase Protection](https://help.venmo.com/)
- [Stripe Connect docs](https://stripe.com/docs/connect)
- [Escrow.com API docs](https://www.escrow.com/api)

**Fraud-prevention sources:**
- eBay Trust & Safety reports (2022-2024)
- Whatnot 2024 Community Standards report
- r/sportscards moderator team writeups (publicly archived)
- Stripe Identity public benchmarks

**Insurance:**
- [Hiscox Tech E&O](https://www.hiscox.com/small-business-insurance/technology)
- [Embroker](https://www.embroker.com/)
- [Vouch](https://www.vouch.us/)
- [Coalition](https://www.coalitioninc.com/)

---

## 17. Open questions resolved

The following questions were open in the research-plan version of
this doc and are now answered:

| Question | Answer | Rationale |
|---|---|---|
| LLC formation? | **Yes, single-member LLC, before launch** | Non-negotiable per §4.1 |
| Initial trade-value cap? | **$50 default, raised by reputation tier per §7.2** | Caps fraud blast radius |
| Discord-link required? | **Yes, for trades >$25** | Reputation signal per §7.1 |
| Both parties' phone verification? | **Yes, before listing or paying** | Per §7.1 |
| Charge a fee per trade? | **No, never** | Touching money triggers marketplace-facilitator status (§3.1, §4.2) |
| EU users? | **Geo-blocked until DSA compliance justified** | Per §4.5 |
| Under-18 users? | **Blocked via ToS 18+ gate** | Per §15 |
| Web Push notifications? | **No** | Per WEB-DESIGN.md §17 — iOS APNs only |
| Algorithmic trader recommendations? | **No, ever** | §230 material-contribution risk per §4.6 |

Net new questions for Ben before Phase 0:

- **State of LLC formation?** Home state (cheapest + most
  straightforward) vs Wyoming/Delaware (more privacy/asset-
  protection but adds foreign-qualification cost in home state)
- **Counsel selection?** Need an attorney who's reviewed
  marketplace ToS for similar-scale apps; budget ~$1,000–3,000
  for ToS customization + ~$500–1,500 for entity formation review
- **Insurance carrier preference?** Hiscox is most common for
  solo devs; Embroker is more startup-focused. Quote both.
- **Phone-verify provider?** Twilio Verify is industry standard
  (~$0.05/check); alternatives include Vonage, MessageBird
- **Trading feature naming?** "Matches" / "Trades" / "Connect" —
  all surface differently in onboarding copy

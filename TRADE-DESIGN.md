# BOBA Playbook — Trading & P2P Design (Research Plan)

> **Status: research plan, not a finished design doc.** This document
> captures the questions to answer + the design decisions that need
> to be made before BOBA Playbook can ship a peer-to-peer trading
> feature on iOS or web. When a section here is researched and
> ratified, replace its TODO block with the binding rule, the same
> way DESIGN.md is structured (rule first, "Why" + "How to apply"
> lines below).
>
> Companion to [`DESIGN.md`](./DESIGN.md) (binding iOS doc),
> [`WEB-DESIGN.md`](./WEB-DESIGN.md) (binding web doc),
> [`DECISIONS.md`](./DECISIONS.md) (architecture log), and
> [`CLAUDE.md`](./CLAUDE.md) (project context).
>
> When all sections are ratified, drop §0.1 + the front-matter
> status block. TRADE-DESIGN.md is then binding.

---

## 0. Why this document exists

The match-alerts pipeline (DECISIONS.md #039) shows users when
someone else's For Sale/Trade overlaps their Wanted/Grail. That
match is the easy half. **The hard half is what happens after the
notification fires** — when two people decide to actually exchange
cards and money.

This is simultaneously:

- **The biggest product opportunity in the app.** Connecting
  collectors to each other based on actual want/have data is
  uniquely valuable. No one else has the catalog + the bobaId
  precision to do this for BoBA cards.

- **The biggest fraud / liability surface.** P2P trading is where
  scammers go. Section-230-style protections matter; Apple's policy
  on payment facilitation matters; sales-tax and 1099-K
  requirements matter; and Ben (the solo developer) carries
  whatever liability the structure of the feature implies.

The job of this document is to answer:

1. **What architecture lets us add value without taking on financial
   risk?** Pure introduction? In-app messaging + off-platform
   payment? Embedded escrow? Marketplace classification?
2. **What does Apple let us do?** Trading cards are physical goods
   so IAP rules differ — but the boundaries are non-obvious.
3. **What's our legal posture?** What ToS clauses are
   non-negotiable? Do we need an LLC? Insurance? Sales-tax
   collection?
4. **How do we deter scammers?** Reputation, identity verification,
   in-app messaging archive, off-platform-pivot detection, dispute
   resolution.
5. **What's the user-facing experience that makes the safety
   visible?** Without users believing we have their back, no one
   uses the feature regardless of how safe it actually is.

Per the project's "Why We Build" mantra (CLAUDE.md): every feature
serves human learning and growth. A trading feature that gets
people scammed serves the opposite. Either we ship a feature that
demonstrably protects users, or we don't ship one at all.

## 0.1 How to use this plan

1. **Pick a section** that's currently a TODO block.
2. **Synthesize from the four research agent outputs** dispatched
   2026-05-05 (Apple policy, US/EU legal liability, payment
   integrations, fraud-prevention patterns).
3. **Draft the binding rule** in the same style as DESIGN.md (rule
   first, then `**Why:**` + `**How to apply:**` lines).
4. **Run it past Ben.** If approved, replace the TODO block with the
   ratified rule.

When all sections are ratified, drop this section + the front-matter
status block. TRADE-DESIGN.md is then binding.

---

## 1. Constraints (input to every other section)

Locked from the project's existing posture:

- **Solo developer** — Ben Wilkoff, no team, no operational support.
  Anything that requires KYC review, dispute resolution staff, or
  daily ops is out of scope.
- **Free app, small audience** — the BoBA community is in the low
  thousands. We can't justify Stripe Connect compliance overhead vs
  expected transaction volume. The feature has to work on a $0
  ops budget.
- **iOS + web parity** — DECISIONS.md #005 is binding. Whatever
  ships on iOS must ship on web (or be explicitly carved out per
  WEB-DESIGN.md §17).
- **Discord-first community** — DECISIONS.md #023 + the existing
  Discord identity link mean many users already have a verified
  Discord identity we can leverage.
- **Card identity is unambiguous** — every card has a `bobaId`
  (CLAUDE.md project mantra). When matching For Sale ↔ Wanted, we
  match on `bobaId`, not loose card name. This kills "wrong
  variation shipped" scams at the catalog level.
- **No card images in Git** — DECISIONS.md #011. User-uploaded
  verification photos go to R2 (per the avatar precedent in
  DECISIONS.md #040), not to the codebase.

**Open: do we incorporate (LLC) before shipping this?** Today Ben
operates as an individual sole proprietor. A trading feature that
even merely facilitates cash exchange may be the right time to
establish an LLC for liability separation. The legal-liability
research agent is asked to weigh in.

---

## 2. Sections this doc should contain (TOC)

```
0. Why this document exists
1. Constraints
2. Apple App Store policy compliance — what we CAN do, what we CAN'T
3. Legal posture — entity, ToS, insurance, jurisdiction
4. Architecture — pure facilitation vs in-app messaging vs escrow
5. Payment integration — PayPal, Venmo, Cash App, Stripe Connect, Escrow.com
6. Identity + reputation — Discord link, phone verify, trust score, KYC
7. In-app messaging policy — archived? deletable? off-platform pivot detection?
8. Fraud prevention checklist — features required for v1
9. Dispute resolution flow — what happens when something goes wrong
10. Required user-facing disclosures — warnings, ToS acceptance gates
11. Reporting + moderation — block, report, escalation
12. UI / IA recipes — match notification → chat → trade complete
13. Roadmap — order of refactors needed to ship v1
14. Out of scope (intentionally) — auctions, digital trades, etc.
15. References
```

---

## 3. Apple App Store policy compliance

> TODO 3.0 — synthesize from the Apple-policy research agent.
>
> Need: definitive rule on whether/when we can use third-party
> payment processors for physical-goods P2P trading. Whether
> in-app messaging that surfaces a PayPal/Venmo handle counts as
> "facilitating an external purchase mechanism" per 3.1.3.
>
> Also: list of specific reviewer red flags + how 5-7 reference
> apps (Mercari, eBay, OfferUp, Whatnot, TCGPlayer, COMC, Reddit)
> handle the same question.

---

## 4. Legal posture

> TODO 4.0 — synthesize from the legal-liability research agent.
>
> Need:
> - Recommended entity (sole proprietor, LLC, S-corp) for
>   minimum-viable trading feature.
> - Required ToS clauses (8-12 specific clauses with sample
>   language patterns).
> - Insurance recommendation with annual cost estimate.
> - State-by-state marketplace facilitator law analysis — at what
>   transaction volume / structure do we trigger sales tax
>   collection requirements.
> - DSA compliance for EU users.
> - Section 230 protection: when does our facilitation become
>   "material contribution" that strips it.

---

## 5. Architecture decision

> TODO 5.0 — pick ONE of these architectures and document the
> rationale. Driven by §3 (what Apple lets us do) and §4 (what
> minimizes Ben's legal exposure).

**Candidate A — Pure facilitation.** We match users by bobaId
overlap, surface their preferred contact method (Discord username,
email), and step out. Zero financial flow through us. Lowest
liability, lowest engagement.

**Candidate B — In-app messaging + off-platform payment.** We host
the conversation thread. Buyer + seller agree on terms in chat.
Buyer sends payment via PayPal G&S link generated in the chat or
typed by hand. Seller ships. Chat archive serves as evidence in
disputes (which we don't resolve, but the parties or PayPal can
reference). Medium engagement, medium liability.

**Candidate C — Embedded escrow.** We integrate Stripe Connect or
Escrow.com. Buyer pays in-app, we hold funds, seller ships, buyer
confirms, funds release. High engagement, high liability + ops
burden + tax complexity.

**Candidate D — Marketplace classification.** We register as a
marketplace facilitator, handle 1099-K reporting, sales-tax
collection per state, etc. Maximum engagement, maximum liability.
Out of scope for a solo dev.

> Recommendation slot — pending research synthesis.

---

## 6. Payment integration

> TODO 6.0 — synthesize from the payment-integration research agent.
>
> Need:
> - Final list of payment methods we surface (PayPal G&S only?
>   PayPal G&S + Venmo Business? Cash App Pay?)
> - Deep-link patterns (paypal.me/{user}/{amt}, venmo://...)
>   verified working in 2026.
> - "Friends & Family" warning — when chat detects F&F language,
>   pop a warning explaining the buyer-protection loss.
> - What we explicitly DON'T support (Zelle? Crypto? Cashier's
>   check?) and why.

---

## 7. Identity + reputation

> TODO 7.0 — synthesize from the fraud-prevention research agent.
>
> Need:
> - Required identity signals before a user can list (phone? email?
>   Discord link?)
> - Reputation scoring model (eBay-style positive/neutral/negative
>   review per completed trade?)
> - How reputation gates feature access (e.g., new accounts can't
>   list >$X cards)
> - KYC trigger — at what transaction value do we require
>   government-ID verification (Persona / Stripe Identity)?
>   Probably never for v1, but document the threshold for v2.

---

## 8. In-app messaging policy

> TODO 8.0 — research-driven decision.
>
> Need:
> - Are messages stored permanently for dispute evidence, or
>   deletable by either party?
> - Off-platform pivot detection — when chat mentions
>   PayPal F&F / Cash App / Zelle, do we warn? Block? Just log?
> - How we handle requests for personal info (address for shipping
>   is required; phone is optional; etc.)
> - Cross-user blocking (block this user from messaging me again)

---

## 9. Fraud prevention checklist

> TODO 9.0 — concrete v1 feature list, ranked by ROI per dev hour.
>
> Synthesize from the fraud-prevention research agent + filter
> against §1 constraints (solo dev, low ops budget, free app).
>
> Expected items:
> - Required Discord link OR phone verify before listing
> - Block list / report user
> - Off-platform pivot warning (PayPal F&F, Cash App detection)
> - Velocity limits (max trades / day for new accounts)
> - 24-hour trade-confirmation window
> - "Show this card with today's date" for trades > $X
> - Card-recognition AI verification (we already have FP-based
>   card-ID via Scan; could be repurposed for trade verification)
> - Trade history visibility on profile
> - Account-age threshold for high-value listings
> - Mod-flag review queue

---

## 10. Dispute resolution flow

> TODO 10.0 — design the user-facing flow for "something went wrong."
>
> Key decision: do we (Ben) actively resolve disputes, or do we
> point users to the relevant payment processor (PayPal G&S
> dispute) and stay out?
>
> Per §1 (solo dev), the answer is almost certainly "we point
> users to PayPal G&S" — but document explicitly so the next
> session doesn't propose otherwise.

---

## 11. Required user-facing disclosures

> TODO 11.0 — list every banner, modal, ToS-acceptance gate
> required before a user can trade for the first time.
>
> Must include:
> - "BOBA Playbook does not handle your money. Use PayPal Goods &
>   Services for buyer protection."
> - "BOBA Playbook does not authenticate cards. Verify the card
>   matches the listing before completing payment."
> - "BOBA Playbook does not resolve disputes. If something goes
>   wrong, contact your payment processor."
> - "Off-platform messaging removes our ability to assist."

---

## 12. Reporting + moderation

> TODO 12.0 — abuse-reporting flow + moderator queue.
>
> Reuse the existing mod role (DECISIONS.md #023) — moderators see
> reported users / messages / listings in the same Mod Panel
> they currently use for card corrections.

---

## 13. UI / IA recipes

> TODO 13.0 — per-surface design recipes (DESIGN.md §8 style).
>
> Surfaces:
> - Match notification (push on iOS, in-app banner on web)
> - Match list view ("3 of your Wanted cards are listed by other
>   users")
> - Trade-thread view (chat + listing context)
> - Send-payment shim (PayPal deep link with verification banner)
> - Trade-complete confirmation
> - Report-user / block flow

---

## 14. Roadmap

> TODO 14.0 — once §3-§13 are ratified, generate the v1 ship-order.
>
> Likely first ship:
> 1. Match-detection backend (no notifications yet)
> 2. Match-list view (pull mode — user opens a tab to see matches)
> 3. In-app messaging (text only, archived)
> 4. Off-platform pivot warning + payment deep-link helper
> 5. Report / block
> 6. Push notifications (the original match-alerts pipeline)
>
> Each of these is independently shippable + testable.

---

## 15. Out of scope (intentionally)

> TODO 15.0 — explicit list of what we are NOT designing for in v1.
>
> Likely:
> - Auctions (Whatnot's territory)
> - Digital-only trades (no card art changes hands; not a thing in
>   BoBA)
> - Cross-border trading (US-only for v1)
> - Card grading / authentication (PSA's territory)
> - Insurance / shipping integration (USPS / FedEx APIs)
> - Crypto / NFT-style ownership tokens

---

## 16. References

> TODO 16.0 — populate from research agent citations.
>
> Expected categories:
> - Apple Developer Guidelines (specific section URLs)
> - Apple Developer Forums posts on P2P + payment policy
> - eBay / Mercari / Whatnot / OfferUp public ToS pages
> - PayPal / Venmo / Stripe / Escrow.com developer documentation
> - Section 230 case law summaries
> - State marketplace facilitator law tables
> - r/sportscards / r/baseballcards trading-best-practices threads

---

## 17. Open questions for Ben

> TODO 17.0 — populate as research surfaces decision points.
>
> Expected:
> - LLC formation: yes/no, and on what timeline
> - Initial trade-value cap: $X for v1, raise as we learn
> - Whether to enforce Discord-link requirement before any trade
> - Whether to require both parties' phone verification
> - Pricing: do we charge a fee per completed trade, or stay free?

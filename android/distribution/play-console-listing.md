# Play Console — paste-ready listing & form answers

Drafted from the iOS App Store listing + the BOBA project's own copy.
All values fit Play Console's character limits. Edit anything that
doesn't fit your voice — the form requires *you* to attest, so the
shape just needs to match what you'd say.

---

## Main store listing

### App name (max 30 chars)
```
BOBA Playbook
```
13/30.

### Short description (max 80 chars)
```
Search · Scan · Collect — the Bo Jackson Battle Arena companion app.
```
68/80. Single line; no marketing speak.

### Full description (max 4000 chars)
```
The companion app for the Bo Jackson Battle Arena (BoBA) trading card game.

SEARCH 17,000+ cards
Browse every BoBA release with high-res scans, hero stats, set + sub-set filtering, and weapon / treatment / cost tokens that compose the way the community talks about the game.

SCAN
Point your camera at any BoBA card and the app identifies it on-device using ML Kit Text Recognition. No photos ever leave your phone. Scan a stack of cards and review the session in one tap.

COLLECT
Track your personal collection across five designations — Personal, For Sale, For Trade, Wanted, and Grails. Add notes, condition, purchase price, asking price. Share a public collection link at bobaplaybook.com/u/{your-username} with friends who don't have the app.

BUILD DECKS
Compose Hero / Plays / Bonus / Hot Dog Decks against every BoBA format. Live DBS budget tracking, legality checks, and templates that start you with a working Apex / Spec / Elite / SPEC+ shell.

LEARN
Read the rules, strategy guides, and tournament reference at any depth — Rookie, Substitution, or Playmaker level. Includes the official 2026 Pro-Tour formats, division reference, and a community glossary with long-press to copy or share any term.

PURCHASE
See live upcoming Whatnot breaks and find local indie game stores running BoBA tournaments. Tap any store to open it in Google Maps.

PRIVACY
Scan processing happens entirely on-device. No photos leave your phone. Account sign-in (optional) uses Google or Discord OAuth; collection data is stored against your account so it follows you across devices.

OPEN-SOURCE
Source at github.com/bhwilkoff/BOBA-Playbook. Pull requests welcome.

Not affiliated with Bo Jackson, Topps, or BoBA Studios. Trading card images © respective rightsholders.
```
~1,800/4,000. Plenty of headroom; add a "What's new in this build" paragraph when the beta ships specific marquee features.

### App category
**Sports** (or Trading cards if available in your region's category list).

### Tags (Play Console suggests, max 5)
- Trading cards
- Sports
- Reference
- Tools
- Collectibles

### Contact details
- **Website:** `https://bobaplaybook.com`
- **Email:** `ben@learningischange.com`
- **Phone:** leave blank (optional; Play doesn't require)

### Privacy policy URL
```
https://bobaplaybook.com/privacy
```

---

## App access

In Play Console → Policy → App content → **App access**.

The reviewer needs login credentials to inspect Save Deck, Designate, Edit Profile flows.

**Recommended option:** "All or some functionality requires a special access" → provide a sandbox account:

- Username: `reviewer+google@learningischange.com` (or whichever existing email you point at Google's reviewers)
- Password: pick one, give it to reviewers
- Instructions to provide:
```
Sign in via "Email / Password" on the Profile sheet (gear icon on the Find tab).
Some features (Save Deck, Designate, Public Collection toggle, Trading toggle)
are gated to authenticated users. Browsing 17k+ cards, scanning, deck drafting,
and viewing the Learn corpus all work without signing in.
```

---

## Ads

**No, my app does not contain ads.**

---

## Content rating (IARC questionnaire)

Walk through the form picking these answers — BOBA fits squarely into the Everyone / PEGI 3 band.

| Question category | Answer |
|---|---|
| Violence — does your app contain violence? | **No** |
| Sexual content | **No** |
| Profanity | **No** |
| Controlled substances (alcohol, tobacco, drugs) | **No** |
| Gambling — does your app simulate gambling? | **No** (the in-game "Double-Up Press/Fold" mechanic is part of a physical card game ruleset, not in-app simulated gambling) |
| Crude humor | **No** |
| Horror / fear-themed | **No** |
| User-generated content shared between users | **Yes** (deck names, usernames, public collection URLs — but no chat / message surface) |
| Location sharing | **No** |
| Personal information sharing | **No** (avatar + username are user-set, not auto-broadcast) |
| Digital purchases | **No** (v1 has no in-app purchases) |
| Unrestricted internet | **No** (app fetches only from boba* domains + Google Maps + Whatnot deep links) |

**Expected outcome:** ESRB **Everyone** / PEGI **3** / IARC **3+**.

---

## Target audience and content

In Play Console → Policy → App content → **Target audience and content**.

- **Target age group:** **13–17** + **18 and over**. (Pick BOTH age groups.) Don't pick a child-only target — the BOBA community is teen+ on Whatnot/Discord and the Designed for Families program adds friction we don't need.
- **Appeal to children:** No.
- **Reason for choosing this target audience:** *"BoBA is a trading card game collected and played primarily by teens and adults. App content is rules / strategy / collection management."*
- **Ads targeting children:** No ads at all.
- **Account sign-in:** **Yes** — the app offers optional sign-in for collection / deck sync.
- **Will you ensure ads, in-app purchases, and other content are appropriate for the selected target audience?** Yes.

---

## Data Safety form

In Play Console → Policy → App content → **Data Safety**. ~30 min to fill out the first time.

### Data collection summary

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS everywhere via Supabase + Cloudflare R2 + Workers; all SDK calls use TLS) |
| Do you provide a way for users to request that their data is deleted? | **Yes — in-app** (Profile → Account → Delete account; routes through the `boba-account-delete` Worker which CASCADE-deletes all user-owned rows in Supabase) |

### Data types collected (per Play's checklist)

**Personal info:**
- ✅ **Name** — Optional. Collected via account sign-in (the `username` field). Used for App functionality + Account management. Required: optional. Shared: Yes (public-collection URLs at bobaplaybook.com/u/{username} share the username). Processed ephemerally: No.
- ✅ **Email address** — Required. Collected via sign-up. App functionality + Account management. Not shared.
- ✅ **User IDs** — Required. Auto-generated Supabase user_id. App functionality + Analytics (we use the ID for own-row RLS only; no third-party analytics SDK consumes it). Not shared.

**Photos and videos:**
- ✅ **Photos** — Optional. Avatar upload only. App functionality + Account management. Shared: Yes if user enables public collection (rendered on bobaplaybook.com/u/{username}). Processed ephemerally: No. Required: optional.

**App activity:**
- ✅ **In-app actions** — Optional. Collection add/edit, deck save/load. App functionality. Not shared.
- ✅ **In-app search history** — Optional, ephemeral. App functionality only. Not shared. Processed ephemerally: Yes.

**App info and performance:**
- ❌ Crash logs — **No** (we don't ship Crashlytics; FCM is messaging-only).
- ❌ Diagnostics — **No**.

**Device or other IDs:**
- ⏳ **Device or other IDs** — Will be **Yes** when push notifications ship; FCM registration token used for App functionality + Account management. Not shared. For *first beta*, declare **No** since push isn't wired yet.

**Financial info:** **No** — no payment flow in v1.
**Health and fitness:** **No.**
**Messages:** **No.**
**Files and docs:** **No** (the in-app card-image cache is generated, not user-supplied files).
**Calendar:** **No.**
**Contacts:** **No.**
**Location:** **No** (the Find a Store map doesn't request the location permission; uses zoomed-to-fit-results camera, not user location).
**Web browsing:** **No.**
**Audio files:** **No.**

### Data sharing summary
- We share **username + avatar + the collection projection on the public-collection URL** when the user opts in via the Profile toggle. Documented in DECISIONS.md #039.
- We share **Discord user-IDs** between two users when both opt into trading (deferred to TRADE-DESIGN.md Phase 1+ — not in v1 beta).
- Otherwise, no data is shared with third parties.

### Security practices

- **Data in transit encryption:** Yes — HTTPS everywhere.
- **Data deletion:** Yes — in-app via Profile → Account → Delete account.
- **Independent security review:** No.
- **Committed to Play's Families Policy:** Not applicable (not a Designed for Families app).

---

## Government / Financial / Health declarations

- **Government apps:** No.
- **Financial features:** No.
- **Health features:** No.
- **News app:** No.
- **COVID-19 contact tracing:** No.

---

## Release notes (first beta)

For the Internal Testing release. Play Console asks for one per locale; English is enough.

### en-US release notes (max 500 chars)
```
First Internal Testing build of BOBA Playbook for Android.

Includes: search across 17k+ cards, on-device card scanning via the camera, deck drafting against the current BoBA formats, collection tracking with five designations, public-collection sharing, Learn-tab rules + strategy + tournament reference, glossary, find-a-store map, upcoming Whatnot breaks.

Known gaps vs. iOS: Hero Shot 3D card video, House of BoBA Easter egg, Personal Showcase. All deferred to v2.
```
~520 chars — trim if needed.

---

## Pricing & distribution

- **Country availability:** Start with US only for beta; expand at production launch.
- **Free vs. paid:** Free. Don't toggle to paid; Play won't let you switch back.
- **Contains ads:** No.

---

## Closed testing → production unlock

For the first beta, **Internal Testing** is enough (no minimum tester count, no minimum days). When ready to broaden:

- **Closed testing** requires ≥12 testers active for ≥14 days for production unlock.
- **Open testing** then takes the closed-testing track public.
- **Production** requires the testing-track gate satisfied.

For v1 beta this matters only if you want to skip the production gating later. Internal Testing → directly to Production is allowed only once the closed-testing 12×14 gate has been served at some point.

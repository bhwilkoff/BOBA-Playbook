# BOBA Playbook — Playtest Pitch

**You know BOBA better than my code does.** I've built a companion iOS app for Bo Jackson Battle Arena — search, scan, collect, and play — and before I keep going, I want it in the hands of people who'd actually spot when a card's power is wrong, when a rule resolves the wrong way, or when a deck the builder accepts shouldn't be legal.

That's where you come in. The iOS beta has open slots:

**→ [Join via TestFlight](https://testflight.apple.com/join/YN52Dgu2)** · ~98 slots open

---

## What's in the app

**Search.** Browse all 17,739 cards in the catalog with filters for element, set, treatment, and power. All images load from the cloud via CDN (currently 91.5% of all cards have verified images), each detail view has stats, athlete bio, and pricing.

**Scan.** Point the camera at a physical card — on-device OCR reads the card number, hero name, and other attributes, matching it to the catalog in a couple seconds. Multi-card mode queues scans so you can inventory a box quickly. **All processing happens on your phone; no image ever leaves your device.**

**Collection.** Sign in/up via discord, apple id, or email/pass and track what you own across five designations: Personal, For Sale, For Trade, Wanted, Grails. Each entry keeps condition, quantity, and value — syncs to the cloud so you can pull it up anywhere.

**Play** (newest; hungriest for feedback):
- **Rules** reference for Rookie, Substitution, and Playmaker modes
- **Deck Builder** with live validation (60 heroes, 10 hot dogs, 30 plays, power-value caps, copy limits)
- **Practice Battle** — play a full 7-battle match against a CPU, with all 383 unique Play card effects wired to actual game logic
- Curated lists (WOBA, Bo Jackson, Ken Griffey Jr., Dr. J, and by sport / weapon)

**Pricing.** Each card detail shows live Buy Now listings and recent sales via an eBay API proxy, plus a "View on Radish" external link that opens the Radish Price Guide site in your browser.

---

## What I'd love you to stress-test

If something's broken, I'd rather find it now than after more people are using it. The things a BOBA expert will spot that I can't:

### Card data accuracy
- Is a card's power, element, treatment, name, or athlete inspiration wrong?
- Is a variant being treated as a duplicate of another card, or vice-versa?

### Practice Battle — Play card effects
- **This is the single most valuable feedback I can get.** Every one of the 383 unique Play card effects has been simulated to resolve correctly. If a Play resolves differently from the printed ability, tell me which card and what happened.
- Are the 3 game modes (Rookie / Substitution / Playmaker) resolving the way they should?
- CPU auto-picks the "best" option when a card offers a choice — does it feel reasonable, or is it making nonsense picks?
- Does the on-screen effect notification accurately describe what just happened?

### Deck Builder legality
- Is the builder letting you build decks it shouldn't (over 60 heroes, too many copies of a power value, duplicate plays, >6 of one hero across variants)?
- Is it blocking decks that should actually be legal?
- Are the 5 starter templates (Fire Aggro, Ice Control, Steel Wall, Mixed Toolbox, Economy/Attrition) decks you'd seriously consider playing?

### Scan accuracy
- Which cards does the camera struggle with? (Foils, full-art, older printings, dim light)


### Missing or wrong images
- Card without art, or with the wrong art? A card number + hero name is enough for me to chase it down.

### Pricing usefulness
- Are the Buy Now / Recent Sales results relevant for the card you're viewing, or does the eBay query need tweaking — especially for treatment variants?

### Anything else
- Crashes, weird layouts, text you couldn't read, confusing flows, buttons that did something you didn't expect. All welcome.

---

## How to share feedback

- **In TestFlight:** the built-in "Send Beta Feedback" button (screenshot or written)
- **Email:** ben@bobaplaybook.com — if you just want to share some unstructured feedback or if you want to talk about the app.

For a bug, **a card number and/or a screenshot is worth a hundred words.** For a Play card that resolved weirdly: card name + what you expected + what happened.

---

## Why this exists

BOBA Playbook is a companion — not a replacement for the cards or for the official rulebook. My guiding question when building any feature: *does this help someone engage with the game more deeply, or does it just do the thinking for them?* Search and scan should save you time. The practice battle should help you feel out a matchup or learn better about how to play. The deck builder should teach you the constraints, not hide them.

If you think the app has drifted from that intention — or could go further in the right direction — those are the ideas I most want to hear.

Thanks for playing along.

— Ben

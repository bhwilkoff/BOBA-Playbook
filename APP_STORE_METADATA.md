# BOBA Playbook — App Store Connect Metadata (copy-paste ready)

> Every field App Store Connect asks for, with the exact text to paste. Pairs with
> [`APP_STORE_RESUBMISSION.md`](./APP_STORE_RESUBMISSION.md) (the submission steps).
> Character limits are noted; the provided text is within them. Placeholders in
> `<ANGLE BRACKETS>` need your input (demo password, LLC name).

---

## 0. The name decision (read first — this is the 4.1 lever)

The rejection cited **4.1(a)/4.1(c)** over the "BOBA" brand in the name. Two paths:

- **Recommended first attempt — keep the name, defuse with framing + evidence.** Submit as **`BOBA Playbook`** but lead every text field with the *unofficial companion* framing (subtitle + first line of description below) and attach the rights-holder acknowledgment in App Review Information (Phase 3/4 of the runbook). The home-screen name is already `Playbook`, so the store name is the only "BOBA"-leading surface.
- **Fallback if Apple holds firm** (do in this order): add the subtitle only → rename so the brand isn't the leading token. Ready alternatives (all ≤30 chars):
  - `Playbook for BoBA` (17)
  - `BoBA Card Companion` (19)
  - `Playbook — TCG Companion` (24)

Everything below is written for the recommended path (name = `BOBA Playbook`). If you rename, only the **App Name** field changes; subtitle/description/keywords still apply.

---

## 1. App Information (set once, applies to all versions)

| Field | Value |
|---|---|
| **Bundle ID** | `app.bobaplaybook.ios` |
| **Primary Category** | **Utilities** — matches the "companion utility" framing of the 4.1 appeal (same category as Collectr/ManaBox). |
| **Secondary Category** | **Reference** |
| **Content Rights** | "No, it does not contain, show, or access third-party content." *(The card NAMES/data are factual catalog references; you display your own sourced imagery. If you prefer to be conservative, you may answer "Yes" and rely on the rights-holder acknowledgment — discuss in App Review notes either way.)* |
| **Age Rating** | **4+** (no objectionable content; see §7 for the questionnaire answers) |

---

## 2. Localizable listing (English — U.S.)

### App Name  *(max 30)*
```
BOBA Playbook
```

### Subtitle  *(max 30 — leads with "Unofficial" to defuse 4.1)*
```
Unofficial BoBA card companion
```

### Promotional Text  *(max 170 — editable anytime without review; good for the set drop)*
```
Now with the full Tecmo Bowl Edition set. Search, scan, and track 31,000+ cards. The unofficial companion built by a collector, for collectors of the BoBA TCG.
```

### Keywords  *(max 100, comma-separated, no spaces — don't repeat words already in the name/subtitle)*
```
bo jackson,trading card,tcg,card scanner,deck builder,collection tracker,collector,scan,decks,catalog
```

### Description  *(max 4000 — the non-affiliation disclaimer is the REQUIRED last paragraph; do not remove it)*
```
BOBA Playbook is the unofficial companion app for collectors and players of the Bo Jackson Battle Arena (BoBA) trading card game. Search the full catalog, identify cards with your camera, track your collection, and build decks — all in one place.

SEARCH
Browse, search, and filter the entire 31,000+ card catalog with images. Find any card by name, hero, weapon, treatment, set, or card number. Tap any card for full stats, every other version, and current pricing.

SCAN
Point your camera at a card to identify it instantly. Recognition runs entirely on your device — no photos are uploaded.

COLLECTION
Track what you own and tag cards as Personal, For Sale, For Trade, Wanted, or Grails. See your collection's estimated value, build custom rainbows, and share a public collection page.

DECKS
Build, save, and manage decks with format legality and a clear cost curve. Import and export decks to share with friends.

LEARN
Rules, strategy, collecting guides, a glossary, and tournament reference — written for every skill level.

PURCHASE
Find local stores and browse upcoming live breaks.

Sign in to sync your collection and decks across devices. The app works fully signed-out for browsing, searching, and building draft decks.

BOBA Playbook is an unofficial, fan-made companion app. It is not affiliated with, endorsed by, or sponsored by Bo Jackson Battle Arena or Imagination Mining Company. All card names, imagery, and game content are the property of their respective owners.
```

### What's New (version release notes)  *(max 4000)*
```
• Added the full Tecmo Bowl Edition set.
• Fixed sign-in and password entry on iPad.
• Improved card scanning for the newest cards.
• Stability and performance improvements.
```

### Promotional / Marketing URLs

| Field | Value |
|---|---|
| **Support URL** *(required)* | `https://bobaplaybook.com` |
| **Marketing URL** *(optional)* | `https://bobaplaybook.com` |
| **Privacy Policy URL** *(required)* | `https://bobaplaybook.com/privacy/` |

### Copyright
```
© 2026 <YOUR LLC NAME>
```

### Version
```
2.418
```
*(Must equal the binary's `CFBundleShortVersionString` = `MARKETING_VERSION`. Create a new App Store version record named `2.418` and attach the build — you cannot reuse the rejected `1.0` record. The build NUMBER auto-increments via `ci_post_clone.sh`.)*

---

## 3. App Review Information (this is where 4.1 is won — see runbook Phase 3/4)

| Field | Value |
|---|---|
| **Sign-in required** | **Yes** |
| **Demo Username** | `<demo account email>` |
| **Demo Password** | `<demo account password>` |
| **First / Last name** | `<your name>` |
| **Phone** | `<your phone>` |
| **Email** | `ben@bobaplaybook.com` |

> ⚠️ Confirm the demo account signs in **on a fresh install** before submitting — the reviewer uses exactly these. Verify password typing works on iPad (the bug that was just fixed).

### Notes (paste the full reply — verbatim from runbook Phase 4)
Paste the three-part reply (4.1, 2.1(a), 5.1.1(v)) from `APP_STORE_RESUBMISSION.md` Phase 4. Summary of what it says:
- **4.1:** independent unofficial companion utility (precedent: TCGplayer/Collectr/ManaBox); no official BoBA app exists to copy; rights holder (Doug Huskey, VP Collectibles, Imagination Mining Company) has acknowledged the app on the stated conditions (no IP claim, no playable game), both met; disclaimer added in-app and in the description.
- **2.1(a):** iPad sign-in + password-field bugs fixed; verified on iPad Air 11" (M3).
- **5.1.1(v):** account deletion is reachable in-app (Profile → Delete Account → confirm by typing username); screen recording attached.

### Attachments
- The **two Discord screenshots** (Doug Huskey / IMC acknowledgment) — your 4.1 evidence.
- A **screen recording on a physical device** of the account-deletion flow (Apple asked for this).
- *(Optional, stronger)* a one-line email from Doug/IMC confirming the same.

---

## 4. Version-specific build settings

- **Build:** the one from `origin/main` built on **Xcode Cloud with "Latest Release" Xcode** (not a beta seed).
- **Export compliance:** "Does your app use encryption?" → standard answer is **No** (only HTTPS / standard OS crypto, exempt). If ASC asks for a reason, the app uses only exempt encryption (`ITSAppUsesNonExemptEncryption = NO`).
- **Content rights / IDFA:** the app does **not** use the Advertising Identifier (IDFA) → answer **No** to the IDFA question.

---

## 5. Screenshots

Required sizes: 6.9" (or 6.7") iPhone and 13" iPad. Reuse the existing screenshots, with one rule:
- **Do not show the Practice / battle simulator** in any public screenshot (keep the playable-game surface out of the store presence — reinforces the 4.1 "no playable game" point). Find / Collection / Card detail / Decks / Scan are all good.

---

## 6. App Privacy (Data Collection questionnaire)

Answer **"Yes, we collect data."** Data types and settings:

| Data type | Purpose | Linked to user? | Used for tracking? |
|---|---|---|---|
| **Email Address** (Contact Info) | App Functionality (account) | Yes | No |
| **User ID** (Identifiers) | App Functionality (account) | Yes | No |
| **Name / Username** (Contact Info → Name) | App Functionality (public collection handle) | Yes | No |
| **Photos** (User Content) — only if avatar upload is enabled | App Functionality (profile picture) | Yes | No |
| **Other User Content** (collection, decks) | App Functionality | Yes | No |

- **Tracking:** **No** — the app does not track users across apps/sites (no IDFA, no third-party ad/analytics SDKs).
- **Camera:** scanning is on-device and uploads no images — there is **no "Photos/Camera data collection"** to declare for scan (nothing leaves the device). Only declare Photos if the avatar-upload feature is active.
- This must stay consistent with `PrivacyInfo.xcprivacy` in the build and the policy at `https://bobaplaybook.com/privacy/`.

---

## 7. Age Rating questionnaire → 4+

Answer **None / No** to every content category (violence, sexual content, profanity, gambling, etc.). The two that sometimes trip companion apps:
- **Unrestricted Web Access:** **No** — external links (Discord, eBay, Whatnot, stores) open in the system browser; there is no in-app unrestricted browser.
- **Gambling / Contests:** **No.**

Result: **4+**.

---

## 8. Pre-submit checklist (fields)

- [ ] App Name, Subtitle, Promotional Text, Keywords, Description (with disclaimer last), What's New — all pasted.
- [ ] Support + Privacy URLs set; Copyright filled with the LLC name.
- [ ] Version record `2.418` created; build attached.
- [ ] App Review Info: sign-in ON + working demo account + contact + Notes (Phase 4 reply) + Discord evidence + deletion screen recording.
- [ ] App Privacy + Age Rating completed as above.
- [ ] Screenshots contain no Practice/battle-simulator surface.
- [ ] Export compliance / IDFA answered.
```

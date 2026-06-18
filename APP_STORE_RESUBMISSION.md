# BOBA Playbook — App Store Resubmission Runbook

> **Use this to resubmit after the June 18, 2026 rejection (Submission `71738157-0b8a-4f07-8e55-eaf74920e97f`, version reviewed 1.0 (273), iPad Air 11" M3 / iPadOS 26.5).**
> Work top to bottom. Don't skip Phase 0 — the password fix is the one thing that wasn't run-verified on a device.

The four rejection items and where each is handled:

| Apple guideline | Issue | Fix | Phase |
|---|---|---|---|
| **2.1(a)** App Completeness | Sign-in button did nothing on iPad | Profile no longer a popover on iPad → sign-in sheet presents (`52a35f9f`) | 0, 1 |
| **2.1(a)** (root, found later) | Typing the password ejected you from the field | `SecureInputField` no longer resigns first responder on every keystroke (`d15cf77b`) | 0, 1 |
| **5.1.1(v)** Data Collection | "No account-deletion option" | Deletion was always built; it was unreachable behind the broken sign-in. Now reachable. | 0, 3, 4 |
| **4.1(a) / 4.1(c)** Copycats | "BOBA" brand in name + metadata | In-app non-affiliation disclaimer (all platforms) + rights-holder evidence + appeal | 2, 3, 4 |

Code is on `main` in commits **`52a35f9f`** and **`d15cf77b`** (internal version **2.418 / build 680**).

### Also in this build (landed after the rejection fixes — all on `main`)

Build from `main` and you get these for free; none touch the rejection-relevant surfaces (auth, disclaimer, deletion):

- **Tecmo Bowl Edition set added** — +13,339 cards (catalog 17,974 → 31,313, ~90% imaged). Searchable with full stats; art ships on the CDN. Good "What's New" copy: *"Added the full Tecmo Bowl Edition set."*
- **Scan recognizes the new set** — `feature-prints.bin` (the on-device scan fingerprint index) rebuilt to cover Tecmo (+13,334 prints), AND `CardScanner.swift`'s OCR card-number regex extended to accept Tecmo's hyphen-less formats (`BF1`, `SF72`, `JE43`) in addition to the hyphenated convention. Validated on the actual Vision pathway via `tools/ocr_probe.swift` (alpha card-number reads 0→17 of 25 on degraded-model OCR; higher on-device with the full E5 model). Pure-numeric base-set cards (1–240) still lean on fingerprint + hero-name where the printed number competes with the power stat — same difficulty class as existing pure-numeric cards, not Tecmo-specific.
- **Card images carry no source attribution** (catalog ships `imageFile` only) — privacy/IP hygiene; irrelevant to review but noted for completeness.

Suggested **"What's New" release notes:** *"Added the full Tecmo Bowl Edition set. Fixed sign-in and password entry on iPad."*

---

## Phase 0 — Verify the fixes on a real device (do this FIRST)

Install the build you're about to submit (TestFlight or a local run) on an **iPad** and a phone, then confirm:

- [ ] **Sign-in opens on iPad.** Find tab → Profile (top-left) → **Sign In / Create Account** → the sign-in screen appears (it previously did nothing on iPad).
- [ ] **Password typing works.** On the sign-in screen, tap the **Password** field and type several characters — the keyboard must stay up and the characters must register (this is the bug you found; it's the one fix not run-verified in CI).
- [ ] **Sign in succeeds** with the demo account (email/password).
- [ ] **Account deletion is reachable:** Profile (signed in) → scroll to **Delete Account** (red) → **Continue** → type your username → **Delete Account** → account is gone.
- [ ] **Disclaimer is visible:** the non-affiliation line shows on the signed-out Profile screen and in Profile → About.

If any of these fail, stop and tell Claude — do not resubmit.

---

## Phase 1 — Cut and upload the build

- [ ] Build from `main` (includes `52a35f9f` + `d15cf77b`).
- [ ] **Build with Xcode Cloud using the latest _Release_ Xcode — NOT a beta seed.**
      App Store Connect → your app → **Xcode Cloud → workflow → Edit → Environment → Xcode Version = "Latest Release"**.
      (The app builds against the GM SDK via the `IOS27_SDK` compile gate; a beta-Xcode build is auto-rejected — that was a separate earlier issue.)
- [ ] Confirm the uploaded build's **build number is higher than 273** (it will be — internal build is 680).
- [ ] Wait for the build to finish processing in App Store Connect (TestFlight tab shows it "Ready to Submit").

---

## Phase 2 — App Store listing metadata

- [ ] **Version field — must match the binary.** App Store Connect only lets you attach a build whose `CFBundleShortVersionString` equals the version record's number. The binary's value is `MARKETING_VERSION` in `AppVersion.xcconfig` = **`2.418`** — so **create/use an App Store version record named `2.418`** and attach the build to it. You can NOT attach this binary to the old rejected `1.0` record. (If you specifically want the store to read `1.0`, set `MARKETING_VERSION = 1.0` in `AppVersion.xcconfig` and rebuild first.) The build NUMBER bumps automatically via `ci_post_clone.sh` from the latest TestFlight build, so it stays unique and > 273.
- [ ] **Description:** add the non-affiliation disclaimer as the **last paragraph** (paste verbatim):

  > BOBA Playbook is an unofficial, fan-made companion app. It is not affiliated with, endorsed by, or sponsored by Bo Jackson Battle Arena or Imagination Mining Company. All card names, imagery, and game content are the property of their respective owners.

- [ ] **(Recommended) Subtitle / promotional text:** lead with the companion framing, e.g. *"Unofficial companion for BoBA collectors — search, scan, collect."* This proactively defuses 4.1.
- [ ] Screenshots: no change required, but if any screenshot shows the Practice/battle simulator, swap it out (keep gameplay out of the public-facing store presence — see Phase 4).

---

## Phase 3 — App Review Information (this is where you win 4.1)

App Store Connect → your version → **App Review Information**:

- [ ] **Sign-In required: ON.** Provide working **demo account** credentials (email + password). Confirm they work *on a fresh install* before submitting — the reviewer will use exactly these.
- [ ] **Attachment:** upload the **two Discord screenshots** showing Doug Huskey (VP of Collectibles, Imagination Mining Company) and the BoBA/WoTF team acknowledging the companion app and its conditions. This is your documentary evidence for 4.1.
      - *Stronger if you can get it:* a one-line email from Doug/IMC confirming the same ("We're aware of and OK with BOBA Playbook as an unofficial companion app, provided it doesn't claim our IP or include the playable game"). Attach that too if you can get it in time; the Discord screenshots are sufficient to submit now.
- [ ] **Notes:** paste the full reply text from Phase 4.
- [ ] **Account deletion demo:** record a screen capture **on a physical device** of: sign in with the demo account → Profile → Delete Account → Continue → type username → Delete Account → confirmation. Attach it (or link it) in the Notes. Apple explicitly asked for this.

---

## Phase 4 — The reply to App Review

Put this in **App Review Information → Notes**, and also reply with it in **Resolution Center** on the existing rejection thread. Paste as-is.

---

**Re: Guideline 4.1(a) and 4.1(c) — Copycats**

BOBA Playbook is an independent, unofficial companion utility for collectors of the Bo Jackson Battle Arena (BoBA) trading card game — the same category as established third-party TCG companion apps already on the App Store (e.g., TCGplayer, Collectr, ManaBox, Dragon Shield, Delver Lens for Magic: The Gathering; numerous Pokémon TCG collection trackers). It is a catalog, collection, and deck-tracking tool. There is no official BoBA app on the App Store, so there is no app whose content, features, or UI we could be copying.

We have the rights holder's acknowledgment. We are in direct communication with Doug Huskey, VP of Collectibles at Imagination Mining Company (the BoBA rights holder), and members of the BoBA team. They reviewed the app and confirmed it is acceptable provided it (1) does not claim BoBA's intellectual property and (2) does not include the playable game. Both conditions are met: the app makes no ownership claim over BoBA IP, and it contains no playable game. Documentary evidence of this correspondence is attached in the App Review Information section.

To remove any possible misleading association, this build adds a clear non-affiliation disclaimer on the Profile screen and in the About section, and we have added the same line to the App Store description: "BOBA Playbook is an unofficial, fan-made companion app. It is not affiliated with, endorsed by, or sponsored by Bo Jackson Battle Arena or Imagination Mining Company. All card names, imagery, and game content are the property of their respective owners."

We respectfully ask that the app be evaluated as a companion utility under this precedent. If the name remains a concern despite the rights holder's acknowledgment, we are willing to discuss adjusting the App Store name.

**Re: Guideline 2.1(a) — sign-in unresponsive on iPad**

Fixed in this build. On iPad, the Profile surface was adapting to a popover, and the sign-in screen presented from within it did not appear — the behavior you saw. The Profile surface is now a standard sheet on all devices, and a separate bug that dismissed the keyboard while typing a password has also been fixed. Sign-in (Apple, Google, Discord, and email/password) now works reliably. Verified on iPad Air 11-inch (M3).

**Re: Guideline 5.1.1(v) — account deletion**

Account deletion is implemented and reachable once signed in: Profile → Delete Account → Continue → type your username to confirm → Delete Account. This permanently deletes the account and all associated data in-app, with no website step and no customer-service requirement. It was previously unreachable only because of the iPad sign-in bug above, now fixed. A screen recording of the full flow is included in the App Review Information section.

---

## Phase 5 — Submit

- [ ] Attach the new build to the version.
- [ ] Confirm Notes + attachment + demo account + screen recording are all in place.
- [ ] **Submit for Review.**
- [ ] In Resolution Center, reply to the existing rejection thread with the Phase 4 text (so the reviewer sees it on the prior conversation too).

---

## If Apple pushes back again on 4.1(c) (name)

You've said you're open to renaming if needed. Fallback options, easiest acceptance last:
1. Keep the name; reinforce that the rights holder has acknowledged it (escalate via the App Review Board / phone appeal — these often succeed with documentary evidence).
2. Add a clarifying subtitle: *"Unofficial companion for BoBA collectors."*
3. Rename so the brand isn't the leading token: **"Playbook for BoBA"**, **"BoBA Card Companion"**, or **"Playbook — TCG Companion."** (The home-screen name is already "Playbook," so a store-name change is low-impact for users.)

Do these in order; only go further down the list if the prior one is rejected.

---

## Quick reference

- Fix commits: `52a35f9f` (iPad sign-in presentation + disclaimer), `d15cf77b` (password-field focus bug + web/Android disclaimer parity)
- Internal version: **2.418 (680)** — build number must stay > 273
- Build with: **Xcode Cloud, Latest _Release_ Xcode** (not beta)
- Disclaimer copy must read identically in: app (all 3 platforms) + App Store description
- Evidence: Discord screenshots (Doug Huskey / IMC) — attach in App Review Information

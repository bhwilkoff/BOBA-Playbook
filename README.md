# BOBA Playbook (archived)

> **BOBA Playbook shut down on November 21, 2026.** It was an unofficial, fan-built companion app for the Bo Jackson Battle Arena trading card game. It never received approval from the game's publisher, so it has been retired.
>
> **→ Read the [post mortem](./POSTMORTEM.md)** for why it shut down, what we learned, and which pieces of this codebase are worth reusing.

## What's here

The complete source for a three-platform card-game companion app:

| Directory | What |
|---|---|
| `index.html`, `js/`, `css/` | Web app: vanilla HTML/CSS/JS, no build step, hosted on GitHub Pages |
| `BOBAPlaybook/`, `BOBAPlaybook.xcodeproj` | iOS / iPadOS app: SwiftUI, Vision-based card scanning |
| `android/` | Android app: Kotlin + Jetpack Compose + Material 3, ML Kit scanning |
| `workers/` | Cloudflare Workers: pricing, image upload, account deletion, feeds |
| `pipeline/`, `scripts/` | Python catalog and image-sourcing pipeline |
| `supabase_schema.sql`, `supabase/` | Database schema (auth + user collections/decks) |
| `DESIGN.md`, `WEB-DESIGN.md`, `ANDROID-DESIGN.md`, `DECISIONS.md` | The design rules and architecture decisions behind it all |

**What's not here:** the card catalog, card images, official rules and checklists. Those belong to the game's publisher and have been removed. The production backends (Supabase, Cloudflare) have been deleted, so none of the apps will run without your own licensed data and infrastructure. See the post mortem's "If you want to build in this space" section.

## License

The code is released under the [MIT License](./LICENSE). The license covers the code only and grants no rights to Bo Jackson Battle Arena names, art, text or trademarks.

BOBA Playbook was never affiliated with, endorsed by, or licensed by Bo Jackson Battle Arena or its parent company.

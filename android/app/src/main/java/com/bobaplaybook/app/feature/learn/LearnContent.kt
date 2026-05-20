package com.bobaplaybook.app.feature.learn

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Inventory
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.PlayCircleFilled
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Learn corpus — port of iOS LearnView.swift content + IA.
 *
 * iOS shape (the model this file mirrors):
 *   Tab → Tile grid of 6 categories → ONE bespoke page per category.
 *   No generic "article" abstraction. Skill-level toggle appears ONLY
 *   on Rules (where content branches by mode), at the category root.
 *
 * Earlier port shipped a generic LearnArticle data class with skill-
 * level scopes on every article. That produced the "content hidden
 * behind a further content area" anti-pattern users flagged:
 * articles where only Rookie has body still rendered the
 * SegmentedButton picker. iOS never does that — categories without
 * mode-branching content (Strategy / Collect / Glossary / Tournament)
 * have a flat page; only Rules forks by mode.
 */

enum class LearnCategoryId(
    val title: String,
    val blurb: String,
    val icon: ImageVector,
    val accent: Color,
) {
    RULES     ("Rules",      "Match flow, card zones, edge cases",            Icons.Default.AutoStories,          Color(0xFFFF4D00)),
    STRATEGY  ("Strategy",   "Power curve, weapon synergy, archetypes",       Icons.Default.Lightbulb,            Color(0xFFFFD700)),
    COLLECT   ("Collect",    "Treatments, parallels, variations",             Icons.Default.Inventory,            Color(0xFF00F5FF)),
    WATCH     ("Watch",      "Tutorials, top plays, deep dives on YouTube",   Icons.Default.PlayCircleFilled,     Color(0xFFFF0000)),
    GLOSSARY  ("Glossary",   "Game terms + trading vocabulary",               Icons.AutoMirrored.Filled.MenuBook, Color(0xFF8B00FF)),
    TOURNAMENT("Tournament", "Pro Tour formats, modes, penalties",            Icons.Default.EmojiEvents,          Color(0xFFC0C0C0)),
    ;

    companion object {
        fun fromId(id: String): LearnCategoryId? = entries.firstOrNull { it.name.equals(id, ignoreCase = true) }
    }
}

/** Mode picker for the Rules page only (iOS BoBALearn parity). */
enum class GameMode(val label: String, val blurb: String) {
    ROOKIE      ("Rookie",       "8 Heroes · 30 Plays · 6 Bonus · 10 HD"),
    SUBSTITUTION("Substitution", "Adds 4 substitutions per match · 1 Coach"),
    PLAYMAKER   ("Playmaker",    "Full deck-build: persistents, scopes, HD economy"),
}

/** A vertical block inside a category page. */
sealed interface LearnSection {
    val heading: String?
    data class Body    (override val heading: String?, val text: String)          : LearnSection
    data class Bullets (override val heading: String?, val items: List<String>)   : LearnSection
    data class Callout (override val heading: String?, val text: String)          : LearnSection
    /** A two-column term + definition row used by Glossary. */
    data class Term    (override val heading: String? = null, val term: String, val definition: String) : LearnSection
}

/** Single source of truth for category content. */
object LearnCorpus {

    // ════════════════════════════════════════════════════════════════
    // RULES — mode-aware content. Picker at page root drives selection.
    // ════════════════════════════════════════════════════════════════

    /** Page-root sections shown regardless of mode. */
    val rulesIntro: List<LearnSection> = listOf(
        LearnSection.Body(
            heading = "How a match plays",
            text = "Each match is a best-of-seven series of Battles. Your Heroes face the opponent's Heroes one Battle at a time. The first coach to win 4 Battles wins the match.",
        ),
        LearnSection.Bullets(
            heading = "The 5 phases of every Battle",
            items = listOf(
                "Bench — pick which 3 Heroes start the next Battle",
                "Plays — both coaches reveal their Plays simultaneously",
                "Battle — apply Plays to Heroes; reveal active Hero",
                "Resolve — total Power, apply persistent effects, declare winner",
                "Next — winner advances, loser retires their Hero, move to next Battle",
            ),
        ),
    )

    /** Mode-specific sections appended after the intro. */
    fun rulesForMode(mode: GameMode): List<LearnSection> = when (mode) {
        GameMode.ROOKIE -> listOf(
            LearnSection.Callout(
                heading = "Rookie deck composition",
                text = "8 Heroes · 30 Plays · 6 Bonus Plays · 10 Heroic Damage. No substitution.",
            ),
            LearnSection.Body(
                heading = "Basic Hero economy",
                text = "Pick your strongest 3 Heroes for the opening Bench. Heroes who win stay in for the next Battle; heroes who lose retire for the rest of the match.",
            ),
            LearnSection.Bullets(
                heading = "Rules to internalize first",
                items = listOf(
                    "Higher total Power at Resolve wins the Battle",
                    "Heroic Damage > 10 = auto-loss (no Power comparison)",
                    "Bonus Plays cost — you can play at most as many as you can pay for",
                    "First to 4 Battle wins takes the match",
                ),
            ),
        )
        GameMode.SUBSTITUTION -> listOf(
            LearnSection.Callout(
                heading = "Substitution mode",
                text = "Rookie rules + 4 substitutions per match + 1 Coach card. Adds bench-management as a real lever.",
            ),
            LearnSection.Body(
                heading = "Substitution math",
                text = "Heroes can be subbed in or out at the Bench phase of any Battle after Battle 1. Bench order matters — Heroes brought in later have less time to ramp up their persistent effects.",
            ),
            LearnSection.Bullets(
                heading = "Sub timing rules",
                items = listOf(
                    "Subbed-in Heroes lose any 'rest of game' persistent effects already in play",
                    "Subbed-out Heroes can NOT return in the same match (BR-04)",
                    "Each coach may sub at most once per Battle",
                    "Subs happen BEFORE Plays reveal in the Plays phase",
                ),
            ),
        )
        GameMode.PLAYMAKER -> listOf(
            LearnSection.Callout(
                heading = "Playmaker mode",
                text = "Full BoBA: persistent-effect scopes, HD economy, hot-dog parallels, all weapon mechanics.",
            ),
            LearnSection.Body(
                heading = "Reading the persistent stack",
                text = "Track which 'rest_of_game' effects have installed (and from which Hero). Late-Battle swings come from compounding persistents — predict them by Battle 4.",
            ),
            LearnSection.Body(
                heading = "The pivot Battle",
                text = "Battle 4 is structurally critical: at 2-1, winning Battle 4 closes the match in 2 more wins. At 1-2, losing means you need 3 in a row to recover. Plan your Hero economy around it.",
            ),
            LearnSection.Body(
                heading = "HD as offense",
                text = "Smart Playmakers use Heroic Damage as offensive currency. Push the opponent's active Hero past 10 HD and you skip the Power calculation entirely (auto-loss for them).",
            ),
        )
    }

    /** Always-visible appendix below the mode-specific body. */
    val rulesAppendix: List<LearnSection> = listOf(
        LearnSection.Bullets(
            heading = "Card zones",
            items = listOf(
                "Bench — face-down Heroes waiting for their Battle",
                "Active — the Hero currently in a Battle",
                "Retired — Heroes who lost; out for the match",
                "Played — face-up Plays applied to the active Hero",
                "Used — face-down spent Plays",
            ),
        ),
        LearnSection.Bullets(
            heading = "Edge cases",
            items = listOf(
                "Tied Power at Resolve → coin flip in casual; sudden-death in tournament",
                "Both coaches reveal identical Plays → ties resolve by base Power",
                "No eligible Hero for next Bench → concede (BR-12)",
            ),
        ),
    )

    // ════════════════════════════════════════════════════════════════
    // STRATEGY — flat page, no mode picker (iOS parity)
    // ════════════════════════════════════════════════════════════════

    val strategy: List<LearnSection> = listOf(
        LearnSection.Body(
            heading = "Power curve",
            text = "A healthy deck spreads Power across low / mid / high tiers. Low-Power Heroes win opening Battles cheaply; high-Power Heroes anchor closing Battles after the opponent has burned reactive Plays.",
        ),
        LearnSection.Body(
            heading = "Substitution strategy",
            text = "Sub for tempo, not desperation. A planned Battle-3 sub that drops in a fresh persistent installer beats an emergency Battle-5 sub trying to hold the line. Use Hot Dog parallels to extend Bonus Play capacity if your deck leans on them.",
        ),
        LearnSection.Body(
            heading = "Weapon synergy",
            text = "Fire chains burn damage across battles; Ice freezes opposing Plays for tempo; Steel stacks defensive layers. Mixed-weapon decks lose synergy bonuses — pick a primary and a secondary at deck-build.",
        ),
        LearnSection.Bullets(
            heading = "Play card types",
            items = listOf(
                "Tempo — cheap Plays that swing a single Battle's Power",
                "Combo — persistent installers that compound across Battles",
                "Value — high Cost, high payoff in the back half",
                "Control — counter-Plays that neutralize opposing persistents",
            ),
        ),
        LearnSection.Body(
            heading = "Resource management",
            text = "Bonus Plays are bounded (6 in Rookie, more with Hot Dogs). Don't blow your Bonus budget in Battles 1–2; the back half is where Bonus Plays compound. HD is its own resource — spending HD to win one Battle can cost you the next.",
        ),
        LearnSection.Bullets(
            heading = "The four archetypes",
            items = listOf(
                "Aggro — high Power, low Cost, fast Battles",
                "Control — defensive Heroes + counter-Plays",
                "Combo — chain persistent effects for compounding bonuses",
                "Midrange — balanced; reactive to the meta",
            ),
        ),
        LearnSection.Callout(
            heading = "Picking an archetype to learn first",
            text = "Midrange is the most-forgiving entry point — it teaches you the full state-machine without locking you into one playstyle. Aggro is fast to win OR lose, so it skips a lot of game-state learning.",
        ),
    )

    // ════════════════════════════════════════════════════════════════
    // COLLECT — flat page, no mode picker
    // ════════════════════════════════════════════════════════════════

    val collect: List<LearnSection> = listOf(
        LearnSection.Body(
            heading = "Two distinct concepts",
            text = "Treatments are DIFFERENT WAYS the same card can be printed. Parallels are ENTIRELY SEPARATE runs that share format but have their own numbering.",
        ),
        LearnSection.Bullets(
            heading = "Rarity by weapon (Inspired Ink serialized)",
            items = listOf(
                "Hex /5 — rarest serialized variant available",
                "Glow /10",
                "Fire /25",
                "Ice /50",
                "Steel / Brawl — base set only; no serialized run",
            ),
        ),
        LearnSection.Bullets(
            heading = "Treatments — standard",
            items = listOf(
                "Base Set — the standard print every card has",
                "Battlefoil Red / Silver / Blue / Orange / Green / Pink / Bubble Gum",
            ),
        ),
        LearnSection.Bullets(
            heading = "Treatments — themed foils",
            items = listOf(
                "Blizzard, Alpha, Headlines, Power Glove",
                "Grandma's Linoleum, Great Grandma's Linoleum",
                "Chillin', Grillin', Icon, Mixtape, Miami Ice",
                "Fire Tracks, Colosseum, Logofoil, Slime",
            ),
        ),
        LearnSection.Bullets(
            heading = "Treatments — premium",
            items = listOf(
                "Inspired Ink (Serialized) — Hex /5, Glow /10, Fire /25, Ice /50",
                "Superfoil — premium variant, rare across most sets",
            ),
        ),
        LearnSection.Bullets(
            heading = "Parallels (separate runs)",
            items = listOf(
                "Billy Cameo Alt Arts",
                "SideKicks",
                "Plays",
                "Bonus Plays",
                "Prize & Promos",
                "Hot Dogs",
            ),
        ),
        LearnSection.Bullets(
            heading = "Variations",
            items = listOf(
                "First Edition — limited initial print run",
                "2026 Edition — annual reprints",
                "Debut — first appearance of a hero in any set",
            ),
        ),
        LearnSection.Callout(
            heading = "Why this matters for trades",
            text = "Collectors who don't separate Treatments from Parallels will undervalue Parallels (scarce by edition limit) and overvalue mid-tier Treatments (scarce only within their treatment family).",
        ),
    )

    // ════════════════════════════════════════════════════════════════
    // GLOSSARY — two flat sections (Game + Trading), terms only
    // ════════════════════════════════════════════════════════════════

    // Verbatim port from iOS LearnView.swift gameTerms array. Each
    // definition pulled exactly from the iOS Term struct.
    val glossaryGame: List<LearnSection.Term> = listOf(
        LearnSection.Term(term = "Coach", definition = "How a BoBA player refers to themselves in any gameplay setting. You lead a squad of heroes into battle — the Heroes bring the power, you bring the strategy."),
        LearnSection.Term(term = "Honors", definition = "The right to act first in a battle — choose to substitute first, play first, and resolve first. After each battle, Honors passes to the battle winner."),
        LearnSection.Term(term = "Sub / Substitute", definition = "Swap the revealed Hero for one from your hand by paying 2 Hot Dogs during the Substitution Window. Only the Honors player can decide whether to substitute first."),
        LearnSection.Term(term = "HTD", definition = "Home Team Discount — a treatment on 60 Play cards in the Alpha Blast set that reduces the Hot Dog cost by 1 when used by the Honors player. Many tournament formats toggle HTD Plays on or off; always check the event's rules."),
        LearnSection.Term(term = "Bonus Play", definition = "Card-number prefix BPL. Supplemental Plays (Alpha Update / Griffey / specialty sets) you can include beyond the 30-card Playbook. Some formats toggle Bonus Plays off entirely."),
        LearnSection.Term(term = "Hot Dog", definition = "The energy resource of the game. Pay Hot Dogs to substitute or play Plays. Your Hot Dog Deck has exactly 10 cards, and they also serve as Power 0 placeholders."),
        LearnSection.Term(term = "DBS", definition = "Deck Balancing System — each Play card has a DBS score (Low / Medium / High / Very High). All Playmaker divisions at the 2026 Nationals cap a deck's total DBS at 1,000 unless specified otherwise. High-DBS plays are individually powerful but crowd out the rest of the deck."),
        LearnSection.Term(term = "Playbook", definition = "The 30 unique-named Plays you bring to the table. Draw 1 after each battle."),
        LearnSection.Term(term = "Rainbow", definition = "Community collecting goal — owning every treatment variation of a single hero (Base + all foils + autos). Tracked in the Collection tab's Rainbow view."),
        LearnSection.Term(term = "Chillin' / Grillen", definition = "Chillin' is an active treatment name (Chillin' Battlefoil). In older Spec rules, players sometimes say 'chillin' for Ice and 'grillen' for Fire — those are legacy slang for the weapon elements. The current rules use Ice and Fire."),
        LearnSection.Term(term = "Double-Up (Press / Fold)", definition = "Optional betting mechanic any game mode can add. Each Coach gets one Press per game to double the game's point value; the opponent then Folds (ends the game) or Presses back. A whole new \"Laundry Phase\" between battles."),
    )

    // Verbatim port from iOS LearnView.swift tradingTerms array.
    val glossaryTrading: List<LearnSection.Term> = listOf(
        LearnSection.Term(term = "ISO", definition = "In Search Of — you want to acquire this card. Posted with a hero name or card number."),
        LearnSection.Term(term = "PC", definition = "Personal Collect (or Personal Collection) — a card you're keeping and not trading/selling. Often paired with a hero name: 'Bo Jackson PC.'"),
        LearnSection.Term(term = "OBO", definition = "Or Best Offer — the listed price is negotiable."),
        LearnSection.Term(term = "FS / F/S", definition = "For Sale — shorthand for a listing. Almost always followed by a price."),
        LearnSection.Term(term = "WTB / WTS / WTT", definition = "Wants To Buy / Sell / Trade — explicit intent tags on a post."),
        LearnSection.Term(term = "shipped", definition = "The listed price includes shipping. 'Raw $50 shipped' means no separate shipping fee."),
        LearnSection.Term(term = "PWE", definition = "Plain White Envelope — cheap, untracked shipping. Fine for low-value cards; risky for expensive ones."),
        LearnSection.Term(term = "BMWT", definition = "Bubble Mailer With Tracking — the safer default for anything above ~$20."),
        LearnSection.Term(term = "G&S / F&F", definition = "PayPal Goods & Services (buyer-protected, has fees) vs. Friends & Family (no protection). Sellers asking for F&F are a scam signal."),
        LearnSection.Term(term = "coin / coined", definition = "A photo of the card with the seller's handwritten username + current date (+ sometimes price). Community-enforced proof-of-possession; ask for one before sending funds for high-value trades."),
        LearnSection.Term(term = "vouch", definition = "A community endorsement of a trader's trustworthiness. New traders often ask for vouches before a first deal."),
        LearnSection.Term(term = "hit", definition = "A valuable card pulled from a pack or box. 'Got a big hit in my Griffey box' = pulled something notable."),
        LearnSection.Term(term = "break", definition = "A livestream-style pack or box opening where seats are sold and cards are distributed to buyers by hero, team, or random draw."),
        LearnSection.Term(term = "breaker", definition = "The person running a break."),
        LearnSection.Term(term = "rip", definition = "Opening a pack or box — 'ripping.'"),
        LearnSection.Term(term = "raw", definition = "Ungraded. The opposite of PSA/BGS/CGC/TAG graded."),
        LearnSection.Term(term = "graded", definition = "Encapsulated and scored by a third-party grader (PSA, BGS, CGC, TAG). 'PSA 10' is the top grade at PSA."),
        LearnSection.Term(term = "TAG", definition = "TAG Grading — an emerging alternative grader using laser-scored analysis. Ask your event organizer whether TAG slabs are accepted as proxies."),
        LearnSection.Term(term = "comps", definition = "Comparable recent sales — used to sanity-check a price. The card detail view's pricing panel pulls comps from Radish + eBay."),
        LearnSection.Term(term = "dumper", definition = "A card sold cheaply — often the lower-value hit in a break-day liquidation."),
        LearnSection.Term(term = "banger", definition = "An impressive or high-value pull. Affectionate."),
        LearnSection.Term(term = "scam / scammer", definition = "Don't engage, report to moderators, and check the vouch history before any trade with a new account."),
    )

    // ════════════════════════════════════════════════════════════════
    // TOURNAMENT — flat page, no mode picker
    // ════════════════════════════════════════════════════════════════

    val tournament: List<LearnSection> = listOf(
        LearnSection.Body(
            heading = "Pro Tour 2026",
            text = "$500,000+ prize pool. Coaches register one Playbook per event; multiple events per Pro Tour stop. Top 8 advances to single elimination.",
        ),
        LearnSection.Bullets(
            heading = "Hero Deck formats",
            items = listOf(
                "Apex — open format, all sets, all weapons legal",
                "Spec — single-weapon decks only",
                "Elite — pre-Standard rotation set only",
                "SPEC+ — Spec with tiered Hero requirements",
            ),
        ),
        LearnSection.Bullets(
            heading = "Game modes (event-level)",
            items = listOf(
                "Rookie — best-of-3 matches, no subs, no Coach",
                "Substitution — best-of-5 matches, 4 subs + 1 Coach",
                "Playmaker — best-of-7 matches, full BoBA",
            ),
        ),
        LearnSection.Body(
            heading = "Double-Up",
            text = "Optional press-and-fold side-bet. Before any Battle, either coach may offer Double-Up. If accepted, the winner of the next Battle scores 2 toward the match. Stacks — sequential Double-Ups can scale 2 → 4 → 8.",
        ),
        LearnSection.Body(
            heading = "Madness modes",
            text = "Team-play variants for paired-coach events. Apex & AlphaTrilogy pairs two coaches per team; HiLo pairs one Apex deck with one rookie deck for handicapped play.",
        ),
        LearnSection.Bullets(
            heading = "Nationals divisions",
            items = listOf(
                "Apex — premier open division",
                "AlphaTrilogy — pre-Standard sets only",
                "Granny's Gum — themed-foil only",
                "Brawl — single-weapon Brawl decks",
                "Tecmo Bowl — retro-themed format",
                "Spec — single-weapon open",
            ),
        ),
        LearnSection.Bullets(
            heading = "Match structure",
            items = listOf(
                "Round-robin pools of 4 → top 2 advance",
                "Single elimination top 8 onward",
                "Score: 3 for win, 1 for draw, 0 for loss",
                "Tiebreakers: head-to-head → opponent match-win % → cumulative Power margin",
            ),
        ),
        LearnSection.Bullets(
            heading = "Penalty reference",
            items = listOf(
                "Slow play — warning → game loss",
                "Marked card — match loss",
                "Misrepresentation — match loss + investigation",
                "Unsporting conduct — DQ from event",
            ),
        ),
    )

    // ════════════════════════════════════════════════════════════════
    // WATCH — placeholder; YouTube feed Worker wiring is M5-polish
    // ════════════════════════════════════════════════════════════════

    val watch: List<LearnSection> = listOf(
        LearnSection.Body(
            heading = "Coming soon",
            text = "The BoBA Playbook YouTube feed (tutorials, top plays, live breaks, shorts) lives in the iOS app today and ships to Android in an upcoming release.",
        ),
        LearnSection.Body(
            heading = "Until then",
            text = "Open YouTube and search for 'Bo Jackson Battle Arena' — the BoBA official channel posts new content every week.",
        ),
    )
}

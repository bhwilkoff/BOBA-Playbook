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

    val glossaryGame: List<LearnSection.Term> = listOf(
        LearnSection.Term(term = "Coach", definition = "Special card representing the deck's strategist. Substitution mode adds one Coach card."),
        LearnSection.Term(term = "Honors", definition = "Bonus tokens earned for winning Battles in dominant fashion (e.g. without taking HD)."),
        LearnSection.Term(term = "Sub", definition = "Substitution — swapping a Bench Hero in or out between Battles."),
        LearnSection.Term(term = "HTD", definition = "Hot Dog — parallel slot allowing >6 Bonus Plays in a deck."),
        LearnSection.Term(term = "Bonus Play", definition = "A Play with a Cost > 0. Cap at 6 in Rookie / Substitution; Hot Dogs extend the cap."),
        LearnSection.Term(term = "DBS", definition = "Deck-Build Sum — total Power cost of the cards in a deck. Tournament-legality check."),
        LearnSection.Term(term = "Playbook", definition = "A complete legal deck list. Tournament submissions are Playbooks."),
        LearnSection.Term(term = "Rainbow", definition = "Collecting goal — owning a card in every Treatment variant."),
        LearnSection.Term(term = "Chillin' / Grillin'", definition = "Themed foil pair celebrating off-season / cooking-show variants of certain heroes."),
        LearnSection.Term(term = "Double-Up", definition = "Press-and-Fold side-bet mechanic in tournament play."),
        LearnSection.Term(term = "Auto-loss", definition = "Battle ends without comparing Power; most commonly when HD > 10."),
    )

    val glossaryTrading: List<LearnSection.Term> = listOf(
        LearnSection.Term(term = "ISO", definition = "In Search Of — what you're hunting for in a trade."),
        LearnSection.Term(term = "PC", definition = "Personal Collection — cards not for sale at any price."),
        LearnSection.Term(term = "OBO", definition = "Or Best Offer — listed price is a starting point."),
        LearnSection.Term(term = "FS", definition = "For Sale — designation on cards available to buy."),
        LearnSection.Term(term = "WTB", definition = "Want To Buy — actively looking, cash-ready."),
        LearnSection.Term(term = "WTS", definition = "Want To Sell — actively looking to move a card."),
        LearnSection.Term(term = "WTT", definition = "Want To Trade — actively looking to trade card-for-card."),
        LearnSection.Term(term = "Shipped", definition = "Card has been mailed. Tracking number expected."),
        LearnSection.Term(term = "PWE", definition = "Plain White Envelope — cheap, no tracking. Risky for valuable cards."),
        LearnSection.Term(term = "BMWT", definition = "Bubble Mailer With Tracking — standard for sub-$50 cards."),
        LearnSection.Term(term = "G&S", definition = "PayPal Goods & Services — buyer protection. The right choice for purchases."),
        LearnSection.Term(term = "F&F", definition = "PayPal Friends & Family — no protection. Prohibited by PayPal for purchases."),
        LearnSection.Term(term = "Coin", definition = "Tip / payment delta — the difference making a trade even."),
        LearnSection.Term(term = "Vouch", definition = "Reputation reference from a prior trade partner."),
        LearnSection.Term(term = "Hit", definition = "Pulling a high-value card from a pack — a 'hit'."),
        LearnSection.Term(term = "Break", definition = "Group rip of a sealed product where each buyer claims a team / division beforehand."),
        LearnSection.Term(term = "Breaker", definition = "Person hosting a Break."),
        LearnSection.Term(term = "Rip", definition = "Opening a sealed pack on stream or for content."),
        LearnSection.Term(term = "Raw", definition = "Ungraded — card has not been graded by PSA / BGS / TAG."),
        LearnSection.Term(term = "Graded", definition = "Card encapsulated by a grading service with a numeric grade (PSA 10, etc.)."),
        LearnSection.Term(term = "Comps", definition = "Recent sold prices used as comparison for valuing a card."),
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

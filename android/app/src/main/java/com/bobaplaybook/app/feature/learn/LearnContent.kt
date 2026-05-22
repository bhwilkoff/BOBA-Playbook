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

/**
 * Archetype catalog entry — port of iOS Archetype struct in
 * LearnView.swift. Used by the Strategy page to render an expandable
 * card with key-play thumbnails resolved against the live catalog.
 */
data class Archetype(
    val id: String,
    val name: String,
    /** UPPERCASE element key — drives the accent color via BobaElements. */
    val element: String,
    val tagline: String,
    val strategy: String,
    val weakness: String,
    val keyPlays: List<String>,
)

/** A vertical block inside a category page. */
sealed interface LearnSection {
    val heading: String?
    data class Body    (override val heading: String?, val text: String)          : LearnSection
    data class Bullets (override val heading: String?, val items: List<String>)   : LearnSection
    /**
     * Tinted callout box — left border + heading color come from the
     * `element` key when provided (FIRE/ICE/HEX/etc.) so callouts read
     * with the same color coding iOS uses for tips, warnings, and
     * concept boxes. `element = null` defaults to the brand cyan
     * (matches generic teaching callouts on iOS).
     */
    data class Callout (
        override val heading: String?,
        val text: String,
        val element: String? = null,
    ) : LearnSection
    /** A two-column term + definition row used by Glossary. */
    data class Term    (override val heading: String? = null, val term: String, val definition: String) : LearnSection
    /**
     * Weapon-synergy block — iOS WeaponSynergySection parity. Renders
     * the weapon name in its element color, then a wrap-flow of
     * element-tinted Play-name pills.
     */
    data class WeaponSynergy(
        override val heading: String? = null,
        val rows: List<Row>,
    ) : LearnSection {
        data class Row(val weapon: String, val plays: List<String>)
    }
    /**
     * Card-examples block — horizontal scroll of card thumbnails
     * resolved against the live catalog. Used for hero-deck examples,
     * play-card-type examples, hot-dog examples, etc. Provides the
     * "this is what a Hot Dog looks like" visual context that text
     * alone can't carry.
     */
    data class CardExamples(
        override val heading: String? = null,
        val description: String? = null,
        val cardNames: List<String>,
        /** When true, only Hot Dog cards match. Otherwise any card type. */
        val hotDogsOnly: Boolean = false,
        /** When true, only Plays match. */
        val playsOnly: Boolean = false,
        /** When true, only Heroes match. */
        val heroesOnly: Boolean = false,
    ) : LearnSection
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
        // Tick 186 — Discord backlog #5: "Understanding DBS" article.
        // Discord §5 finding: 15-20% of rules questions are about DBS.
        // Lives in the always-visible appendix because DBS comes up in
        // every Playmaker discussion regardless of game-mode picker.
        LearnSection.Body(
            heading = "Understanding DBS (Deck Balancing System)",
            text = "DBS is a per-Play cost system used in Nationals-style formats to keep individually powerful plays from crowding out the rest of a deck. Every Play has a DBS score and your deck's total must stay under the format's cap (1,000 for all Playmaker divisions at 2026 Nationals).",
        ),
        LearnSection.Bullets(
            heading = "How DBS works",
            items = listOf(
                "Every Play card has a DBS value (Low 1-20 / Medium 21-40 / High 41-60 / Very High 67+)",
                "Your 30 Plays sum to a total DBS; deck-builder shows it live",
                "Stay ≤ deck's budget (typically 1,000) — over-cap decks fail legality check",
                "Non-Nationals formats (Rookie, Substitution, Playmaker base) ignore DBS entirely",
                "Bonus Plays count toward DBS in formats that include both",
                "High-DBS plays are powerful but force you to fill the rest of the deck with low-DBS plays",
            ),
        ),
        LearnSection.Callout(
            heading = "Quick DBS tip",
            text = "Tap the DBS chip on any Play card to see how adding it changes your active deck's total. The chip is purple and lives next to Power / Cost on the card detail.",
        ),
        LearnSection.Callout(
            heading = "April 2026 update",
            text = "BoBA rebalanced DBS values to restore meaningful decisions: low-cost Plays (especially 0- and 1-cost effects) carry higher DBS than before; key cards that enabled full-deck cycling or repeat loops were rebalanced. Effects like draw, recovery, and manipulation are still powerful — they just come with a real cost now. See bobattlearena.com/blog/dbs-update-live-now for the BoBA team's announcement.",
        ),
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
            text = "A healthy deck spreads Power across low / mid / high tiers. Low-Power Heroes win opening Battles cheaply; high-Power Heroes anchor closing Battles after the opponent has burned reactive Plays. The 6-per-power-value rule forces you to spread across levels — a smart build balances three tiers.",
        ),
        // Tick 251 — iOS PowerCurveSection content port. iOS shows mini-
        // card samples + tier captions; Android renders the same tiering
        // logic as a bullet list (simpler than wiring image samples in
        // LearnSection).
        LearnSection.Bullets(
            heading = "Three power tiers",
            items = listOf(
                "LOW (85-115) — position wisely. Use early to bait reactive Plays out of the opponent.",
                "MID (120-155) — consistency layer. The bulk of a balanced deck sits here.",
                "HIGH (160+) — save for clutch. Front-loaded for Honors momentum or back-loaded for Battle 5-7 closeouts.",
            ),
        ),
        LearnSection.Bullets(
            heading = "Positioning tips",
            items = listOf(
                "Front-load strong Heroes to establish Honors momentum early.",
                "Save High-tier Heroes for Battles 5-7 — games are often decided in the final stretch.",
                "Late Hit (+35 in Battle 7) and The Closer (+40 in Battle 7) amplify back-loaded positioning.",
            ),
        ),
        LearnSection.Body(
            heading = "Substitution strategy",
            text = "Sub for tempo, not desperation. A planned Battle-3 sub that drops in a fresh persistent installer beats an emergency Battle-5 sub trying to hold the line. Use Hot Dog parallels to extend Bonus Play capacity if your deck leans on them.",
        ),
        LearnSection.Body(
            heading = "Weapon synergy",
            text = "Fire chains burn damage across battles; Ice freezes opposing Plays for tempo; Steel stacks defensive layers. Mixed-weapon decks lose synergy bonuses — pick a primary and a secondary at deck-build.",
        ),
        LearnSection.WeaponSynergy(
            heading = "Plays that reward weapon focus",
            rows = listOf(
                LearnSection.WeaponSynergy.Row("FIRE",  listOf("Fire Boost", "Fire Crew", "Flame Wall", "Burning Fever", "Eternal Flame", "Smitty")),
                LearnSection.WeaponSynergy.Row("ICE",   listOf("Ice Boost", "Ice Crew", "Icy Shield", "Frozen Resolve", "Frozen Lineup", "Unbreakable Ice")),
                LearnSection.WeaponSynergy.Row("STEEL", listOf("Steel Boost", "Steel Crew", "Steel Defense", "Steel Shield", "Chrome Will", "Steel Cage")),
            ),
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
        LearnSection.CardExamples(
            heading = "Example Plays",
            description = "Tap any card to open its detail.",
            cardNames = listOf("Add Firepower", "First Draw", "Crystal Ball", "Frozen Resolve", "Steel Shield", "Forced Substitution"),
            playsOnly = true,
        ),
        LearnSection.Body(
            heading = "Resource management",
            text = "Bonus Plays are bounded (6 in Rookie, more with Hot Dogs). Don't blow your Bonus budget in Battles 1–2; the back half is where Bonus Plays compound. HD is its own resource — spending HD to win one Battle can cost you the next.",
        ),
        LearnSection.CardExamples(
            heading = "Hot Dogs",
            description = "Your 10-card resource pile. Always public; spent Hot Dogs go to Hot Dog Discard.",
            cardNames = listOf("Frank", "Grillbert"),
            hotDogsOnly = true,
        ),
        LearnSection.Callout(
            heading = "Picking an archetype to learn first",
            text = "Frozen Tempo is the most-forgiving entry point — it teaches Substitution as a strategic axis without locking you into one weapon. Brawl Beatdown is fast to win OR lose, so it skips a lot of game-state learning.",
            element = "ICE",
        ),
    )

    // ════════════════════════════════════════════════════════════════
    // ARCHETYPE TEMPLATES — port of iOS LearnView ArchetypesSection.
    // Five meta-informed archetype decks matching TemplateDeck.json
    // (DeckBuilderStore.swift metadata block, replaced 2026-04-28).
    // Rendered by LearnArticleScreen as expandable cards with key-play
    // thumbnails pulled from the live catalog.
    // ════════════════════════════════════════════════════════════════

    val archetypes: List<Archetype> = listOf(
        Archetype(
            id = "lockdown-locker",
            name = "Lockdown Locker",
            element = "STEEL",
            tagline = "Steel-anchored disruption; close mid-game with high-DBS lockouts",
            strategy = "60 STEEL Heroes (85–160 power) build hot-dog economy early, then pivot to Steel-stacked battles where lockout Plays end the round before your opponent can swing back. Teaches when to hold lockouts for late-battle swings rather than burning them on a bad matchup.",
            weakness = "Stain-Less-Steel · early aggro before lockouts come online",
            keyPlays = listOf("Molten Steel", "Frost-Hardened", "Frozen Resolve", "Hero Reset", "Crystal Ball", "Discard Rebate"),
        ),
        Archetype(
            id = "frozen-tempo",
            name = "Frozen Tempo",
            element = "ICE",
            tagline = "Ice synergy + substitution control + economy denial",
            strategy = "60 ICE Heroes (75–160 power) anchor a substitution-heavy game plan. Forced Substitution and Blind Substitution flip matchups; Icy Shield prevents your Heroes from being subbed out. Teaches Substitution as a strategic axis, not just a panic button.",
            weakness = "Ice Pick · Icevantage · opponents who don't substitute",
            keyPlays = listOf("Forced Substitution", "Blind Substitution", "Icy Shield", "Frozen Resolve", "Deep In The Playbook", "Hero Reset"),
        ),
        Archetype(
            id = "draw-and-adapt",
            name = "Draw and Adapt",
            element = "NONE",
            tagline = "Engine-first deck; maximum draw and situational answers",
            strategy = "12 Heroes each across FIRE / ICE / STEEL / GLOW / HEX gives you an answer for any matchup. The Plays package leans on draw, recovery, and lineup pressure rather than weapon synergy. Teaches how draw advantage compounds across 7 battles — every extra Play you see is leverage.",
            weakness = "No single dominant synergy; loses to focused weapon-stacks early",
            keyPlays = listOf("First Draw", "Crystal Ball", "Lineup Pressure", "Frozen Lineup", "Hero Reset", "Jump Ball"),
        ),
        Archetype(
            id = "glow-sacrifice",
            name = "Glow Sacrifice",
            element = "GLOW",
            tagline = "Discard-as-fuel + GLOW synergy + bonus-play toolbox",
            strategy = "60 GLOW Heroes (95–160 power) feed a discard engine that turns spent Plays into power. Flip & Glow and Glowaway recycle resources; Lost Plays punishes opponents who hoard. Built around the SPEC format constraints (≤160 power) where every discard counts as a tempo move.",
            weakness = "GLOW-counter Plays · empty hand mid-engine",
            keyPlays = listOf("Flip & Glow", "Glowaway", "Lost Plays", "Frozen Resolve", "Discard Rebate", "Hero Reset"),
        ),
        Archetype(
            id = "brawl-beatdown",
            name = "Brawl Beatdown",
            element = "BRAWL",
            tagline = "Aggro tempo. BRAWL/FIRE mix; win the first 3–4 battles",
            strategy = "30 BRAWL + 30 FIRE Heroes (80–160 power) front-load the curve. Add Firepower, Burn To Burn, and Banked Power push damage early; Flame Wall protects your tempo lead. Teaches tempo-aggro counter-strategy — you don't need to win all 7 battles, just the first four.",
            weakness = "Late-game stall · economy decks that survive the first wave",
            keyPlays = listOf("Add Firepower", "Burn To Burn", "Banked Power", "Fire Crew", "Flame Wall", "Molten Steel"),
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
            element = "GLOW",
        ),
        // Tick 209 — Discord-mined content. Set Ascension explains how
        // formats evolve as new sets release and old ones graduate into
        // legacy formats. Source: 2026-02-10 blog post "The BoBA Set
        // Ascension: How Heroes Progress Through the Arena".
        LearnSection.Body(
            heading = "Set Ascension — how formats evolve",
            text = "BoBA organizes play across three formats based on when cards released. Older sets don't fade — they ascend into legacy formats with their own competitive scene. The framework is intentional: 'time adds context and fond memories' so cards take on new identity over time.",
        ),
        LearnSection.Bullets(
            heading = "Three progression tiers",
            items = listOf(
                "Modern (Active Era) — cards from the past 2 years. Primary competitive format; best entry point for new players.",
                "Hall of Fame (Ascended Era) — cards released 2+ years ago (as of Jan 1). Larger pool, complex interactions; reserved for special high-skill events.",
                "AlphaTrilogy (Founders Era) — exclusively original Alpha-era cards (first year). Celebrated annually with dedicated events; Alpha cards also playable in Hall of Fame.",
            ),
        ),
        LearnSection.Callout(
            heading = "Alpha Battlefoils bridge the eras",
            text = "A special card type that lets newer players participate in Hall of Fame and AlphaTrilogy events without owning original Alpha cards. Connects the modern audience to the game's foundation.",
            element = "ICE",
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
        // Tick 229 — Set Ascension glossary terms (web tick 228 parity).
        // Picked up automatically by GlossaryAwareBody since it pulls
        // from LearnCorpus.glossaryGame.
        LearnSection.Term(term = "Set Ascension", definition = "BoBA's framework for organizing play across three formats based on when cards released. Older sets don't fade — they ascend into legacy formats. The three tiers are Modern (active era), Hall of Fame (ascended era), and AlphaTrilogy (founders era). See Learn → Collect for the full article."),
        LearnSection.Term(term = "Modern", definition = "The Active-Era format in BoBA's Set Ascension. Cards from the past 2 years. Primary competitive format; best entry point for new players. Where most gameplay happens."),
        LearnSection.Term(term = "Hall of Fame", definition = "The Ascended-Era format in BoBA's Set Ascension. Cards released 2+ years ago (as of January 1). Larger card pool with complex interactions; reserved for special, high-skill events. Emphasizes mastery over volume."),
        LearnSection.Term(term = "AlphaTrilogy", definition = "The Founders-Era format in BoBA's Set Ascension. Exclusively original Alpha-era cards (first year). Celebrated annually with dedicated events. Alpha cards are also playable in Hall of Fame — preserves BoBA's foundation."),
        LearnSection.Term(term = "Checklist", definition = "BoBA format where deck-building is restricted to a curated list of Plays (a Checklist). Each event publishes its own theme — high-offense, control, chaos, etc. Core mechanics stay identical; only the available card pool changes. Rewards creativity within constraints rather than finding the 'optimal' build."),
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
        // ─── Pro Tour intro ─────────────────────────────────────
        LearnSection.Callout(
            heading = "2026 PRO-TOUR",
            text = "$500,000+ Prize Pool. The 2026 World Championships at The National offers an estimated $500,000+ in total prizing, with up to $375,000+ available as cash payouts. APEX events are free to enter.",
        ),
        LearnSection.Body(
            heading = "You are a Coach",
            text = "As a Coach, you lead a squad of superheroes into battle. The Heroes bring the power; you bring the strategy. You decide the roster, call the Plays, and pick when to push or hold. Assistant Coaches are allowed in all events unless otherwise specified — a pairing to increase accessibility for younger Coaches or those with special needs.",
        ),

        // ─── Hero deck formats ──────────────────────────────────
        LearnSection.Body(
            heading = "Apex",
            text = "No power limit. Standard deck rules (max 6 Heroes per power). The open-power-cap division.",
        ),
        LearnSection.Body(
            heading = "Spec",
            text = "160 Power cap. Every Hero ≤ 160 Power. Standard deck rules (max 6 per power).",
        ),
        LearnSection.Body(
            heading = "Elite",
            text = "8,250 total power cap. Combined Power across all Heroes ≤ 8,250. Starter cards legal; Trainer cards NOT legal. Otherwise standard rules.",
        ),
        LearnSection.Body(
            heading = "SPEC+",
            text = "Up to 70 Heroes (tiered). 60 Heroes ≤ 160 Power (a full Spec deck), plus up to 10 optional higher-power Heroes with stacking limits.",
        ),
        LearnSection.Bullets(
            heading = "SPEC+ optional 10-slot overflow tiers",
            items = listOf(
                "165 Power · max 2 per deck",
                "170 Power · max 2 per deck",
                "175 Power · max 1 per deck",
                "180 Power · max 1 per deck",
                "185 Power · max 1 per deck",
                "190 Power · max 1 per deck",
                "195 Power · max 1 per deck",
                "200 Power · max 1 per deck",
                "No Heroes above 200 Power.",
            ),
        ),
        LearnSection.Callout(
            heading = null,
            text = "All Playmaker divisions are 1,000 DBS unless specified otherwise. Heroes can now appear unlimited times per deck (\"one-of\" still applies to an exact card).",
        ),

        // Tick 231 — Checklist Format explainer (Discord-mined from
        // 2026-03-27 blog post). Was referenced by the format-legality
        // chip strip + format dropdowns but never explained in Learn.
        LearnSection.Body(
            heading = "Checklist Format",
            text = "Build decks from a curated list of Plays — a Checklist. Each Checklist creates its own gameplay environment with themed restrictions: high-offense, control, chaos, weapon-focused, etc. Core BoBA mechanics stay identical; only the available card pool changes.",
        ),
        LearnSection.Bullets(
            heading = "What makes Checklist different",
            items = listOf(
                "Limited card pool — only Plays from the active Checklist are legal",
                "Theme-driven gameplay (offense / control / chaos / weapon-focused)",
                "Rotating or event-specific Checklists ensure variety",
                "Some overlooked Plays suddenly become stars within their environment",
                "Players answer 'how do I win in this environment?' rather than 'what's optimal?'",
            ),
        ),
        LearnSection.Callout(
            heading = "When Checklist fires",
            text = "Event-specific. Each tournament publishes its active Checklist with the event listing. The Checklist column in the per-card format-legality chip shows green when a card is generally legal under Checklist rules, but the actual event Checklist may exclude it — always check the event's announced Checklist.",
            element = "GLOW",
        ),

        // ─── Game modes ─────────────────────────────────────────
        LearnSection.Body(
            heading = "Rookie mode",
            text = "Reduced rule surface for new Coaches and demo events. Best-of-3 matches; no Substitution Window; no Coach card; no Double-Up. Keeps the game on rails for first-timers.",
        ),
        LearnSection.Body(
            heading = "Substitution mode",
            text = "Adds the Substitution Window (pay 2 Hot Dogs to swap the revealed Hero before Plays resolve) and 1 Coach card. Best-of-5 matches. The first format where reading your opponent matters.",
        ),
        LearnSection.Body(
            heading = "Playmaker mode",
            text = "Full BoBA rule surface. Best-of-7 matches. Adds Bonus Plays from Alpha Update / Griffey / specialty sets, the full DBS economy, and every persistent-effect scope.",
        ),

        // ─── Double-Up ──────────────────────────────────────────
        LearnSection.Body(
            heading = "Double-Up (Press / Fold)",
            text = "Optional betting mechanic any game mode can add. Each Coach gets one Press per game to double the game's point value; the opponent then Folds (ends the game) or Presses back, doubling again. A whole new \"Laundry Phase\" between battles for offering / accepting Presses.",
        ),

        // ─── Madness modes ─────────────────────────────────────
        LearnSection.Body(
            heading = "Madness — team play",
            text = "Apex & AlphaTrilogy pairs two coaches per team — one Apex deck + one AlphaTrilogy deck per side, with strict mid-match swap rules. HiLo pairs one Apex deck with one Rookie deck for handicapped play; the higher-skill coach takes Rookie.",
        ),

        // ─── Nationals divisions ───────────────────────────────
        LearnSection.Bullets(
            heading = "2026 Nationals divisions",
            items = listOf(
                "Apex — premier open division. No power cap. Standard deck rules.",
                "AlphaTrilogy — Alpha Edition + Alpha Update + Alpha Blast only.",
                "Granny's Gum — themed-foil only. Bubble Gum + Granny's Linoleum + Great Granny's.",
                "Brawl — single-weapon Brawl decks. Bo Jackson Battle Arena's heritage format.",
                "Tecmo Bowl — retro-themed format. Tecmo + Pixel art treatments only.",
                "Spec — single-weapon open. Pick your weapon and live with it for the event.",
            ),
        ),

        // ─── Match structure ───────────────────────────────────
        LearnSection.Bullets(
            heading = "Match structure",
            items = listOf(
                "Pools of 4 round-robin → top 2 advance from each pool",
                "Single elimination top 8 onward",
                "Score: 3 for win, 1 for draw, 0 for loss",
                "Tiebreakers: head-to-head → opponent match-win % → cumulative Power margin",
                "Best-of-N varies by mode: Rookie BO3 / Substitution BO5 / Playmaker BO7",
            ),
        ),

        // ─── Penalty reference ─────────────────────────────────
        LearnSection.Bullets(
            heading = "Penalty reference",
            items = listOf(
                "Slow play — warning → game loss on repeat",
                "Marked card — match loss",
                "Misrepresentation of deck contents — match loss + investigation",
                "Unsporting conduct — DQ from event",
                "Outside assistance during a match — game loss; repeat = match loss",
                "Tardiness > 10 min — game loss; > 20 min — match loss",
            ),
        ),

        LearnSection.Callout(
            heading = null,
            text = "The 2026 draft is marked NOT YET FINALIZED — check the official rules PDF for the current published version before any tournament.",
        ),
    )

}

package com.bobaplaybook.app.feature.learn

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Inventory
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Learn corpus — port of the iOS Learn-tab content.
 *
 * Each category contains one or more articles. Each article has skill-
 * level variants (Rookie / Substitution / Playmaker) per
 * ANDROID-DESIGN.md §8.2 (skill-level SegmentedButton scope).
 *
 * Content authored here intentionally — porting from iOS BoBALearn
 * data tables. The shape mirrors iOS so the cross-platform Glossary
 * lookup map can be a single source of truth when web parity ships.
 *
 * Reference: Game Rules/ comprehensive guide PDF at repo root.
 */

enum class LearnCategoryId(
    val title: String,
    val blurb: String,
    val icon: ImageVector,
) {
    RULES     ("Rules",      "Match flow, phases, win conditions",     Icons.Default.AutoStories),
    STRATEGY  ("Strategy",   "Archetype guides + matchups",            Icons.Default.Lightbulb),
    COLLECT   ("Collecting", "Sets, treatments, parallels, rarity",    Icons.Default.Inventory),
    GLOSSARY  ("Glossary",   "Every BoBA term in one place",           Icons.AutoMirrored.Filled.MenuBook),
    TOURNAMENT("Tournament", "Format rules, divisions, scoring",       Icons.Default.EmojiEvents),
    ;

    companion object {
        fun fromId(id: String): LearnCategoryId? = entries.firstOrNull { it.name.equals(id, ignoreCase = true) }
    }
}

enum class SkillLevel(val label: String) {
    ROOKIE      ("Rookie"),
    SUBSTITUTION("Substitution"),
    PLAYMAKER   ("Playmaker"),
}

data class LearnArticle(
    val id: String,
    val title: String,
    val categoryId: LearnCategoryId,
    val sections: Map<SkillLevel, List<LearnSection>>,
    /** Glossary terms this article highlights for [TooltipBox] lookup. */
    val glossaryTerms: List<String> = emptyList(),
)

/**
 * A section inside an article — either a paragraph of body text or a
 * bulleted list. Headings render as `BOBASectionHeader`.
 */
sealed interface LearnSection {
    val heading: String?
    data class Body(override val heading: String?, val text: String) : LearnSection
    data class Bullets(override val heading: String?, val items: List<String>) : LearnSection
    data class Callout(override val heading: String?, val text: String) : LearnSection
}

/**
 * Glossary entries — keyed by lowercased term so `TooltipBox` lookups
 * are O(1) and case-insensitive.
 */
data class GlossaryEntry(val term: String, val definition: String, val seeAlso: List<String> = emptyList())

/**
 * The full Learn corpus. Authored in-source so v1 ships without a
 * separate JSON pipeline. Migrate to JSON shared with iOS/web in v2
 * when the corpus grows past ~20 KB.
 */
object LearnCorpus {

    val articles: List<LearnArticle> = listOf(
        // ─── RULES ─────────────────────────────────────────────
        LearnArticle(
            id = "match-flow",
            title = "Match Flow",
            categoryId = LearnCategoryId.RULES,
            sections = mapOf(
                SkillLevel.ROOKIE to listOf(
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
                    LearnSection.Callout(
                        heading = null,
                        text = "Tip: an active Hero stays in for as long as they keep winning. Substitution happens between Battles, not during.",
                    ),
                ),
                SkillLevel.SUBSTITUTION to listOf(
                    LearnSection.Body(
                        heading = "Substitution math",
                        text = "Heroes can be subbed in or out at the Bench phase of any Battle after Battle 1. Your bench order matters — Heroes brought in later have less time to ramp up their persistent effects.",
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
                ),
                SkillLevel.PLAYMAKER to listOf(
                    LearnSection.Body(
                        heading = "Advanced match flow",
                        text = "At the Playmaker level, match flow is about reading the persistent-effect stack across battles. Track which 'rest_of_game' effects have installed (and from which Hero) so you can predict the late-Battle swing.",
                    ),
                    LearnSection.Body(
                        heading = "The pivot Battle",
                        text = "Battle 4 is structurally critical: if you're 2-1, winning Battle 4 closes the match in 2 more wins. If you're 1-2, losing Battle 4 means you need 3 in a row to recover. Plan your Hero economy around it.",
                    ),
                ),
            ),
            glossaryTerms = listOf("Hero", "Bench", "Play", "Bonus Play", "Persistent Effect", "Heroic Damage"),
        ),

        LearnArticle(
            id = "win-conditions",
            title = "Win Conditions",
            categoryId = LearnCategoryId.RULES,
            sections = mapOf(
                SkillLevel.ROOKIE to listOf(
                    LearnSection.Body(
                        heading = "How to win a Battle",
                        text = "The Hero with higher total Power at Resolve wins the Battle. Total Power = Hero's base Power + all Play modifiers + persistent-effect bonuses.",
                    ),
                    LearnSection.Body(
                        heading = "How to win a match",
                        text = "First to 4 Battles wins. A match cannot end in a tie — if Battle 7 ties, sudden-death rules apply (see Tournament reference).",
                    ),
                ),
                SkillLevel.SUBSTITUTION to listOf(
                    LearnSection.Bullets(
                        heading = "Auto-loss conditions",
                        items = listOf(
                            "Hero has Heroic Damage > 10 at Resolve — auto-loss (B.8)",
                            "Coach has no eligible Heroes left to send to Bench — concede",
                            "Both coaches reveal identical Plays in Battle 7 with tied Power — coin flip",
                        ),
                    ),
                ),
                SkillLevel.PLAYMAKER to listOf(
                    LearnSection.Body(
                        heading = "HD as a win condition",
                        text = "Smart Playmakers use Heroic Damage as offensive currency. If you can push the opponent's active Hero past 10 HD, you skip the Power calculation entirely (auto-loss for them).",
                    ),
                ),
            ),
            glossaryTerms = listOf("Heroic Damage", "Power", "Auto-loss"),
        ),

        // ─── STRATEGY ──────────────────────────────────────────
        LearnArticle(
            id = "deck-archetypes",
            title = "Deck Archetypes",
            categoryId = LearnCategoryId.STRATEGY,
            sections = mapOf(
                SkillLevel.ROOKIE to listOf(
                    LearnSection.Body(
                        heading = "The four archetypes",
                        text = "Most competitive decks fall into one of four shapes: Aggro, Control, Combo, or Midrange. Each balances Power, Cost, and persistent-effect tempo differently.",
                    ),
                    LearnSection.Bullets(
                        heading = "Quick guide",
                        items = listOf(
                            "Aggro — high Power, low Cost, fast Battles",
                            "Control — defensive Heroes + counter-Plays",
                            "Combo — chain persistent effects for compounding bonuses",
                            "Midrange — balanced; reactive to the meta",
                        ),
                    ),
                ),
                SkillLevel.SUBSTITUTION to listOf(
                    LearnSection.Body(
                        heading = "Picking an archetype to learn first",
                        text = "Midrange is the most-forgiving entry point — it teaches you the full state-machine without locking you into one playstyle. Aggro is fast to win OR lose, which makes it tempting but it skips a lot of game state learning.",
                    ),
                ),
                SkillLevel.PLAYMAKER to listOf(
                    LearnSection.Body(
                        heading = "Hybrid archetypes",
                        text = "Top tournament decks rarely live cleanly in one archetype. Aggro-Combo (fast pressure + a back-half compounding line) and Control-Midrange (defensive opener, midrange pivot at Battle 4) are the meta picks at the time of writing.",
                    ),
                ),
            ),
            glossaryTerms = listOf("Aggro", "Control", "Combo", "Midrange", "Persistent Effect"),
        ),

        // ─── COLLECTING ────────────────────────────────────────
        LearnArticle(
            id = "treatments-vs-parallels",
            title = "Treatments vs Parallels",
            categoryId = LearnCategoryId.COLLECT,
            sections = mapOf(
                SkillLevel.ROOKIE to listOf(
                    LearnSection.Body(
                        heading = "Two distinct concepts",
                        text = "Treatments are DIFFERENT WAYS the same card can be printed (Base Set, Battlefoil, Superfoil…). Parallels are ENTIRELY SEPARATE runs that share a format but have their own numbering (SideKicks, Plays, Bonus Plays…).",
                    ),
                    LearnSection.Bullets(
                        heading = "Common treatments",
                        items = listOf(
                            "Base Set — the standard print",
                            "Battlefoil — 7 color subsets (Red, Silver, Blue, Orange, Green, Pink, Bubble Gum)",
                            "Superfoil — premium variant",
                            "Inspired Ink — serialized; weapon-tied numbering (Hex /5, Glow /10, Fire /25, Ice /50)",
                        ),
                    ),
                    LearnSection.Bullets(
                        heading = "Common parallels",
                        items = listOf(
                            "Billy Cameo Alt Arts",
                            "SideKicks",
                            "Plays / Bonus Plays",
                            "Prize / Promos",
                            "Hot Dogs",
                        ),
                    ),
                ),
                SkillLevel.SUBSTITUTION to listOf(
                    LearnSection.Body(
                        heading = "Why this matters for trades",
                        text = "Collectors who don't separate Treatments from Parallels will undervalue Parallels (which are scarce by edition limit) and overvalue Treatments (which are scarce only at specific tier within a Treatment family).",
                    ),
                ),
                SkillLevel.PLAYMAKER to listOf(
                    LearnSection.Body(
                        heading = "Rarity by weapon",
                        text = "Inspired Ink (serialized) variants follow weapon tiers: Hex /5 → Glow /10 → Fire /25 → Ice /50. Hex Inspired Ink is the rarest serialized variant available for any given card.",
                    ),
                ),
            ),
            glossaryTerms = listOf("Treatment", "Parallel", "Battlefoil", "Superfoil", "Inspired Ink", "Hot Dog"),
        ),

        // ─── TOURNAMENT ────────────────────────────────────────
        LearnArticle(
            id = "tournament-format",
            title = "Tournament Format",
            categoryId = LearnCategoryId.TOURNAMENT,
            sections = mapOf(
                SkillLevel.ROOKIE to listOf(
                    LearnSection.Body(
                        heading = "Standard tournament rules",
                        text = "Tournament play uses the Standard Construction (8 Heroes / 30 Plays / 6 Bonus / 10 HD / 1 Coach), with a 4-card Sideboard and locked weapon distribution.",
                    ),
                ),
                SkillLevel.SUBSTITUTION to listOf(
                    LearnSection.Bullets(
                        heading = "Divisions + scoring",
                        items = listOf(
                            "Rookie (1000–1199) — open entry, best-of-3 matches",
                            "Substitution (1200–1399) — best-of-5 matches",
                            "Playmaker (1400+) — best-of-7 matches, double elimination",
                            "Score: 3 for win, 1 for draw, 0 for loss",
                        ),
                    ),
                ),
                SkillLevel.PLAYMAKER to listOf(
                    LearnSection.Body(
                        heading = "Sideboard usage",
                        text = "Sideboard cards swap in between games of a best-of-N match — never mid-game. Common picks: 1 anti-archetype Coach + 3 counter-Plays that target the most-likely opposing archetype.",
                    ),
                ),
            ),
        ),
    )

    val glossary: Map<String, GlossaryEntry> = listOf(
        GlossaryEntry("Hero", "A card you field in a Battle. Has Power, Weapon, persistent effects, and (for some) HD damage capacity."),
        GlossaryEntry("Bench", "Your active 3-Hero rotation for the current Battle. Sub between Battles to swap which Heroes are available."),
        GlossaryEntry("Play", "A card that modifies Power or triggers a persistent effect during the Plays phase of a Battle."),
        GlossaryEntry("Bonus Play", "A Play with a Cost > 0. Cap at 7 in standard decks; Hot Dog parallel slot beyond 7."),
        GlossaryEntry("Persistent Effect", "A scoped modifier installed by a Play. Scopes: this_battle, next_battle, rest_of_game, etc."),
        GlossaryEntry("Heroic Damage", "Damage applied to an active Hero. > 10 = auto-loss at Resolve (B.8)."),
        GlossaryEntry("Power", "Base score of a Hero. Modified by Plays + persistent effects. Highest total at Resolve wins the Battle."),
        GlossaryEntry("Treatment", "A print variant of a single card (Base, Battlefoil, Superfoil, Inspired Ink, themed foils, etc.)."),
        GlossaryEntry("Parallel", "An entirely separate card run that shares format but has its own numbering (SideKicks, Plays, Prize/Promos, Hot Dogs)."),
        GlossaryEntry("Battlefoil", "Treatment family with 7 color subsets: Red, Silver, Blue, Orange, Green, Pink, Bubble Gum."),
        GlossaryEntry("Superfoil", "Premium treatment variant. Rare across most sets."),
        GlossaryEntry("Inspired Ink", "Serialized treatment. Weapon-tied print runs: Hex /5, Glow /10, Fire /25, Ice /50."),
        GlossaryEntry("Hot Dog", "Parallel slot allowing >7 Bonus Plays in a deck. Distinguished by Hot Dog parallel art."),
        GlossaryEntry("Aggro", "Deck archetype prioritizing high-Power, low-Cost Heroes for fast Battle wins."),
        GlossaryEntry("Control", "Deck archetype focused on counter-Plays and defensive persistent effects."),
        GlossaryEntry("Combo", "Deck archetype that chains persistent effects for compounding bonuses."),
        GlossaryEntry("Midrange", "Deck archetype with balanced Power and reactive Plays."),
        GlossaryEntry("Auto-loss", "Conditions that end a Battle without comparing Power — most commonly Heroic Damage > 10."),
    ).associateBy { it.term.lowercase() }

    fun articlesIn(category: LearnCategoryId): List<LearnArticle> =
        articles.filter { it.categoryId == category }

    fun findArticle(id: String): LearnArticle? = articles.firstOrNull { it.id == id }
}

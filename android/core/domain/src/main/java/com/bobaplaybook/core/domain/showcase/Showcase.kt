package com.bobaplaybook.core.domain.showcase

import com.bobaplaybook.core.domain.model.Card

/**
 * Showcase — a named subset of the catalog. Mirrors iOS
 * `BOBAPlaybook/Models/Showcase.swift` verbatim so the cross-
 * platform behavior is identical.
 *
 * Three call sites:
 *  - Find FilterSheet "Showcase" picker
 *  - Find featured-ribbons no-search state
 *  - Search-bar smart-match (typing "WoBA" → narrows automatically)
 */
data class Showcase(
    val id: String,
    val name: String,
    /** Lowercase tokens that resolve to this showcase from the search bar. */
    val searchTokens: List<String>,
    val description: String,
    val countLabel: String,
    val match: (Card) -> Boolean,
)

object Showcases {

    // ─── WoBA — Women of BoBA ──────────────────────────────────
    val wobaHeroes: Set<String> = setOf(
        "AJax", "Belladonna", "Brandi", "C.C.", "Cameleon", "Cheryl Bomb",
        "Coopanova", "Eraser", "Halo", "JPEG", "Lady Magic", "Leducky",
        "PB Buckets", "Pauldron", "Peek-A-Boo", "Ramponage", "Swoopes",
    )

    val woba = Showcase(
        id = "woba",
        name = "WoBA (Women of BoBA)",
        searchTokens = listOf("woba", "women of boba", "women"),
        description = "Women of BOBA — heroes inspired by legendary female athletes across every sport.",
        countLabel = "884 cards",
    ) { card -> card.hero in wobaHeroes }

    // ─── Rookie Inspired ───────────────────────────────────────
    val rookieInspired = Showcase(
        id = "rookie_inspired",
        name = "Rookie Inspired",
        searchTokens = listOf("rookie", "rookie inspired", "rookies"),
        description = "Cards whose hero is inspired by an athlete in their rookie season at print time.",
        countLabel = "2,733 cards",
    ) { card -> card.rookieInspired }

    // ─── BoBA-team-curated Featured Collections ────────────────
    // Mirrors iOS BrowseFeaturedData.collections (Bo Jackson, Ken Griffey
    // Jr., Dr. J). Each is a hand-picked filter the design team flagged
    // as "worth surfacing on the explore tab."
    val bojax = Showcase(
        id = "bojax",
        name = "Bo Jackson",
        searchTokens = listOf("bo jackson", "bojax"),
        description = "The man who inspired it all — every BoJax card across every set and treatment.",
        countLabel = "147 cards",
    ) { card ->
        card.athleteInspiration == "Bo Jackson" ||
            card.hero == "BoJax" || card.hero == "Bojax"
    }

    val kenGriffeyJr = Showcase(
        id = "kid",
        name = "Ken Griffey Jr.",
        searchTokens = listOf("ken griffey", "griffey", "the kid"),
        description = "The Kid — one of baseball's most beloved players.",
        countLabel = "~76 cards",
    ) { card ->
        card.athleteInspiration == "Ken Griffey Jr." || card.hero == "The Kid"
    }

    val drJ = Showcase(
        id = "drj",
        name = "Dr. J",
        searchTokens = listOf("dr j", "dr. j", "julius erving"),
        description = "Julius Erving — the original aerial artist of basketball.",
        countLabel = "70 cards",
    ) { card ->
        card.athleteInspiration == "Julius Erving" || card.hero == "Dr. J"
    }

    // ─── Sport showcases ───────────────────────────────────────
    private val basketball = setOf(
        "LeBron James", "Lebron James", "Steph Curry", "Kevin Durant",
        "Giannis Antetokounmpo", "Giannis Anteokounmpo", "Giannis Antetetokounmpo",
        "Nikola Jokic", "Luka Doncic", "Cooper Flagg", "Paige Bueckers",
        "Julius Erving", "Magic Johnson", "Allen Iverson", "Kawhi Leonard",
        "Ja Morant", "Jayson Tatum", "Jason Tatum", "Caitlin Clark",
        "Angel Reese", "A'ja Wilson", "Cynthia Cooper", "Cheryl Miller",
        "Sheryl Swoopes", "Nancy Lieberman", "Elena Delle Donne",
        "Devin Booker", "Anthony Edwards", "Damian Lillard",
    )
    private val football = setOf(
        "Patrick Mahomes", "Josh Allen", "Lamar Jackson", "Travis Kelce",
        "Bo Jackson", "Barry Sanders", "Adrian Peterson", "Derrick Henry",
        "Justin Jefferson", "Joe Burrow", "Justin Herbert", "CJ Stroud",
        "Caleb Williams", "Jordan Love", "Aaron Rodgers", "Saquan Barkley",
        "Christian McCaffrey", "Christian McCaffery", "Tyreek Hill",
        "Travis Hunter", "Dak Prescott", "Jalen Hurts", "Jayden Daniels",
    )
    private val baseball = setOf(
        "Ken Griffey Jr.", "Ken Griffey Sr.", "Shohei Ohtani", "Aaron Judge",
        "Mike Trout", "Mookie Betts", "Juan Soto", "Bo Jackson",
        "Ronald Acuna Jr.", "Fernando Tatis Jr.", "Fernando Tatís Jr.",
        "Vladimir Guerrero Jr.", "Julio Rodriguez", "Jackson Holliday",
        "Paul Skenes", "Rafael Devers", "Bobby Witt Jr", "Bobby Witt Jr.",
        "Elly De La Cruz", "Gunnar Henderson", "Corbin Carroll", "Jackson Chourio",
    )
    private val hockey = setOf(
        "Connor McDavid", "Nathan MacKinnon", "Sidney Crosby", "Alexander Ovechkin",
        "Wayne Gretzky", "Mario Lemieux", "Auston Matthews", "Henrik Lundqvist",
    )
    private val soccer = setOf(
        "Lionel Messi", "Cristiano Ronaldo", "Kylian Mbappe", "Erling Haaland",
        "Brandi Chastain", "Chastain", "Christie Pearce Rampone", "Jozy Altidore",
    )
    private val boxing = setOf(
        "Floyd Mayweather Jr.", "Muhammad Ali", "Manny Pacquiao", "Sugar Ray Robinson",
    )
    // Smaller iOS-parity sports — added 2026-05-19 to match
    // BrowseFeaturedData.sports verbatim.
    private val tennis = setOf("Jessica Pegula", "Paula Badosa")
    private val golf = setOf("Bryson DeChambeau", "Jordan Spieth")

    val sportAthletes: List<Pair<String, Set<String>>> = listOf(
        "Basketball" to basketball,
        "Football"   to football,
        "Baseball"   to baseball,
        "Hockey"     to hockey,
        "Soccer"     to soccer,
        "Boxing"     to boxing,
        "Tennis"     to tennis,
        "Golf"       to golf,
    )

    val sports: List<Showcase> = sportAthletes.map { (sport, athletes) ->
        Showcase(
            id = "sport_${sport.lowercase()}",
            name = sport,
            searchTokens = listOf(sport.lowercase()),
            description = "$sport heroes — players whose card art is inspired by athletes in $sport.",
            countLabel = "—",
        ) { card -> card.athleteInspiration?.let { it in athletes } ?: false }
    }

    val all: List<Showcase> = listOf(
        woba, bojax, kenGriffeyJr, drJ, rookieInspired,
    ) + sports

    fun byId(id: String): Showcase? = all.firstOrNull { it.id == id }

    fun matching(searchToken: String): Showcase? {
        val needle = searchToken.lowercase().trim()
        if (needle.isEmpty()) return null
        return all.firstOrNull { showcase ->
            showcase.searchTokens.any { it == needle }
        }
    }
}

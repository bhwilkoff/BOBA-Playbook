package com.bobaplaybook.app.feature.find

import androidx.compose.ui.graphics.Color
import com.bobaplaybook.core.domain.model.Card
import com.bobaplaybook.core.ui.theme.BobaBrand

/**
 * Designer-curated featured-collection data. Mirrors iOS
 * `BrowseFeaturedData.swift` verbatim — extend in lockstep.
 *
 * Three flavors:
 *  - Featured Collections (hand-curated cross-cuts: WoBA, Bo Jackson,
 *    Ken Griffey Jr., Dr. J)
 *  - Weapon-type filter chips (8 elements)
 *  - Sport filter chips (athlete name lists per sport)
 */
object BrowseFeaturedData {

    data class FeaturedCollection(
        val id: String,
        val name: String,
        val description: String,
        val countLabel: String,
        val color: Color,
        val matches: (Card) -> Boolean,
    )

    val collections: List<FeaturedCollection> = listOf(
        FeaturedCollection(
            id = "woba",
            name = "WoBA",
            description = "Women of BOBA — heroes inspired by 17 legendary female athletes across every sport.",
            countLabel = "884 cards",
            color = Color(0xFFFF69B4),
        ) { card ->
            val heroes = setOf(
                "AJax", "Belladonna", "Brandi", "C.C.", "Cameleon", "Cheryl Bomb",
                "Coopanova", "Eraser", "Halo", "JPEG", "Lady Magic", "Leducky",
                "PB Buckets", "Pauldron", "Peek-A-Boo", "Ramponage", "Swoopes",
            )
            card.hero in heroes
        },
        FeaturedCollection(
            id = "bojax",
            name = "Bo Jackson",
            description = "The man who inspired it all — every BoJax card across every set and treatment.",
            countLabel = "147 cards",
            color = BobaBrand.Orange,
        ) { card ->
            card.athleteInspiration == "Bo Jackson" || card.hero == "BoJax" || card.hero == "Bojax"
        },
        FeaturedCollection(
            id = "kid",
            name = "Ken Griffey Jr.",
            description = "The Kid — one of baseball's most beloved players.",
            countLabel = "~76 cards",
            color = BobaBrand.Cyan,
        ) { card ->
            card.athleteInspiration == "Ken Griffey Jr." || card.hero == "The Kid"
        },
        FeaturedCollection(
            id = "drj",
            name = "Dr. J",
            description = "Julius Erving — the original aerial artist of basketball.",
            countLabel = "70 cards",
            color = Color(0xFF8B00FF),
        ) { card ->
            card.athleteInspiration == "Julius Erving" || card.hero == "Dr. J"
        },
    )

    val weapons: List<Pair<String, String>> = listOf(
        "FIRE" to "Fire",
        "ICE" to "Ice",
        "STEEL" to "Steel",
        "BRAWL" to "Brawl",
        "GLOW" to "Glow",
        "HEX" to "Hex",
        "GUM" to "Gum",
        "SUPER" to "Super",
    )

    data class SportShelf(val label: String, val athletes: Set<String>)

    val sports: List<SportShelf> = listOf(
        SportShelf("Basketball", setOf(
            "LeBron James", "Lebron James", "Steph Curry", "Kevin Durant", "Giannis Antetokounmpo",
            "Giannis Anteokounmpo", "Giannis Antetetokounmpo", "Nikola Jokic", "Luka Doncic",
            "Cooper Flagg", "Paige Bueckers", "Julius Erving", "Magic Johnson", "Allen Iverson",
            "Kawhi Leonard", "Ja Morant", "Jayson Tatum", "Jason Tatum", "Caitlin Clark",
            "Angel Reese", "A'ja Wilson", "Cynthia Cooper", "Cheryl Miller", "Sheryl Swoopes",
            "Nancy Lieberman", "Elena Delle Donne", "Devin Booker", "Anthony Edwards", "Damian Lillard",
        )),
        SportShelf("Football", setOf(
            "Patrick Mahomes", "Josh Allen", "Lamar Jackson", "Travis Kelce", "Bo Jackson",
            "Barry Sanders", "Adrian Peterson", "Derrick Henry", "Justin Jefferson", "Joe Burrow",
            "Justin Herbert", "CJ Stroud", "Caleb Williams", "Jordan Love", "Aaron Rodgers",
            "Saquan Barkley", "Christian McCaffrey", "Christian McCaffery", "Tyreek Hill",
            "Travis Hunter", "Dak Prescott", "Jalen Hurts", "Jayden Daniels",
        )),
        SportShelf("Baseball", setOf(
            "Ken Griffey Jr.", "Ken Griffey Sr.", "Shohei Ohtani", "Aaron Judge", "Mike Trout",
            "Mookie Betts", "Juan Soto", "Bo Jackson", "Ronald Acuna Jr.", "Fernando Tatis Jr.",
            "Fernando Tatís Jr.", "Vladimir Guerrero Jr.", "Julio Rodriguez", "Jackson Holliday",
            "Paul Skenes", "Rafael Devers", "Bobby Witt Jr", "Bobby Witt Jr.", "Elly De La Cruz",
            "Gunnar Henderson", "Corbin Carroll", "Jackson Chourio",
        )),
        SportShelf("Hockey", setOf("Sidney Crosby", "Alexander Ovechkin", "Henrik Lundqvist")),
        SportShelf("Tennis", setOf("Jessica Pegula", "Paula Badosa")),
        SportShelf("Golf", setOf("Bryson DeChambeau", "Jordan Spieth")),
        SportShelf("Soccer", setOf("Brandi Chastain", "Chastain", "Christie Pearce Rampone", "Jozy Altidore")),
    )
}

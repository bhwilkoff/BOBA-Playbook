import Foundation

// MARK: - Showcase
//
// A named subset of the catalog — "WOBA" (Women of BOBA), each sport
// (Basketball / Football / Baseball / …), and eventually team-specific
// or user-defined curations. Used in three places:
//
//   • Find tab filter sheet — "Showcase" section under Card Type
//   • Learn > Browse tab — the same set of chips already lived here
//   • Search bar smart-match — typing "WOBA" or "Baseball" narrows to
//     the matching showcase without opening the filter sheet
//
// Keep all showcase definitions in this file so the three surfaces
// stay in sync without per-view duplication.

struct Showcase: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Lowercase tokens that should resolve to this showcase when
    /// typed in the search bar. e.g. ["woba", "women of boba"].
    let searchTokens: [String]
    /// Short line shown beneath the chip label when hovered / in the
    /// Learn > Browse section.
    let description: String
    /// Approximate card count used for chip subtitles. Kept as a string
    /// since several showcases are compound sets whose exact count
    /// shifts as the catalog grows.
    let countLabel: String
    let match: @Sendable (Card) -> Bool

    static func == (l: Showcase, r: Showcase) -> Bool { l.id == r.id }
}

enum Showcases {

    // MARK: - WOBA

    /// Women of BOBA — every hero inspired by one of the 17 canonical
    /// women-in-sport athletes. Sourced from DISCORD_TERMINOLOGY.md §3
    /// + the roster posted to the trade channel.
    ///
    /// `nonisolated` on every static here because Swift 6 infers
    /// MainActor isolation on type-level statics in this module, and
    /// the `Showcase.match` closure is `@Sendable` — capturing a
    /// MainActor-isolated Set<String> inside a Sendable closure trips
    /// the compiler. Set<String> is inherently Sendable (immutable
    /// value type), so opting out of isolation is safe.
    nonisolated static let wobaHeroes: Set<String> = [
        "AJax", "Belladonna", "Brandi", "C.C.", "Cameleon", "Cheryl Bomb",
        "Coopanova", "Eraser", "Halo", "JPEG", "Lady Magic", "Leducky",
        "PB Buckets", "Pauldron", "Peek-A-Boo", "Ramponage", "Swoopes",
    ]

    nonisolated static let woba = Showcase(
        id: "woba",
        name: "WOMEN OF BOBA (WOBA)",
        searchTokens: ["woba", "women of boba", "women"],
        description: "Women of BOBA — heroes inspired by legendary female athletes across every sport.",
        countLabel: "884 cards"
    ) { card in
        Showcases.wobaHeroes.contains(card.hero)
    }

    // MARK: - Sports

    /// Sport → canonical athleteInspiration list. Keep the lists
    /// permissive — catalog spelling variants (McCaffrey/McCaffery,
    /// Tatis/Tatís) are already normalized in cards.json but we keep
    /// both spellings here in case a rogue variant slips through.
    nonisolated static let sportAthletes: [(label: String, athletes: Set<String>)] = [
        ("Basketball", ["LeBron James","Lebron James","Steph Curry","Kevin Durant",
                        "Giannis Antetokounmpo","Giannis Anteokounmpo","Giannis Antetetokounmpo",
                        "Nikola Jokic","Luka Doncic","Cooper Flagg","Paige Bueckers",
                        "Julius Erving","Magic Johnson","Allen Iverson","Kawhi Leonard",
                        "Ja Morant","Jayson Tatum","Jason Tatum","Caitlin Clark",
                        "Angel Reese","A'ja Wilson","Cynthia Cooper","Cheryl Miller",
                        "Sheryl Swoopes","Nancy Lieberman","Elena Delle Donne",
                        "Devin Booker","Anthony Edwards","Damian Lillard"]),
        ("Football",   ["Patrick Mahomes","Josh Allen","Lamar Jackson","Travis Kelce",
                        "Bo Jackson","Barry Sanders","Adrian Peterson","Derrick Henry",
                        "Justin Jefferson","Joe Burrow","Justin Herbert","CJ Stroud",
                        "Caleb Williams","Jordan Love","Aaron Rodgers","Saquan Barkley",
                        "Christian McCaffrey","Christian McCaffery","Tyreek Hill",
                        "Travis Hunter","Dak Prescott","Jalen Hurts","Jayden Daniels"]),
        ("Baseball",   ["Ken Griffey Jr.","Ken Griffey Sr.","Shohei Ohtani","Aaron Judge",
                        "Mike Trout","Mookie Betts","Juan Soto","Bo Jackson",
                        "Ronald Acuna Jr.","Fernando Tatis Jr.","Fernando Tatís Jr.",
                        "Vladimir Guerrero Jr.","Julio Rodriguez","Jackson Holliday",
                        "Paul Skenes","Rafael Devers","Bobby Witt Jr","Bobby Witt Jr.",
                        "Elly De La Cruz","Gunnar Henderson","Corbin Carroll","Jackson Chourio"]),
        ("Hockey",     ["Sidney Crosby","Alexander Ovechkin","Henrik Lundqvist"]),
        ("Tennis",     ["Jessica Pegula","Paula Badosa"]),
        ("Golf",       ["Bryson DeChambeau","Jordan Spieth"]),
        ("Soccer",     ["Brandi Chastain","Chastain","Christie Pearce Rampone","Jozy Altidore"]),
    ]

    /// Materialized Showcase list for every sport above. Generated once
    /// and cached so the three consuming surfaces share the same
    /// instances.
    nonisolated static let sports: [Showcase] = sportAthletes.map { entry in
        let athletes = entry.athletes
        return Showcase(
            id: "sport_\(entry.label.lowercased())",
            name: entry.label,
            searchTokens: [entry.label.lowercased()],
            description: "\(entry.label) athletes and their inspired heroes.",
            countLabel: ""
        ) { card in
            guard let insp = card.athleteInspiration else { return false }
            return athletes.contains(insp)
        }
    }

    // MARK: - Catalog

    /// All showcases visible as filter chips / searchable terms, in the
    /// order they should appear. New community or team-specific
    /// showcases (Cardinals, Red Sox, etc.) slot in here.
    nonisolated static let all: [Showcase] = [woba] + sports

    /// Look up a showcase by its id.
    static func byId(_ id: String) -> Showcase? {
        all.first { $0.id == id }
    }

    /// Resolve a raw search term (lowercase) to a showcase — used by the
    /// smart search path.
    static func matching(searchToken: String) -> Showcase? {
        let needle = searchToken.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }
        return all.first { $0.searchTokens.contains(needle) }
    }
}

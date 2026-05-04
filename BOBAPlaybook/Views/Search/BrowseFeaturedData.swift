//
//  BrowseFeaturedData.swift
//  BOBAPlaybook
//
//  Designer-curated featured-collection data extracted from the
//  legacy LearnView.BrowseView (deleted as part of the DESIGN.md
//  §8.1 Browse → Find migration). The Find tab rebuild will consume
//  these constants when assembling its featured ribbons.
//
//  Owners: extend the lists here as new featured collections are
//  curated. Don't fork into per-view literals — both legacy access
//  paths (Browse → grid) and the new Find ribbons read from these.
//

import SwiftUI

enum BrowseFeaturedData {

    // MARK: - Featured collections

    /// Single curated collection definition. `matches` is a predicate
    /// over Card so the data file doesn't need to know catalog
    /// internals.
    struct Collection: Identifiable, Equatable {
        let id: String
        let name: String
        let description: String
        let countLabel: String
        let color: Color
        let matches: (Card) -> Bool

        static func == (l: Collection, r: Collection) -> Bool { l.id == r.id }
    }

    /// Hand-curated Featured Collections — currently four (WOBA, Bo
    /// Jackson, Ken Griffey Jr., Dr. J). Each row is a single
    /// hand-picked filter the BoBA design team flagged as "worth
    /// surfacing on the explore tab."
    static let collections: [Collection] = [
        Collection(
            id: "woba",
            name: "WOBA",
            description: "Women of BOBA — heroes inspired by 17 legendary female athletes across every sport.",
            countLabel: "884 cards",
            color: Color(hex: "FF69B4")
        ) { card in
            let heroes: Set<String> = [
                "AJax","Belladonna","Brandi","C.C.","Cameleon","Cheryl Bomb",
                "Coopanova","Eraser","Halo","JPEG","Lady Magic","Leducky",
                "PB Buckets","Pauldron","Peek-A-Boo","Ramponage","Swoopes"
            ]
            return heroes.contains(card.hero)
        },
        Collection(
            id: "bojax",
            name: "Bo Jackson",
            description: "The man who inspired it all — every BoJax card across every set and treatment.",
            countLabel: "147 cards",
            color: Design.Colors.bobaOrange
        ) { card in
            card.athleteInspiration == "Bo Jackson" || card.hero == "BoJax" || card.hero == "Bojax"
        },
        Collection(
            id: "kid",
            name: "Ken Griffey Jr.",
            description: "The Kid — one of baseball's most beloved players.",
            countLabel: "~76 cards",
            color: Design.Colors.bobaCyan
        ) { card in
            card.athleteInspiration == "Ken Griffey Jr." || card.hero == "The Kid"
        },
        Collection(
            id: "drj",
            name: "Dr. J",
            description: "Julius Erving — the original aerial artist of basketball.",
            countLabel: "70 cards",
            color: Color(hex: "8B00FF")
        ) { card in
            card.athleteInspiration == "Julius Erving" || card.hero == "Dr. J"
        }
    ]

    // MARK: - Weapon-type filter chips

    /// Every weapon type with its display label. Card.element is
    /// always uppercase per CLAUDE.md; `label` is the mixed-case
    /// render form.
    static let weapons: [(element: String, label: String)] = [
        ("FIRE",  "Fire"),
        ("ICE",   "Ice"),
        ("STEEL", "Steel"),
        ("BRAWL", "Brawl"),
        ("GLOW",  "Glow"),
        ("HEX",   "Hex"),
        ("GUM",   "Gum"),
        ("SUPER", "Super"),
    ]

    // MARK: - Sport filter chips

    /// Athletes grouped by sport for the "By Sport" ribbon. Each entry
    /// is the sport's display name plus the set of `card.athleteInspiration`
    /// strings whose hero counts under that sport. Multi-sport
    /// athletes (Bo Jackson) appear in more than one set deliberately.
    static let sports: [(label: String, athletes: Set<String>)] = [
        ("Basketball", [
            "LeBron James","Lebron James","Steph Curry","Kevin Durant","Giannis Antetokounmpo",
            "Giannis Anteokounmpo","Giannis Antetetokounmpo","Nikola Jokic","Luka Doncic",
            "Cooper Flagg","Paige Bueckers","Julius Erving","Magic Johnson","Allen Iverson",
            "Kawhi Leonard","Ja Morant","Jayson Tatum","Jason Tatum","Caitlin Clark",
            "Angel Reese","A'ja Wilson","Cynthia Cooper","Cheryl Miller","Sheryl Swoopes",
            "Nancy Lieberman","Elena Delle Donne","Devin Booker","Anthony Edwards","Damian Lillard"
        ]),
        ("Football", [
            "Patrick Mahomes","Josh Allen","Lamar Jackson","Travis Kelce","Bo Jackson",
            "Barry Sanders","Adrian Peterson","Derrick Henry","Justin Jefferson","Joe Burrow",
            "Justin Herbert","CJ Stroud","Caleb Williams","Jordan Love","Aaron Rodgers",
            "Saquan Barkley","Christian McCaffrey","Christian McCaffery","Tyreek Hill",
            "Travis Hunter","Dak Prescott","Jalen Hurts","Jayden Daniels"
        ]),
        ("Baseball", [
            "Ken Griffey Jr.","Ken Griffey Sr.","Shohei Ohtani","Aaron Judge","Mike Trout",
            "Mookie Betts","Juan Soto","Bo Jackson","Ronald Acuna Jr.","Fernando Tatis Jr.",
            "Fernando Tatís Jr.","Vladimir Guerrero Jr.","Julio Rodriguez","Jackson Holliday",
            "Paul Skenes","Rafael Devers","Bobby Witt Jr","Bobby Witt Jr.","Elly De La Cruz",
            "Gunnar Henderson","Corbin Carroll","Jackson Chourio"
        ]),
        ("Hockey",  ["Sidney Crosby","Alexander Ovechkin","Henrik Lundqvist"]),
        ("Tennis",  ["Jessica Pegula","Paula Badosa"]),
        ("Golf",    ["Bryson DeChambeau","Jordan Spieth"]),
        ("Soccer",  ["Brandi Chastain","Chastain","Christie Pearce Rampone","Jozy Altidore"]),
    ]
}

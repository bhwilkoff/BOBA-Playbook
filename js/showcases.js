/* Showcases — curated subsets of the catalog shared by iOS and web.
 * Mirror of BOBAPlaybook/Models/Showcase.swift; keep the two in sync
 * when adding new showcases (team / city / custom) so the Find tab
 * filter chips + smart-search tokens behave identically across
 * platforms. Each entry has a `match(card)` predicate used by
 * computeResults() in js/app.js.
 */
(function() {
  'use strict';

  const WOBA_HEROES = new Set([
    "AJax", "Belladonna", "Brandi", "C.C.", "Cameleon", "Cheryl Bomb",
    "Coopanova", "Eraser", "Halo", "JPEG", "Lady Magic", "Leducky",
    "PB Buckets", "Pauldron", "Peek-A-Boo", "Ramponage", "Swoopes",
  ]);

  const SPORT_ATHLETES = {
    "Basketball": new Set([
      "LeBron James","Lebron James","Steph Curry","Kevin Durant",
      "Giannis Antetokounmpo","Giannis Anteokounmpo","Giannis Antetetokounmpo",
      "Nikola Jokic","Luka Doncic","Cooper Flagg","Paige Bueckers",
      "Julius Erving","Magic Johnson","Allen Iverson","Kawhi Leonard",
      "Ja Morant","Jayson Tatum","Jason Tatum","Caitlin Clark",
      "Angel Reese","A'ja Wilson","Cynthia Cooper","Cheryl Miller",
      "Sheryl Swoopes","Nancy Lieberman","Elena Delle Donne",
      "Devin Booker","Anthony Edwards","Damian Lillard",
    ]),
    "Football": new Set([
      "Patrick Mahomes","Josh Allen","Lamar Jackson","Travis Kelce",
      "Bo Jackson","Barry Sanders","Adrian Peterson","Derrick Henry",
      "Justin Jefferson","Joe Burrow","Justin Herbert","CJ Stroud",
      "Caleb Williams","Jordan Love","Aaron Rodgers","Saquan Barkley",
      "Christian McCaffrey","Christian McCaffery","Tyreek Hill",
      "Travis Hunter","Dak Prescott","Jalen Hurts","Jayden Daniels",
    ]),
    "Baseball": new Set([
      "Ken Griffey Jr.","Ken Griffey Sr.","Shohei Ohtani","Aaron Judge",
      "Mike Trout","Mookie Betts","Juan Soto","Bo Jackson",
      "Ronald Acuna Jr.","Fernando Tatis Jr.","Fernando Tatís Jr.",
      "Vladimir Guerrero Jr.","Julio Rodriguez","Jackson Holliday",
      "Paul Skenes","Rafael Devers","Bobby Witt Jr","Bobby Witt Jr.",
      "Elly De La Cruz","Gunnar Henderson","Corbin Carroll","Jackson Chourio",
    ]),
    "Hockey": new Set(["Sidney Crosby","Alexander Ovechkin","Henrik Lundqvist"]),
    "Tennis": new Set(["Jessica Pegula","Paula Badosa"]),
    "Golf":   new Set(["Bryson DeChambeau","Jordan Spieth"]),
    "Soccer": new Set(["Brandi Chastain","Chastain","Christie Pearce Rampone","Jozy Altidore"]),
  };

  const showcases = [
    {
      id: "woba",
      name: "WoBA (Women of BoBA)",
      searchTokens: ["woba", "women of boba", "women"],
      description: "Women of BOBA — heroes inspired by legendary female athletes.",
      match: (card) => WOBA_HEROES.has(card.hero),
    },
    ...Object.entries(SPORT_ATHLETES).map(([label, athletes]) => ({
      id: `sport_${label.toLowerCase()}`,
      name: label,
      searchTokens: [label.toLowerCase()],
      description: `${label} athletes and their inspired heroes.`,
      match: (card) => card.athleteInspiration && athletes.has(card.athleteInspiration),
    })),
  ];

  window.Showcases = {
    all: showcases,
    byId: (id) => showcases.find((s) => s.id === id) || null,
    matching: (token) => {
      const needle = String(token || "").trim().toLowerCase();
      if (!needle) return null;
      return showcases.find((s) => s.searchTokens.includes(needle)) || null;
    },
  };
})();

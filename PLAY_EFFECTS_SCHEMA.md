# Play Effects Schema — `play-effects.json`

A canonical, hand-authored table of every Play card's effect, keyed by `bobaId`. Shared across web and iOS so one source drives the practice battle engine, deck builder evaluation, and any future view that needs to reason about Play behavior.

**Location:** `assets/data/play-effects.json` (web) + mirrored into `BOBAPlaybook/` for iOS bundle (same protocol as `cards.json`).

**Scope:** ~383 unique Play names across 505 Play rows. Keying by `bobaId` lets us handle reprints, typo variants, or rare printings that share a name but diverge in ability text.

**Goal:** zero `note`-only entries. Every Play card must be executable by the runtime without free-text interpretation.

**Version:** schema v2 (2026-04-15). Supersedes v1, which shipped with 118 `note`-only entries. Extends the op / condition / trigger vocabulary to cover every remaining Play; see [§ Changelog](#changelog) at the bottom.

---

## Top-level entry

```json
{
  "bobaId": "BP-42-Low_Turnover-Base_Set-First_Edition",
  "name": "Low Turnover",
  "cost": 1,
  "ability": "If there are 0 Heroes in your Discard Pile, give your Hero +15.",
  "category": "value",
  "effects": [ /* array of ops and branches, executed in order on play */ ],
  "persistent": [ /* optional: installed effects that trigger later */ ],
  "ui": { /* optional: player-choice / targeting hints */ },
  "strategy": "Rewards lean hero decks; disables if you sub aggressively."
}
```

- `cost` — Hot Dog cost (mirror of `playCost` for self-containment)
- `category` — `tempo | value | disruption | economy | utility | conditional`
- `effects` — **required**, may be empty `[]` for cards with no mechanical effect yet (rare)
- `persistent` — **optional**, used for "for the rest of the game" / "next Battle" effects
- `ui` — **optional**, runtime hints: `{"requires_target": "opponent_bench", "player_choice": true, "name_weapon": true}`
- `strategy` — **optional**, one-line note for deck builder hints (future use)

---

## `effects` — ordered list of ops and branches

Each item is **either** an op (has `op`) **or** a branch (has `if` + `then`) **or** a player choice (has `choice`).

---

## Ops

### Power

| op | params | meaning |
|---|---|---|
| `power` | `target`, `delta: int \| formula` | adjust active-battle power |
| `power_set` | `target`, `source: {target, attr: "current_power" \| "start_power"} \| {value: int}`, `offset: int` | e.g. Edge Rush |
| `power_swap` | `scope: "current"` | swap current battle powers |
| `power_double` | `target: "self" \| "opponent"` | double current power |
| `power_steal` | `amount: int \| formula` | self +amount, opponent -amount |
| `power_cap_min` | `target`, `min: int` | floor power (Glow protection) |
| `power_reset` | `scope: "self" \| "opponent" \| "both"` | reset to `start_power` |
| `add_previous_hero_delta` | `target` | add (prev_hero.final_power − prev_hero.start_power) to `target` |
| `mirror_power_effects_to_opponent` | — | copy all Plays currently affecting self onto opponent for this Battle (Ha! Gotcha) |
| `flip_opponent_debuffs` | `target: "self"` | any opponent Play this Battle that lowers `target`'s power instead raises it (Sweet Relish) |

### Resources

| op | params |
|---|---|
| `hd` | `target`, `delta: int \| formula` — immediate HD change |
| `hd_recover` | `target`, `amount: int \| formula`, `from: "discard"` |
| `swap_hd_counts` | — | swap self ↔ opponent HD counts (Hot Dog Stock Exchange) |
| `draw` | `target`, `kind: "play" \| "hero"`, `count: int \| formula` |
| `discard` | `target`, `kind: "play" \| "hero" \| "hot_dog" \| "any"`, `count: int \| formula \| "all"`, `mode: "random" \| "choice"` |
| `variable_cost_bonus` | `target: "self"`, `factor: int` | player chooses X extra HDs; self +factor·X (Get What You Pay For) |

### Deck & search

| op | params |
|---|---|
| `search` | `target`, `from: "playbook" \| "hero_deck" \| "discard"`, `filter: {weapon?, max_power?, min_cost?, max_cost?, name_eq?, card_type?}`, `action: "to_hand" \| "play_free" \| "swap_active"` |
| `shuffle_discard_into_deck` | `target`, `filter?: {kind?, exclude_kind?, weapon?}` |
| `reveal` | `target`, `kind: "play" \| "hero"`, `from: "deck_top" \| "playbook_top"`, `count: int`, `then?: "discard_all" \| "keep_one" \| {if: <cond_on_revealed>, then: [ops], else: [ops]}` |
| `reveal_top_hero_deck` | `target`, `count: int`, `then_keep: int`, `then_discard_rest: bool` | Locker Room Evacuation, Pallet Cleansing |
| `reorder_top_playbook` | `target`, `count: int`, `peek: true` | Play Re-Order |
| `reorder_opponent_playbook_top` | `count: int`, `keep_on_top: int`, `send_to_bottom: int` | Playbook Knowledge |
| `discard_top` | `target`, `from: "hero_deck" \| "playbook"`, `count: int`, `bonus_per_match?: {filter: {weapon? \| min_cost?}, factor: int, target: "self"}` | Big Spender Bonus, Roster Cuts, Lost Plays |
| `swap_active_with_discard` | `target: "self"`, `filter?: {weapon, power_cmp?}` | Fire/Ice/Steel/Radiant Comeback, Another Man's Treasure, Don't Call It A Comeback |
| `swap_active_from_hand` | `target`, `then_draw?: {kind, count}` | Curveball, Sub And Power-Up |
| `replace_active_with_top_hero_deck` | `target: "self" \| "opponent" \| "both"` | Blind Substitution, Big Free Agent Pick-Up, Leave It To Fate |
| `add_top_hero_power_to_self` | — | Dogpile |
| `shuffle_hand_into_playbook` | `target`, `kind: "play"`, `then_draw?: int \| "same_count"` | Sandstorm, 4 New Plays Baby!, Clean Slate, Play Reset |
| `shuffle_used_plays_into_playbook` | `target`, `then_draw?: int`, `scope: "all_prior_battles" \| "specific"`, `count?: int` | Recycle, Refill And Reload |
| `return_used_play_to_hand` | `target: "self"`, `count: int`, `mode: "choice"` | Reload, Game Sealing Interception |

### Future-battle / unrevealed Heroes

| op | params |
|---|---|
| `peek_unrevealed_hero` | `target`, `which: "next" \| "specific"`, `battle_num?: int \| "player_choice"` | X-Ray Vision |
| `reorder_unrevealed_heroes` | `target`, `peek: false` | Change The Future, Perfect Playcalling |
| `swap_active_with_unrevealed` | `peek: false` | Last-Minute Re-Org |
| `replace_unrevealed_heroes` | `target`, `scope: "all_future" \| "next"`, `from: "hero_deck_top"` | Lineup Randomizer |
| `mark_future_battle` | `battle_ref: "next" \| "player_choice"`, `on_reveal: [ops]` | Plan Ahead |
| `mark_unrevealed_hero` | `target`, `on_reveal: [ops]` | Delayed Recovery |
| `conditional_future_discard` | `target`, `scope: "next"`, `if: <cond on the hero>`, `then: [ops]` | Drop The Giant, A Hard Bargain |

### Meta / state

| op | params |
|---|---|
| `cancel_opponent_plays` | `scope: "this_battle" \| "battle_7"`, `retroactive?: bool`, `max?: int` | `cap_opponent_plays` (Restricted List) uses `max: 1` |
| `protect_self` | `scope: "this_battle"` | immune to opponent Plays |
| `force_sub` | `target: "opponent"`, `scope: "next_battle"` |
| `block_sub` | `target: "opponent"`, `scope: "next_battle" \| "battle_7" \| "next_2_battles"` |
| `block_draw` | `target: "opponent"`, `scope: "this_battle" \| "until_opp_wins"` |
| `block_hd_recover` | `target: "opponent"`, `scope: "next_battle" \| "rest_of_game"` | Drain And Deny, Drought |
| `block_plays` | `target`, `scope` | targeted equivalent of `cancel_opponent_plays` (Maximum Effort next-battle persistent) |
| `play_cost_delta` | `target`, `delta: int`, `scope: "this_and_next" \| "next_battle"` |
| `honors_set` | `target`, `scope: "next_battle"` |
| `substitute_free` | `target`, `scope: "next_battle"` |
| `opponent_pays_next_sub` | — | Pay It For Me |
| `opponent_must_sub_paying` | `cost: int` | Forced Substitution (opp pays 2 HD and substitutes next battle) |
| `end_battle_by_power` | — | ends current Battle immediately; higher power wins, ties = tie (Call it a Day) |
| `cancel_persistent` | `scope: "rest_of_game" \| "all"`, `owner: "self" \| "opponent" \| "all"` | Pulling The Plug |
| `transform_to_hot_dog` | `target: "this_card"`, `immune_to_opponent_plays: bool` | Ghost Dog |

### Hand / choice

| op | params |
|---|---|
| `choice` | `target: "self" \| "opponent"`, `options: [{label, effects: [ops]}, ...]` | Adding Depth, Plays Or Dogs?, Hero Tax fallback |
| `name_and_discard` | `target: "opponent"`, `kind: "play" \| "hero"`, `chooser: "self"` | Called Shot |
| `peek_opponent_hand` | `count: int`, `mode: "random" \| "choice"`, `reveal_to: "self" \| "both"` | Pre-Game Spy, Transparency Clause |

### Randomness

**Coin flip — extended.**
```json
{ "op": "coin_flip", "times": 1, "heads": [ops], "tails": [ops] }
```
Aggregate mode — resolve all flips, then branch on the combined result:
```json
{
  "op": "coin_flip",
  "times": 3,
  "aggregate": "at_least_n_heads",
  "n": 2,
  "then": [ops],
  "else": [ops]
}
```
Allowed `aggregate` values:
- `"all_heads"` — all N flips heads
- `"all_tails"` — all N flips tails
- `"at_least_n_heads"` — requires `n`
- `"at_least_n_tails"` — requires `n`
- `"per_head"` — run `then` once per heads; `else` runs per tails (for mixed-outcome cards like 3rd Time Charm)
- `"per_tail"` — mirror of above
- `"exact_heads"` — requires `n`

Combined form (3rd Time Charm — "all 3 heads → double; each tails → draw a Play"):
```json
{
  "op": "coin_flip",
  "times": 3,
  "branches": [
    { "aggregate": "all_heads", "then": [{"op":"power_double","target":"self"}] },
    { "aggregate": "per_tail",  "then": [{"op":"draw","target":"self","kind":"play","count":1}] }
  ]
}
```
Branches run in order, all that match fire. Use `aggregate: "none_match"` for a fallback.

**Dice roll — extended.**
Single-player:
```json
{
  "op": "dice_roll",
  "count": 1,
  "branches": [
    { "on": [1],    "then": [ops] },
    { "on": "else", "then": [ops] }
  ]
}
```
Pick-then-roll (Genius GM, Only Upside, Cloudy With A Chance Of Hot Dogs):
```json
{ "op": "dice_roll", "count": 1, "player_pick": true, "on_match": [ops], "on_miss": [ops] }
```
Opposed roll (Dice Duel, Great Draft Picks, Luck Of The Draw):
```json
{
  "op": "dice_roll",
  "players": "both",
  "resolve_by": "higher",
  "on_self_higher": [ops],
  "on_opponent_higher": [ops],
  "on_tie": [ops]
}
```
Both-pick-and-roll (Crystal Ball):
```json
{ "op": "dice_roll", "players": "both", "both_pick_distinct": true, "on_any_match": [ops] }
```
Repeat-while (Sack Streak):
```json
{
  "op": "dice_roll",
  "count": 1,
  "branches": [
    { "on": [4,5,6], "then": [ops_on_hit], "repeat": true },
    { "on": [1,2,3], "then": [] }
  ]
}
```
Combined coin + die (Lucky Shot):
```json
{
  "op": "compound_roll",
  "coin": 1,
  "dice": 1,
  "if": { "coin_heads": true, "dice_in": [4,5,6] },
  "then": [ops],
  "else": [ops]
}
```

### Rule modifiers (global)

Some cards install a **rule modifier** that fires on every occurrence of an event for the rest of the game. Express as a persistent entry with the appropriate trigger — see [§ `persistent`](#persistent).

Shorthand op for single-line modifiers:
```json
{ "op": "rule_modifier", "trigger": "on_dice_roll", "target": "any_player", "effect": {ops} }
```
Used for Deep In The Playbook, Loan Sharked, Pay The Price, etc.

### Escape hatch

| op | params |
|---|---|
| `note` | `text: string` — engine logs, applies no mechanical effect. **Do not use in v2 unless the ability text is genuinely blank** (e.g., `Lucky Seven`). For every other card, use structured ops below. |

---

## Branches — `if / then / else`

```json
{ "if": <condition>, "then": [ ops ], "else": [ ops ] }
```
`else` is optional. Branches may be nested inside ops (e.g., `coin_flip.heads`) or sit at the top level of `effects`.

---

## Condition vocabulary

### Weapon / card
| type | params |
|---|---|
| `weapon` | `target`, `weapon: "FIRE" \| "ICE" \| "STEEL" \| "BRAWL" \| "GLOW" \| "HEX" \| "GUM" \| "SUPER"` |
| `weapon_same` / `weapon_different` | `between: "self_opp" \| "self_prev" \| "self_prev_n"`, `prev_n?: int` — compare self vs opponent, self vs prev Hero, or self vs last N of own Heroes |
| `weapon_previous_all_match` | `target`, `prev_n: int`, `against: "self_active" \| <weapon>` — 3 Weapon Streak, 5 Weapon Streak |
| `opponent_used_weapon` | `weapon: <weapon> \| "same_as_self_active"` — Brothers In Arms |
| `hero_name` | `target`, `equals: "MVFree" \| ...` — Series MVP Award |
| `hero_deck_top_attr` | `target`, `attr: "start_power"`, `comparison`, `value` — A Hard Bargain, Might Of The Underdog, Drop The Giant |

### Counts & numeric comparisons
| type | params |
|---|---|
| `hd_count` | `target`, `comparison: "gte" \| "lte" \| "eq"`, `value: int` |
| `discard_count` | `target`, `kind: "hero" \| "play" \| "hot_dog"`, `weapon?: <weapon>`, `comparison`, `value` |
| `hand_count` | `target`, `kind?: "play" \| "hero"`, `comparison`, `value` |
| `metric_compare` | `left: {metric, target, ...}`, `right: {metric, target, ...} \| {value: int}`, `comparison` | supersedes the ad-hoc `hd_count_compare` / `hand_count_compare` |
| `power_threshold` | `target`, `attr: "current_power" \| "start_power"`, `comparison`, `value` |
| `power_delta_eq_zero` | `target` — current_power == start_power (Baseline Bonus) |

### Match history
| type | params |
|---|---|
| `battle_num` | `comparison`, `value` (1-indexed 1–7) |
| `battles_won` | `target`, `comparison`, `value` |
| `battles_lost` | `target`, `comparison`, `value` |
| `battles_won_streak` | `target`, `comparison`, `value` — Streaky |
| `battle_won_nth` | `target`, `n: int` — Opening Strike |
| `battles_lost_first_n` | `target`, `n: int` — Turn the Tide |
| `battle_tied` / `battle_winning` / `battle_losing` | — current battle state after reveal |
| `prev_battle` | `result: "won" \| "lost" \| "tied"`, `target: "self"` |
| `prev_n_battles_all` | `target`, `n: int`, `result: "won" \| "lost" \| "tied"` — Comeback Time |
| `plays_used` | `target`, `scope: "this_battle" \| "match"`, `comparison`, `value` |
| `hd_spent_this_battle` | `target`, `comparison`, `value` |
| `heroes_revealed_total` | `target`, `comparison`, `value` |
| `substituted_this_battle` | `target` |
| `honors` | `target` |

### Boolean composition
| type | params |
|---|---|
| `all` | `of: [conditions]` |
| `any` | `of: [conditions]` |
| `not` | `cond: <condition>` |

---

## Metrics (use inside `formula` deltas and `metric_compare`)

A **metric** is a named runtime value. Use either form:
- inline shorthand: `"metric": "plays_used_this_battle", "target": "self"`
- object form inside formulas: see next section.

| metric | params | returns |
|---|---|---|
| `plays_used_this_battle` | `target` | int |
| `plays_used_total` | `target` | int |
| `heroes_used_total` | `target`, `weapon?` | int (count of heroes self has revealed, optionally filtered by weapon) |
| `heroes_revealed_total` | `target` | int |
| `battles_won` | `target` | int |
| `battles_lost` | `target` | int |
| `battles_tied` | `target` | int |
| `battles_remaining` | — | int (including current) |
| `hd_count` | `target` | int (current HD) |
| `hd_spent_this_battle` | `target` | int |
| `hd_discarded_this_battle` | `target` | int (including substitutions) |
| `hand_count` | `target`, `kind?: "play" \| "hero"` | int |
| `discard_count` | `target`, `kind?`, `weapon?: <weapon> \| "same_as_active"` | int |
| `distinct_weapons_revealed` | `scope: "match"` | int (distinct weapons across both players) |

---

## Formulas — scaling deltas / amounts / counts

Every op that takes an integer (`delta`, `amount`, `count`) also accepts a **formula object**:
```json
{ "factor": 10, "metric": "plays_used_this_battle", "target": "self", "offset": -1, "min": 0, "max": 100 }
```
Evaluated as `max(min, min(max, factor * metric(target) + offset))`. `offset`, `min`, `max` are optional.

Examples:
- `10 Per Play` — `+10 per other Play this Battle`
  ```json
  {"op":"power","target":"self","delta":{"factor":10,"metric":"plays_used_this_battle","target":"self","offset":-10}}
  ```
- `Banked Power` — `+5 per HD remaining after cost`
  ```json
  {"op":"power","target":"self","delta":{"factor":5,"metric":"hd_count","target":"self"}}
  ```
  (HD cost is subtracted before the effect resolves — no post-cost flag needed.)
- `Early Round Magic` — `+5 per battle remaining`
  ```json
  {"op":"power","target":"self","delta":{"factor":5,"metric":"battles_remaining"}}
  ```
- `Fire Crew` — `+10 per Fire Hero used`
  ```json
  {"op":"power","target":"self","delta":{"factor":10,"metric":"heroes_used_total","target":"self","weapon":"FIRE"}}
  ```
- `Competitive Disadvantage` — `-10 per opponent win`
  ```json
  {"op":"power","target":"opponent","delta":{"factor":-10,"metric":"battles_won","target":"opponent"}}
  ```

---

## `persistent` — effects that trigger later

```json
"persistent": [
  {
    "scope": "rest_of_game" | "next_battle" | "next_2_battles" | "battles_4_7" | "this_battle",
    "trigger": <trigger>,
    "target_filter": <condition>,   // optional: only fire if condition holds when trigger fires
    "effect": <op or branch>
  }
]
```

### Trigger vocabulary

| trigger | fires on |
|---|---|
| `battle_start` | start of each in-scope Battle (before reveal) |
| `on_reveal` | when Heroes flip for a Battle |
| `on_hero_revealed` | when any face-down Hero becomes active (Delayed Recovery, Plan Ahead, Good Guess) |
| `on_win` / `on_loss` / `on_tie` | after Battle resolution |
| `on_battle_end` | after any Battle resolves |
| `continuous` | always-on modifier, re-evaluated each read |
| `on_coin_flip` | any coin flip (by either player) — Loan Sharked |
| `on_dice_roll` | any dice roll — Deep In The Playbook, Pay The Price, Taking Down The Dynasty |
| `on_substitute` | any substitution event — Substitution Boost |
| `on_play_run` | self runs a Play — Overcommitted |
| `on_opponent_play_run` | opponent runs a Play — You're Not Alone |

### Scope vocabulary

`rest_of_game`, `next_battle`, `next_2_battles`, `battles_4_7`, `battle_7`, `this_battle`, `until_opp_wins`, `until_end_of_next_battle`.

Example — Fire Boost (continuous, rest of game):
```json
"persistent": [{
  "scope": "rest_of_game",
  "trigger": "continuous",
  "effect": {
    "if": {"type": "weapon", "target": "self", "weapon": "FIRE"},
    "then": [{"op": "power", "target": "self", "delta": 10}]
  }
}]
```

Example — Plan Ahead (mark a future Battle):
```json
"effects": [{
  "op": "mark_future_battle",
  "battle_ref": "player_choice",
  "on_reveal": [{"op":"power","target":"self","delta":35}]
}]
```

---

## UI hints

`ui` is a free-form object the runtime can read for targeting / choice prompts:
- `{"player_choice": true}` — effect has a branching decision
- `{"name_weapon": true}` — prompts player to name a weapon (Dead Red, Good Guess)
- `{"name_play": true}` — prompts for a Play name (Called Shot)
- `{"pick_die_face": true}` — player picks 1–6 before roll
- `{"pick_future_battle": true}` — player picks an unrevealed Battle slot
- `{"pick_from_hand": "hero" | "play"}`
- `{"pick_from_discard": {weapon?, kind?}}`
- `{"requires_battle_7": true}` — Hot Dog Stock Exchange
- `{"variable_cost": true}` — Get What You Pay For

---

## v3 additions (2026-04-15) — Cowork v2 vocabulary, promoted

When Cowork authored the v2 pass covering the remaining 102 `note`-only entries, they introduced new op / condition / metric names that are now **part of the canonical schema**. The data ships with these names; the runtime must support them. Each is listed below with its intended semantics so executors on both platforms (`js/practice.js`, `PracticeStore.swift`) implement them consistently.

### v3 ops (promoted — runtime must implement)

**Deck / hand manipulation**
| op | params | meaning |
|---|---|---|
| `shuffle_hand_into_deck` | `target`, `kind: "play" \| "hero"` | shuffle all cards of `kind` from hand back into their source deck (Playbook for plays, Hero Deck for heroes). Used by 4 New Plays Baby!, Sandstorm, Play Reset. Replaces earlier `shuffle_hand_into_playbook`. |
| `shuffle_from_discard_to_deck` | `target`, `kind`, `filter?`, `count?` | shuffle N cards matching `filter` from Discard back into source deck. Discard Rebate, Recycle, Refill And Reload, Second Wind. Replaces earlier `shuffle_used_plays_into_playbook`. |
| `shuffle_revealed_back` | `target`, `kind` | shuffle just-revealed cards back into their source deck (for reveal-then-maybe-keep flows). Cheap Trick. |
| `reveal_top` | `target`, `kind: "play" \| "hero"`, `count: int` | reveal top N cards of `kind`'s source deck without moving them. Cheap Trick, Power Pick, Locker Room Evacuation. |
| `discard_revealed_hero` | `target` | discard all revealed Hero cards (chain after `reveal_top`). A Game Of War. |
| `discard_other_revealed` | `target` | discard revealed cards not chosen in the prior `deploy_chosen_revealed`. Opps' Choice. |
| `discard_revealed` | `target`, `kind` | generic form for Wildcard Wager. |
| `discard_hero` | `target`, `source: "active" \| "next_battle" \| "hand"` | discard a Hero from a specific slot. An Ace Is Found, Blind Substitution, Forced Retreat. |
| `discard_hero_from_hand` | `target` | player chooses a Hero from hand to discard. Fallen Fighters. |
| `discard_top` | `target`, `kind`, `count`, `reveal?: bool`, `bonus_per_match?: {filter, factor, target}` | extends base `discard_top`: adds optional reveal and per-card bonus scoring. Big Spender Bonus, Lost Plays, Roster Cuts, Lucky Discard. |
| `discard_hand_all` | `target` | discard entire hand. Storm The Field. |
| `add_chosen_revealed_to_hand_discard_rest` | `target`, `kind` | after a `reveal_top`, player picks 1 to add to hand; discard the rest. Locker Room Evacuation, Power Pick. |
| `deploy_chosen_revealed` | `target`, `chooser: "self" \| "opponent"` | chooser picks 1 revealed Hero to become active; non-chosen cards still need a follow-up op. An Ace Is Found, Opps' Choice. |
| `peek_and_reorder_top` | `target`, `kind`, `count` | look at top N, reorder and place back on top. Play Re-Order. |
| `reveal_top_reorder_or_bottom` | `target`, `kind`, `count`, `chooser` | reveal top N; chooser puts 1 back on top, sends 1 to bottom. Playbook Knowledge. |
| `force_reveal_from_hand` | `target`, `kind`, `count`, `chooser` | chooser picks up to N cards in opponent's hand; opponent reveals them. Transparency Clause. |

**Replacement / swap**
| op | params | meaning |
|---|---|---|
| `replace_active_with_top_hero_deck` | `target` | discard active Hero, replace with top of Hero Deck. Big Free Agent Pick-Up, Blind Substitution, Leave It To Fate. |
| `replace_active_from_hand` | `target` | opponent replaces active from their own hand. Forced Retreat. |
| `replace_next_with_top_hero_deck` | `target` | discard opponent's next-Battle Hero, replace with top of deck. Drop The Giant (inside a conditional). |
| `replace_all_unrevealed_with_top_hero_deck` | `target`, `preserve_order: bool` | discard all face-down future Heroes, refill from deck in order. Lineup Randomizer. |
| `swap_active_with_discard` | `target`, `weapon_filter?`, `if_possible?: bool` | swap active with a Hero in Discard (optionally weapon-filtered). Another Man's Treasure, Don't Call It A Comeback, Dumpster Battle, all weapon Comeback cards. |
| `swap_active_with_hand` | `target` | swap active Hero with one from hand (replaces `swap_active_from_hand`). Curveball, Missed The Kerveball, Sub And Power-Up. |
| `swap_active_with_future_hero` | `target`, `blind: bool` | swap active with a face-down future Hero, optionally without peeking. Last-Minute Re-Org. |
| `swap_hd_counts` | `target`, `source` | swap HD counts between two players. Hot Dog Stock Exchange. |

**Peek / inspect**
| op | params | meaning |
|---|---|---|
| `peek_unrevealed_hero` | `target`, `selector` | look at a specific face-down Hero. X-Ray Vision. |
| `peek_opponent_hand` | `target`, `kind`, `count`, `mode` | look at random/chosen cards in opponent hand. Pre-Game Spy. |

**Future Hero / mark**
| op | params | meaning |
|---|---|---|
| `mark_future_battle` | `target`, `selector: "next" \| "player_choice"`, `on_reveal_effects: [ops]` | install a payload that fires when the selected future Hero is revealed. Plan Ahead, Delayed Recovery, Good Guess. |
| `reorder_unrevealed_heroes` | `target`, `blind: bool` | reorder face-down future Heroes (blind = no peek). Change The Future, Perfect Playcalling. |

**Meta / misc**
| op | params | meaning |
|---|---|---|
| `name_and_discard` | `target`, `kind`, `source` | name a card, if opponent has it in `source` they discard. Called Shot. |
| `reclaim_used_play` | `target`, `source`, `count` | return N Plays used in prior Battles to hand. Game Sealing Interception, Reload. (Replaces `return_used_play_to_hand`.) |
| `play_top_of_playbook_free` | `target` | play top card of Playbook for free (if able). Used inside dice branches for Great Draft Picks, Luck Of The Draw. |
| `play_revealed_free` | `target` | play a just-revealed Play for free (if able). Wildcard Wager. |
| `copy_last_play` | `target`, `scope: "self_last"` | re-resolve the last Play the target ran (same effect, same cost). Copycat. Scope defaults to `self_last`. |
| `transform_to_hot_dog` | `target: "this_card"`, `immune_to_removal: bool`, `discard_on_spend: bool` | the card itself converts to a Hot Dog. Ghost Dog. |
| `variable_cost_bonus` | `target`, `per_hd`, `source_hd` | player chooses how many HDs to spend; self gains `per_hd * spent`. Get What You Pay For. |
| `tax_per_hero_in_hand` | `target`, `per_hero_cost`, `fallback: [ops]` | opponent pays N HDs per Hero in hand; if unable, run fallback (e.g., discard random Hero). Hero Tax. |
| `transfer_sub_cost` | `target`, `when`, `amount` | redirect the next substitution's HD cost to the other player. Pay It For Me. (Replaces `opponent_pays_next_sub`.) |
| `force_substitute` | `target`, `cost`, `when` | target must substitute; optionally must pay `cost` from their own HDs. Forced Substitution. (Replaces `opponent_must_sub_paying`.) |
| `dice_roll_again` | `while_match: [ints]` | nested inside a `dice_roll` branch — re-roll while result is in the match set. Sack Streak. |
| `weapon_debuff_or_penalty` | `named_weapon`, `if_match: [ops]`, `else: [ops]` | Dead Red persistent payload — runs one of two branches based on opponent's current Hero weapon matching the named weapon. |

### v3 conditions (promoted)

| type | params | meaning |
|---|---|---|
| `weapon_streak` | `target`, `length`, `weapon_ref: "self_active"` | previous `length` revealed Heroes (by `target`) all share weapon with active. 3 Weapon Streak, 5 Weapon Streak. |
| `opponent_played_weapon_match` | `weapon_ref: "self_active"` | opponent has previously played a Hero sharing weapon with self's active. Brothers In Arms. |
| `previous_two_heroes_share_weapon` | `target` | target's two prior revealed Heroes share a weapon type. Synergy Snacks. |
| `previous_and_current_share_weapon` | `target` | target's previous revealed Hero and current Hero share weapon. Weapon-Sync. |
| `discarded_hero_weapon_matches_active` | `target` | most-recent discarded Hero shares weapon with target's active Hero (used right after a `discard_top kind:hero reveal:true`). Lucky Discard. |
| `next_hero_power_gt` | `target`, `value` | opponent's face-down next-Battle Hero has start_power > `value`. Drop The Giant. |
| `next_hero_weapon_equals` | `target`, `weapon` | opponent's next Hero has a specific weapon. Good Guess. |

### v3 metrics (promoted — usable inside `formula(...)` and `metric_compare`)

Transient per-resolution values (the executor tracks these during a single op chain):
- `previous_hero_power_gained` — final − starting power of the previous Battle's active Hero
- `previous_hero_extra_power` — alias for above; used by Going Back to Back, Back 2 Back 4 Garnet & Black
- `revealed_hero_power` — power of the top Hero just revealed by `reveal_top kind:hero`
- `drawn_hero_power` — power of a Hero just drawn (Dogpile, Might Of The Underdog)
- `drawn_play_cost` — cost of a Play just drawn (Cheap Trick)
- `revealed_play_cost` — cost of a revealed Play (Power Pick)
- `chosen_play_cost` — cost of the Play the player chose from a reveal set
- `hd_count_before_cost` — HDs before this Play's cost was paid (for Buff Or Debuff, Belly Buster)

Persistent match-history metrics:
- `hd_discarded_this_battle` (with optional `kind: "include_substitutions"`) — Hot Dog Dominance
- `battles_lost_streak` — consecutive losses (symmetric with `battles_won_streak`). Comeback Time.
- `discard_pile_heroes_weapon_match` (weapon arg) — count of Heroes in Discard with a given weapon. Weapon Lineage, Fallen Fighters.
- `discard_pile_count_excluding_hd` — total Discard minus Hot Dogs. Recycle For 5.
- `discard_pile_heroes` — count of Heroes in Discard. The Heroes Favorite Hot Dogs.
- `opponent_hd_used_this_battle` (with optional `include_prior_this_battle: bool`) — The Champion's Lasso.
- `plays_used_this_battle` (with optional `kind: "include_this_play"` to include the currently-resolving Play). Play Booster.
- `cards_discarded_by_this_play` — running count of cards this very Play has discarded. Storm The Field.
- `hand_count` (with `kind: "heroes_and_plays"` for the combined total). Strength in Numbers.
- `plays_in_hand_before_shuffle` — snapshot metric for Play Reset (draws back same count that was shuffled).
- `discarded_plays_cost_gte` (with `threshold` inside a `ui.note`-adjacent form) — Big Spender Bonus. **Cleanup target:** promote to `formula(factor, metric="discard_count", kind="play", min_cost=N)` in a later refactor; for now, the runtime reads the threshold from the card's `ui.note`.

### v3 UI-hint keys (promoted)

- `ui.prompt: string` — free-text prompt surfaced to the player before the effect resolves. Used on Cloudy With A Chance Of Hot Dogs, Crystal Ball, Genius GM, Only Upside, Good Guess, Dead Red.
- `ui.note: string` — engine-facing annotation for details the op vocabulary doesn't yet express cleanly (e.g., "bonus applies to discarded Plays with cost ≥ 3"). Used on Big Spender Bonus, Buff Or Debuff.

### v3 compound op form

`compound_roll` now carries `components` and `branches`, where each branch has `match: {coin, die_range} | "otherwise"` and `effect: [ops]`. Lucky Shot.

### v3 author-time open items (do not block runtime)

Flagged by Cowork; runtime implementers should be aware but can ship:
1. `Copycat` — `copy_last_play` scope locked to `self_last` (the source text says "the last Play you used"). If playtesting reveals ambiguity, revisit.
2. `Ha! Gotcha` (`mirror_power_effects_to_opponent`) and `Sweet Relish` (`flip_opponent_debuffs`) require the executor to track applied power modifiers by source — non-trivial but local to the battle state.
3. `Pulling The Plug` (`cancel_persistent`) — treat as **forward-looking only** (existing `rest_of_game` effects stop firing from this point; already-applied deltas are not reverted). If playtesting requires retroactive behavior, add a `retroactive: true` flag.
4. `Dead Red` — kept as a single persistent with a `weapon_debuff_or_penalty` payload. Restructure into two parallel persistents (`if_match` + `if_miss`) only if it simplifies the executor.
5. `Big Spender Bonus` — current encoding reads threshold from `ui.note`. Cleanup target above.

---

## Authoring rules for Cowork (v2)

1. **Zero `note`-only entries.** Every entry must have at least one structured op (or branch, or choice). `note` ops are allowed *inside* structured entries as annotations, but must not be the sole content.
2. **One exception:** if the source ability text is genuinely blank in `cards.json` (today: only `Lucky Seven`), ship `effects: []` with an empty effect and a `note` op, and flag the card for text recovery.
3. **Copy `ability` verbatim from the card.** Engine reads it for toast/strategy display.
4. **Prefer the smallest op combination.** If a stacked combo of existing ops fits, use them before inventing.
5. **Use metrics + formulas for all "+N per X" cards.** Do not leave these as `note`.
6. **Coin/dice aggregates.** Any card that flips N coins or rolls N dice and branches on the combined outcome must use `aggregate` (coin) or `players`/`resolve_by`/`player_pick` (dice). No `note` for these.
7. **Future-Hero / unrevealed manipulation** uses the `mark_*` / `peek_*` / `reorder_*` / `replace_*` ops listed above — not `note`.
8. **Rename the 18 entries using old invented vocab** to the promoted names:
   - `persistent_delta` → plain `persistent[]` entry with a `power`/`hd` op
   - `hd_count_compare` / `hand_count_compare` → `metric_compare` using the generic metric system
   - everything else (`block_hd_recover`, `block_plays`, `cap_opponent_plays`, `battle_won_nth`, `battles_lost_first_n`, `battles_won_streak`, `power_threshold`, `hero_name`, `on_coin_flip`, `on_dice_roll`, `on_substitute`, `on_play_run`, `on_opponent_play_run`) is promoted **as-is** — no rename needed.
9. **Leave `strategy` blank for now.** We'll author that in a later pass with the deck builder in mind.
10. **Keep the file keyed by `name`.** `bobaId` expansion is a post-pass.

---

## Runtime expectations

The executor on each platform is ~200 LOC:
- Iterate `effects`, executing each op / branch / choice against the current match state
- Ops return deltas that the engine applies to `battle.playerEffectPower`, `playerHD`, hand, discard, etc.
- `persistent` entries go into a `matchState.persistentEffects[]` list, checked at each `trigger` event
- **Formulas** are resolved at op-execution time by passing the metric name + target to a `resolveMetric(metric, target, scope)` helper
- **Player choices** are surfaced to the UI; the runtime pauses, waits for user selection, then resumes with the chosen branch
- **Rule modifiers** install a `persistentEffect` with the appropriate trigger; the engine publishes events (`coin_flipped`, `dice_rolled`, `play_run`, etc.) that modifiers listen to
- Unknown ops / conditions / metrics log a warning and are skipped (forward compat)

The same JSON drives both `js/practice.js` and `BOBAPlaybook/Store/PracticeStore.swift`.

---

## Changelog

**v3 (2026-04-15)** — promoted the ~40 ops / 7 conditions / 15 metrics / 2 UI-hint keys Cowork introduced while authoring the v2 data pass. All now part of the canonical schema; the runtime executor must implement them. Lucky Seven fixed in place with user-sourced text (`dice_roll` count:2 aggregate:sum → +100 on 7, else discard random hero — identical to `Lucky 7`). **Data state:** 383/383 Play names structured, 0 `note`-only entries, md5 `1d4e054e1ab56d2deaa696a3604fe81e` on both web and iOS bundles. Runtime wiring is now unblocked.

**v2 (2026-04-15)** — extended vocabulary to eliminate all `note`-only entries. Promoted 4 ops (`block_hd_recover`, `block_plays`, `cap_opponent_plays`, `persistent_delta`→rewrite), 7 conditions (`battle_won_nth`, `battles_lost_first_n`, `battles_won_streak`, `power_threshold`, `hero_name`, `hd_count_compare`→`metric_compare`, `hand_count_compare`→`metric_compare`), and 5 persistent triggers (`on_coin_flip`, `on_dice_roll`, `on_substitute`, `on_play_run`, `on_opponent_play_run`). Added ~25 new ops (future-hero, swap, shuffle-variants, choice, variable_cost_bonus, end_battle_by_power, cancel_persistent, transform_to_hot_dog, etc.), formula/metric system for "+N per X" scaling, coin-flip aggregates, multi-player dice rolls, and rule-modifier persistents.

**v1 (2026-04-14)** — initial schema, 20 worked examples in seed. Shipped with 118 `note`-only entries authored by Cowork pending v2.

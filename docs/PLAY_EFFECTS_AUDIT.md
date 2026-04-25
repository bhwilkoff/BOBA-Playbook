# Play Effects Audit

_383 entries · 77 known ops · **0 errors** · **3 warnings** · **61 info** · **327 clean**_

Run with: `python3 scripts/audit_play_effects.py`

## Findings by category

### `missing_dice_op` (warning, 1 cards)

- **Leave It To Chance** — Ability text mentions dice roll but JSON has no dice op

### `missing_discard_op` (info, 35 cards)

- **Add Firepower** — Ability text mentions discard but JSON has no discard op
- **Another Man's Treasure** — Ability text mentions discard but JSON has no discard op
- **Back From The Dumps** — Ability text mentions discard but JSON has no discard op
- **Called Shot** — Ability text mentions discard but JSON has no discard op
- **Cloudy With A Chance Of Hot Dogs** — Ability text mentions discard but JSON has no discard op
- **Diamonds In The Rough** — Ability text mentions discard but JSON has no discard op
- **Discard Rebate** — Ability text mentions discard but JSON has no discard op
- **Discarded Heroes** — Ability text mentions discard but JSON has no discard op
- **Dumpster Battle** — Ability text mentions discard but JSON has no discard op
- **Fire Comeback** — Ability text mentions discard but JSON has no discard op
- **Ghost Dog** — Ability text mentions discard but JSON has no discard op
- **High Turnover** — Ability text mentions discard but JSON has no discard op
- **Hungry Demands** — Ability text mentions discard but JSON has no discard op
- **Icy Comeback** — Ability text mentions discard but JSON has no discard op
- **Instant Refund** — Ability text mentions discard but JSON has no discard op
- **It's Gonna Cost Ya** — Ability text mentions discard but JSON has no discard op
- **LAD vs NYY** — Ability text mentions discard but JSON has no discard op
- **Lineup Randomizer** — Ability text mentions discard but JSON has no discard op
- **Locker Room Evacuation** — Ability text mentions discard but JSON has no discard op
- **Low Turnover** — Ability text mentions discard but JSON has no discard op
- **Mutually Assured Dogstruction** — Ability text mentions discard but JSON has no discard op
- **Pick Your Poison** — Ability text mentions discard but JSON has no discard op
- **Polished Comeback** — Ability text mentions discard but JSON has no discard op
- **Power Drain** — Ability text mentions discard but JSON has no discard op
- **Power Pick** — Ability text mentions discard but JSON has no discard op
- **Radiant Comeback** — Ability text mentions discard but JSON has no discard op
- **Recycle For 5** — Ability text mentions discard but JSON has no discard op
- **Return from the Depths** — Ability text mentions discard but JSON has no discard op
- **Risky Recovery** — Ability text mentions discard but JSON has no discard op
- **Roller Dogs** — Ability text mentions discard but JSON has no discard op
- **Second Wind** — Ability text mentions discard but JSON has no discard op
- **The Heroes Favorite Hot Dogs** — Ability text mentions discard but JSON has no discard op
- **Trash Bandit** — Ability text mentions discard but JSON has no discard op
- **Weapon Lineage** — Ability text mentions discard but JSON has no discard op
- **Wildcard Wager** — Ability text mentions discard but JSON has no discard op

### `missing_hd_op` (info, 21 cards)

- **3-Dog-Special** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **50/50 Plays on Sale** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Add Firepower** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Back-Up Magic** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Banked Power** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Belly Buster** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Buff Or Debuff** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Bull Market** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Bundle Deal** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Copycat** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Drain And Deny** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Emergency Shutdown** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Flash Sale** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Ghost Dog** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Hot Dog Dominance** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **It's Gonna Cost Ya** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Pay It For Me** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Pinch HItter** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Recycle For 5** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Running On Fumes** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent
- **Second Wind** — Ability text mentions Hot Dogs but JSON has no HD-related op or persistent

### `missing_sub_op` (info, 5 cards)

- **10 For A Sub** — Ability text mentions substitution but JSON has no substitution op
- **Hot Dog Dominance** — Ability text mentions substitution but JSON has no substitution op
- **No Retreat** — Ability text mentions substitution but JSON has no substitution op
- **Pay It For Me** — Ability text mentions substitution but JSON has no substitution op
- **Substitution Boost** — Ability text mentions substitution but JSON has no substitution op

### `placeholder_op` (warning, 2 cards)

- **Pick Your Poison** — Card uses ONLY op:"note" — needs a concrete implementation
- **Scare Tactics** — Card uses ONLY op:"note" — needs a concrete implementation


# Play Effects Audit

_383 entries · 81 known ops · **0 errors** · **15 warnings** · **0 info** · **369 clean**_

Run with: `python3 scripts/audit_play_effects.py`

## Findings by category

### `unread_op_field` (warning, 15 cards)

- **Dumpster Battle** — Op 'swap_active_with_discard' has JSON field 'if_possible' the engine never reads — value is silently dropped
- **Forced Substitution** — Op 'force_substitute' has JSON field 'when' the engine never reads — value is silently dropped
- **Get What You Pay For** — Op 'variable_cost_bonus' has JSON field 'source_hd' the engine never reads — value is silently dropped
- **Ghost Dog** — Op 'transform_to_hot_dog' has JSON field 'immune_to_removal' the engine never reads — value is silently dropped
- **Ghost Dog** — Op 'transform_to_hot_dog' has JSON field 'discard_on_spend' the engine never reads — value is silently dropped
- **Last-Minute Re-Org** — Op 'swap_active_with_future_hero' has JSON field 'blind' the engine never reads — value is silently dropped
- **Lineup Randomizer** — Op 'replace_all_unrevealed_with_top_hero_deck' has JSON field 'preserve_order' the engine never reads — value is silently dropped
- **Lucky Discard** — Op 'discard_top' has JSON field 'reveal' the engine never reads — value is silently dropped
- **Might Of The Underdog** — Op 'draw' has JSON field 'reveal_to' the engine never reads — value is silently dropped
- **Pay It For Me** — Op 'transfer_sub_cost' has JSON field 'when' the engine never reads — value is silently dropped
- **Playbook Knowledge** — Op 'reveal_top_reorder_or_bottom' has JSON field 'chooser' the engine never reads — value is silently dropped
- **Restricted List** — Op 'cap_opponent_plays' has JSON field 'max' the engine never reads — value is silently dropped
- **Second Wind** — Op 'shuffle_from_discard_to_deck' has JSON field 'exclude_kind' the engine never reads — value is silently dropped
- **The Perfect Offense** — Op 'cancel_opponent_plays' has JSON field 'retroactive' the engine never reads — value is silently dropped
- **Transparency Clause** — Op 'force_reveal_from_hand' has JSON field 'chooser' the engine never reads — value is silently dropped


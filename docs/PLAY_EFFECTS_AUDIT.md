# Play Effects Audit

_383 entries · 81 known ops · **0 errors** · **0 warnings** · **2 info** · **381 clean**_

Run with: `python3 scripts/audit_play_effects.py`

## Findings by category

### `missing_discard_op` (info, 1 cards)

- **Power Pick** — Ability text mentions discard but JSON has no discard op or read

### `missing_sub_op` (info, 1 cards)

- **Substitution Boost** — Ability text mentions substitution but JSON has no substitution op


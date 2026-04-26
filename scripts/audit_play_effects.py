#!/usr/bin/env python3
"""
audit_play_effects.py — End-to-end auditor for play-effects.json.

Walks every entry in play-effects.json and cross-checks it against
(a) its JSON shape, (b) the corresponding card's ability text in
display-cards.json, and (c) the executor's known op vocabulary
(parsed out of BOBAPlaybook/Store/PlayEffects.swift).

Surfaces a markdown report grouped by severity then by card so we
can fix issues programmatically instead of hunting them by playing
the game.

Usage:
    python3 scripts/audit_play_effects.py
    python3 scripts/audit_play_effects.py --json   # raw JSON output

Outputs:
    docs/PLAY_EFFECTS_AUDIT.md  (markdown report)
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
PLAY_EFFECTS_PATH = ROOT / "BOBAPlaybook" / "play-effects.json"
DISPLAY_CARDS_PATH = ROOT / "BOBAPlaybook" / "display-cards.json"
EXECUTOR_PATH = ROOT / "BOBAPlaybook" / "Store" / "PlayEffects.swift"
OUTPUT_PATH = ROOT / "docs" / "PLAY_EFFECTS_AUDIT.md"


# ─── Severity / Finding model ─────────────────────────────────────


@dataclasses.dataclass
class Finding:
    card: str
    severity: str  # error | warning | info
    category: str
    message: str

    def to_dict(self) -> dict:
        return dataclasses.asdict(self)


# ─── Loaders ──────────────────────────────────────────────────────


def load_play_effects() -> dict[str, dict]:
    raw = json.loads(PLAY_EFFECTS_PATH.read_text())
    return raw.get("entries") or raw  # support either nested or flat shape


def load_catalog() -> dict[str, dict]:
    """Index Play cards by name."""
    cards = json.loads(DISPLAY_CARDS_PATH.read_text())
    out: dict[str, dict] = {}
    for c in cards:
        if c.get("cardType") == "Play":
            out[c["name"]] = c
    return out


def load_known_ops() -> set[str]:
    """Parse the `knownOps` set out of PlayEffects.swift so we don't
    hard-code a duplicate vocabulary list that could drift."""
    src = EXECUTOR_PATH.read_text()
    # Find the knownOps Set literal
    m = re.search(r"private static let knownOps: Set<String> = \[(.*?)\]", src, re.DOTALL)
    if not m:
        print("⚠️  Could not parse knownOps from PlayEffects.swift", file=sys.stderr)
        return set()
    body = m.group(1)
    # Strip comments
    body = re.sub(r"//.*", "", body)
    return set(re.findall(r'"([^"]+)"', body))


# Triggers the engine actually fires. Persistent entries with any
# other trigger value silently install but never run their effect.
# These are the strings the engine passes to firePersistentTriggers
# (in PracticeStore.swift) plus the special-case scopes
# applyContinuousPersistents accepts.
KNOWN_TRIGGERS: set[str] = {
    "continuous",
    "battle_start",       # legacy alias of on_battle_start; handled by applyContinuousPersistents
    "on_battle_start",
    "on_battle_win",
    "on_battle_loss",
    "on_plays_resolved",
    "on_opp_play",        # dice_gate
    "on_turn_end",        # auto_lose_battle
}


# ─── Walkers / helpers ────────────────────────────────────────────


def walk_ops(node: Any):
    """Yield every (op, step_dict) found anywhere in a nested entry."""
    if isinstance(node, dict):
        if "op" in node and isinstance(node.get("op"), str):
            yield node["op"], node
        for v in node.values():
            yield from walk_ops(v)
    elif isinstance(node, list):
        for item in node:
            yield from walk_ops(item)


def has_conditional(entry: dict) -> bool:
    """True if any `if` or `branches` block exists anywhere."""
    def walk(node):
        if isinstance(node, dict):
            if "if" in node or "branches" in node:
                return True
            return any(walk(v) for v in node.values())
        if isinstance(node, list):
            return any(walk(v) for v in node)
        return False
    return walk(entry)


def all_ops(entry: dict) -> set[str]:
    return {op for op, _ in walk_ops(entry)}


def all_targets(entry: dict) -> set[str]:
    out: set[str] = set()
    for _, step in walk_ops(entry):
        if isinstance(step.get("target"), str):
            out.add(step["target"])
    return out


def all_metrics(entry: dict) -> set[str]:
    """Every `metric` string AND condition `type` string appearing
    anywhere in the entry tree. Used to recognize that a card READS
    something (HD count, discard count, etc.) even if it doesn't
    have a corresponding mutating op."""
    out: set[str] = set()
    def walk(node, in_cond=False):
        if isinstance(node, dict):
            m = node.get("metric")
            if isinstance(m, str): out.add(m)
            elif isinstance(m, dict):
                t = m.get("type")
                if isinstance(t, str): out.add(t)
            # Condition `type` — `if: { type: "discard_count" }` etc.
            if in_cond:
                t = node.get("type")
                if isinstance(t, str): out.add(t)
            for k, v in node.items():
                # `if` / `requires` / sub-`of` arrays carry conditions
                walk(v, in_cond=in_cond or k in ("if", "requires", "of", "and", "or", "not", "all", "any"))
        elif isinstance(node, list):
            for v in node: walk(v, in_cond=in_cond)
    walk(entry)
    return out


def all_from_sources(entry: dict) -> set[str]:
    """Every `from` value (e.g. hd_recover from:"discard")."""
    out: set[str] = set()
    def walk(node):
        if isinstance(node, dict):
            f = node.get("from")
            if isinstance(f, str): out.add(f)
            for v in node.values(): walk(v)
        elif isinstance(node, list):
            for v in node: walk(v)
    walk(entry)
    return out


def all_triggers(entry: dict) -> set[str]:
    """Every `trigger` value found in any persistent block."""
    out: set[str] = set()
    for p in (entry.get("persistent") or []):
        if isinstance(p, dict) and isinstance(p.get("trigger"), str):
            out.add(p["trigger"])
    return out


def all_string_values(entry: dict, key: str) -> set[str]:
    """Every value found at any nested `key` field, when stringy."""
    out: set[str] = set()
    def walk(node):
        if isinstance(node, dict):
            v = node.get(key)
            if isinstance(v, str): out.add(v)
            for x in node.values(): walk(x)
        elif isinstance(node, list):
            for x in node: walk(x)
    walk(entry)
    return out


def all_deltas(entry: dict) -> tuple[list[int], bool]:
    """Returns (literal_deltas, has_formula_deltas).

    Formula deltas (`delta: {factor: N, metric: "..."}` or
    `variable_cost_bonus` with `factor`/`per_hd`) can't be matched
    against ability text claims because their final value depends
    on runtime state — but we still need to know they exist so the
    auditor doesn't false-positive a "missing delta" finding."""
    literals: list[int] = []
    has_formula = False
    def walk(node):
        nonlocal has_formula
        if isinstance(node, dict):
            d = node.get("delta")
            if isinstance(d, int):
                literals.append(d)
            elif isinstance(d, dict):
                has_formula = True
            # variable_cost_bonus (Get What You Pay For etc.) and
            # similar multiplier ops live as `factor` / `per_hd`
            # rather than `delta`. Treat them as formula deltas so
            # text claims like "+10 per HD" don't trip the auditor.
            if isinstance(node.get("factor"), int) or isinstance(node.get("per_hd"), int):
                has_formula = True
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk(entry)
    return literals, has_formula


# ─── Per-card audits ──────────────────────────────────────────────


def audit_card(name: str, entry: dict, card: dict | None,
               known_ops: set[str]) -> list[Finding]:
    fnd: list[Finding] = []

    # ── Catalog presence ─────────────────────────────────────────
    if card is None:
        fnd.append(Finding(name, "warning", "catalog",
                           "No Play card in catalog matches this entry"))
        return fnd

    ability = (card.get("playAbility") or "").strip()
    lower = ability.lower()

    # ── Cost mismatch ────────────────────────────────────────────
    if isinstance(entry.get("cost"), int) and isinstance(card.get("playCost"), int):
        if entry["cost"] != card["playCost"]:
            fnd.append(Finding(name, "warning", "cost_mismatch",
                               f"JSON cost {entry['cost']} ≠ catalog playCost {card['playCost']}"))

    # ── Empty effects[] AND empty persistent[] ───────────────────
    has_effects = bool(entry.get("effects"))
    has_persistent = bool(entry.get("persistent"))
    if not has_effects and not has_persistent:
        fnd.append(Finding(name, "error", "empty_entry",
                           "Entry has neither effects nor persistent — card will do nothing"))

    # ── Unknown op vocabulary ────────────────────────────────────
    used = all_ops(entry)
    unknown = used - known_ops
    if unknown:
        fnd.append(Finding(name, "warning", "unknown_op",
                           f"Uses op(s) not in executor vocabulary: {sorted(unknown)}"))

    # ── op:"note" placeholders ───────────────────────────────────
    # Only flag when the entry has NO functional op alongside the
    # note. A note is a no-op in the executor — fine as inline
    # documentation alongside a real power/hd/persistent op, but a
    # bug if it's the only effect the card produces.
    if "note" in used and not (used - {"note"}) and not has_persistent:
        fnd.append(Finding(name, "warning", "placeholder_op",
                           'Card uses ONLY op:"note" — needs a concrete implementation'))

    # ── requires gate sanity ─────────────────────────────────────
    req = entry.get("requires")
    if isinstance(req, dict):
        req_type = req.get("type")
        # Validate shape
        if req_type not in {
            "battle_num", "battles_lost", "battles_won", "weapon", "hd_count",
            "hand_count", "discard_count", "battles_remaining",
            "all", "any", "and", "or", "not", "prev_battle"
        }:
            fnd.append(Finding(name, "warning", "requires_unknown_type",
                               f"`requires.type` = '{req_type}' may not be recognized by evalCondition"))

    # ── Battle gate text vs JSON ─────────────────────────────────
    battle_text_mentions = re.findall(
        r"(?:in\s+battle\s+(\d+)|battle\s+(\d+)\s+(?:or|to|through)|first\s+(\d+)\s+battles)",
        lower,
    )
    has_battle_scoped_persistent = any(
        isinstance(p, dict) and isinstance(p.get("scope"), str)
        and re.match(r"^(battle_\d|battles_\d)", p["scope"])
        for p in (entry.get("persistent") or [])
    )
    if (battle_text_mentions and not has_conditional(entry) and req is None
            and not has_battle_scoped_persistent):
        fnd.append(Finding(name, "warning", "missing_battle_gate",
                           "Ability mentions a specific battle number but card has no `requires` gate or conditional"))

    # ── Power claim vs JSON delta ────────────────────────────────
    plus_claims = [int(x) for x in re.findall(r"(?<![-/])\+(\d+)", ability)]
    minus_claims = [int(x) for x in re.findall(r"(?:gets?|loses?|gives?\s+it)\s+-(\d+)", lower)]
    deltas, has_formula_delta = all_deltas(entry)
    pos_deltas = [d for d in deltas if d > 0]
    neg_deltas = [d for d in deltas if d < 0]
    # Cards using a formula delta (e.g. "+10 per Hot Dog") can't be
    # checked against literal text claims at audit time — the value
    # depends on runtime state.
    if not has_formula_delta:
        for claim in set(plus_claims):
            if claim not in pos_deltas:
                fnd.append(Finding(name, "warning", "missing_pos_delta",
                                   f"Ability text claims +{claim} but no JSON delta of {claim} found"))
        for claim in set(minus_claims):
            if -claim not in neg_deltas:
                fnd.append(Finding(name, "warning", "missing_neg_delta",
                                   f"Ability text claims -{claim} but no JSON delta of -{claim} found"))

    metrics = all_metrics(entry)
    sources = all_from_sources(entry)
    triggers = all_triggers(entry)
    exclude_kinds = all_string_values(entry, "exclude_kind")

    # ── Hot Dog mentions ─────────────────────────────────────────
    # Recognize HD ops, HD-driving intents, formula reads of hd_count,
    # play_cost_delta (transforms HD cost of plays), block_hd_recover
    # (denies HDs), substitute_free / transfer_sub_cost (HD-cost
    # mods on substitutions), and copy_last_play (re-charges HD).
    # Also recognize transform_to_hot_dog (literal HD transform) and
    # `exclude_kind: "hot_dog"` (HD filter on a shuffle/discard op).
    hd_text = "hot dog" in lower
    hd_ops = used & {
        "hd", "hd_recover", "swap_hd_counts", "variable_cost_bonus",
        "play_cost_delta", "block_hd_recover", "copy_last_play",
        "substitute_free", "force_substitute", "transfer_sub_cost",
        "transform_to_hot_dog",
    }
    hd_metric_reads = bool(metrics & {
        "hd_count", "hd_count_before_cost", "hd_discarded_this_battle",
        "opponent_hd_used_this_battle",
    })
    # Cards that filter the discard pile by hot_dog implicitly
    # reference HDs ("Shuffle pile excluding Hot Dogs", "+5 per
    # card except Hot Dogs").
    hd_kind_filter = "hot_dog" in exclude_kinds or any(
        "exclude" in m or "_excluding_hd" in m for m in metrics
    )
    if hd_text and not (hd_ops or has_persistent or hd_metric_reads or hd_kind_filter):
        # Skip cost-only mentions ("costs 0 Hot Dogs", "pay X Hot Dogs to play")
        if not re.search(r"(costs?|pay)\s+\d+\s+hot\s+dog", lower):
            fnd.append(Finding(name, "info", "missing_hd_op",
                               "Ability text mentions Hot Dogs but JSON has no HD-related op, persistent, or metric read"))

    # ── Discard mentions ─────────────────────────────────────────
    # A card "mentions discard" can mean (a) it discards something
    # — needs a discard op — or (b) it reads/recovers from the
    # discard pile — covered by swap_active_with_discard,
    # shuffle_from_discard_to_deck, hd_recover from:"discard", or
    # a `discard_count` / `discard_pile_*` metric read.
    if re.search(r"\bdiscard\b", lower):
        discard_mutation_ops = used & {
            "discard", "discard_top", "discard_hand_all",
            "discard_hero", "discard_hero_from_hand",
            "discard_revealed", "discard_revealed_hero", "discard_revealed_play",
            # Implicit-discard ops (the discard happens as a side
            # effect of the op's main behavior):
            "name_and_discard",                              # forces opp to discard a named play
            "replace_all_unrevealed_with_top_hero_deck",     # discards unrevealed heroes
            "replace_active_with_top_hero_deck",             # discards old active
            "replace_next_with_top_hero_deck",               # discards next-battle hero
            "replace_active_from_hand",                      # discards active
            "transform_to_hot_dog",                          # consumes/discards the play
            "discard_other_revealed",                        # see executor handler
            "add_chosen_revealed_to_hand_discard_rest",      # discards the unchosen
        }
        discard_read_ops = used & {
            "swap_active_with_discard", "shuffle_from_discard_to_deck",
            "shuffle_revealed_back",
        }
        discard_metric_reads = any(m.startswith("discard_") or "discard_pile" in m for m in metrics)
        recovers_from_discard = "discard" in sources
        # `hd ... via:"discard"` is a discard-flavored HD spend
        via_discard = any(
            isinstance(s, dict) and s.get("via") == "discard"
            for _, s in walk_ops(entry)
        )
        if not (discard_mutation_ops or discard_read_ops
                or discard_metric_reads or recovers_from_discard
                or via_discard or has_persistent):
            fnd.append(Finding(name, "info", "missing_discard_op",
                               "Ability text mentions discard but JSON has no discard op or read"))

    # ── Coin flip / dice mentions ────────────────────────────────
    if "flip a coin" in lower:
        if "coin_flip" not in used and "compound_roll" not in used:
            fnd.append(Finding(name, "warning", "missing_coin_op",
                               "Ability text mentions coin flip but JSON has no coin_flip op"))
    if re.search(r"roll\s+(?:a\s+)?(?:di(?:e|ce)|d\d+)", lower):
        if not (used & {"dice_roll", "compound_roll", "versus_dice_roll", "dice_roll_again", "dice_gate"}):
            fnd.append(Finding(name, "warning", "missing_dice_op",
                               "Ability text mentions dice roll but JSON has no dice op"))

    # ── Substitution mentions ────────────────────────────────────
    if "substitut" in lower:
        sub_ops = used & {
            "force_substitute", "substitute_free", "block_sub",
            "swap_active_with_hand", "swap_active_with_discard",
            "transfer_sub_cost", "play_cost_delta",
        }
        # Persistent triggers and conditional reads count too —
        # cards like Substitution Boost (trigger: on_substitute),
        # 10 For A Sub (if: substituted_this_battle), No Retreat
        # (persistent reads substituted_this_battle).
        sub_signals = (
            "on_substitute" in triggers
            or "substituted_this_battle" in metrics
            or "include_substitutions" in (all_string_values(entry, "kind") | metrics)
        )
        if not sub_ops and not sub_signals:
            fnd.append(Finding(name, "info", "missing_sub_op",
                               "Ability text mentions substitution but JSON has no substitution op"))

    # ── "Both players" / opponent mention ────────────────────────
    # Skip the lifecycle phrase "after both players finish their turn"
    # which is a TIMING signal, not a multi-player effect target.
    targets = all_targets(entry)
    is_lifecycle_phrase = bool(re.search(
        r"both\s+players?\s+(finish|complete|end|are\s+done)",
        lower,
    ))
    if "both players" in lower and not is_lifecycle_phrase:
        if not (targets & {"both", "opponent"}) and "versus_dice_roll" not in used:
            fnd.append(Finding(name, "warning", "missing_both_target",
                               'Ability mentions "both players" but JSON targets neither both nor opponent'))

    # ── Stub ops (in knownOps but executor only emits a notification) ──
    # These ops pass the unknown-op check but their actual behavior is
    # a no-op — they print "Did X" without performing X. Real example:
    # Opp's Choice used `deploy_chosen_revealed` and `discard_other_
    # revealed`, both of which only emit notifications. The card looked
    # like it should "send hero to discard, draw 2, opp picks, deploy"
    # but produced no game-state change. Update this list when an op
    # gets a real executor handler.
    stub_ops = used & {
        "deploy_chosen_revealed",
        "add_chosen_revealed_to_hand_discard_rest",
        "discard_other_revealed",
        "discard_revealed",
        "discard_revealed_hero",
        "shuffle_revealed_back",
    }
    # Only flag when the ENTIRE entry depends on stubs — if a real op
    # accompanies the stub, the card still produces a real effect and
    # the stub is just a flavor notification.
    real_ops = used - stub_ops - {"note", "choice"}
    if stub_ops and not real_ops and not has_persistent:
        fnd.append(Finding(name, "warning", "stub_op",
                           f"Card relies entirely on stubbed op(s) {sorted(stub_ops)} — "
                           f"executor only emits a notification, no real effect runs"))

    # ── Single-option `choice` op (no real choice) ───────────────
    # `choice` is supposed to surface multiple alternatives. A choice
    # block with one option is a structural mistake — it adds a layer
    # of indirection but reduces to "always run the option's effects".
    # In practice the executor's `choice` handler is also a no-op, so
    # such cards don't fire anything at all (Opp's Choice was the
    # canonical example).
    for op_name, step in walk_ops(entry):
        if op_name == "choice":
            opts = step.get("options")
            if isinstance(opts, list) and len(opts) <= 1:
                fnd.append(Finding(name, "warning", "single_option_choice",
                                   f"`choice` op has {len(opts)} option(s); collapse to direct ops "
                                   f"or add real alternatives"))

    # ── Unknown persistent trigger ───────────────────────────────
    # A persistent with an unrecognized trigger string silently
    # installs but never fires. Real example: Overcommited used
    # `on_play_run`, which was never wired into the engine; the
    # card looked correct in the JSON but did nothing on the next
    # battle (and worse, the empty `effects[]` made it fall back
    # to the regex resolver, which misfired on the CURRENT battle).
    for p in (entry.get("persistent") or []):
        if not isinstance(p, dict): continue
        trig = p.get("trigger")
        if not isinstance(trig, str): continue
        if trig not in KNOWN_TRIGGERS:
            fnd.append(Finding(name, "warning", "unknown_trigger",
                               f"Persistent trigger '{trig}' is not in the engine's "
                               f"firePersistentTriggers vocabulary — effect will install "
                               f"but never fire. Allowed: {sorted(KNOWN_TRIGGERS)}"))

    # ── Overlapping persistent scopes ────────────────────────────
    # Two persistents with the same effect op + overlapping scopes
    # multiply-fire. Lose 1 To Win 2 (Hopefully) was the canonical
    # example: one persistent at scope=next_battle, another at scope=
    # next_2_battles, same +15 power effect → next battle got +30
    # instead of the intended +15-each-of-next-2.
    persistents = entry.get("persistent") or []
    if isinstance(persistents, list) and len(persistents) >= 2:
        # Build a fingerprint per persistent that captures effect + trigger.
        # Same fingerprint + scopes that overlap → flag.
        def overlap(a: str, b: str) -> bool:
            # Conservative: any pair where one scope is a strict subset
            # of the other (e.g. next_battle ⊆ next_2_battles), or
            # where both scopes match the same battle index.
            pairs = {
                ("next_battle", "next_2_battles"),
                ("next_battle", "next_N_battles"),
                ("next_battle", "this_and_next"),
                ("next_battle", "rest_of_game"),
                ("this_battle", "this_and_next"),
                ("this_battle", "rest_of_game"),
                ("this_and_next", "next_2_battles"),
                ("this_and_next", "rest_of_game"),
                ("next_2_battles", "rest_of_game"),
                ("next_N_battles", "rest_of_game"),
            }
            return (a, b) in pairs or (b, a) in pairs or a == b
        for i in range(len(persistents)):
            for j in range(i + 1, len(persistents)):
                pi, pj = persistents[i], persistents[j]
                if not (isinstance(pi, dict) and isinstance(pj, dict)): continue
                ei = pi.get("effect") or {}
                ej = pj.get("effect") or {}
                if ei.get("op") != ej.get("op"): continue
                # Same op + different target on the inner effect is a
                # distinct effect (e.g. Lunch Table recovers HDs for
                # both self and opponent — two persistents, different
                # targets, no overlap).
                if ei.get("target") != ej.get("target"): continue
                if pi.get("trigger") != pj.get("trigger"): continue
                if overlap(pi.get("scope", ""), pj.get("scope", "")):
                    fnd.append(Finding(name, "warning", "overlapping_persistent",
                                       f"Persistent entries [{i}] scope={pi.get('scope')!r} and "
                                       f"[{j}] scope={pj.get('scope')!r} share trigger "
                                       f"{pi.get('trigger')!r} + effect op {ei.get('op')!r} — "
                                       f"both will fire and stack"))

    # ── Conditional that doesn't differ across contexts ──────────
    # (skip — needs engine simulation; left for runtime smoke testing)

    return fnd


# ─── Reporting ────────────────────────────────────────────────────


def to_markdown(findings: list[Finding], total_cards: int, known_ops_count: int) -> str:
    by_severity = {"error": 0, "warning": 0, "info": 0}
    for f in findings:
        by_severity[f.severity] = by_severity.get(f.severity, 0) + 1
    clean = total_cards - len({f.card for f in findings})

    out = "# Play Effects Audit\n\n"
    out += f"_{total_cards} entries · {known_ops_count} known ops · "
    out += f"**{by_severity['error']} errors** · "
    out += f"**{by_severity['warning']} warnings** · "
    out += f"**{by_severity['info']} info** · "
    out += f"**{clean} clean**_\n\n"
    out += "Run with: `python3 scripts/audit_play_effects.py`\n\n"

    by_cat: dict[str, list[Finding]] = defaultdict(list)
    for f in findings:
        by_cat[f.category].append(f)

    out += "## Findings by category\n\n"
    for cat in sorted(by_cat.keys()):
        items = by_cat[cat]
        sev = items[0].severity
        out += f"### `{cat}` ({sev}, {len(items)} cards)\n\n"
        for f in sorted(items, key=lambda x: x.card):
            out += f"- **{f.card}** — {f.message}\n"
        out += "\n"
    return out


# ─── Entry point ──────────────────────────────────────────────────


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--json", action="store_true", help="Print raw JSON to stdout")
    args = p.parse_args()

    entries = load_play_effects()
    catalog = load_catalog()
    known_ops = load_known_ops()

    findings: list[Finding] = []
    for name in sorted(entries.keys()):
        findings.extend(audit_card(name, entries[name], catalog.get(name), known_ops))

    if args.json:
        print(json.dumps([f.to_dict() for f in findings], indent=2))
        return 0

    # Markdown report
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    md = to_markdown(findings, len(entries), len(known_ops))
    OUTPUT_PATH.write_text(md)

    by_sev = {"error": 0, "warning": 0, "info": 0}
    for f in findings:
        by_sev[f.severity] = by_sev.get(f.severity, 0) + 1
    print(f"📋 Audit complete: {len(entries)} entries · "
          f"{by_sev['error']} errors · "
          f"{by_sev['warning']} warnings · "
          f"{by_sev['info']} info")
    print(f"📄 Report: {OUTPUT_PATH.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

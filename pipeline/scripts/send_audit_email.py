#!/usr/bin/env python3
"""
send_audit_email.py — Stage C audit email via Resend

Reads the most recent commit-type pipeline_runs row for the current
GH Actions run, formats a one-page audit email, and sends to
ben@bobaplaybook.com via Resend.

The email is intentionally tap-friendly: every merged card is a row
with a thumbnail, a score, and a Universal Link that opens the iOS
app on bobaplaybook.com/?card={bobaId}. Skim, tap, verify in 60 sec.

USAGE
─────
    python pipeline/scripts/send_audit_email.py \\
        --pr-url       https://github.com/bhwilkoff/BOBA-Playbook/pull/123 \\
        --to           ben@bobaplaybook.com \\
        --from         pipeline@bobaplaybook.com

ENV (required):
    SUPABASE_URL, SUPABASE_SERVICE_KEY
    RESEND_API_KEY

Resend free tier: 3000 emails/mo, 100/day. We send 1 email per Stage C
run (weekly cadence) — comfortably free.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Optional

import requests
from supabase import Client, create_client


CDN_BASE = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev"
WEB_BASE = "https://bobaplaybook.com"


def fetch_latest_commit_run(supabase: Client, gh_run_id: Optional[str]) -> Optional[dict]:
    """Return the matching commit run, or the most recent if no GH run id."""
    q = (supabase.table("pipeline_runs")
         .select("*")
         .eq("run_type", "commit")
         .order("started_at", desc=True)
         .limit(1))
    if gh_run_id:
        q = q.eq("gh_actions_run_id", gh_run_id)
    res = q.execute()
    return (res.data or [None])[0]


def build_email(run: dict, pr_url: Optional[str]) -> tuple[str, str, str]:
    """Return (subject, html_body, text_body) for the audit email."""
    summary = run.get("summary") or {}
    merged  = summary.get("merged_cards") or []
    n       = len(merged)

    subject = (f"BOBA pipeline · {n} card image{'s' if n != 1 else ''} merged"
               if n > 0 else
               f"BOBA pipeline · run completed (no cards merged)")

    # ─── HTML body (lightweight; supports gmail / iOS Mail rendering) ──
    rows = []
    for card in merged[:200]:
        bid     = card["boba_id"]
        score   = card.get("score") or 0
        margin  = card.get("margin")
        thumb   = f"{CDN_BASE}/thumbs/{card['image_file']}"
        link    = f"{WEB_BASE}/?card={bid}"
        margin_cell = f"{margin:.2f}" if margin is not None else "—"
        rows.append(
            f"<tr>"
            f"<td><a href='{link}'><img src='{thumb}' width='80' style='border-radius:4px'></a></td>"
            f"<td><a href='{link}' style='color:#00F5FF;text-decoration:none;font-family:monospace'>{bid}</a></td>"
            f"<td style='font-family:monospace'>{score:.2f}</td>"
            f"<td style='font-family:monospace'>{margin_cell}</td>"
            f"</tr>"
        )

    overflow = (
        f"<tr><td colspan='4' style='padding-top:16px;color:#999'>"
        f"+ {n - 200} more not shown — see PR for the full list."
        f"</td></tr>"
    ) if n > 200 else ""

    pr_link = (
        f"<p><strong>PR:</strong> <a href='{pr_url}'>{pr_url}</a></p>"
        if pr_url else
        "<p style='color:#999'>(No PR opened — no catalog diff this run.)</p>"
    )

    counts_block = (
        f"<ul style='line-height:1.6'>"
        f"<li><strong>Merged:</strong> {summary.get('winners_committed', 0)}</li>"
        f"<li><strong>Within-pipeline collisions:</strong> {summary.get('collisions', 0)}</li>"
        f"<li><strong>Upload failures:</strong> {summary.get('upload_failures', 0)}</li>"
        f"<li><strong>Started:</strong> {run.get('started_at')}</li>"
        f"<li><strong>Run log:</strong> <a href='{run.get('gh_actions_run_url') or '#'}'>"
        f"{run.get('gh_actions_run_id') or 'manual'}</a></li>"
        f"</ul>"
    )

    if n == 0:
        html = (
            f"<div style='font-family:system-ui,sans-serif;max-width:680px'>"
            f"<h2>BOBA pipeline · {subject}</h2>"
            f"<p>No cards crossed the AUTO threshold this run. Check the PR queue "
            f"for the REVIEW tier (pending your tap).</p>"
            f"{counts_block}"
            f"</div>"
        )
        text = (
            f"BOBA pipeline · run completed.\n"
            f"No cards merged. Check the PR queue for REVIEW-tier candidates."
        )
        return subject, html, text

    html = f"""
<div style='font-family:system-ui,sans-serif;max-width:680px;color:#222'>
  <h2 style='font-family:"Bebas Neue",system-ui,sans-serif;letter-spacing:0.05em'>BOBA pipeline · {n} card{'s' if n != 1 else ''} shipped</h2>
  <p>Auto-merged this run. Tap any thumbnail or bobaId to verify on the app.</p>
  {pr_link}
  {counts_block}
  <h3 style='margin-top:32px'>Merged cards</h3>
  <table cellpadding='8' cellspacing='0' style='border-collapse:collapse;width:100%'>
    <thead>
      <tr style='border-bottom:1px solid #ddd;text-align:left'>
        <th>Thumb</th><th>bobaId</th><th>Score</th><th>Margin</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows)}
      {overflow}
    </tbody>
  </table>
  <p style='margin-top:32px;color:#999;font-size:12px'>
    Sent by the BOBA Playbook image-sourcing pipeline. Reply to this email
    if any merge looks wrong — provide the bobaId and I'll roll it back.
  </p>
</div>
""".strip()

    text_lines = [f"BOBA pipeline · {subject}", ""]
    if pr_url:
        text_lines.append(f"PR: {pr_url}")
    text_lines.append("")
    for card in merged[:200]:
        bid    = card["boba_id"]
        score  = card.get("score") or 0
        margin = card.get("margin")
        m_str  = f" margin={margin:.2f}" if margin is not None else ""
        text_lines.append(f"  {bid}  score={score:.2f}{m_str}  {WEB_BASE}/?card={bid}")
    if n > 200:
        text_lines.append(f"  + {n - 200} more — see PR")
    text_lines.append("")
    text_lines.append("Reply to this email with the bobaId of any merge that looks wrong.")

    return subject, html, "\n".join(text_lines)


def send_email(api_key: str, sender: str, recipient: str,
               subject: str, html: str, text: str) -> dict:
    resp = requests.post(
        "https://api.resend.com/emails",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type":  "application/json",
        },
        json={
            "from":    sender,
            "to":      [recipient],
            "subject": subject,
            "html":    html,
            "text":    text,
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pr-url", default=None,
                    help="PR URL opened by Stage C (included in email body)")
    ap.add_argument("--to",   default="ben@bobaplaybook.com")
    ap.add_argument("--from", dest="sender", default="pipeline@bobaplaybook.com")
    args = ap.parse_args()

    api_key = os.environ.get("RESEND_API_KEY")
    if not api_key:
        sys.exit("RESEND_API_KEY not set")

    supabase = create_client(os.environ["SUPABASE_URL"],
                             os.environ["SUPABASE_SERVICE_KEY"])
    run = fetch_latest_commit_run(supabase, os.environ.get("GITHUB_RUN_ID"))
    if run is None:
        print("no commit run found — nothing to email")
        return

    subject, html, text = build_email(run, args.pr_url)
    print(f"sending to {args.to}: {subject}")

    res = send_email(api_key, args.sender, args.to, subject, html, text)
    print(f"  resend id: {res.get('id')}")


if __name__ == "__main__":
    main()

/**
 * Xcode Cloud → Discord webhook translator.
 *
 * Xcode Cloud POSTs its own JSON payload on build state changes; Discord
 * expects a specific embed shape. This Worker sits in the middle:
 * receives Apple's payload, reshapes into a Discord embed, forwards to
 * the configured Discord webhook URL.
 *
 * Config (set via `wrangler secret put`):
 *   DISCORD_WEBHOOK_URL — the full Discord webhook URL for the target channel
 *
 * Optional env var (wrangler.toml vars):
 *   NOTIFY_ON_RUNNING   — "true" to also fire on PENDING / RUNNING states.
 *                         Default: false (only notify on COMPLETE).
 *
 * Xcode Cloud workflow → Webhook setup:
 *   App Store Connect → Xcode Cloud → your workflow → ⓘ "Post Actions"
 *   add a Webhook with the Worker URL. No auth header is sent by Apple,
 *   so keep the Worker URL unguessable.
 */

// Discord embed colors (decimal RGB). Maps Xcode Cloud completion status
// to the color bar on the left of the embed.
const COLOR = {
  SUCCEEDED: 0x4CAF50,  // green
  FAILED:    0xE53935,  // red
  ERRORED:   0xE53935,  // red — infra/compile error, treat as fail
  CANCELED:  0x8A9BB0,  // steel — manual cancel, no alarm
  RUNNING:   0x00BFFF,  // cyan — informational
  PENDING:   0xA0A0C0,  // muted
};

const STATUS_EMOJI = {
  SUCCEEDED: "✅",
  FAILED:    "❌",
  ERRORED:   "⚠️",
  CANCELED:  "⏹️",
  RUNNING:   "🛠️",
  PENDING:   "⏳",
};

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return new Response("POST only", { status: 405 });
    }
    if (!env.DISCORD_WEBHOOK_URL) {
      return new Response("DISCORD_WEBHOOK_URL not configured", { status: 500 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response("Invalid JSON", { status: 400 });
    }

    // Apple nests everything under `data.attributes` for state-change
    // events; the older "ciBuildRun" wrapper is kept for compatibility
    // with workflow-created notifications.
    const run      = body.ciBuildRun?.attributes ?? body.data?.attributes ?? body.ciBuildRun ?? {};
    const workflow = body.ciWorkflow?.attributes ?? body.ciWorkflow ?? {};
    const product  = body.ciProduct?.attributes ?? body.ciProduct ?? {};
    const repo     = body.scmGitReference?.attributes ?? body.scmGitReference ?? {};

    const progress = (run.executionProgress ?? "").toUpperCase();
    const status   = (run.completionStatus  ?? "").toUpperCase();

    // Noise control — by default, only notify on COMPLETE runs. Apple
    // fires separate events at PENDING and RUNNING transitions; those
    // spam the channel. Set NOTIFY_ON_RUNNING="true" to opt back in.
    if (progress && progress !== "COMPLETE" && env.NOTIFY_ON_RUNNING !== "true") {
      return new Response("skipped: not a completion event", { status: 200 });
    }

    // Pick the best status signal available. Apple sometimes sends a
    // "complete" run with no completionStatus (e.g. mid-state), so fall
    // back to progress.
    const effective = status || progress || "UNKNOWN";
    const color  = COLOR[effective]        ?? 0x666680;
    const emoji  = STATUS_EMOJI[effective] ?? "ℹ️";

    const productName  = product.name      || "BOBA Playbook";
    const workflowName = workflow.name     || "Xcode Cloud";
    const buildNumber  = run.number != null ? `#${run.number}` : "";
    const branch       = repo.name || repo.kind || "";
    const startedISO   = run.startedDate   || run.startDate   || null;
    const finishedISO  = run.finishedDate  || run.endDate     || null;

    // Duration: parse ISO timestamps if both present.
    let duration = "";
    if (startedISO && finishedISO) {
      const secs = Math.max(0, Math.round((new Date(finishedISO) - new Date(startedISO)) / 1000));
      const m = Math.floor(secs / 60);
      const s = secs % 60;
      duration = m > 0 ? `${m}m ${s}s` : `${s}s`;
    }

    const embed = {
      title: `${emoji} ${productName} ${buildNumber} — ${effective}`.trim(),
      description: `**${workflowName}**${branch ? ` · \`${branch}\`` : ""}`,
      color,
      fields: [],
      timestamp: finishedISO || startedISO || new Date().toISOString(),
      footer: { text: "Xcode Cloud" },
    };
    if (duration)     embed.fields.push({ name: "Duration", value: duration, inline: true });
    if (run.sourceCommitInfo?.commitSha) {
      embed.fields.push({
        name:   "Commit",
        value:  `\`${String(run.sourceCommitInfo.commitSha).slice(0, 7)}\``,
        inline: true,
      });
    }
    const webUrl = run.links?.testflightURL || run.links?.selfURL;
    if (webUrl) embed.fields.push({ name: "Link", value: webUrl, inline: false });

    // Forward to Discord. Swallow errors — if Discord rejects, we still
    // want to 200 to Xcode Cloud so it doesn't mark the notification
    // as failed and retry in a loop.
    try {
      const res = await fetch(env.DISCORD_WEBHOOK_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ embeds: [embed] }),
      });
      if (!res.ok) {
        const text = await res.text().catch(() => String(res.status));
        console.log("[discord-forward] non-OK:", res.status, text.slice(0, 200));
      }
    } catch (err) {
      console.log("[discord-forward] error:", String(err));
    }

    return new Response("ok", { status: 200 });
  },
};

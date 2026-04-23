# Xcode Cloud → Discord webhook translator

A tiny Cloudflare Worker that takes Xcode Cloud's build-state webhook
payload and reshapes it into a Discord embed before forwarding it to
a Discord webhook URL.

## Why this exists

Xcode Cloud fires webhooks on workflow state changes, but the payload is
Apple's shape (`ciBuildRun`, `ciWorkflow`, `ciProduct`, …). Discord
expects a specific `{ embeds: [...] }` body. Rather than write a
translator in each consumer, one Worker handles it centrally.

## Deploy

```bash
cd workers/xcode-discord
wrangler secret put DISCORD_WEBHOOK_URL       # paste the Discord channel's webhook URL
wrangler deploy
```

After deploying, copy the Worker URL (something like
`https://boba-xcode-discord.<subdomain>.workers.dev/`) and paste it
into your Xcode Cloud workflow:

1. App Store Connect → **Xcode Cloud** → your workflow → edit
2. **Post Actions** → **Webhooks** → **Add Webhook**
3. Paste the Worker URL. Leave the payload format as `JSON`. Apple
   doesn't sign webhook requests, so the URL itself is the secret —
   don't share it.
4. Save. The next workflow run posts to Discord.

## Noise control

Xcode Cloud fires events at `PENDING`, `RUNNING`, and `COMPLETE`. By
default this Worker only forwards `COMPLETE` events to keep the channel
clean. To see every state transition, set the Worker variable:

```
wrangler vars put NOTIFY_ON_RUNNING true
```

(Or edit `wrangler.toml` and re-deploy.)

## Embed shape

- **Title**: `{emoji} {product} #{build} — {status}` (✅ success, ❌
  fail, ⚠️ errored, ⏹️ canceled).
- **Description**: workflow name + branch / ref.
- **Color**: green / red / steel by status.
- **Fields**: duration, commit SHA (first 7 chars), TestFlight link if
  present.
- **Timestamp**: the build's finish time.

## Troubleshooting

- **Nothing lands in Discord**: check `wrangler tail` for
  `[discord-forward] non-OK:` lines — Discord returns 400 on
  malformed embeds. Usually means an empty `description` field; the
  Worker guards against this but check the tail output.
- **Too many pings**: confirm `NOTIFY_ON_RUNNING` is unset or
  `"false"`.
- **401 / 404 from Discord**: webhook URL revoked. Regenerate in
  Discord → Edit Channel → Integrations → Webhooks, then
  `wrangler secret put DISCORD_WEBHOOK_URL` again.

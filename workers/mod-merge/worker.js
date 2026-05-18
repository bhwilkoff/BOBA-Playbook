/**
 * BOBA Playbook — Mod Image Merge Worker
 *
 * Why this exists: when an admin uploads a card image (or approves a
 * moderator's pending upload), the image needs to appear in the app
 * IMMEDIATELY — not on the next daily merge cron run. This Worker is
 * the server-side automation that closes that gap.
 *
 * Flow:
 *   1. Mod or admin uploads JPEG → Supabase Storage `mod-card-images`
 *      bucket. card_image_overrides row written with storage_path.
 *   2. If uploader is admin: row status='approved' immediately.
 *      If mod: row status='pending'; admin approves → status='approved'.
 *   3. iOS/web call this Worker (POST /merge) with the override id.
 *   4. Worker:
 *      - Verifies caller is admin via Supabase /auth/v1/user + role check
 *      - Fetches override row (service-role key bypasses RLS)
 *      - Looks up the target card to determine the R2 image filename
 *        (existing imageFile, OR generates one from boba_id when the
 *        card had no image yet)
 *      - Downloads JPEG from Supabase Storage
 *      - Uploads to R2 at full/{filename} AND thumbs/{filename}
 *      - Purges Cloudflare cache for both URLs so users see the new
 *        image within seconds (not the year-long edge cache TTL)
 *      - Updates row: status='applied', applied_image_file=filename,
 *        applied_at=now()
 *      - Returns { ok: true, imageFile, urls: [...] }
 *
 *   5. Client reads card_image_overrides with status='applied' on
 *      sign-in. Catalog rendering checks the runtime override map:
 *      if a card has an applied override, use applied_image_file
 *      regardless of cards.json's imageFile (handles first-image
 *      uploads where cards.json has imageFile=null until the next
 *      pipeline run).
 *
 * Endpoints:
 *   POST /merge
 *     Headers: Authorization: Bearer <admin_user_jwt>
 *     Body:    { "overrideId": "<uuid>" }
 *     Returns: 200 { ok, imageFile, urls } or 4xx/5xx with detail
 *
 * Trade-offs documented:
 *   • Thumb tier: this MVP uploads the SAME full-size JPEG to both
 *     full/ and thumbs/ R2 keys. Slightly more storage; functional.
 *     The daily merge pipeline can normalize WebP + proper thumb
 *     dimensions when it runs.
 *   • No WebP encoding here. Cloudflare Workers can't WebP-encode
 *     in-process without paid Image Resizing. JPEG bytes stored at
 *     a .webp filename work fine — clients render image bytes
 *     regardless of extension. The pipeline normalizes long-term.
 *
 * Configuration:
 *   wrangler.toml binds R2_CDN to boba-card-images bucket.
 *   Secrets via `wrangler secret put <NAME>`:
 *     SUPABASE_URL          https://<project>.supabase.co
 *     SUPABASE_SERVICE_KEY  service_role (bypasses RLS)
 *     CF_API_TOKEN          Zone-scoped token with Cache Purge permission
 *     CF_ZONE_ID            The zone serving pub-...r2.dev (or custom domain)
 */

const CDN_BASE = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev";

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

/// Resolve caller to a user record + role. Throws { status, error } on failure.
async function verifyAdmin(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw { status: 401, error: "Missing Authorization: Bearer <jwt>" };
  }
  const jwt = match[1];

  // Verify token + get user
  const meRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      "Authorization": `Bearer ${jwt}`,
      "apikey":        env.SUPABASE_SERVICE_KEY,
    },
  });
  if (!meRes.ok) throw { status: 401, error: "Invalid or expired token" };
  const me = await meRes.json();
  if (!me?.id) throw { status: 401, error: "Could not resolve user from token" };

  // Check role
  const roleRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/user_profiles?user_id=eq.${me.id}&select=role`,
    {
      headers: {
        "apikey":        env.SUPABASE_SERVICE_KEY,
        "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      },
    },
  );
  if (!roleRes.ok) throw { status: 500, error: "Could not load role" };
  const rows = await roleRes.json();
  const role = rows?.[0]?.role;
  if (role !== "admin") {
    throw { status: 403, error: "Admin role required for merge" };
  }
  return me.id;
}

/// Fetch the override row by id, with service-role auth.
async function fetchOverride(env, overrideId) {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/card_image_overrides?id=eq.${overrideId}&select=id,card_number,boba_id,action,status,storage_path`,
    {
      headers: {
        "apikey":        env.SUPABASE_SERVICE_KEY,
        "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      },
    },
  );
  if (!res.ok) throw { status: 502, error: "Could not load override row" };
  const rows = await res.json();
  if (!rows?.length) throw { status: 404, error: "Override not found" };
  return rows[0];
}

/// Update the override row to applied. Service-role auth.
async function markApplied(env, overrideId, appliedImageFile) {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/card_image_overrides?id=eq.${overrideId}`,
    {
      method: "PATCH",
      headers: {
        "apikey":        env.SUPABASE_SERVICE_KEY,
        "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
        "Content-Type":  "application/json",
        "Prefer":        "return=minimal",
      },
      body: JSON.stringify({
        status:              "applied",
        applied_image_file:  appliedImageFile,
        applied_at:          new Date().toISOString(),
      }),
    },
  );
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw { status: 502, error: "Failed to mark override applied", detail };
  }
}

/// Download the uploaded JPEG from Supabase Storage. Returns ArrayBuffer.
async function fetchImageBytes(env, storagePath) {
  const url = `${env.SUPABASE_URL}/storage/v1/object/mod-card-images/${storagePath}`;
  const res = await fetch(url, {
    headers: {
      "apikey":        env.SUPABASE_SERVICE_KEY,
      "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
    },
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw { status: 502, error: `Storage fetch failed (HTTP ${res.status})`, detail };
  }
  return await res.arrayBuffer();
}

/// Compute the target R2 filename. Existing imageFile from cards.json
/// wins (so replacements overwrite in place); falls back to a safe
/// bobaId-derived filename for cards that had no image.
function safeFilenameForBobaId(bobaId) {
  // Mirror scripts/merge_approved_additions.py:safe_filename_for_boba_id
  let out = "";
  for (const ch of bobaId) {
    if (/[A-Za-z0-9._-]/.test(ch)) out += ch;
    else out += "_";
  }
  out = out.replace(/[_-]+$/, "");
  return out + ".webp";
}

/// Cloudflare cache purge for an array of URLs. Best-effort — if the
/// token isn't configured, log + continue. Edge cache will eventually
/// rotate; we only need this to make the new image visible sooner.
async function purgeCloudflareCache(env, urls) {
  if (!env.CF_API_TOKEN || !env.CF_ZONE_ID) {
    return { purged: false, reason: "CF_API_TOKEN or CF_ZONE_ID missing" };
  }
  const res = await fetch(
    `https://api.cloudflare.com/client/v4/zones/${env.CF_ZONE_ID}/purge_cache`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.CF_API_TOKEN}`,
        "Content-Type":  "application/json",
      },
      body: JSON.stringify({ files: urls }),
    },
  );
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    return { purged: false, reason: `CF purge HTTP ${res.status}`, detail };
  }
  return { purged: true };
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }
    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_KEY) {
      return jsonResponse({ error: "Worker misconfigured (missing Supabase secrets)" }, 500);
    }
    if (!env.R2_CDN) {
      return jsonResponse({ error: "Worker misconfigured (missing R2 binding)" }, 500);
    }
    const url = new URL(request.url);
    if (url.pathname !== "/merge") {
      return jsonResponse({ error: "Not found" }, 404);
    }

    // 1. Auth — only admins can trigger merge
    let adminId;
    try { adminId = await verifyAdmin(request, env); }
    catch (e) { return jsonResponse({ error: e.error, detail: e.detail }, e.status || 401); }

    // 2. Parse body
    let body;
    try { body = await request.json(); }
    catch (_) { return jsonResponse({ error: "Body must be JSON" }, 400); }
    const overrideId = body?.overrideId;
    if (!overrideId) return jsonResponse({ error: "Missing overrideId" }, 400);

    // 3. Fetch override row
    let row;
    try { row = await fetchOverride(env, overrideId); }
    catch (e) { return jsonResponse({ error: e.error, detail: e.detail }, e.status || 500); }

    if (row.action !== "replace") {
      return jsonResponse({
        error: `Merge only supports action=replace (got ${row.action})`,
      }, 400);
    }
    if (row.status !== "approved") {
      return jsonResponse({
        error: `Override must be status=approved before merge (got ${row.status})`,
      }, 400);
    }
    if (!row.storage_path) {
      return jsonResponse({ error: "Override row has no storage_path" }, 400);
    }

    // 4. Decide R2 target filename. If the override row carries a
    //    boba_id, derive the filename from it. (cards.json lookup
    //    would be ideal but the Worker would need to bundle/fetch the
    //    catalog — skipping for v1; the iOS/web client resolves the
    //    final URL via applied_image_file on the override row.)
    const bid = row.boba_id || row.card_number || overrideId;
    const filename = safeFilenameForBobaId(bid);

    // 5. Download from Supabase Storage
    let bytes;
    try { bytes = await fetchImageBytes(env, row.storage_path); }
    catch (e) { return jsonResponse({ error: e.error, detail: e.detail }, e.status || 502); }

    // 6. Upload to R2 — both tiers (MVP uses full JPEG for thumb too;
    //    daily pipeline normalizes later).
    try {
      const fullKey  = `full/${filename}`;
      const thumbKey = `thumbs/${filename}`;
      const meta = {
        httpMetadata: {
          contentType:  "image/jpeg",   // bytes are JPEG; CDN serves as-is
          cacheControl: "public, max-age=300",  // 5 min — lets cache-purge propagate before locking in
        },
      };
      await env.R2_CDN.put(fullKey,  bytes, meta);
      await env.R2_CDN.put(thumbKey, bytes, meta);

      // 7. Purge Cloudflare edge cache so users see the new image
      //    within seconds. Best-effort — token may be unset.
      const urls = [`${CDN_BASE}/${fullKey}`, `${CDN_BASE}/${thumbKey}`];
      const purge = await purgeCloudflareCache(env, urls);

      // 8. Mark override applied so clients see the new filename
      await markApplied(env, overrideId, filename);

      return jsonResponse({
        ok:        true,
        imageFile: filename,
        urls,
        purge,
        adminId,
      });
    } catch (e) {
      return jsonResponse({ error: "R2 write failed", detail: String(e) }, 502);
    }
  },
};

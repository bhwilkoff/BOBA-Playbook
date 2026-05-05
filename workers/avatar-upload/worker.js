/**
 * BOBA Playbook — Avatar Upload Proxy
 *
 * Why this exists: client uploads to R2 require either signed URLs (a
 * round-trip per upload) or a Worker holding the R2 binding. The
 * Worker pattern is simpler and lets us validate content-type + size
 * + caller identity before the bucket write.
 *
 * Endpoints:
 *   POST /avatar
 *     Headers: Authorization: Bearer <user_jwt>
 *              Content-Type:  image/jpeg | image/png | image/webp
 *     Body:    raw image bytes (≤ 2 MB; client should crop to square
 *              and downscale to ≤ 512px before sending)
 *     Returns: 200 { "url": "...", "version": <timestamp> }
 *              The caller persists `url` to user_profiles.avatar_url
 *              via the set_avatar_url RPC. `version` lets the client
 *              cache-bust the previous avatar URL (?v=<ts>).
 *
 *   DELETE /avatar
 *     Headers: Authorization: Bearer <user_jwt>
 *     Returns: 200 { "ok": true }
 *              Removes the user's avatar from R2; client should clear
 *              user_profiles.avatar_url so the resolver falls back to
 *              the Discord avatar (or default silhouette).
 *
 * R2 layout: avatars/{user_id}.{ext} in the boba-card-images bucket.
 * Public URL: https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev/avatars/{user_id}.{ext}
 */

const CORS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Methods": "POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};

const CDN_BASE = "https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev";

const MAX_BYTES = 2 * 1024 * 1024;   // 2 MB cap after crop
const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);
const EXT_BY_TYPE = {
  "image/jpeg": "jpg",
  "image/png":  "png",
  "image/webp": "webp",
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

/// Verify the caller's JWT and return their user_id, or throw.
async function verifyUser(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw { status: 401, error: "Missing Authorization: Bearer <jwt>" };
  }
  const userJwt = match[1];
  const meRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      "Authorization": `Bearer ${userJwt}`,
      "apikey":        env.SUPABASE_SERVICE_KEY,
    },
  });
  if (!meRes.ok) {
    throw { status: 401, error: "Invalid or expired token" };
  }
  const me = await meRes.json();
  if (!me?.id) {
    throw { status: 401, error: "Could not resolve user from token" };
  }
  return me.id;
}

/// Find any existing avatar object for this user (any extension) and
/// delete it. Avoids stale .png hanging around after a .webp upload.
async function deleteAllUserAvatars(env, userId) {
  const list = await env.AVATARS.list({ prefix: `avatars/${userId}.` });
  if (!list?.objects?.length) return;
  await Promise.all(list.objects.map(o => env.AVATARS.delete(o.key)));
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_KEY) {
      return jsonResponse({ error: "Worker misconfigured (missing secrets)" }, 500);
    }
    if (!env.AVATARS) {
      return jsonResponse({ error: "Worker misconfigured (missing R2 binding)" }, 500);
    }

    const url = new URL(request.url);
    if (url.pathname !== "/avatar") {
      return jsonResponse({ error: "Not found" }, 404);
    }

    let userId;
    try { userId = await verifyUser(request, env); }
    catch (e) { return jsonResponse({ error: e.error }, e.status || 401); }

    if (request.method === "DELETE") {
      try {
        await deleteAllUserAvatars(env, userId);
        return jsonResponse({ ok: true });
      } catch (e) {
        return jsonResponse({ error: "Delete failed", detail: String(e) }, 500);
      }
    }

    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const contentType = (request.headers.get("Content-Type") || "").toLowerCase();
    if (!ALLOWED_TYPES.has(contentType)) {
      return jsonResponse({
        error: `Unsupported Content-Type. Use one of: ${Array.from(ALLOWED_TYPES).join(", ")}`,
      }, 415);
    }

    // Read the body once — Cloudflare Workers can stream R2 puts but
    // we need the byte length for the size cap. arrayBuffer is fine
    // for ≤ 2 MB.
    let bytes;
    try {
      bytes = await request.arrayBuffer();
    } catch (e) {
      return jsonResponse({ error: "Could not read request body", detail: String(e) }, 400);
    }
    if (!bytes || bytes.byteLength === 0) {
      return jsonResponse({ error: "Empty body" }, 400);
    }
    if (bytes.byteLength > MAX_BYTES) {
      return jsonResponse({
        error: `Avatar too large (${bytes.byteLength} bytes; max ${MAX_BYTES}). Crop + downscale on the client first.`,
      }, 413);
    }

    const ext = EXT_BY_TYPE[contentType];
    const key = `avatars/${userId}.${ext}`;

    try {
      // Drop any prior avatar with a different extension before writing
      // the new one. Otherwise the resolver doesn't know which is current.
      await deleteAllUserAvatars(env, userId);
      await env.AVATARS.put(key, bytes, {
        httpMetadata: {
          contentType,
          cacheControl: "public, max-age=300",  // 5 min — survives a re-upload via ?v= cache-bust
        },
      });
    } catch (e) {
      return jsonResponse({ error: "R2 write failed", detail: String(e) }, 502);
    }

    const version = Date.now();
    return jsonResponse({
      url:     `${CDN_BASE}/${key}`,
      version,
    });
  },
};

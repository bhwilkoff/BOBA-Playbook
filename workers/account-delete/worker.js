/**
 * BOBA Playbook — Account Deletion Proxy
 *
 * Why this exists: Supabase's `auth.admin.deleteUser()` requires the
 * service_role key, which must NEVER ship in a client (it bypasses RLS
 * and can read/write any row). The iOS app and web app POST to this
 * Worker; the Worker holds the key as a secret and forwards the
 * delete to Supabase.
 *
 * Endpoint: POST /account/delete
 *   Headers: Authorization: Bearer <user_jwt>
 *   Body:    (none required)
 *   Returns: 200 { "ok": true } on success
 *            401 / 403 / 500 on failure
 *
 * Cascade behavior (Postgres FK ON DELETE CASCADE on auth.users):
 *   - user_cards       → cascade delete
 *   - decks            → cascade delete (deck_cards cascade through decks)
 *   - shows            → cascade delete (show_cards cascade through shows)
 *   - user_profiles    → cascade delete
 *   - card_corrections, card_image_overrides → submitted_by SET NULL
 *     (preserves the mod-audit trail with anonymous authorship)
 *
 * App Store guideline 5.1.1(v) compliance: this is the in-app account
 * deletion path. The dialog's destructive confirmation lives on the
 * client; this Worker is the irreversible action.
 */

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

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    const url = new URL(request.url);
    if (url.pathname !== "/account/delete" || request.method !== "POST") {
      return jsonResponse({ error: "Not found" }, 404);
    }

    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_KEY) {
      return jsonResponse({ error: "Worker misconfigured (missing secrets)" }, 500);
    }

    // Verify the caller's JWT before deleting anything. We hit
    // Supabase's /auth/v1/user endpoint with the bearer token; if it
    // returns 200, the caller is who they claim to be. The userId
    // returned is the authoritative subject we'll delete.
    const auth = request.headers.get("Authorization") || "";
    const match = auth.match(/^Bearer\s+(.+)$/i);
    if (!match) {
      return jsonResponse({ error: "Missing Authorization: Bearer <jwt>" }, 401);
    }
    const userJwt = match[1];

    let userId;
    try {
      const meRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
        headers: {
          "Authorization": `Bearer ${userJwt}`,
          "apikey":        env.SUPABASE_SERVICE_KEY,  // service key as anon proxy
        },
      });
      if (!meRes.ok) {
        const body = await meRes.text();
        return jsonResponse({ error: "Invalid or expired token", detail: body }, 401);
      }
      const me = await meRes.json();
      userId = me?.id;
      if (!userId) {
        return jsonResponse({ error: "Could not resolve user from token" }, 401);
      }
    } catch (e) {
      return jsonResponse({ error: "Token verification failed", detail: String(e) }, 500);
    }

    // Call the admin delete endpoint. Supabase cascades through every
    // FK keyed on auth.users via ON DELETE CASCADE — see schema.
    try {
      const delRes = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
        method: "DELETE",
        headers: {
          "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY}`,
          "apikey":        env.SUPABASE_SERVICE_KEY,
          "Content-Type":  "application/json",
        },
      });
      if (!delRes.ok) {
        const body = await delRes.text();
        return jsonResponse(
          { error: "Supabase admin delete failed", status: delRes.status, detail: body },
          502
        );
      }
    } catch (e) {
      return jsonResponse({ error: "Admin delete request failed", detail: String(e) }, 500);
    }

    return jsonResponse({ ok: true, userId });
  },
};

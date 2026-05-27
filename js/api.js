/**
 * API & Data Layer — BOBA Playbook
 *
 * Handles: card catalog loading, CDN image URLs, Supabase (M2+).
 * All data loading is cached in memory after first fetch.
 * Views never call fetch() directly — always go through this module.
 */
const API = (() => {
  'use strict';

  /* ----------------------------------------------------------------
     CDN — Cloudflare R2
  ---------------------------------------------------------------- */
  const CDN_BASE = 'https://pub-d2cb69f3a56c44a6b98f5e3975bc44c2.r2.dev';

  function thumbUrl(imageFile) {
    return `${CDN_BASE}/thumbs/${imageFile}`;
  }

  function fullUrl(imageFile) {
    return `${CDN_BASE}/full/${imageFile}`;
  }

  // Sealed product images live under sealed/thumbs/ and sealed/optimized/
  function sealedThumbUrl(imageFile) {
    return `${CDN_BASE}/sealed/thumbs/${imageFile}`;
  }

  function sealedFullUrl(imageFile) {
    return `${CDN_BASE}/sealed/optimized/${imageFile}`;
  }

  // Resolves the correct URL based on card type
  function cardThumbUrl(card) {
    if (!card.imageFile) return null;
    return card.cardType === 'Sealed Product'
      ? sealedThumbUrl(card.imageFile)
      : thumbUrl(card.imageFile);
  }

  function cardFullUrl(card) {
    if (!card.imageFile) return null;
    return card.cardType === 'Sealed Product'
      ? sealedFullUrl(card.imageFile)
      : fullUrl(card.imageFile);
  }

  /// Returns a `srcset` string pairing the 200w thumb with the
  /// 1200w full so the browser picks the right resolution per
  /// rendered cell width. Use with `sizes="auto"` on a lazy-loaded
  /// `<img>` to mirror iOS's "thumb in dense grids, full in sparse
  /// grids" rule. nil when the card has no imageFile.
  function cardImageSrcset(card) {
    if (!card.imageFile) return null;
    const t = cardThumbUrl(card);
    const f = cardFullUrl(card);
    if (!t || !f) return null;
    return `${t} 200w, ${f} 1200w`;
  }

  /* ----------------------------------------------------------------
     Card Catalog — static JSON files served from GitHub Pages
  ---------------------------------------------------------------- */
  let _cards       = null;
  let _searchIndex = null;
  let _categories  = null;

  async function loadCards() {
    if (_cards) return _cards;
    const resp = await fetch('assets/data/cards.json');
    if (!resp.ok) throw new Error(`Failed to load cards.json: ${resp.status}`);
    _cards = await resp.json();
    return _cards;
  }

  async function loadSearchIndex() {
    if (_searchIndex) return _searchIndex;
    const resp = await fetch('assets/data/search-index.json');
    if (!resp.ok) throw new Error(`Failed to load search-index.json: ${resp.status}`);
    _searchIndex = await resp.json();
    return _searchIndex;
  }

  async function loadCategories() {
    if (_categories) return _categories;
    const resp = await fetch('assets/data/categories.json');
    if (!resp.ok) throw new Error(`Failed to load categories.json: ${resp.status}`);
    _categories = await resp.json();
    return _categories;
  }

  /* ----------------------------------------------------------------
     Store locator — authorized-retailer list (refreshed weekly by
     GitHub Actions). Manifest-first protocol: fetch the tiny
     stores-manifest.json, compare its sha256 against the cached copy
     in localStorage, and only re-download the 1.4 MB stores.json when
     the manifest has actually changed. Falls back to cache on any
     network failure.
  ---------------------------------------------------------------- */
  async function loadStores() {
    let localManifest = null;
    let localStores   = null;
    try {
      localManifest = JSON.parse(localStorage.getItem('stores_manifest') || 'null');
      localStores   = JSON.parse(localStorage.getItem('stores_cache')    || 'null');
    } catch { /* corrupt entry — treat as no cache */ }

    try {
      const res = await fetch('assets/data/stores-manifest.json', { cache: 'no-store' });
      if (!res.ok) throw new Error(`stores-manifest ${res.status}`);
      const remote = await res.json();

      if (localStores && localManifest?.stores_sha256 === remote.stores_sha256) {
        return { stores: localStores, manifest: remote };
      }

      const storesRes = await fetch('assets/data/stores.json');
      if (!storesRes.ok) throw new Error(`stores ${storesRes.status}`);
      const stores = await storesRes.json();

      try {
        localStorage.setItem('stores_cache',    JSON.stringify(stores));
        localStorage.setItem('stores_manifest', JSON.stringify(remote));
      } catch (e) {
        console.warn('[stores] localStorage write failed:', e);
      }
      return { stores, manifest: remote };
    } catch (err) {
      if (localStores) return { stores: localStores, manifest: localManifest };
      throw err;
    }
  }

  // Community-alias files — load in parallel with catalog, merge into one
  // lowercase lookup: slang → [canonical, ...]. Sourced from the Discord
  // terminology handoff; missing files are a no-op (aliases only expand
  // the search, never gate it).
  let _aliasIndex = null;
  async function loadAliasIndex() {
    if (_aliasIndex) return _aliasIndex;
    const safeFetch = async (path) => {
      try {
        const r = await fetch(path);
        if (!r.ok) return null;
        return await r.json();
      } catch { return null; }
    };
    const [hero, treatment] = await Promise.all([
      safeFetch('assets/data/hero_aliases.json'),
      safeFetch('assets/data/treatment_aliases.json'),
    ]);
    const idx = {};
    const absorb = (obj) => {
      for (const canonical of Object.keys(obj || {})) {
        for (const slang of (obj[canonical] || [])) {
          const key = String(slang).toLowerCase();
          (idx[key] ||= []).push(String(canonical).toLowerCase());
        }
      }
    };
    absorb(hero?.aliases);
    absorb(treatment?.aliases);
    absorb(treatment?.element_aliases);
    _aliasIndex = idx;
    return _aliasIndex;
  }

  /* ----------------------------------------------------------------
     Supabase — M2: auth + user collections
     Fill in YOUR_SUPABASE_ANON_KEY from your .env.local file.
     The anon key is public by design — protected by RLS policies.
  ---------------------------------------------------------------- */
  const SUPABASE_URL  = (window.ENV || {}).SUPABASE_URL  || 'https://pazkimtkwwwekuguxkff.supabase.co';
  const SUPABASE_ANON = (window.ENV || {}).SUPABASE_ANON || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBhemtpbXRrd3d3ZWt1Z3V4a2ZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUyMzY4MTIsImV4cCI6MjA5MDgxMjgxMn0.8f-d_RT8ESxQR-QbYbfpp1MWqhQ7Tm5IKJJeivI-U9k';

  let _supa = null;
  function supa() {
    if (!_supa) _supa = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON, {
      auth: { detectSessionInUrl: true, persistSession: true, autoRefreshToken: true }
    });
    return _supa;
  }

  // ---- Auth ----

  async function authSignUp(email, password) {
    const { data, error } = await supa().auth.signUp({ email, password });
    if (error) throw new Error(error.message);
    return data; // { user, session } — session is null when confirmation email required
  }

  async function authSignIn(email, password) {
    const { data, error } = await supa().auth.signInWithPassword({ email, password });
    if (error) throw new Error(error.message);
    return data.session;
  }

  function authSignInWithApple() {
    // Strip query/hash so redirectTo is the clean app URL
    const redirectTo = window.location.origin + window.location.pathname;
    return supa().auth.signInWithOAuth({ provider: 'apple', options: { redirectTo } });
  }

  function authSignInWithDiscord() {
    const redirectTo = window.location.origin + window.location.pathname;
    return supa().auth.signInWithOAuth({ provider: 'discord', options: { redirectTo } });
  }

  // Tick 483 — Sign in with Google on web (Android tick 99-era parity;
  // iOS doesn't ship it either). Requires Google provider enabled in
  // Supabase Auth dashboard. Returns Supabase's OAuth promise; the
  // caller handles errors via the existing supa().auth state-change
  // listener.
  function authSignInWithGoogle() {
    const redirectTo = window.location.origin + window.location.pathname;
    return supa().auth.signInWithOAuth({ provider: 'google', options: { redirectTo } });
  }

  async function authSignOut() {
    const { error } = await supa().auth.signOut();
    if (error) throw new Error(error.message);
  }

  function authOnStateChange(cb) {
    return supa().auth.onAuthStateChange((event, session) => cb(event, session));
  }

  // ---- Collection ----

  async function collectionFetch() {
    const { data, error } = await supa()
      .from('user_cards').select('*').order('acquired_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data;
  }

  async function collectionAdd(card) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const { data, error } = await supa()
      .from('user_cards')
      .insert({ ...card, user_id: session.user.id })
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  }

  async function collectionDelete(id) {
    const { error } = await supa().from('user_cards').delete().eq('id', id);
    if (error) throw new Error(error.message);
  }

  async function collectionUpdate(id, fields) {
    const { data, error } = await supa()
      .from('user_cards')
      .update(fields)
      .eq('id', id)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  }

  // ---- Mod / roles ----

  let _userRole = null;

  /* ----------------------------------------------------------------
     Custom Rainbows — user-defined collecting goals stored in
     `user_custom_rainbows` (iOS schema parity per DECISIONS.md
     custom_rainbows + Models/CustomRainbow.swift). Web shipped as
     read-only display in this tick; editor is iOS-only today.
  ---------------------------------------------------------------- */

  async function fetchCustomRainbows() {
    const { data: { user } } = await supa().auth.getUser();
    if (!user) return [];
    const { data, error } = await supa()
      .from('user_custom_rainbows')
      .select('id, user_id, name, criteria, created_at, updated_at')
      .order('created_at', { ascending: false });
    if (error) {
      console.warn('fetchCustomRainbows failed', error);
      return [];
    }
    return (data ?? []).map(row => ({
      id: row.id,
      name: row.name,
      criteria: row.criteria || {},
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    }));
  }

  /// Insert a new custom rainbow. Returns the created row (id +
  /// timestamps) so the caller can splice it into the local list
  /// without a refetch. Mirrors iOS `SupabaseClient.createCustomRainbow`.
  async function createCustomRainbow(name, criteria) {
    const trimmed = String(name || '').trim();
    if (!trimmed) throw new Error('Name cannot be empty');
    const { data: { user } } = await supa().auth.getUser();
    if (!user) throw new Error('Not signed in');
    const { data, error } = await supa()
      .from('user_custom_rainbows')
      .insert({ user_id: user.id, name: trimmed, criteria: criteria || {} })
      .select('id, user_id, name, criteria, created_at, updated_at')
      .single();
    if (error) throw new Error(error.message);
    return {
      id: data.id,
      name: data.name,
      criteria: data.criteria || {},
      createdAt: data.created_at,
      updatedAt: data.updated_at,
    };
  }

  /// Patch an existing rainbow's name and/or criteria. The RLS
  /// policy scopes the update to own-row by default. Mirrors iOS
  /// `SupabaseClient.updateCustomRainbow`.
  async function updateCustomRainbow(id, { name, criteria }) {
    const patch = {};
    if (typeof name === 'string') {
      const trimmed = name.trim();
      if (!trimmed) throw new Error('Name cannot be empty');
      patch.name = trimmed;
    }
    if (criteria !== undefined) patch.criteria = criteria || {};
    patch.updated_at = new Date().toISOString();
    const { error } = await supa()
      .from('user_custom_rainbows')
      .update(patch)
      .eq('id', id);
    if (error) throw new Error(error.message);
  }

  /// Hard-delete a custom rainbow. RLS gates by own-row.
  async function deleteCustomRainbow(id) {
    const { error } = await supa()
      .from('user_custom_rainbows')
      .delete()
      .eq('id', id);
    if (error) throw new Error(error.message);
  }

  /// Match a Card against a RainbowCriteria object. Mirrors iOS
  /// RainbowCriteria.matches verbatim — each non-empty dimension's
  /// values OR-combine, dimensions AND-combine.
  function rainbowCriteriaMatches(card, criteria) {
    const ci = (a, b) => a && b && a.toLowerCase() === b.toLowerCase();
    const inList = (list, value) => Array.isArray(list) && list.length > 0
      ? list.some(v => ci(v, value || ''))
      : true;
    if (!inList(criteria.heroes,     card.hero))              return false;
    if (!inList(criteria.sets,       card.set))               return false;
    if (!inList(criteria.subSets,    card.subSet || ''))      return false;
    if (!inList(criteria.elements,   card.element))           return false;
    if (!inList(criteria.treatments, card.treatment || ''))   return false;
    if (!inList(criteria.cardTypes,  card.cardType))          return false;
    if (!inList(criteria.releases,   card.release))           return false;
    if (criteria.inspiredInkOnly && !(card.treatment || '').toLowerCase().includes('inspired ink')) {
      return false;
    }
    return true;
  }

  /// One-line summary of the criteria. Mirrors iOS RainbowCriteria.summary.
  function rainbowCriteriaSummary(criteria) {
    const parts = [];
    const push = (arr) => { if (Array.isArray(arr) && arr.length) parts.push(arr.join(' · ')); };
    push(criteria.heroes);
    push(criteria.sets);
    push(criteria.subSets);
    push(criteria.elements);
    push(criteria.treatments);
    push(criteria.cardTypes);
    push(criteria.releases);
    if (criteria.inspiredInkOnly) parts.push('Inspired Ink');
    return parts.join(' · ');
  }

  async function fetchUserRole() {
    const { data: { user } } = await supa().auth.getUser();
    if (!user) { _userRole = 'user'; return 'user'; }
    const { data, error } = await supa()
      .from('user_profiles')
      .select('role')
      .eq('user_id', user.id)
      .single();
    if (error) {
      _userRole = 'user';
      return 'user';
    }
    _userRole = data?.role ?? 'user';
    return _userRole;
  }

  function getCachedRole() {
    return _userRole ?? 'user';
  }

  /* ----------------------------------------------------------------
     Mod promotion requests
  ---------------------------------------------------------------- */


  // Admin-only: list pending mod requests via SECURITY DEFINER RPC.
  async function adminFetchPendingModRequests() {
    const { data, error } = await supa().rpc('get_pending_mod_requests');
    if (error) throw new Error(error.message);
    return data ?? [];
  }

  // Admin-only: approve (promote to moderator) or deny (clear request).
  async function adminReviewModRequest(userId, approve) {
    const { error } = await supa().rpc('review_mod_request', {
      target_user_id: userId,
      approve,
    });
    if (error) throw new Error(error.message);
  }

  async function submitCardCorrection(cardNumber, corrections, notes, status = 'pending', cardContext = {}) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const row = {
      card_number:    cardNumber,
      boba_id:        cardContext.bobaId    ?? null,
      corrections,
      notes:          notes || null,
      submitted_by:   session.user.id,
      status,
      card_hero:      cardContext.hero      ?? null,
      card_element:   cardContext.element   ?? null,
      card_power:     cardContext.power     ?? null,
      card_treatment: cardContext.treatment ?? null,
    };
    const { error } = await supa().from('card_corrections').insert(row);
    if (error) throw new Error(error.message);
  }

  async function submitImageOverride(cardNumber, action, storagePath, status = 'pending', bobaId = null) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const payload = {
      card_number:  cardNumber,
      boba_id:      bobaId ?? null,
      action,
      submitted_by: session.user.id,
      status,
    };
    if (storagePath) payload.storage_path = storagePath;
    // upsert on card_number — repeated submissions update the row, not add duplicates.
    // Return the upserted row so the caller can chain to applyImageOverride().
    const { data, error } = await supa()
      .from('card_image_overrides')
      .upsert(payload, { onConflict: 'card_number' })
      .select('id')
      .single();
    if (error) throw new Error(error.message);
    return data?.id ?? null;
  }

  // Trigger the boba-mod-merge Cloudflare Worker — applies an approved
  // image override immediately (R2 write + CF cache purge + sets
  // applied_image_file on the row so clients pick up the new filename
  // before the daily cron + git deploy). Only admins succeed.
  const MOD_MERGE_WORKER_URL = 'https://boba-mod-merge.benwilkoff.workers.dev';
  async function applyImageOverride(overrideId) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const res = await fetch(`${MOD_MERGE_WORKER_URL}/merge`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({ overrideId }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw new Error(`Merge worker failed (HTTP ${res.status}) — ${body.slice(0, 240) || 'no body'}`);
    }
    return res.json();
  }

  // Applied image overrides — runtime map for the client. Catalog
  // rendering checks this before falling back to cards.json imageFile.
  async function loadAppliedImageOverrides() {
    const { data, error } = await supa()
      .from('card_image_overrides')
      .select('card_number, boba_id, applied_image_file')
      .eq('status', 'applied')
      .not('applied_image_file', 'is', null);
    if (error) return { byBobaId: new Map(), byCardNumber: new Map() };
    const byBobaId = new Map();
    const byCardNumber = new Map();
    for (const row of (data ?? [])) {
      if (row.boba_id) byBobaId.set(String(row.boba_id), row.applied_image_file);
      byCardNumber.set(String(row.card_number), row.applied_image_file);
    }
    return { byBobaId, byCardNumber };
  }

  // Fetch card numbers that have an active image removal (pending or approved, not rejected).
  // Called at startup — results are applied directly to the in-memory card objects.
  async function loadActiveImageRemovals() {
    const { data, error } = await supa()
      .from('card_image_overrides')
      .select('card_number')
      .eq('action', 'remove')
      .neq('status', 'rejected');
    if (error) return new Set();
    return new Set((data ?? []).map(r => String(r.card_number)));
  }

  async function uploadModImage(cardNumber, file) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const ext  = file.name.split('.').pop() || 'jpg';
    const path = `${session.user.id}/${cardNumber}-${Date.now()}.${ext}`;
    const { error } = await supa().storage
      .from('mod-card-images')
      .upload(path, file, { contentType: file.type || 'image/jpeg' });
    if (error) throw new Error(error.message);
    return path;
  }

  // Admin-only: fetch row count for a table (uses Range header)
  async function adminFetchCount(table) {
    const { count, error } = await supa()
      .from(table)
      .select('*', { count: 'exact', head: true });
    if (error) throw new Error(error.message);
    return count ?? 0;
  }

  // Admin-only: fetch count of pending-only rows (for metrics that have a status column)
  async function adminFetchPendingCount(table) {
    const { count, error } = await supa()
      .from(table)
      .select('*', { count: 'exact', head: true })
      .eq('status', 'pending');
    if (error) throw new Error(error.message);
    return count ?? 0;
  }

  // Admin-only: fetch pending image overrides (missing art queue)
  async function adminFetchPendingImageOverrides() {
    const { data, error } = await supa()
      .from('card_image_overrides')
      .select('id, card_number, action, status, submitted_by, created_at')
      .eq('status', 'pending')
      .order('created_at', { ascending: true });
    if (error) throw new Error(error.message);
    return data ?? [];
  }

  // Admin-only: approve an image removal (confirmed — stays hidden everywhere)
  async function adminApproveImageOverride(id) {
    const { error } = await supa()
      .from('card_image_overrides')
      .update({ status: 'approved' })
      .eq('id', id);
    if (error) throw new Error(error.message);
  }

  // Admin-only: reject an image removal (image comes back)
  async function adminRejectImageOverride(id) {
    const { error } = await supa()
      .from('card_image_overrides')
      .update({ status: 'rejected' })
      .eq('id', id);
    if (error) throw new Error(error.message);
  }

  // Admin-only: fetch full user stats (last sign-in, display name, collection count/value)
  async function adminFetchUsers() {
    const { data, error } = await supa().rpc('get_admin_user_stats');
    if (error) throw new Error(error.message);
    return data ?? [];
  }

  // Admin-only: update a user's role
  async function adminUpdateRole(userId, role) {
    const { error } = await supa()
      .from('user_profiles')
      .update({ role })
      .eq('user_id', userId);
    if (error) throw new Error(error.message);
  }

  // Admin-only: fetch pending corrections for review
  async function adminFetchPendingCorrections() {
    const { data, error } = await supa()
      .from('card_corrections')
      .select('id, card_number, corrections, notes, submitted_by, created_at, status')
      .eq('status', 'pending')
      .order('created_at', { ascending: true });
    if (error) throw new Error(error.message);
    return data ?? [];
  }

  // Admin-only: approve a correction
  async function adminApproveCorrection(id) {
    const { error } = await supa()
      .from('card_corrections')
      .update({ status: 'approved' })
      .eq('id', id);
    if (error) throw new Error(error.message);
  }

  // Admin-only: reject a correction
  async function adminRejectCorrection(id) {
    const { error } = await supa()
      .from('card_corrections')
      .update({ status: 'rejected' })
      .eq('id', id);
    if (error) throw new Error(error.message);
  }

  /* ----------------------------------------------------------------
     Deck Builder — save / load / delete
  ---------------------------------------------------------------- */

  // Save a deck (insert or replace). Returns the saved deck id.
  // cards: array of { bobaId, cardType } where cardType is 'hero'|'play'|'bonus_play'|'hot_dog'
  async function deckSave(deckId, deckName, format, cards) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');

    let id = deckId;
    if (id) {
      // Update existing deck metadata
      const { error } = await supa()
        .from('decks')
        .update({ name: deckName, format, updated_at: new Date().toISOString() })
        .eq('id', id)
        .eq('user_id', session.user.id);
      if (error) throw new Error(error.message);
    } else {
      // Insert new deck
      const { data, error } = await supa()
        .from('decks')
        .insert({ name: deckName, format, user_id: session.user.id })
        .select('id')
        .single();
      if (error) throw new Error(error.message);
      id = data.id;
    }

    // Replace all cards: delete then insert
    const { error: delErr } = await supa().from('deck_cards').delete().eq('deck_id', id);
    if (delErr) throw new Error(delErr.message);

    if (cards.length > 0) {
      const rows = cards.map((c, i) => ({
        deck_id: id,
        boba_id: c.bobaId,
        card_type: c.cardType,
        sort_order: i,
      }));
      const { error: insErr } = await supa().from('deck_cards').insert(rows);
      if (insErr) throw new Error(insErr.message);
    }

    return id;
  }

  // List all decks for the signed-in user (metadata only, no cards)
  async function deckList() {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) return [];
    const { data, error } = await supa()
      .from('decks')
      .select('id, name, format, updated_at')
      .eq('user_id', session.user.id)
      .order('updated_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data ?? [];
  }

  // Load a single deck's cards
  async function deckLoad(deckId) {
    const { data, error } = await supa()
      .from('deck_cards')
      .select('boba_id, card_type, sort_order')
      .eq('deck_id', deckId)
      .order('sort_order', { ascending: true });
    if (error) throw new Error(error.message);
    return data ?? [];
  }

  // Delete a deck (and its cards via cascade)
  /* ----------------------------------------------------------------
     Profile RPCs (mirror of iOS SupabaseClient methods)
     check_username / set_username / set_public_collection_enabled /
     set_notification_prefs / set_discord_identity / request_role /
     get_pending_role_requests / review_role_request — all defined
     in supabase_schema.sql and applied to the live DB.
  ---------------------------------------------------------------- */

  async function fetchProfile() {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) return null;
    const { data, error } = await supa()
      .from('user_profiles')
      .select('username,public_collection_enabled,notifications_enabled,match_alerts_enabled,discord_user_id,discord_avatar_url,avatar_url,requested_role,requested_role_at')
      .eq('user_id', session.user.id)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data;
  }

  async function checkUsername(candidate) {
    const { data, error } = await supa().rpc('check_username', { candidate });
    if (error) throw new Error(error.message);
    // RPC returns a bare JSON string ("available" / "taken" / etc.)
    return data ?? 'invalid_chars';
  }

  async function setUsername(newUsername) {
    const { data, error } = await supa().rpc('set_username', { new_username: newUsername });
    if (error) throw new Error(error.message);
    return data ?? 'invalid_chars';
  }

  async function setPublicCollectionEnabled(enabled) {
    const { error } = await supa().rpc('set_public_collection_enabled', { enabled });
    if (error) throw new Error(error.message);
  }

  /// Generalized role-request RPC. Replaces submitModRequest for new
  /// code paths — works for both "moderator" and "streamer".
  async function requestRole(role, reason) {
    const { error } = await supa().rpc('request_role', { target_role: role, reason });
    if (error) throw new Error(error.message);
  }

  /// Submit a community sold-comp (Tier 3, PRICING_PLAYBOOK §5). Auth-gated;
  /// the RPC enforces rate limits (5/user/day, 1/bobaId/user/week) + field
  /// validation server-side. Returns { ok, id } or { error } (never throws —
  /// the caller surfaces res.error via a toast).
  async function submitCommunityComp({ bobaId, price, soldAt, platform, notes, photoUrl } = {}) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) return { error: 'Sign in to add a price.' };
    const { data, error } = await supa().rpc('submit_community_comp', {
      p_boba_id:   bobaId,
      p_price:     price,
      p_sold_at:   soldAt,
      p_platform:  platform,
      p_photo_url: photoUrl || null,
      p_notes:     notes || null,
    });
    if (error) return { error: error.message };
    return { ok: true, id: data };
  }

  /// Mod queue — pending community comps awaiting review. RLS + the RPC
  /// both gate to moderator/admin; a non-mod gets an empty list. Returns
  /// full community_comps rows (id, boba_id, price_usd, sold_at,
  /// source_platform, photo_url, notes, created_at, …).
  async function getPendingCommunityComps() {
    const { data, error } = await supa().rpc('get_pending_community_comps');
    if (error) throw new Error(error.message);
    return data || [];
  }

  /// Approve or reject a pending community comp. Approving flips status to
  /// 'approved' so it flows through get_approved_comps → the estimator;
  /// rejecting records the optional reason. Mod/admin only (enforced
  /// server-side). Returns { ok } or { error }.
  async function reviewCommunityComp(id, approve, rejectReason) {
    const { error } = await supa().rpc('review_community_comp', {
      p_id:            id,
      p_approve:       approve,
      p_reject_reason: rejectReason || null,
    });
    if (error) return { error: error.message };
    return { ok: true };
  }

  /// Triggers Supabase's native password-reset email. Mirrors iOS
  /// SupabaseClient.requestPasswordReset.
  async function requestPasswordReset(email) {
    const { error } = await supa().auth.resetPasswordForEmail(email, {
      redirectTo: 'https://bobaplaybook.com/'
    });
    if (error) throw new Error(error.message);
  }

  /// boba-account-delete Worker URL — see BOBAPlaybook/Config.swift
  /// (kept in sync with WorkerConfig.accountDeleteURL).
  const ACCOUNT_DELETE_WORKER_URL =
    'https://boba-account-delete.benwilkoff.workers.dev';

  /// boba-avatar-upload Worker — POST /avatar (image bytes) and
  /// DELETE /avatar. See workers/avatar-upload/.
  const AVATAR_UPLOAD_WORKER_URL =
    'https://boba-avatar-upload.benwilkoff.workers.dev';

  /// Upload a square-cropped image (Blob, ≤2MB) and receive the
  /// public CDN URL + version token for cache-busting. Caller is
  /// responsible for cropping client-side; the Worker only validates
  /// type + size. Use setAvatarUrl(url) to persist on user_profiles.
  async function uploadAvatar(blob) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const res = await fetch(`${AVATAR_UPLOAD_WORKER_URL}/avatar`, {
      method:  'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type':  blob.type || 'image/jpeg',
      },
      body: blob,
    });
    if (!res.ok) {
      let detail = '';
      try { detail = (await res.json())?.error || ''; }
      catch (_) { /* non-JSON — ignore */ }
      throw new Error(`Upload failed (HTTP ${res.status})${detail ? ': ' + detail : ''}`);
    }
    return res.json();  // { url, version }
  }

  /// Remove the user's avatar from R2. Caller is also responsible for
  /// calling setAvatarUrl(null) so the user_profiles column matches.
  async function deleteAvatar() {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const res = await fetch(`${AVATAR_UPLOAD_WORKER_URL}/avatar`, {
      method:  'DELETE',
      headers: { 'Authorization': `Bearer ${session.access_token}` },
    });
    if (!res.ok) {
      let detail = '';
      try { detail = (await res.json())?.error || ''; }
      catch (_) { /* non-JSON */ }
      throw new Error(`Delete failed (HTTP ${res.status})${detail ? ': ' + detail : ''}`);
    }
  }

  /// Persist the user_profiles.avatar_url column via the
  /// set_avatar_url RPC. Pass null to clear (resolver falls back to
  /// Discord avatar / silhouette). The RPC enforces that non-null
  /// URLs match the BOBA R2 avatars prefix.
  async function setAvatarUrl(newUrl) {
    const { error } = await supa().rpc('set_avatar_url', { new_url: newUrl });
    if (error) throw new Error(error.message);
  }

  /// Fetch the publicly-shareable profile fields for a username
  /// (avatar URL, Discord avatar fallback). Returns null if the
  /// user hasn't enabled public sharing or doesn't exist. Used by
  /// the public-collection page to render the owner's avatar.
  /// Permanently delete the current user's account via the
  /// boba-account-delete Worker. The Worker holds the Supabase
  /// service_role key and proxies the admin auth.users delete (which
  /// cascades through every user-data table via FK ON DELETE CASCADE).
  /// On success the caller MUST sign out locally so the stale JWT
  /// stops getting sent on subsequent requests.
  async function deleteAccount() {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const res = await fetch(`${ACCOUNT_DELETE_WORKER_URL}/account/delete`, {
      method:  'POST',
      headers: {
        'Authorization': `Bearer ${session.access_token}`,
        'Content-Type':  'application/json',
      },
    });
    if (!res.ok) {
      let detail = '';
      try { detail = (await res.json())?.error || ''; }
      catch (_) { /* non-JSON response — ignore detail */ }
      throw new Error(`Delete failed (HTTP ${res.status})${detail ? ': ' + detail : ''}`);
    }
  }

  /* ----------------------------------------------------------------
     Public collections (read-only — no auth required)
     Backed by the get_public_collection(handle) Supabase RPC.
     The RPC bypasses user_cards RLS via SECURITY DEFINER and only
     returns rows for users with public_collection_enabled = true,
     filtered to safe-to-share columns (no purchase_price, no notes,
     no asking_price). Wanted designation is also excluded — the
     public surface reads as "what they have," not "what they want."
  ---------------------------------------------------------------- */
  async function fetchPublicProfile(username) {
    const { data, error } = await supa()
      .rpc('get_public_profile', { handle: username });
    if (error) throw new Error(error.message);
    // RPC returns at most one row; return null when the handle is
    // unknown OR the user opted out of sharing.
    return Array.isArray(data) && data.length ? data[0] : null;
  }

  async function fetchPublicCollection(username) {
    const { data, error } = await supa()
      .rpc('get_public_collection', { handle: username });
    if (error) throw new Error(error.message);
    return data ?? [];
  }

  async function deckDelete(deckId) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const { error } = await supa()
      .from('decks')
      .delete()
      .eq('id', deckId)
      .eq('user_id', session.user.id);
    if (error) throw new Error(error.message);
  }

  /// Rename a saved deck. Updates only the name column; format +
  /// deck_cards are untouched. Parity with iOS DeckManagementSheet
  /// rename action (DESIGN.md §8.3) and Android Manage Decks rename
  /// shipped overnight 2026-05-20.
  async function deckRename(deckId, newName) {
    const { data: { session } } = await supa().auth.getSession();
    if (!session) throw new Error('Not signed in');
    const trimmed = String(newName || '').trim();
    if (!trimmed) throw new Error('Name cannot be empty');
    const { error } = await supa()
      .from('decks')
      .update({ name: trimmed, updated_at: new Date().toISOString() })
      .eq('id', deckId)
      .eq('user_id', session.user.id);
    if (error) throw new Error(error.message);
  }

  /* ----------------------------------------------------------------
     Exports
  ---------------------------------------------------------------- */
  return {
    thumbUrl,
    fullUrl,
    sealedThumbUrl,
    sealedFullUrl,
    cardThumbUrl,
    cardFullUrl,
    cardImageSrcset,
    fetchCustomRainbows,
    createCustomRainbow,
    updateCustomRainbow,
    deleteCustomRainbow,
    rainbowCriteriaMatches,
    rainbowCriteriaSummary,
    loadCards,
    loadSearchIndex,
    loadCategories,
    loadAliasIndex,
    loadStores,
    // Auth
    authSignUp,
    authSignIn,
    authSignInWithApple,
    authSignInWithDiscord,
    authSignInWithGoogle,
    authSignOut,
    authOnStateChange,
    authGetSession: async () => {
      const { data: { session } } = await supa().auth.getSession();
      return session;
    },
    authRefreshSession: async (refreshToken) => {
      const { data, error } = await supa().auth.refreshSession({ refresh_token: refreshToken });
      if (error) throw new Error(error.message);
      return data.session;
    },
    // Collection
    collectionFetch,
    collectionAdd,
    collectionDelete,
    collectionUpdate,
    // Mod
    fetchUserRole,
    getCachedRole,
    adminFetchPendingModRequests,
    adminReviewModRequest,
    submitCardCorrection,
    submitImageOverride,
    applyImageOverride,
    loadAppliedImageOverrides,
    uploadModImage,
    // Admin
    adminFetchCount,
    adminFetchPendingCount,
    adminFetchUsers,
    adminUpdateRole,
    adminFetchPendingCorrections,
    adminApproveCorrection,
    adminRejectCorrection,
    adminFetchPendingImageOverrides,
    adminApproveImageOverride,
    adminRejectImageOverride,
    loadActiveImageRemovals,
    // Deck Builder
    deckSave,
    deckList,
    deckLoad,
    deckDelete,
    deckRename,
    // Public collections
    fetchPublicProfile,
    fetchPublicCollection,
    // Profile RPCs
    fetchProfile,
    checkUsername,
    setUsername,
    setPublicCollectionEnabled,
    requestRole,
    submitCommunityComp,
    getPendingCommunityComps,
    reviewCommunityComp,
    requestPasswordReset,
    deleteAccount,
    uploadAvatar,
    deleteAvatar,
    setAvatarUrl,
  };
})();

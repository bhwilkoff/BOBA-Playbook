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

  // Is the current user's mod-access request still pending?
  async function hasPendingModRequest() {
    const { data: { user } } = await supa().auth.getUser();
    if (!user) return false;
    const { data, error } = await supa()
      .from('user_profiles')
      .select('mod_request_at')
      .eq('user_id', user.id)
      .single();
    if (error) return false;
    return !!data?.mod_request_at;
  }

  // Submit a mod-access request (writes to own profile row, allowed by RLS).
  async function submitModRequest(reason) {
    const { data: { user } } = await supa().auth.getUser();
    if (!user) throw new Error('Not signed in');
    const { error } = await supa()
      .from('user_profiles')
      .update({
        mod_request_reason: reason,
        mod_request_at: new Date().toISOString(),
      })
      .eq('user_id', user.id);
    if (error) throw new Error(error.message);
  }

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
    // upsert on card_number — repeated submissions update the row, not add duplicates
    const { error } = await supa()
      .from('card_image_overrides')
      .upsert(payload, { onConflict: 'card_number' });
    if (error) throw new Error(error.message);
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
    authSignOut,
    authOnStateChange,
    authGetSession: async () => {
      const { data: { session } } = await supa().auth.getSession();
      return session;
    },
    authSetSession: async (accessToken, refreshToken) => {
      const { error } = await supa().auth.setSession({
        access_token: accessToken,
        refresh_token: refreshToken,
      });
      if (error) throw new Error(error.message);
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
    hasPendingModRequest,
    submitModRequest,
    adminFetchPendingModRequests,
    adminReviewModRequest,
    submitCardCorrection,
    submitImageOverride,
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
    // Public collections
    fetchPublicProfile,
    fetchPublicCollection,
  };
})();

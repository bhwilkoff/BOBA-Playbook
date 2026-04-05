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
     Supabase — M2: auth + user collections
     Fill in YOUR_SUPABASE_ANON_KEY from your .env.local file.
     The anon key is public by design — protected by RLS policies.
  ---------------------------------------------------------------- */
  const SUPABASE_URL  = (window.ENV || {}).SUPABASE_URL  || 'https://pazkimtkwwwekuguxkff.supabase.co';
  const SUPABASE_ANON = (window.ENV || {}).SUPABASE_ANON || 'sb_publishable_nAaO0c10a0dJaNRRYUFv7w_PmH1XjET';

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
    // Auth
    authSignUp,
    authSignIn,
    authSignInWithApple,
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
    // Collection
    collectionFetch,
    collectionAdd,
    collectionDelete,
    collectionUpdate,
  };
})();

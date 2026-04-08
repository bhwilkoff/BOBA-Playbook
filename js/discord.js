// MARK: - discord.js
// Discord Trade Room for BOBA Playbook (web).
// OAuth2 PKCE flow → user sends/receives messages as themselves.
// Token storage: access_token in sessionStorage, refresh_token in localStorage.
// Message data is never persisted.

const Discord = (() => {
  // ─── Constants ──────────────────────────────────────────────────────────────
  const CLIENT_ID    = '1491134218829304009';
  const CHANNEL_ID   = '1306146115757936650';
  const GUILD_ID     = '1305710603440095252';
  const INVITE_CODE  = 'bobattlearena';
  const REDIRECT_URI = 'https://bobaplaybook.com/discord-callback.html';
  const REFRESH_URL  = 'https://boba-ebay-proxy.benwilkoff.workers.dev/discord/refresh';
  const POLL_MS      = 2500;

  // ─── State ──────────────────────────────────────────────────────────────────
  let _accessToken  = sessionStorage.getItem('discord_access_token');
  let _tokenExpires = Number(localStorage.getItem('discord_token_expires') || 0);
  let _currentUser  = null;
  let _isMember     = false;
  let _messages     = [];      // [{id, author:{id,username,globalName,avatar}, content, timestamp, reactions, referencedMessage, type}]
  let _newestId     = null;
  let _oldestId     = null;
  let _hasMore      = true;
  let _pollTimer    = null;
  let _unreadCount  = 0;
  let _onUpdate     = null;    // callback → re-render

  // ─── Public API ─────────────────────────────────────────────────────────────
  function setUpdateCallback(fn) { _onUpdate = fn; }
  function notify() { _onUpdate?.(); }

  function getState() {
    return {
      isAuthorized: !!_accessToken,
      isMember:     _isMember,
      currentUser:  _currentUser,
      messages:     _messages,
      hasMore:      _hasMore,
      unreadCount:  _unreadCount,
    };
  }

  // ─── PKCE helpers ──────────────────────────────────────────────────────────

  function _randomBytes(n) {
    const arr = new Uint8Array(n);
    crypto.getRandomValues(arr);
    return arr;
  }

  function _base64url(bytes) {
    return btoa(String.fromCharCode(...bytes))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  async function _sha256(str) {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str));
    return _base64url(new Uint8Array(buf));
  }

  // ─── Authorization ─────────────────────────────────────────────────────────

  async function authorize() {
    const verifier   = _base64url(_randomBytes(32));
    const challenge  = await _sha256(verifier);
    const state      = _base64url(_randomBytes(16));

    sessionStorage.setItem('discord_pkce_verifier', verifier);
    sessionStorage.setItem('discord_pkce_state',    state);

    const params = new URLSearchParams({
      client_id:            CLIENT_ID,
      response_type:        'code',
      redirect_uri:         REDIRECT_URI,
      scope:                'identify guilds',
      code_challenge:       challenge,
      code_challenge_method:'S256',
      state,
    });

    // Open in a popup so users stay on the page
    const popup = window.open(
      `https://discord.com/oauth2/authorize?${params}`,
      'discord_auth',
      'width=480,height=700,resizable=yes'
    );

    return new Promise((resolve) => {
      const handler = async (e) => {
        if (e.origin !== window.location.origin) return;
        if (!e.data?.type === 'discord_callback') return;
        window.removeEventListener('message', handler);
        popup?.close();
        const { code, state: retState } = e.data;
        if (!code || retState !== sessionStorage.getItem('discord_pkce_state')) {
          resolve(false); return;
        }
        const ok = await _exchangeCode(code, sessionStorage.getItem('discord_pkce_verifier'));
        sessionStorage.removeItem('discord_pkce_verifier');
        sessionStorage.removeItem('discord_pkce_state');
        if (ok) {
          await _fetchCurrentUser();
          await _checkMembership();
        }
        notify();
        resolve(ok);
      };
      window.addEventListener('message', handler);
    });
  }

  async function _exchangeCode(code, verifier) {
    try {
      const res = await fetch('https://discord.com/api/oauth2/token', {
        method:  'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body:    new URLSearchParams({
          client_id:     CLIENT_ID,
          grant_type:    'authorization_code',
          code,
          redirect_uri:  REDIRECT_URI,
          code_verifier: verifier,
        }),
      });
      if (!res.ok) return false;
      const t = await res.json();
      _storeTokens(t);
      return true;
    } catch { return false; }
  }

  function _storeTokens(t) {
    _accessToken  = t.access_token;
    _tokenExpires = Date.now() + (t.expires_in - 60) * 1000;
    sessionStorage.setItem('discord_access_token',  _accessToken);
    localStorage.setItem('discord_token_expires',   String(_tokenExpires));
    if (t.refresh_token) {
      localStorage.setItem('discord_refresh_token', t.refresh_token);
    }
  }

  // ─── Token refresh ─────────────────────────────────────────────────────────

  async function _refreshIfNeeded() {
    if (_accessToken && Date.now() < _tokenExpires) return true;
    return _silentRefresh();
  }

  async function _silentRefresh() {
    const rt = localStorage.getItem('discord_refresh_token');
    if (!rt) { _disconnect(); return false; }
    try {
      const res = await fetch(REFRESH_URL, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ refresh_token: rt }),
      });
      if (!res.ok) throw new Error('refresh failed');
      const t = await res.json();
      _storeTokens(t);
      return true;
    } catch {
      _disconnect();
      return false;
    }
  }

  // ─── User + membership ─────────────────────────────────────────────────────

  async function _fetchCurrentUser() {
    if (!await _refreshIfNeeded()) return;
    const res = await fetch('https://discord.com/api/v10/users/@me', {
      headers: { Authorization: `Bearer ${_accessToken}` },
    });
    if (!res.ok) return;
    _currentUser = await res.json();
  }

  async function _checkMembership() {
    if (!await _refreshIfNeeded()) return;
    const res = await fetch('https://discord.com/api/v10/users/@me/guilds', {
      headers: { Authorization: `Bearer ${_accessToken}` },
    });
    if (!res.ok) return;
    const guilds = await res.json();
    _isMember = Array.isArray(guilds) && guilds.some(g => g.id === GUILD_ID);
  }

  async function checkMembership() {
    await _checkMembership();
    notify();
  }

  // ─── Messages ──────────────────────────────────────────────────────────────

  function _filterValid(msgs) {
    return msgs.filter(m => m.type === 0 || m.type === 19);
  }

  async function loadInitialMessages() {
    if (!await _refreshIfNeeded()) return;
    const res = await fetch(
      `https://discord.com/api/v10/channels/${CHANNEL_ID}/messages?limit=50`,
      { headers: { Authorization: `Bearer ${_accessToken}` } }
    );
    if (!res.ok) return;
    const fetched = await res.json();
    const valid = _filterValid(fetched).reverse();
    _messages  = valid;
    _newestId  = valid.at(-1)?.id ?? null;
    _oldestId  = valid.at(0)?.id  ?? null;
    _hasMore   = fetched.length === 50;
    _updateUnread();
    notify();
  }

  async function loadOlderMessages() {
    if (!_hasMore || !_oldestId) return;
    if (!await _refreshIfNeeded()) return;
    const res = await fetch(
      `https://discord.com/api/v10/channels/${CHANNEL_ID}/messages?before=${_oldestId}&limit=50`,
      { headers: { Authorization: `Bearer ${_accessToken}` } }
    );
    if (!res.ok) return;
    const fetched = await res.json();
    const valid   = _filterValid(fetched).reverse();
    _messages  = [...valid, ..._messages];
    _oldestId  = valid.at(0)?.id ?? _oldestId;
    _hasMore   = fetched.length === 50;
    notify();
    return valid.length;   // caller can scroll to preserve position
  }

  async function _pollNewMessages() {
    if (!_newestId || !await _refreshIfNeeded()) return;
    const res = await fetch(
      `https://discord.com/api/v10/channels/${CHANNEL_ID}/messages?after=${_newestId}&limit=50`,
      { headers: { Authorization: `Bearer ${_accessToken}` } }
    );
    if (!res.ok) return;
    const fetched = await res.json();
    const newMsgs = _filterValid(fetched).sort((a, b) => a.id < b.id ? -1 : 1);
    if (newMsgs.length) {
      _messages = [..._messages, ...newMsgs];
      _newestId = newMsgs.at(-1).id;
      _updateUnread();
      notify();
    }
  }

  function startPolling() {
    stopPolling();
    _pollTimer = setInterval(_pollNewMessages, POLL_MS);
  }

  function stopPolling() {
    if (_pollTimer) { clearInterval(_pollTimer); _pollTimer = null; }
  }

  // ─── Send ──────────────────────────────────────────────────────────────────

  async function send(content, replyToId = null) {
    if (!await _refreshIfNeeded()) return false;
    const payload = { content };
    if (replyToId) payload.message_reference = { message_id: replyToId };
    const res = await fetch(`https://discord.com/api/v10/channels/${CHANNEL_ID}/messages`, {
      method:  'POST',
      headers: {
        Authorization:  `Bearer ${_accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
    if (!res.ok) return false;
    const msg = await res.json();
    if (msg.type === 0 || msg.type === 19) {
      _messages.push(msg);
      _newestId = msg.id;
      notify();
    }
    return true;
  }

  // ─── Reactions ─────────────────────────────────────────────────────────────

  async function addReaction(messageId, emoji) {
    if (!await _refreshIfNeeded()) return;
    const enc = encodeURIComponent(emoji);
    await fetch(
      `https://discord.com/api/v10/channels/${CHANNEL_ID}/messages/${messageId}/reactions/${enc}/@me`,
      { method: 'PUT', headers: { Authorization: `Bearer ${_accessToken}` } }
    );
    _applyLocalReaction(messageId, emoji, true);
    notify();
  }

  async function removeReaction(messageId, emoji) {
    if (!await _refreshIfNeeded()) return;
    const enc = encodeURIComponent(emoji);
    await fetch(
      `https://discord.com/api/v10/channels/${CHANNEL_ID}/messages/${messageId}/reactions/${enc}/@me`,
      { method: 'DELETE', headers: { Authorization: `Bearer ${_accessToken}` } }
    );
    _applyLocalReaction(messageId, emoji, false);
    notify();
  }

  function _applyLocalReaction(messageId, emoji, adding) {
    const msg = _messages.find(m => m.id === messageId);
    if (!msg) return;
    if (!msg.reactions) msg.reactions = [];
    const existing = msg.reactions.find(r => (r.emoji.name ?? r.emoji.id) === emoji);
    if (existing) {
      existing.count += adding ? 1 : -1;
      existing.me     = adding;
      if (existing.count <= 0) msg.reactions = msg.reactions.filter(r => r !== existing);
    } else if (adding) {
      msg.reactions.push({ emoji: { id: null, name: emoji }, count: 1, me: true });
    }
  }

  // ─── Unread tracking ──────────────────────────────────────────────────────

  function _updateUnread() {
    const lastSeen = localStorage.getItem('discord_last_seen_id');
    _unreadCount = lastSeen
      ? _messages.filter(m => m.id > lastSeen).length
      : Math.min(_messages.length, 99);
  }

  function markRead() {
    const id = _newestId ?? _messages.at(-1)?.id;
    if (id) {
      localStorage.setItem('discord_last_seen_id', id);
      _unreadCount = 0;
      notify();
    }
  }

  // ─── Disconnect ────────────────────────────────────────────────────────────

  function _disconnect() {
    stopPolling();
    _accessToken = null;
    _currentUser = null;
    _isMember    = false;
    _messages    = [];
    _newestId    = null;
    _oldestId    = null;
    _hasMore     = true;
    sessionStorage.removeItem('discord_access_token');
    localStorage.removeItem('discord_token_expires');
    localStorage.removeItem('discord_refresh_token');
    notify();
  }

  function disconnect() { _disconnect(); }

  // ─── Init (called on page load) ─────────────────────────────────────────────

  async function init() {
    if (!_accessToken) return;
    if (!await _refreshIfNeeded()) return;
    await _fetchCurrentUser();
    await _checkMembership();
    _updateUnread();
    notify();
  }

  // ─── Avatar URL helper ─────────────────────────────────────────────────────

  function avatarUrl(user, size = 32) {
    if (!user) return null;
    if (user.avatar) {
      const ext = user.avatar.startsWith('a_') ? 'gif' : 'webp';
      return `https://cdn.discordapp.com/avatars/${user.id}/${user.avatar}.${ext}?size=${size}`;
    }
    const uid = BigInt(user.id);
    const idx = Number(uid % 5n);
    return `https://cdn.discordapp.com/embed/avatars/${idx}.png`;
  }

  function displayName(user) {
    if (!user) return '';
    return (user.global_name && user.global_name.trim()) ? user.global_name : user.username;
  }

  return {
    init,
    setUpdateCallback,
    getState,
    authorize,
    checkMembership,
    loadInitialMessages,
    loadOlderMessages,
    startPolling,
    stopPolling,
    send,
    addReaction,
    removeReaction,
    markRead,
    disconnect,
    avatarUrl,
    displayName,
    INVITE_CODE,
  };
})();

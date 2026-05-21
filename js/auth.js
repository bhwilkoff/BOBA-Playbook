/**
 * Auth — BOBA Playbook
 * Manages auth state and sign-in modal UI.
 * Must be loaded after api.js.
 *
 * Auth state changes are broadcast as a custom DOM event 'auth-change'
 * so collection.js and app.js can react without tight coupling.
 */
const Auth = (() => {
  'use strict';

  let _session = null;
  let _mode = 'signIn'; // 'signIn' | 'signUp'
  let _loading = false;

  const overlay = document.getElementById('auth-modal-overlay');
  const box     = document.getElementById('auth-modal-box');

  /* ================================================================
     MODAL OPEN / CLOSE
  ================================================================ */

  function open(mode = 'signIn') {
    _mode = mode;
    _loading = false;
    renderModal();
    // Dynamic aria-label — reflects the active mode so screen
    // readers announce "Create account" vs "Sign in" correctly
    // when the user tab-switches mid-modal. renderModal() also
    // updates this on every re-render.
    _updateAriaLabel();
    // Native <dialog> per WEB-DESIGN.md §13. showModal() handles
    // focus trap + ESC + scroll lock + top-layer rendering. Falls
    // back to the legacy hidden-attribute path if the markup
    // somehow isn't <dialog>.
    if (typeof overlay.showModal === 'function' && !overlay.open) {
      overlay.showModal();
    } else {
      overlay.hidden = false;
      document.body.style.overflow = 'hidden';
    }
    setTimeout(() => box.querySelector('#auth-email')?.focus(), 60);
  }

  function _updateAriaLabel() {
    overlay?.setAttribute(
      'aria-label',
      _mode === 'signUp' ? 'Create your BOBA Playbook account' : 'Sign in to BOBA Playbook'
    );
  }

  function close() {
    if (typeof overlay.close === 'function' && overlay.open) {
      overlay.close();
    } else {
      overlay.hidden = true;
      // Only restore scrolling if no other full-screen modal is open.
      const cardModal = document.getElementById('card-modal-overlay');
      const addModal  = document.getElementById('add-collection-overlay');
      const cardOpen  = cardModal && (cardModal.open ?? !cardModal.hidden);
      const addOpen   = addModal  && (addModal.open  ?? !addModal.hidden);
      if (!cardOpen && !addOpen) {
        document.body.style.overflow = '';
      }
    }
  }

  /* ================================================================
     MODAL RENDER
  ================================================================ */

  function renderModal() {
    box.innerHTML = `
      <button class="modal-close" id="auth-close-btn" aria-label="Close sign-in">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" width="18" height="18" aria-hidden="true">
          <path d="M18 6 6 18M6 6l12 12"/>
        </svg>
      </button>

      <div class="auth-modal-inner">
        <div class="auth-wordmark">
          <span class="auth-wordmark-boba">BOBA</span><span class="auth-wordmark-pb"> Playbook</span>
        </div>
        <p class="auth-tagline">
          ${_mode === 'signIn' ? 'Sign in to track your collection' : 'Create your account'}
        </p>

        <button class="btn-apple-signin" id="auth-apple-btn" type="button">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/>
          </svg>
          Sign in with Apple
        </button>

        <button class="btn-discord-signin" id="auth-discord-btn" type="button">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057c.001.022.015.045.036.06a19.904 19.904 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028c.462-.63.874-1.295 1.226-1.994a.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z"/>
          </svg>
          Sign in with Discord
        </button>

        <div class="auth-divider"><span>or</span></div>

        <div class="auth-mode-tabs" role="tablist">
          <button class="auth-mode-tab ${_mode === 'signIn' ? 'active' : ''}"
                  data-mode="signIn" role="tab" aria-selected="${_mode === 'signIn'}">Sign In</button>
          <button class="auth-mode-tab ${_mode === 'signUp' ? 'active' : ''}"
                  data-mode="signUp" role="tab" aria-selected="${_mode === 'signUp'}">Create Account</button>
        </div>

        <div class="auth-form">
          <div class="form-field">
            <label class="form-label" for="auth-email">EMAIL</label>
            <input class="form-input" type="email" id="auth-email"
                   autocomplete="email" autocorrect="off" autocapitalize="none" spellcheck="false"
                   required aria-required="true"
                   placeholder="you@example.com">
          </div>
          <div class="form-field">
            <label class="form-label" for="auth-password">PASSWORD</label>
            <input class="form-input" type="password" id="auth-password"
                   autocomplete="${_mode === 'signIn' ? 'current-password' : 'new-password'}"
                   required aria-required="true"
                   ${_mode === 'signUp' ? 'minlength="6" aria-describedby="auth-password-hint"' : ''}
                   placeholder="••••••••">
            ${_mode === 'signUp' ? '<p id="auth-password-hint" class="auth-field-hint">6 characters minimum.</p>' : ''}
          </div>
          ${_mode === 'signUp' ? `
          <div class="form-field">
            <label class="form-label" for="auth-confirm">CONFIRM PASSWORD</label>
            <input class="form-input" type="password" id="auth-confirm"
                   autocomplete="new-password"
                   required aria-required="true" minlength="6"
                   placeholder="••••••••">
          </div>` : ''}
          <p class="auth-error" id="auth-error" hidden role="alert"></p>
          <p class="auth-info"  id="auth-info"  hidden role="status"></p>
          <button class="btn-primary auth-submit-btn" id="auth-submit" type="button">
            ${_mode === 'signIn' ? 'Sign In' : 'Create Account'}
          </button>
        </div>
      </div>`;

    // Events
    box.querySelector('#auth-close-btn').addEventListener('click', close);

    box.querySelectorAll('.auth-mode-tab').forEach(tab => {
      tab.addEventListener('click', () => {
        _mode = tab.dataset.mode;
        renderModal();
        _updateAriaLabel();
        box.querySelector('#auth-email')?.focus();
      });
    });

    box.querySelector('#auth-apple-btn').addEventListener('click', () => {
      API.authSignInWithApple();
    });

    box.querySelector('#auth-discord-btn').addEventListener('click', () => {
      API.authSignInWithDiscord();
    });

    const emailInput    = box.querySelector('#auth-email');
    const passwordInput = box.querySelector('#auth-password');
    const confirmInput  = box.querySelector('#auth-confirm');
    const submitBtn     = box.querySelector('#auth-submit');

    submitBtn.addEventListener('click', handleSubmit);

    passwordInput.addEventListener('keydown', e => {
      if (e.key !== 'Enter') return;
      if (_mode === 'signUp' && confirmInput) confirmInput.focus();
      else handleSubmit();
    });

    confirmInput?.addEventListener('keydown', e => {
      if (e.key === 'Enter') handleSubmit();
    });

    emailInput.addEventListener('keydown', e => {
      if (e.key === 'Enter') passwordInput?.focus();
    });
  }

  /* ================================================================
     FORM SUBMISSION
  ================================================================ */

  async function handleSubmit() {
    if (_loading) return;

    const email    = box.querySelector('#auth-email')?.value.trim()  || '';
    const password = box.querySelector('#auth-password')?.value       || '';
    const confirm  = box.querySelector('#auth-confirm')?.value        || '';

    clearMessages();

    if (!email || !password) { showError('Email and password are required.'); return; }
    if (_mode === 'signUp' && password !== confirm) {
      showError('Passwords do not match.');
      return;
    }

    setLoading(true);
    try {
      if (_mode === 'signIn') {
        const session = await API.authSignIn(email, password);
        // Set session immediately — don't wait for onAuthStateChange — so that
        // Auth.isAuthenticated() is true the moment the modal closes. This prevents
        // the PWA / mobile Safari race where the SIGNED_IN event fires after close()
        // and something renders the signed-out gate before the event arrives.
        if (session) {
          _session = session;
          updateNavUI();
          await API.fetchUserRole().catch(() => {});
          document.dispatchEvent(new CustomEvent('auth-change', { detail: { event: 'SIGNED_IN', session } }));
        }
        close();
      } else {
        const result = await API.authSignUp(email, password);
        if (!result.session) {
          showInfo('Check your email to confirm your account, then sign in.');
          setLoading(false);
          return;
        }
        if (result.session) {
          _session = result.session;
          updateNavUI();
          await API.fetchUserRole().catch(() => {});
          document.dispatchEvent(new CustomEvent('auth-change', { detail: { event: 'SIGNED_IN', session: result.session } }));
        }
        close();
      }
    } catch (err) {
      showError(err.message);
    }
    setLoading(false);
  }

  function setLoading(val) {
    _loading = val;
    const btn = box.querySelector('#auth-submit');
    if (!btn) return;
    btn.disabled = val;
    btn.textContent = val ? 'Loading…' : (_mode === 'signIn' ? 'Sign In' : 'Create Account');
  }

  function showError(msg) {
    const el = box.querySelector('#auth-error');
    if (!el) return;
    el.textContent = msg; el.hidden = false;
  }

  function showInfo(msg) {
    const el = box.querySelector('#auth-info');
    if (!el) return;
    el.textContent = msg; el.hidden = false;
  }

  function clearMessages() {
    ['#auth-error', '#auth-info'].forEach(sel => {
      const el = box.querySelector(sel);
      if (el) { el.textContent = ''; el.hidden = true; }
    });
  }

  /* ================================================================
     NAV UI
  ================================================================ */

  function updateNavUI() {
    // Show a subtle indicator on the Profile nav item when signed in
    document.getElementById('nav-profile-btn')
      ?.classList.toggle('signed-in', !!_session);
  }

  /* ================================================================
     TOKEN HELPERS
  ================================================================ */

  // Returns true if the session's access token expires within windowMs (default 15 min).
  // Supabase v2 provides expires_at (Unix seconds) directly on the session object.
  function sessionExpiresSoon(session, windowMs = 15 * 60 * 1000) {
    if (!session?.expires_at) return false;
    return (session.expires_at * 1000) - Date.now() < windowMs;
  }

  /* ================================================================
     INIT
  ================================================================ */

  async function init() {
    // ── 0. QR code session transfer ───────────────────────────────────────────
    // When an Android (or any non-iOS) user scans the QR code from the desktop
    // Scan view, the URL contains ?rt=REFRESH_TOKEN. Exchange it for a fresh
    // session so the user is authenticated on their mobile browser without any
    // manual sign-in step.
    const urlParams = new URLSearchParams(window.location.search);
    const rtParam   = urlParams.get('rt');
    if (rtParam) {
      try {
        const session = await API.authRefreshSession(rtParam);
        if (session) {
          _session = session;
          updateNavUI();
          await API.fetchUserRole().catch(() => {});
          document.dispatchEvent(new CustomEvent('auth-change', {
            detail: { event: 'SIGNED_IN', session }
          }));
        }
      } catch (e) {
        console.warn('[auth] Could not restore session from ?rt= param:', e);
      }
      // Remove ?rt= from the URL so it doesn't linger in history.
      // ?view= is preserved — app.js reads it after Auth.init() completes.
      const cleanUrl = new URL(window.location.href);
      cleanUrl.searchParams.delete('rt');
      history.replaceState(null, '', cleanUrl.toString());
    }

    // ── 1. Eager session restore ──────────────────────────────────────────────
    // Skip if we already established a session from the ?rt= QR param above.
    // authGetSession() reads from Supabase's in-memory state (populated from
    // localStorage during createClient) before the async INITIAL_SESSION event
    // fires. Setting _session here means Auth.isAuthenticated() returns true on
    // the first frame, preventing the signed-out flash on every page reload.
    if (!_session) {
      const savedSession = await API.authGetSession();
      if (savedSession) {
        _session = savedSession;
        updateNavUI();
        await API.fetchUserRole().catch(() => {});
        document.dispatchEvent(new CustomEvent('auth-change', {
          detail: { event: 'INITIAL_SESSION', session: savedSession }
        }));

        // Proactively refresh if the restored token is close to expiry (or stale).
        // Supabase's autoRefreshToken handles the scheduled refresh, but it won't
        // fire if the app was closed and reopened with an expired-but-refreshable token.
        if (sessionExpiresSoon(savedSession)) {
          API.authRefreshSession(savedSession.refresh_token).catch(() => {});
        }
      }
    }

    // ── 2. Supabase auth state subscription ──────────────────────────────────
    // We handle each event type explicitly to avoid iOS Safari / PWA edge cases
    // where TOKEN_REFRESHED or a stale INITIAL_SESSION fires with session=null
    // and incorrectly clears a just-established session.
    API.authOnStateChange(async (event, session) => {
      if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED') {
        if (!session) return; // Supabase guarantees session for these events; bail if missing
        // Skip duplicate SIGNED_IN if handleSubmit or eager restore already set same user
        if (event === 'SIGNED_IN' && _session?.user?.id === session?.user?.id) return;
        _session = session;
        updateNavUI();
        await API.fetchUserRole().catch(() => {});
        document.dispatchEvent(new CustomEvent('auth-change', { detail: { event, session } }));

      } else if (event === 'SIGNED_OUT') {
        _session = null;
        updateNavUI();
        // Reset cached role to 'user' so any UI that reads
        // getCachedRole() after sign-out doesn't see the prior
        // user's admin/mod role. fetchUserRole with no session
        // sets _userRole = 'user'.
        await API.fetchUserRole().catch(() => {});
        document.dispatchEvent(new CustomEvent('auth-change', { detail: { event, session: null } }));

      } else if (event === 'INITIAL_SESSION') {
        if (session && session.user?.id !== _session?.user?.id) {
          // Different user than what we eagerly restored (e.g. Supabase returned a
          // freshly-refreshed session with a new access token for a different account).
          _session = session;
          updateNavUI();
          await API.fetchUserRole().catch(() => {});
          document.dispatchEvent(new CustomEvent('auth-change', { detail: { event, session } }));
        } else if (!session && !_session) {
          // No stored session at all — user is signed out; render sign-in gates.
          document.dispatchEvent(new CustomEvent('auth-change', { detail: { event, session: null } }));
        }
        // Else: same user already broadcast via eager restore above — no-op.
      }
    });

    // ── 3. Proactive token refresh on tab focus ───────────────────────────────
    // When the user returns to a backgrounded tab, the token may be expired or
    // close to expiry. Refresh silently here so the next API call doesn't fail.
    // If the refresh token itself is expired, Supabase fires SIGNED_OUT and the
    // auth-change listener above clears the session gracefully.
    document.addEventListener('visibilitychange', async () => {
      if (document.hidden || !_session) return;
      if (sessionExpiresSoon(_session)) {
        try {
          await API.authRefreshSession(_session.refresh_token);
        } catch { /* SIGNED_OUT event will handle auth failure */ }
      }
    });

    // ── 4. Modal UI event handlers ────────────────────────────────────────────
    // Click on the dialog backdrop area (not the inner box) closes.
    overlay.addEventListener('click', e => { if (e.target === overlay) close(); });
    // Native <dialog> fires `cancel` on ESC — preventDefault so we
    // can route through close() (which handles other-modal scroll-
    // lock coordination). Falls back to manual ESC for the legacy
    // hidden-attribute path.
    overlay.addEventListener('cancel', e => {
      e.preventDefault();
      close();
    });
    document.addEventListener('keydown', e => {
      if (e.key !== 'Escape') return;
      const isOpen = overlay.open ?? !overlay.hidden;
      if (isOpen && overlay.tagName !== 'DIALOG') close();
    });
  }

  /* ================================================================
     PUBLIC API
  ================================================================ */

  return {
    init,
    open,
    close,
    isAuthenticated: () => !!_session,
    getSession:      () => _session,
    signOut: async () => {
      await API.authSignOut();
    },
  };
})();

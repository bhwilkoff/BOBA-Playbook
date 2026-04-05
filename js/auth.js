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
    overlay.hidden = false;
    document.body.style.overflow = 'hidden';
    setTimeout(() => box.querySelector('#auth-email')?.focus(), 60);
  }

  function close() {
    overlay.hidden = true;
    document.body.style.overflow = '';
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
                   placeholder="you@example.com">
          </div>
          <div class="form-field">
            <label class="form-label" for="auth-password">PASSWORD</label>
            <input class="form-input" type="password" id="auth-password"
                   autocomplete="${_mode === 'signIn' ? 'current-password' : 'new-password'}"
                   placeholder="••••••••">
          </div>
          ${_mode === 'signUp' ? `
          <div class="form-field">
            <label class="form-label" for="auth-confirm">CONFIRM PASSWORD</label>
            <input class="form-input" type="password" id="auth-confirm"
                   autocomplete="new-password" placeholder="••••••••">
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
        box.querySelector('#auth-email')?.focus();
      });
    });

    box.querySelector('#auth-apple-btn').addEventListener('click', () => {
      API.authSignInWithApple();
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
        await API.authSignIn(email, password);
        close();
      } else {
        const result = await API.authSignUp(email, password);
        if (!result.session) {
          showInfo('Check your email to confirm your account, then sign in.');
          setLoading(false);
          return;
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
     INIT
  ================================================================ */

  async function init() {
    // Restore session from QR code URL.
    // The QR code embeds only the refresh token as a query param (?rt=...) —
    // query params survive iOS Safari's QR URL handling; hash fragments do not.
    // We use refreshSession() rather than setSession() so we only need the
    // shorter refresh token (the JWT access token is ~600 chars and makes the
    // QR code too dense to scan reliably).
    const params = new URLSearchParams(window.location.search);
    const rt = params.get('rt');
    if (rt) {
      try {
        await API.authRefreshSession(rt);
      } catch (e) {
        console.warn('[auth] Could not restore session from URL:', e);
      }
      // Remove rt from the URL so it doesn't linger in browser history
      const cleanUrl = new URL(window.location.href);
      cleanUrl.searchParams.delete('rt');
      history.replaceState(null, '', cleanUrl.toString());
    }

    // Subscribe to Supabase auth state
    API.authOnStateChange((event, session) => {
      _session = session;
      updateNavUI();
      // Broadcast so collection.js and app.js can react
      document.dispatchEvent(
        new CustomEvent('auth-change', { detail: { event, session } })
      );
    });

    // Close on overlay background click
    overlay.addEventListener('click', e => { if (e.target === overlay) close(); });

    // Close on Escape
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && !overlay.hidden) close();
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

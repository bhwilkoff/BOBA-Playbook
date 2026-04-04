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
          <svg width="16" height="16" viewBox="0 0 814 1000" fill="currentColor" aria-hidden="true">
            <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76 0-103.7 40.8-165.9 40.8s-105-57.8-155.5-127.4C46 391.1 0 306 0 228c0-74.9 22.5-145.9 65.5-200.5C130 0 211.6 0 252.1 0c128.3 0 215.7 84.9 279.6 84.9 60.5 0 163.7-88.5 296.6-88.5 46.6 0 169.5 4.5 241.8 112.5zm-256.3-159c45.5-56.7 110.5-82.8 175.5-82.8 5.7 0 11.5.3 17.1.7-3.6 58.7-32.3 121.5-75.5 161.1-40.2 36.8-103.5 63.7-170.5 57.5 0-57 23.1-117.5 53.4-136.5z"/>
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

  function init() {
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

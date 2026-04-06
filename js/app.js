/**
 * BOBA Playbook — Main Application
 *
 * M1: Search Mode — browse, search, and filter BOBA cards.
 *
 * Data model note: cards.json has multiple rows per physical card when a card
 * has multiple hero associations (same cardNumber, different hero/athleteInspiration).
 * The grid shows one entry per unique cardNumber. The detail modal shows all
 * hero associations for that card.
 *
 * Search-index note: tokenIndex / byElement / bySet etc. store CARD NUMBERS
 * (strings like "1", "BF-208") as values — NOT array positions.
 */

(function () {
  'use strict';

  /* ================================================================
     CONSTANTS
  ================================================================ */
  const PAGE_SIZE           = 60;
  const SEARCH_DEBOUNCE_MS  = 280;

  /* ================================================================
     HELPERS
  ================================================================ */
  const $ = (id) => document.getElementById(id);

  function escHtml(str) {
    if (str == null) return '';
    const d = document.createElement('div');
    d.textContent = String(str);
    return d.innerHTML;
  }

  function relativeDate(iso) {
    if (!iso) return '';
    const date = new Date(iso);
    if (isNaN(date)) return '';
    const days = Math.floor((Date.now() - date.getTime()) / 86400000);
    if (days < 0)  return '';
    if (days === 0) return 'today';
    if (days < 7)  return `${days}d ago`;
    const weeks = Math.floor(days / 7);
    if (weeks < 5) return `${weeks}w ago`;
    return `${Math.floor(days / 30)}mo ago`;
  }

  /* ================================================================
     STATE
  ================================================================ */
  let cards         = [];         // raw catalog (may have multi-hero dupes)
  let searchIndex   = null;
  let categories    = null;

  // Built after load:
  let cardsByNumber = new Map();  // cardNumber (string) → Card[] (all hero associations)
  let displayCards  = [];         // one Card per unique cardNumber (for the grid)

  let filteredCards  = [];
  let displayedCount = 0;

  const filters = {
    query:    '',
    element:  '',
    set:      '',
    treatment:'',
    hasImage: false,
    powerMin: null,
    powerMax: null,
  };

  /* ================================================================
     DOM REFS
  ================================================================ */
  const loadingState    = $('loading-state');
  const cardGrid        = $('card-grid');
  const emptyState      = $('empty-state');
  const searchInput     = $('search-input');
  const searchClear     = $('search-clear');
  const searchCount     = $('search-count');
  const elementFilters  = $('element-filters');
  const setFilter       = $('set-filter');
  const treatmentFilter = $('treatment-filter');
  const hasImageToggle  = $('has-image-toggle');
  const loadSentinel    = $('load-sentinel');
  const clearFiltersBtn = $('clear-filters-btn');
  const powerMinInput  = $('power-min');
  const powerMaxInput  = $('power-max');
  const filterToggleBtn = $('filter-toggle-btn');
  const filterPanel     = $('filter-panel');
  const filterBadge     = $('filter-badge');

  const modalOverlay  = $('card-modal-overlay');
  const modalContent  = $('modal-content');
  const modalCloseBtn = $('modal-close-btn');

  const sidebarToggle  = $('sidebar-toggle');
  const sidebar        = $('channels-sidebar');
  const sidebarOverlay = $('sidebar-overlay');

  /* ================================================================
     SIDEBAR (mobile)
  ================================================================ */
  sidebarToggle.addEventListener('click', () => {
    if (sidebar.classList.contains('open')) {
      closeSidebar();
    } else {
      sidebar.classList.add('open');
      sidebarOverlay.classList.add('visible');
      sidebarToggle.setAttribute('aria-expanded', 'true');
    }
  });

  function closeSidebar() {
    sidebar.classList.remove('open');
    sidebarOverlay.classList.remove('visible');
    sidebarToggle.setAttribute('aria-expanded', 'false');
    // Remove focus from the button so :focus-visible ring clears after close
    sidebarToggle.blur();
  }
  sidebarOverlay.addEventListener('click', closeSidebar);

  /* ================================================================
     FILTER PANEL TOGGLE (mobile)
  ================================================================ */
  filterToggleBtn?.addEventListener('click', () => {
    const open = filterPanel.classList.toggle('open');
    filterToggleBtn.setAttribute('aria-expanded', String(open));
    filterPanel.setAttribute('aria-hidden', String(!open));
  });

  function updateFilterBadge() {
    let count = 0;
    if (filters.element)                                count++;
    if (filters.set)                                    count++;
    if (filters.treatment)                              count++;
    if (filters.powerMin !== null || filters.powerMax !== null) count++;
    if (filters.hasImage)                               count++;
    if (filterBadge) {
      filterBadge.textContent = String(count);
      filterBadge.hidden = count === 0;
    }
    filterToggleBtn?.classList.toggle('has-filters', count > 0);
  }

  /* ================================================================
     VIEW SYSTEM
  ================================================================ */
  const viewIds = ['search', 'scan', 'rules', 'collection', 'profile'];
  const navBtnIds = {
    search:     'nav-search-btn',
    scan:       'nav-scan-btn',
    rules:      'nav-rules-btn',
    collection: 'nav-collection-btn',
    profile:    'nav-profile-btn',
  };

  function showView(name, fromHistory = false) {
    viewIds.forEach(id => {
      const el = $(`view-${id}`);
      if (el) el.hidden = id !== name;
    });
    Object.entries(navBtnIds).forEach(([id, btnId]) => {
      const btn = $(btnId);
      if (!btn) return;
      const active = id === name;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-current', active ? 'page' : 'false');
    });
    closeSidebar();
    if (name === 'scan') {
      initScanView();
    } else {
      teardownScan();
    }
    if (name === 'rules') {
      initPlayView();
    }
    if (!fromHistory) {
      history.pushState({ view: name }, '', name === 'search' ? '?' : `?view=${name}`);
    }
  }

  Object.entries(navBtnIds).forEach(([view, btnId]) => {
    const btn = $(btnId);
    if (btn) btn.addEventListener('click', () => showView(view));
  });

  window.addEventListener('popstate', (e) => {
    showView(e.state?.view || 'search', true);
  });

  /* ================================================================
     PLAY VIEW
  ================================================================ */
  let playViewInitialized = false;

  function initPlayView() {
    if (playViewInitialized) return;
    playViewInitialized = true;

    // Top-level tab pills: Rules ↔ Strategy
    const tabs   = document.querySelectorAll('.play-tab');
    const panels = document.querySelectorAll('.play-panel');

    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const target = tab.dataset.tab;
        tabs.forEach(t => {
          t.classList.toggle('active', t.dataset.tab === target);
          t.setAttribute('aria-selected', String(t.dataset.tab === target));
        });
        panels.forEach(p => {
          p.hidden = p.id !== `play-panel-${target}`;
        });
      });
    });

    // Mode buttons inside the Rules panel: Rookie / Substitution / Playmaker
    const modeBtns    = document.querySelectorAll('.rules-mode-btn');
    const modeContent = document.querySelectorAll('.rules-content');

    modeBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const mode = btn.dataset.mode;
        modeBtns.forEach(b => b.classList.toggle('active', b.dataset.mode === mode));
        modeContent.forEach(el => {
          el.hidden = el.id !== `rules-${mode}`;
        });
      });
    });
  }

  /* ================================================================
     SCAN VIEW
  ================================================================ */
  const WORKER_URL = 'https://boba-ebay-proxy.benwilkoff.workers.dev';
  let scanStream = null;

  function initScanView() {
    const container = $('scan-container');
    if (!container || container.dataset.initialized === '1') return;
    container.dataset.initialized = '1';

    if (!navigator.mediaDevices?.getUserMedia) {
      renderScanUnavailable(container);
      return;
    }
    renderScanCamera(container);
  }

  function teardownScan() {
    if (scanStream) {
      scanStream.getTracks().forEach(t => t.stop());
      scanStream = null;
    }
    const container = $('scan-container');
    if (container) {
      container.innerHTML = '';
      delete container.dataset.initialized;
    }
  }

  async function renderScanCamera(container) {
    const isDesktop = window.innerWidth >= 1024;

    container.innerHTML = `
      <div class="scan-wrap">
        <div class="scan-camera-area">
          <div class="scan-video-wrap">
            <video id="scan-video" class="scan-video" autoplay playsinline muted></video>
            <div class="scan-guide-frame" aria-hidden="true"></div>
          </div>
          <p class="scan-status" id="scan-status" aria-live="polite">Starting camera…</p>
          <button class="scan-capture-btn" id="scan-capture-btn" disabled>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
                 width="20" height="20" aria-hidden="true">
              <circle cx="12" cy="12" r="9"/>
              <circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/>
            </svg>
            Capture Card
          </button>
          <canvas id="scan-canvas" style="display:none"></canvas>
          <div class="scan-result" id="scan-result" hidden></div>
        </div>
        ${isDesktop ? `
          <div class="scan-desktop-aside">
            <p class="scan-aside-label">Scan on your phone for best results:</p>
            <div id="scan-qr-container" class="scan-qr-img" style="width:220px;height:220px;display:flex;align-items:center;justify-content:center;">
              <span style="font-size:0.75rem;color:var(--boba-text-muted)">Loading…</span>
            </div>
            <p class="scan-aside-sub" id="scan-qr-note"></p>
          </div>
        ` : ''}
      </div>
    `;

    startCamera();
    $('scan-capture-btn').addEventListener('click', handleCapture);

    if (isDesktop) generateScanQR().catch(() => {});
  }

  async function generateScanQR() {
    const qrContainer = $('scan-qr-container');
    const note        = $('scan-qr-note');
    if (!qrContainer) return;

    // Use the iOS app deep link as the QR target.
    // The restricted web view opened by iOS QR scanners doesn't support
    // Supabase auth (no localStorage persistence, sign-in causes a page
    // reload). Opening the native app avoids the web auth problem entirely —
    // the user is already authenticated in the iOS app.
    // bobaplaybook://scan → ContentView sets selectedTab = 1 (Scan tab).
    const scanUrl = 'bobaplaybook://scan';

    // Lazy-load qrcodejs — has a proper browser bundle unlike the 'qrcode' npm package
    if (!window.QRCode) {
      await new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = 'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js';
        s.onload = resolve;
        s.onerror = reject;
        document.head.appendChild(s);
      });
    }

    // qrcodejs takes a container div and creates the canvas inside it
    qrContainer.innerHTML = '';
    new window.QRCode(qrContainer, {
      text:           scanUrl,
      width:          220,
      height:         220,
      colorDark:      '#00F5FF',
      colorLight:     '#0D0D1A',
      correctLevel:   window.QRCode.CorrectLevel.L,
    });

    if (note) {
      note.textContent = 'Scan with your iPhone to open the BOBA app.';
    }
  }

  async function startCamera() {
    const statusEl = $('scan-status');
    const captureBtn = $('scan-capture-btn');
    try {
      scanStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } }
      });
      const video = $('scan-video');
      video.srcObject = scanStream;
      await video.play();
      captureBtn.disabled = false;
      statusEl.textContent = 'Position card so the number is clearly visible, then tap Capture.';
    } catch {
      captureBtn.hidden = true;
      statusEl.textContent = 'Camera access denied. Enable camera permissions and refresh.';
    }
  }

  async function handleCapture() {
    const captureBtn  = $('scan-capture-btn');
    const statusEl    = $('scan-status');
    const resultEl    = $('scan-result');
    const video       = $('scan-video');
    const canvas      = $('scan-canvas');

    captureBtn.disabled = true;
    resultEl.hidden = true;

    if (!video.videoWidth) {
      statusEl.textContent = 'Camera not ready yet. Please wait a moment and try again.';
      captureBtn.disabled = false;
      return;
    }

    statusEl.textContent = 'Scanning…';

    // Resize frame to max 400px wide before encoding (keeps payload small for AI)
    const maxW = 640;
    const vw = video.videoWidth  || maxW;
    const vh = video.videoHeight || 480;
    const scale = Math.min(1, maxW / vw);
    canvas.width  = Math.round(vw * scale);
    canvas.height = Math.round(vh * scale);
    canvas.getContext('2d').drawImage(video, 0, 0, canvas.width, canvas.height);
    const base64 = canvas.toDataURL('image/jpeg', 0.85).split(',')[1];

    try {
      const res  = await fetch(`${WORKER_URL}/ocr`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ image: base64 })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      const { cardNumber, rawText } = data;

      console.log('[scan] rawText:', rawText);
      console.log('[scan] cardNumber:', cardNumber);

      // Primary: card number match — exact, no ambiguity
      const numberMatches = cardNumber
        ? (cardsByNumber.get(String(cardNumber).toUpperCase()) ?? [])
        : [];

      // Fallback: hero + power + element scoring, returns ranked candidates
      const textCandidates = (!numberMatches.length && rawText)
        ? findCardsByOCRText(rawText)
        : [];

      const candidates = numberMatches.length ? numberMatches : textCandidates;

      if (candidates.length === 1) {
        showScanMatch(resultEl, candidates[0]);
        statusEl.textContent = `Found: ${candidates[0].name}`;
      } else if (candidates.length > 1) {
        showScanCandidates(resultEl, candidates);
        statusEl.textContent = `${candidates.length} possible matches — select the right card.`;
      } else if (cardNumber) {
        statusEl.textContent = `Detected #${cardNumber} — not in catalog.`;
        showScanRetry(resultEl);
      } else {
        statusEl.textContent = 'No card detected. Ensure good lighting and try again.';
        showScanRetry(resultEl);
      }
    } catch (err) {
      statusEl.textContent = `Scan failed: ${err.message}`;
      showScanRetry(resultEl);
      console.error('OCR error:', err);
    }

    captureBtn.disabled = false;
  }

  // Multi-facet OCR matching — mirrors iOS secondary path but returns ALL ranked candidates.
  // Scores each card by how many facets agree with the transcribed text.
  // Caller shows a picker when > 1 result.
  const OCR_ELEMENTS = ['FIRE','ICE','HEX','STEEL','BRAWL','GLOW','GUM','SUPER'];
  // Words in OCR text that hint at a set name
  const OCR_SET_HINTS = [
    { words: ['griffey'],               sets: ['Griffey'] },
    { words: ['alpha blast'],           sets: ['Alpha Blast'] },
    { words: ['alpha update'],          sets: ['Alpha Update'] },
    { words: ['alpha'],                 sets: ['Alpha', 'Alpha Blast', 'Alpha Update'] },
    { words: ['world champion'],        sets: ['World Champions 2024','World Champions 2025'] },
    { words: ['big league'],            sets: ['Big League Chew'] },
    { words: ['national'],              sets: ['National 24 Starter Set'] },
    { words: ['battle trainer'],        sets: ['Battle Trainer Kit'] },
  ];

  function findCardsByOCRText(rawText) {
    const text    = rawText.toLowerCase();
    const textUp  = rawText.toUpperCase();

    // 2–3 digit integers (powers run ~60–200)
    const nums = new Set(
      [...text.matchAll(/\b(\d{2,3})\b/g)].map(m => parseInt(m[1]))
    );
    if (nums.size === 0) return [];

    // Which elements appear in the OCR text?
    const seenElements = new Set(OCR_ELEMENTS.filter(el => textUp.includes(el)));

    // Which sets are hinted?
    const hintedSets = new Set();
    for (const hint of OCR_SET_HINTS) {
      if (hint.words.some(w => text.includes(w))) hint.sets.forEach(s => hintedSets.add(s));
    }

    const scored = [];
    for (const card of displayCards) {
      if (!card.hero || card.power == null) continue;

      const heroWords = card.hero.toLowerCase().split(/\s+/).filter(w => w.length > 2);
      if (!heroWords.length) continue;
      if (!heroWords.every(w => text.includes(w))) continue;  // hero must match
      if (!nums.has(card.power)) continue;                     // power must match

      // Score additional facets — more agreement = higher confidence
      let score = 0;
      if (seenElements.size > 0) {
        if (seenElements.has(card.element))  score += 3;  // element confirmed
        else                                  score -= 1;  // different element mentioned
      }
      if (hintedSets.size > 0) {
        if (hintedSets.has(card.set))  score += 2;
        else                            score -= 1;
      }
      if (card.imageFile) score += 1;  // prefer cards with images for visual confirmation

      scored.push({ card, score });
    }

    if (!scored.length) return [];
    scored.sort((a, b) => b.score - a.score);

    // Cap at 12 to keep the picker usable
    return scored.slice(0, 12).map(s => s.card);
  }

  function showScanCandidates(container, candidates) {
    container.innerHTML = `
      <div class="scan-candidates">
        <p class="scan-candidates-label">Select the card you scanned:</p>
        <div class="scan-candidates-list">
          ${candidates.map((card, i) => {
            const imgSrc  = API.cardThumbUrl(card);
            const element = card.element || 'NONE';
            const meta    = [card.set, card.treatment].filter(Boolean).join(' · ');
            return `
              <button class="scan-candidate-item" data-index="${i}"
                      aria-label="${escHtml(card.name)}, ${element}, power ${card.power}">
                ${imgSrc
                  ? `<img class="scan-candidate-img" src="${escHtml(imgSrc)}" alt="" loading="lazy">`
                  : `<div class="scan-candidate-img scan-candidate-placeholder"></div>`}
                <div class="scan-candidate-info">
                  <div class="scan-candidate-name">${escHtml(card.name)}</div>
                  <div class="scan-candidate-meta">
                    <span class="element-badge" data-element="${escHtml(element)}">${escHtml(element)}</span>
                    <span class="scan-candidate-power">${card.power}</span>
                    ${meta ? `<span class="scan-candidate-set">${escHtml(meta)}</span>` : ''}
                  </div>
                  <div class="scan-candidate-number">#${escHtml(card.cardNumber)}</div>
                </div>
              </button>`;
          }).join('')}
        </div>
        <button class="btn-ghost-sm scan-again-btn" style="margin-top:.75rem">Scan Again</button>
      </div>`;
    container.hidden = false;
    candidates.forEach((card, i) => {
      container.querySelectorAll('.scan-candidate-item')[i]
        .addEventListener('click', () => {
          showScanMatch(container, card);
          $('scan-status').textContent = `Found: ${card.name}`;
        });
    });
    container.querySelector('.scan-again-btn').addEventListener('click', resetScan);
  }

  function showScanMatch(container, card) {
    const imgSrc  = API.cardThumbUrl(card);
    const element = card.element || 'NONE';
    container.innerHTML = `
      <div class="scan-result-card">
        ${imgSrc ? `<img class="scan-result-img" src="${escHtml(imgSrc)}" alt="${escHtml(card.name)}">` : ''}
        <div class="scan-result-info">
          <span class="element-badge" data-element="${escHtml(element)}">${escHtml(element)}</span>
          <div class="scan-result-name">${escHtml(card.name)}</div>
          <div class="scan-result-num">#${escHtml(card.cardNumber)}</div>
          <div class="scan-result-actions">
            <button class="btn-primary scan-view-btn">View Card</button>
            <button class="btn-ghost-sm scan-again-btn">Scan Again</button>
          </div>
        </div>
      </div>
    `;
    container.hidden = false;
    container.querySelector('.scan-view-btn').addEventListener('click', () => openModal(card));
    container.querySelector('.scan-again-btn').addEventListener('click', resetScan);
  }

  function showScanRetry(container) {
    container.innerHTML = `<button class="btn-ghost-sm scan-again-btn">Try Again</button>`;
    container.hidden = false;
    container.querySelector('.scan-again-btn').addEventListener('click', resetScan);
  }

  function resetScan() {
    const resultEl = $('scan-result');
    if (resultEl) resultEl.hidden = true;
    const statusEl = $('scan-status');
    if (statusEl) statusEl.textContent = 'Position card so the number is clearly visible, then tap Capture.';
  }

  function renderScanUnavailable(container) {
    const scanUrl = window.location.origin + window.location.pathname + '?view=scan';
    const qrSrc   = `https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(scanUrl)}&color=00F5FF&bgcolor=0D0D1A&qzone=1`;
    container.innerHTML = `
      <div class="view-inner">
        <h2 class="view-heading">Scan</h2>
        <p class="placeholder-text">Camera scanning isn't available in this browser.</p>
        <p class="placeholder-text">For instant on-device scanning, use the <strong>BOBA Playbook iOS app</strong>.</p>
        <div class="scan-qr-block">
          <p class="scan-aside-label">Open on your phone:</p>
          <img class="scan-qr-img" src="${escHtml(qrSrc)}" alt="QR code" width="180" height="180">
        </div>
      </div>
    `;
  }

  /* ================================================================
     DATA PREPARATION
     Build lookup structures after cards.json loads.
  ================================================================ */

  function prepareData() {
    // Build cardsByNumber: string cardNumber → all Card variants (hero associations)
    // Kept for the modal "hero variants" panel — not used to collapse displayCards.
    for (const card of cards) {
      const num = String(card.cardNumber);
      if (!cardsByNumber.has(num)) cardsByNumber.set(num, []);
      cardsByNumber.get(num).push(card);
    }

    // Every card is distinct (different imageFile per hero association).
    // Show all cards; sort with images first.
    displayCards.push(...cards);
    displayCards.sort((a, b) => {
      const aImg = !!(a.imageFile);
      const bImg = !!(b.imageFile);
      if (aImg !== bImg) return aImg ? -1 : 1;
      return 0;
    });
  }

  /* ================================================================
     SEARCH LOGIC
     search-index values are card NUMBERS (strings), not array positions.
  ================================================================ */

  function computeResults() {
    let resultNums = null; // null = "all cards"

    // Text search
    const q = filters.query.trim().toLowerCase();
    if (q) {
      const tokens = q.split(/\s+/).filter(Boolean);
      for (const token of tokens) {
        const matches = new Set();
        for (const key in searchIndex.tokenIndex) {
          if (key.startsWith(token)) {
            for (const cardNum of searchIndex.tokenIndex[key]) {
              matches.add(String(cardNum));
            }
          }
        }
        resultNums = resultNums === null ? matches : intersect(resultNums, matches);
      }
      if (resultNums !== null && resultNums.size === 0) return [];
    }

    // Element filter
    if (filters.element) {
      const s = new Set((searchIndex.byElement[filters.element] || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    // Set filter
    if (filters.set) {
      const s = new Set((searchIndex.bySet[filters.set] || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    // Treatment filter
    if (filters.treatment) {
      const s = new Set((searchIndex.byTreatment[filters.treatment] || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    // Has image filter
    if (filters.hasImage) {
      const s = new Set((searchIndex.hasImage || []).map(String));
      resultNums = resultNums === null ? s : intersect(resultNums, s);
    }

    if (resultNums === null) {
      // No search/filter applied — apply power filter directly against all cards if needed
      if (filters.powerMin !== null || filters.powerMax !== null) {
        return displayCards.filter(card => {
          const p = Number(card.power);
          const minOk = filters.powerMin === null || p >= filters.powerMin;
          const maxOk = filters.powerMax === null || p <= filters.powerMax;
          return minOk && maxOk;
        });
      }
      return displayCards;
    }

    // Expand card numbers → all matching individual cards
    const results = [];
    for (const num of resultNums) {
      const variants = cardsByNumber.get(num);
      if (variants) results.push(...variants);
    }

    // Power range filter applied per-card (cards sharing a number can have different power)
    if (filters.powerMin !== null || filters.powerMax !== null) {
      return results.filter(card => {
        const p = Number(card.power);
        const minOk = filters.powerMin === null || p >= filters.powerMin;
        const maxOk = filters.powerMax === null || p <= filters.powerMax;
        return minOk && maxOk;
      });
    }

    return results;
  }

  function intersect(a, b) {
    return new Set([...a].filter(x => b.has(x)));
  }

  /* ================================================================
     TREATMENT & SET CLASS HELPERS
  ================================================================ */

  function getTreatmentClass(treatment) {
    if (!treatment) return 'tf-base';
    const t = treatment.toLowerCase();
    if (t.includes('blizzard')) return 'tf-blizzard';
    if (t.includes('superfoil')) return 'tf-superfoil';
    if (t.includes('battlefoil')) return 'tf-battlefoil';
    if (t.includes('inspired ink') || t.includes('inspired-ink')) return 'tf-inspired';
    if (t.includes('inspired')) return 'tf-inspired-m';
    if (t.includes('logofoil')) return 'tf-logofoil';
    if (t.includes('blast')) return 'tf-blast';
    if (t.includes('paper')) return 'tf-paper';
    if (t === 'base' || t === 'standard' || t === '') return 'tf-base';
    return 'tf-special';
  }

  function getSetClass(set) {
    if (!set) return 'set-other';
    const s = set.toLowerCase();
    if (s.includes('alpha')) return 'set-alpha';
    if (s.includes('griffey')) return 'set-griffey';
    if (s.includes('world champions') || s.includes('champions')) return 'set-champions';
    if (s.includes('starter')) return 'set-starter';
    return 'set-other';
  }

  /* ================================================================
     FILTER UI
  ================================================================ */

  function buildElementFilters() {
    const elements = Object.keys(searchIndex.byElement).sort();

    const allPill = makePill('', 'All');
    allPill.classList.add('active');
    allPill.setAttribute('aria-pressed', 'true');
    allPill.addEventListener('click', () => setElementFilter(''));
    elementFilters.appendChild(allPill);

    for (const el of elements) {
      const pill = makePill(el, el);
      pill.addEventListener('click', () => setElementFilter(el));
      elementFilters.appendChild(pill);
    }
  }

  function makePill(element, label) {
    const btn = document.createElement('button');
    btn.className = 'element-pill';
    btn.dataset.element = element;
    btn.setAttribute('aria-pressed', 'false');
    const dot = document.createElement('span');
    dot.className = 'element-pill-dot';
    btn.appendChild(dot);
    btn.appendChild(document.createTextNode(label));
    return btn;
  }

  function setElementFilter(element) {
    filters.element = element;
    elementFilters.querySelectorAll('.element-pill').forEach(pill => {
      const active = pill.dataset.element === element;
      pill.classList.toggle('active', active);
      pill.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    applyFilters();
  }

  function buildSetFilter() {
    const sets = Object.keys(categories.sets || {}).sort();
    for (const set of sets) {
      const opt = document.createElement('option');
      opt.value = set;
      const count = categories.sets[set]?.count;
      opt.textContent = count ? `${set} (${count.toLocaleString()})` : set;
      setFilter.appendChild(opt);
    }
  }

  function buildTreatmentFilter(selectedSet) {
    while (treatmentFilter.options.length > 1) treatmentFilter.remove(1);
    const all = selectedSet
      ? (categories.sets[selectedSet]?.treatments || []).sort()
      : [...new Set(Object.values(categories.sets || {}).flatMap(s => s.treatments || []))].sort();
    for (const t of all) {
      const opt = document.createElement('option');
      opt.value = t;
      opt.textContent = t;
      treatmentFilter.appendChild(opt);
    }
  }

  setFilter.addEventListener('change', () => {
    filters.set = setFilter.value;
    const prev = treatmentFilter.value;
    buildTreatmentFilter(filters.set);
    // Restore treatment selection if still valid in new set
    if ([...treatmentFilter.options].some(o => o.value === prev)) {
      treatmentFilter.value = prev;
      filters.treatment = prev;
    } else {
      filters.treatment = '';
    }
    applyFilters();
  });

  treatmentFilter.addEventListener('change', () => {
    filters.treatment = treatmentFilter.value;
    applyFilters();
  });

  hasImageToggle.addEventListener('click', () => {
    filters.hasImage = !filters.hasImage;
    hasImageToggle.setAttribute('aria-pressed', String(filters.hasImage));
    applyFilters();
  });

  // Power range inputs
  let powerTimer = null;
  function onPowerInput() {
    clearTimeout(powerTimer);
    powerTimer = setTimeout(() => {
      const minVal = powerMinInput?.value.trim();
      const maxVal = powerMaxInput?.value.trim();
      filters.powerMin = minVal !== '' ? Number(minVal) : null;
      filters.powerMax = maxVal !== '' ? Number(maxVal) : null;
      // Clear active state on presets when manual input is used
      document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
      if (filters.powerMin === null && filters.powerMax === null) {
        document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
      }
      applyFilters();
    }, 300);
  }
  powerMinInput?.addEventListener('input', onPowerInput);
  powerMaxInput?.addEventListener('input', onPowerInput);

  // Power preset buttons
  document.querySelectorAll('.power-preset').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const minVal = btn.dataset.min;
      const maxVal = btn.dataset.max;
      filters.powerMin = minVal !== '' ? Number(minVal) : null;
      filters.powerMax = maxVal !== '' ? Number(maxVal) : null;
      if (powerMinInput) powerMinInput.value = minVal;
      if (powerMaxInput) powerMaxInput.value = maxVal;
      applyFilters();
    });
  });

  clearFiltersBtn?.addEventListener('click', resetFilters);

  function resetFilters() {
    filters.query = '';
    filters.element = '';
    filters.set = '';
    filters.treatment = '';
    filters.hasImage = false;
    filters.powerMin = null;
    filters.powerMax = null;
    searchInput.value = '';
    searchClear.hidden = true;
    setFilter.value = '';
    buildTreatmentFilter('');
    hasImageToggle.setAttribute('aria-pressed', 'false');
    if (powerMinInput) powerMinInput.value = '';
    if (powerMaxInput) powerMaxInput.value = '';
    document.querySelectorAll('.power-preset').forEach(b => b.classList.remove('active'));
    document.querySelector('.power-preset[data-min=""]')?.classList.add('active');
    setElementFilter('');
    updateFilterBadge();
  }

  /* ================================================================
     CARD GRID RENDERING
  ================================================================ */

  function applyFilters() {
    filteredCards = computeResults();
    displayedCount = 0;
    cardGrid.innerHTML = '';
    renderNextPage();
    updateResultsCount();
    updateFilterBadge();
  }

  function renderNextPage() {
    const end = Math.min(displayedCount + PAGE_SIZE, filteredCards.length);
    const fragment = document.createDocumentFragment();
    for (let i = displayedCount; i < end; i++) {
      fragment.appendChild(buildCardElement(filteredCards[i]));
    }
    cardGrid.appendChild(fragment);
    displayedCount = end;

    const isEmpty = filteredCards.length === 0;
    cardGrid.hidden = isEmpty;
    emptyState.hidden = !isEmpty;
  }

  function buildCardElement(card) {
    const treatmentClass = getTreatmentClass(card.treatment);
    const el = document.createElement('article');
    el.className = `card-item ${treatmentClass}`;
    el.setAttribute('role', 'listitem');
    el.dataset.element = card.element || 'NONE';
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-label', `${card.name}, ${card.element || 'No element'}, Power ${card.power}`);

    const thumbSrc = API.cardThumbUrl(card);
    const imgHtml = thumbSrc
      ? `<img class="card-img" src="${escHtml(thumbSrc)}"
              alt="${escHtml(card.name)}" loading="lazy" decoding="async">`
      : `<div class="card-img-placeholder" aria-hidden="true">
           <span class="placeholder-brand">BOBA PB</span>
           <span class="placeholder-status">Image Pending</span>
         </div>`;

    // Only show treatment ribbon for non-base treatments
    const ribbonHtml = (treatmentClass !== 'tf-base')
      ? `<div class="card-treatment-ribbon" aria-hidden="true">${escHtml(card.treatment)}</div>`
      : '';

    el.innerHTML = `
      <div class="card-img-wrap">
        ${imgHtml}
        ${ribbonHtml}
      </div>
      <div class="card-info">
        <div class="card-number">${escHtml(card.cardType === 'Sealed Product' ? card.set : card.cardNumber)}</div>
        <div class="card-name">${escHtml(card.name)}</div>
        <div class="card-meta">
          ${card.cardType === 'Sealed Product'
            ? `<span class="element-badge" data-element="SEALED">${escHtml(card.productType ? card.productType.replace(/-/g, ' ').toUpperCase() : 'SEALED')}</span>
               ${card.msrp ? `<span class="card-power">$${card.msrp.toFixed(2)}</span>` : ''}`
            : `<span class="element-badge" data-element="${escHtml(card.element || 'NONE')}">${escHtml(card.element || 'NONE')}</span>
               <span class="card-power" aria-label="Power ${card.power}">P${escHtml(String(card.power))}</span>`
          }
        </div>
      </div>
      <div class="card-element-bar" aria-hidden="true"></div>`;

    el.addEventListener('click', () => openModal(card));
    el.addEventListener('keydown', e => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openModal(card); }
    });
    return el;
  }

  function updateResultsCount() {
    searchCount.textContent = `${filteredCards.length.toLocaleString()} cards`;
  }

  /* ================================================================
     LOAD MORE — IntersectionObserver on sentinel
  ================================================================ */
  // root: main-content because main is the scroll container (body does not scroll)
  const sentinelObserver = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && displayedCount < filteredCards.length) {
      renderNextPage();
    }
  }, { root: document.getElementById('main-content'), rootMargin: '300px' });

  sentinelObserver.observe(loadSentinel);

  /* ================================================================
     SEARCH INPUT
  ================================================================ */
  let searchTimer = null;

  searchInput.addEventListener('input', () => {
    const val = searchInput.value;
    searchClear.hidden = !val;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => {
      filters.query = val;
      applyFilters();
    }, SEARCH_DEBOUNCE_MS);
  });

  searchClear.addEventListener('click', () => {
    searchInput.value = '';
    searchClear.hidden = true;
    filters.query = '';
    searchInput.focus();
    applyFilters();
  });

  /* ================================================================
     CARD DETAIL MODAL
  ================================================================ */

  /* ---- Zoom / Pan ---- */
  let _zoomAbort = null;

  function initZoom() {
    if (_zoomAbort) _zoomAbort.abort();
    _zoomAbort = new AbortController();
    const sig = _zoomAbort.signal;

    const artEl  = modalContent.querySelector('.modal-art');
    const imgEl  = modalContent.querySelector('.modal-card-img') ||
                   modalContent.querySelector('.modal-img-placeholder');
    if (!artEl || !imgEl) return;

    let scale = 1, tx = 0, ty = 0;
    let pinchDist = 0;
    let dragging  = false, dStartX = 0, dStartY = 0, dStartTx = 0, dStartTy = 0;
    let lastTap   = 0;

    function apply(animated) {
      imgEl.style.transition = animated ? 'transform 0.22s ease' : 'none';
      imgEl.style.transform  = `translate(${tx}px,${ty}px) scale(${scale})`;
      artEl.classList.toggle('zoomed',   scale > 1);
      artEl.classList.toggle('can-pan',  scale > 1 && !dragging);
      artEl.classList.toggle('dragging', dragging);
    }

    function clamp() {
      if (scale <= 1) { tx = 0; ty = 0; return; }
      const mx = artEl.clientWidth  * (scale - 1) / 2;
      const my = artEl.clientHeight * (scale - 1) / 2;
      tx = Math.max(-mx, Math.min(mx, tx));
      ty = Math.max(-my, Math.min(my, ty));
    }

    /* Touch — pinch + drag */
    imgEl.addEventListener('touchstart', (e) => {
      if (e.touches.length === 2) {
        e.preventDefault();
        pinchDist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY);
      } else if (e.touches.length === 1 && scale > 1) {
        dragging = true;
        dStartX = e.touches[0].clientX; dStartY = e.touches[0].clientY;
        dStartTx = tx; dStartTy = ty;
        apply(false);
      }
    }, { passive: false, signal: sig });

    imgEl.addEventListener('touchmove', (e) => {
      if (e.touches.length === 2) {
        e.preventDefault();
        const d = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY);
        scale = Math.max(1, Math.min(6, scale * d / pinchDist));
        pinchDist = d;
        clamp(); apply(false);
      } else if (dragging && e.touches.length === 1) {
        e.preventDefault();
        tx = dStartTx + e.touches[0].clientX - dStartX;
        ty = dStartTy + e.touches[0].clientY - dStartY;
        clamp(); apply(false);
      }
    }, { passive: false, signal: sig });

    imgEl.addEventListener('touchend', (e) => {
      dragging = false;
      if (scale < 1.08) { scale = 1; tx = 0; ty = 0; }
      // Double-tap to toggle zoom
      const now = Date.now();
      if (now - lastTap < 280 && e.changedTouches.length === 1) {
        scale = scale > 1 ? 1 : 2.5;
        tx = 0; ty = 0;
      }
      lastTap = now;
      clamp(); apply(true);
    }, { signal: sig });

    /* Wheel zoom (desktop) */
    artEl.addEventListener('wheel', (e) => {
      e.preventDefault();
      scale = Math.max(1, Math.min(6, scale * (e.deltaY < 0 ? 1.12 : 0.88)));
      if (scale === 1) { tx = 0; ty = 0; }
      clamp(); apply(false);
    }, { passive: false, signal: sig });

    /* Mouse drag (desktop) */
    artEl.addEventListener('mousedown', (e) => {
      if (scale <= 1) return;
      dragging = true;
      dStartX = e.clientX; dStartY = e.clientY;
      dStartTx = tx; dStartTy = ty;
      e.preventDefault();
      apply(false);
    }, { signal: sig });

    document.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      tx = dStartTx + e.clientX - dStartX;
      ty = dStartTy + e.clientY - dStartY;
      clamp(); apply(false);
    }, { signal: sig });

    document.addEventListener('mouseup', () => {
      if (!dragging) return;
      dragging = false; apply(false);
    }, { signal: sig });

    /* Double-click to toggle zoom (desktop) */
    let clickTimer = null;
    artEl.addEventListener('click', (e) => {
      // Only count as double-click if not a drag
      if (Math.abs(e.clientX - dStartX) > 4 || Math.abs(e.clientY - dStartY) > 4) return;
      if (clickTimer) {
        clearTimeout(clickTimer);
        clickTimer = null;
        scale = scale > 1 ? 1 : 2.5;
        tx = 0; ty = 0;
        clamp(); apply(true);
      } else {
        clickTimer = setTimeout(() => { clickTimer = null; }, 280);
      }
    }, { signal: sig });
  }

  function cleanupZoom() {
    if (_zoomAbort) { _zoomAbort.abort(); _zoomAbort = null; }
  }

  function openModal(card) {
    modalContent.innerHTML = buildModalContent(card);
    modalOverlay.hidden = false;
    document.body.style.overflow = 'hidden';
    modalCloseBtn.focus();
    initZoom();

    // Wire "Add to Collection" button
    modalContent.querySelector('[data-action="add-to-collection"]')
      ?.addEventListener('click', () => Collection.openAddSheet(card));

    // Load live pricing (skip for sealed products — they have their own links)
    if (card.cardType !== 'Sealed Product') loadPricing(card);
  }

  /* ================================================================
     PRICING
  ================================================================ */
  // Set name → Radish slug (mirrors iOS PricingSection.radishURL setMap)
  const SET_SLUG_MAP = {
    'Alpha':                   ['2024', 'Alpha_Edition'],
    'Alpha Blast':             ['2025', 'Alpha_Blast'],
    'Alpha Update':            ['2025', 'Alpha_Update'],
    'Griffey':                 ['2026', 'Griffey_Edition'],
    'Battle Trainer Kit':      ['2024', 'Battle_Trainer_Kit'],
    'National 24 Starter Set': ['2024', 'National_24_Starter_Set'],
    'World Champions 2024':    ['2024', 'World_Champions'],
    'World Champions 2025':    ['2025', 'World_Champions'],
    'Promo Cards':             ['2025', 'Promo_Cards'],
    'Big League Chew':         ['2025', 'Big_League_Chew'],
  };

  function buildEbayUrl(card) {
    // "bo jackson battle arena {hero} {cardNumber}" — card number encodes treatment
    // (e.g. "RAD-352"), which is more reliable than full treatment names that
    // sellers rarely write out. Mirrors iOS PricingSection and worker query formula.
    const query  = ['bo jackson battle arena', card.hero, card.cardNumber]
      .filter(Boolean).join(' ');
    const params = new URLSearchParams({
      _nkw: query, LH_Sold: '1', LH_Complete: '1',
      _sacat: '0', _from: 'R40', _trksid: 'm570.l1313', _osacat: '0',
    });
    return `https://www.ebay.com/sch/i.html?${params}`;
  }

  function buildRadishUrl(card) {
    if (card.radishUrl) return card.radishUrl;
    // Programmatic fallback — mirrors iOS PricingSection.radishURL
    const prefixRemap = { LOGO: 'Logo', RAD: 'Rad', MIX: 'Mix' };
    let cardNum = card.cardNumber || '';
    for (const [ours, theirs] of Object.entries(prefixRemap)) {
      if (cardNum.startsWith(ours + '-')) {
        cardNum = theirs + cardNum.slice(ours.length);
        break;
      }
    }
    const [year, slug] = SET_SLUG_MAP[card.set] || ['2024', 'Alpha_Edition'];
    const hero = encodeURIComponent(card.hero || '');
    const num  = encodeURIComponent(cardNum);
    return `https://radishpriceguide.com/boba/${year}/${slug}/${hero}/${num}`;
  }

  function loadPricing(card) {
    const section = $('modal-pricing');
    if (!section) return;

    const ebayUrl   = buildEbayUrl(card);
    const radishUrl = buildRadishUrl(card);
    let days = 30;

    async function fetchAndRender() {
      section.innerHTML = `
        <div class="pricing-header">
          <h3 class="section-label">Pricing</h3>
          <div class="pricing-day-picker" role="group" aria-label="Time range">
            <button class="day-btn${days === 7  ? ' active' : ''}" data-days="7">7d</button>
            <button class="day-btn${days === 30 ? ' active' : ''}" data-days="30">30d</button>
            <button class="day-btn${days === 90 ? ' active' : ''}" data-days="90">90d</button>
          </div>
        </div>
        <div class="pricing-body">
          <div class="pricing-loading">
            <div class="loading-spinner-sm" aria-hidden="true"></div>
            <span>Loading…</span>
          </div>
        </div>
        <div class="pricing-links">
          <a href="${escHtml(ebayUrl)}" target="_blank" rel="noopener" class="btn-pricing-ebay">eBay Sales</a>
          <a href="${escHtml(radishUrl)}" target="_blank" rel="noopener" class="btn-pricing-radish">Radish</a>
        </div>
      `;
      section.querySelectorAll('.day-btn').forEach(btn => {
        btn.addEventListener('click', () => { days = parseInt(btn.dataset.days); fetchAndRender(); });
      });

      try {
        const params = new URLSearchParams({
          cardNumber: card.cardNumber,
          hero:    card.hero    || '',
          set:     card.set     || '',
          element: card.element || '',
          days:    String(days),
          ...(card.power    != null ? { power:     String(card.power) }  : {}),
          ...(card.radishUrl       ? { radishUrl:  card.radishUrl }       : {}),
        });
        const res  = await fetch(`${WORKER_URL}?${params}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        renderPricingData(section, data);
      } catch {
        const body = section.querySelector('.pricing-body');
        if (body) body.innerHTML = '<p class="pricing-error">Pricing unavailable</p>';
      }
    }

    fetchAndRender();
  }

  function renderPricingData(section, data) {
    const body = section.querySelector('.pricing-body');
    if (!body) return;
    const { low, average, high, count, priceType, items = [] } = data;
    if (!count) {
      body.innerHTML = '<p class="pricing-none">No eBay listings found.</p>';
      return;
    }
    const isSold  = priceType === 'sold';
    const typeStr = isSold ? 'sold' : 'active listing';
    const fmt     = n => n > 0 ? `$${n.toFixed(2)}` : '—';

    const itemsHtml = items.length === 0 ? '' : `
      <div class="pricing-items">
        <p class="pricing-items-label">${isSold ? 'RECENT SALES' : 'CURRENT LISTINGS'}</p>
        ${items.map(item => {
          const dateStr = isSold && item.date ? relativeDate(item.date) : '';
          return `
            <a href="${escHtml(item.url)}" target="_blank" rel="noopener" class="pricing-item-row">
              <span class="pricing-item-price">${fmt(item.price)}</span>
              <span class="pricing-item-title">${escHtml(item.title)}</span>
              ${dateStr ? `<span class="pricing-item-date">${escHtml(dateStr)}</span>` : '<span class="pricing-item-arrow">↗</span>'}
            </a>`;
        }).join('')}
      </div>`;

    body.innerHTML = `
      <div class="pricing-grid">
        <div class="pricing-stat">
          <span class="pricing-label">LOW</span>
          <span class="pricing-val">${fmt(low)}</span>
        </div>
        <div class="pricing-stat pricing-stat-center">
          <span class="pricing-label">AVG</span>
          <span class="pricing-val pricing-val-avg">${fmt(average)}</span>
        </div>
        <div class="pricing-stat">
          <span class="pricing-label">HIGH</span>
          <span class="pricing-val">${fmt(high)}</span>
        </div>
      </div>
      <p class="pricing-sale-count">${count} ${typeStr}${count !== 1 ? 's' : ''}</p>
      ${itemsHtml}
    `;
  }

  function closeModal() {
    cleanupZoom();
    modalOverlay.hidden = true;
    document.body.style.overflow = '';
  }

  function buildModalContent(card) {
    const imgSrc = card.imageFile ? API.cardFullUrl(card) : null;
    const treatmentClass = getTreatmentClass(card.treatment);
    const setClass = getSetClass(card.set);
    const element = card.element || 'NONE';

    const imgHtml = imgSrc
      ? `<img class="modal-card-img" src="${escHtml(imgSrc)}" alt="${escHtml(card.name)}" loading="eager">`
      : `<div class="modal-img-placeholder" aria-hidden="true">
           <span class="placeholder-brand">BOBA PB</span>
           <span class="placeholder-card-num">${escHtml(card.cardNumber)}</span>
           <span class="placeholder-status">Image Pending</span>
         </div>`;

    // All hero/athlete associations for this card
    const variants = cardsByNumber.get(String(card.cardNumber)) || [card];

    let heroSection = '';
    if (variants.length > 1) {
      const heroCards = variants.map(v => `
        <div class="hero-card">
          <div>
            <div class="hero-card-name">${escHtml(v.hero || '—')}</div>
            ${v.athleteInspiration ? `<div class="hero-card-athlete">${escHtml(v.athleteInspiration)}</div>` : ''}
          </div>
        </div>`).join('');
      heroSection = `
        <div class="hero-associations">
          <h3 class="section-label">Hero Associations</h3>
          <p class="hero-association-note">This card works with ${variants.length} heroes — a BOBA game mechanic.</p>
          <div class="hero-cards">${heroCards}</div>
        </div>`;
    }

    // Build stat cells — grid layout
    const statDefs = [
      { label: 'Set',       val: card.set,       full: false },
      { label: 'Sub-Set',   val: card.subSet,     full: false },
      { label: 'Type',      val: card.cardType,   full: false },
      { label: 'Variation', val: card.variation,  full: false },
    ].filter(s => s.val);

    if (variants.length === 1 && card.athleteInspiration) {
      statDefs.push({ label: 'Athlete', val: card.athleteInspiration, full: true });
    }
    if (card.playCost) {
      statDefs.push({ label: 'Play Cost', val: card.playCost, full: false });
    }

    let statCells = statDefs.map(s =>
      `<div class="stat-cell${s.full ? ' full' : ''}">
         <div class="stat-label-sm">${escHtml(s.label)}</div>
         <div class="stat-val">${escHtml(s.val ?? '—')}</div>
       </div>`
    ).join('');

    if (card.playAbility) {
      statCells += `
        <div class="stat-cell full">
          <div class="stat-label-sm">Ability</div>
          <div class="stat-val ability">${escHtml(card.playAbility)}</div>
        </div>`;
    }

    // Sealed product modal — distinct layout
    if (card.cardType === 'Sealed Product') {
      const highlightsHtml = (card.highlights || []).map(h =>
        `<li class="sealed-highlight">${escHtml(h)}</li>`
      ).join('');
      const ebayUrl = card.ebaySearchQuery
        ? `https://www.ebay.com/sch/i.html?_nkw=${encodeURIComponent(card.ebaySearchQuery)}&LH_Complete=1&LH_Sold=1&_sacat=0`
        : null;
      const productTypeLabel = card.productType
        ? card.productType.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
        : 'Sealed Product';

      return `
        <div class="modal-layout tf-sealed" data-element="SEALED">
          <div class="modal-art">${imgHtml}</div>
          <div class="modal-details">
            <div class="modal-badges">
              <span class="element-badge element-badge-lg" data-element="SEALED">SEALED</span>
              <span class="set-badge">${escHtml(card.set || 'Unknown')}</span>
            </div>
            <div>
              <h2 class="modal-card-name" id="modal-card-name">${escHtml(card.name)}</h2>
              <div class="modal-card-number">${escHtml(productTypeLabel)}</div>
            </div>
            <div class="modal-stats" aria-label="Product stats">
              ${card.packsPerBox ? `<div class="stat-cell"><div class="stat-label-sm">Packs / Box</div><div class="stat-val">${card.packsPerBox}</div></div>` : ''}
              ${card.cardsPerPack ? `<div class="stat-cell"><div class="stat-label-sm">Cards / Pack</div><div class="stat-val">${card.cardsPerPack}</div></div>` : ''}
              ${card.totalCards ? `<div class="stat-cell"><div class="stat-label-sm">Total Cards</div><div class="stat-val">${card.totalCards}</div></div>` : ''}
              ${card.msrp ? `<div class="stat-cell"><div class="stat-label-sm">MSRP</div><div class="stat-val">$${card.msrp.toFixed(2)}</div></div>` : ''}
              ${card.upc ? `<div class="stat-cell full"><div class="stat-label-sm">UPC</div><div class="stat-val">${escHtml(card.upc)}</div></div>` : ''}
            </div>
            ${highlightsHtml ? `
            <div class="sealed-highlights">
              <h3 class="section-label">What's Inside</h3>
              <ul class="sealed-highlights-list">${highlightsHtml}</ul>
            </div>` : ''}
            <div class="sealed-links">
              ${ebayUrl ? `
              <a href="${escHtml(ebayUrl)}" target="_blank" rel="noopener" class="btn-ebay-sealed">
                <svg viewBox="0 0 24 24" fill="currentColor" width="14" height="14" aria-hidden="true">
                  <path d="M7 18c-1.1 0-1.99.9-1.99 2S5.9 22 7 22s2-.9 2-2-.9-2-2-2zm10 0c-1.1 0-1.99.9-1.99 2S15.9 22 17 22s2-.9 2-2-.9-2-2-2zm-9.4-5h9.1c.75 0 1.41-.41 1.75-1.03L21 7H5.21l-.94-2H1v2h2l3.6 8.59L5.25 17c-.16.28-.25.61-.25.95C5 19.1 5.9 20 7 20h12v-2H7.42c-.14 0-.25-.11-.25-.25l.03-.12.9-1.63z"/>
                </svg>
                eBay Sales
              </a>` : ''}
              ${card.radishUrl ? `
              <a href="${escHtml(card.radishUrl)}" target="_blank" rel="noopener" class="btn-radish-sealed">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                     width="14" height="14" aria-hidden="true">
                  <polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/>
                  <polyline points="16 7 22 7 22 13"/>
                </svg>
                Radish Guide
              </a>` : ''}
            </div>
            <div class="modal-collection-action">
              <button class="btn-collection-add" data-action="add-to-collection">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                     width="15" height="15" aria-hidden="true">
                  <path d="M12 5v14M5 12h14"/>
                </svg>
                Add to Collection
              </button>
            </div>
          </div>
        </div>`;
    }

    // Treatment banner (only for non-base)
    const treatmentBanner = (treatmentClass !== 'tf-base' && card.treatment)
      ? `<span class="treatment-banner ${treatmentClass}">${escHtml(card.treatment)}</span>`
      : '';

    return `
      <div class="modal-layout ${treatmentClass}" data-element="${escHtml(element)}">
        <div class="modal-art">${imgHtml}</div>
        <div class="modal-details">
          <div class="modal-badges">
            <span class="element-badge element-badge-lg"
                  data-element="${escHtml(element)}">${escHtml(element)}</span>
            <span class="set-badge ${setClass}">${escHtml(card.set || 'Unknown')}</span>
            ${treatmentBanner}
          </div>
          <div>
            <h2 class="modal-card-name" id="modal-card-name">${escHtml(card.name)}</h2>
            <div class="modal-card-number"># ${escHtml(card.cardNumber)}</div>
          </div>
          <div class="modal-power-display">
            <span class="power-label-txt">POWER</span>
            <span class="power-number">${escHtml(String(card.power))}</span>
          </div>
          <div class="modal-stats" aria-label="Card stats">
            ${statCells}
          </div>
          ${heroSection}
          <div class="modal-collection-action">
            <button class="btn-collection-add" data-action="add-to-collection">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
                   width="15" height="15" aria-hidden="true">
                <path d="M12 5v14M5 12h14"/>
              </svg>
              Add to Collection
            </button>
          </div>
          <div class="pricing-section" id="modal-pricing"></div>
        </div>
      </div>`;
  }

  modalCloseBtn.addEventListener('click', closeModal);
  modalOverlay.addEventListener('click', (e) => { if (e.target === modalOverlay) closeModal(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !modalOverlay.hidden) closeModal();
  });

  // Fired by collection detail when a variation tile is tapped
  document.addEventListener('open-card-by-number', ({ detail: { cardNumber } }) => {
    const cardSet = cardsByNumber.get(String(cardNumber));
    if (cardSet?.length) openModal(cardSet[0]);
  });

  /* ================================================================
     INITIALIZATION
  ================================================================ */
  async function init() {
    // Init auth + collection modules (must be before first render)
    await Auth.init();
    Collection.init();

    const params = new URLSearchParams(window.location.search);
    const urlView = params.get('view');
    showView(viewIds.includes(urlView) ? urlView : 'search', true);

    try {
      [cards, searchIndex, categories] = await Promise.all([
        API.loadCards(),
        API.loadSearchIndex(),
        API.loadCategories(),
      ]);
    } catch (err) {
      loadingState.innerHTML = `<p style="color:var(--boba-orange);font-family:var(--font-mono)">
        Failed to load card catalog. Please refresh the page.</p>`;
      console.error('Catalog load error:', err);
      return;
    }

    prepareData();
    Collection.setCardLookup(num => cardsByNumber.get(String(num))?.[0]);
    Collection.setVariantLookup((hero, excludeNum) =>
      displayCards.filter(c => c.hero === hero && String(c.cardNumber) !== String(excludeNum))
    );

    loadingState.hidden = true;
    buildElementFilters();
    buildSetFilter();
    buildTreatmentFilter('');

    filteredCards = displayCards;
    renderNextPage();
    updateResultsCount();
  }

  init();
})();

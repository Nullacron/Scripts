(() => {
  if (window.__stimSuite) window.__stimSuite.destroy();

  // --- CONFIG & STATE (STARTS DISABLED) ---
  const state = {
    master: false,
    // Speeds (in ms)
    clickDelay: 15,
    minigameDelay: 40,
    marketDelay: 250,
    mailDelay: 400,
    // Feature Toggles (unchecked initially)
    mainBtn: false,
    upgrades: false,
    allowOceanReset: false,
    press: false,
    lootBoxes: false,
    chickenEggs: false,
    duolingo: false,
    powerups: false,
    tradeMarket: false,
    mailInbox: false,
    // Per-Clicker Mute States (false = Unmuted 🔊, true = Muted 🔇)
    mute: {
      mainBtn: true,       // Mute main button by default (saves your ears at 60+ CPS)
      press: true,         // Mute hydraulic press by default
      lootBoxes: false,
      chickenEggs: false,
      duolingo: false,
      bgChaos: false       // Mute videos, podcasts, and ASMR
    },
    // Stock Thresholds
    marketLimits: {
      Tesla: { buy: 380, sell: 540 },
      Bitcoin: { buy: 18000, sell: 26000 }
    }
  };

  const mailTraps = [
    "Thank them for the opportunity",
    "Donate 2,000 stimulation",
    "Send money",
    "Wire transfer"
  ];

  // --- AUDIO INTERCEPTION ENGINE ---
  let activeClickCategory = null;

  const originalAudioPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    const src = (this.src || this.currentSrc || '').toLowerCase();

    // 1. Mute if triggered during an active auto-click with mute enabled
    if (activeClickCategory && state.mute[activeClickCategory]) {
      this.muted = true;
      this.volume = 0;
      try { this.pause(); } catch(e) {}
      return Promise.resolve();
    }

    // 2. Keyword fallback for delayed/async audio playback
    if (state.mute.mainBtn && (src.includes('click') || src.includes('tap') || src.includes('pop') || src.includes('button'))) {
      this.muted = true;
      this.volume = 0;
      try { this.pause(); } catch(e) {}
      return Promise.resolve();
    }

    if (state.mute.press && (src.includes('press') || src.includes('hydraulic') || src.includes('crush') || src.includes('squash'))) {
      this.muted = true;
      this.volume = 0;
      try { this.pause(); } catch(e) {}
      return Promise.resolve();
    }

    if (state.mute.bgChaos && (this.tagName === 'VIDEO' || src.includes('podcast') || src.includes('crime') || src.includes('asmr') || src.includes('lofi'))) {
      this.muted = true;
      this.volume = 0;
      try { this.pause(); } catch(e) {}
      return Promise.resolve();
    }

    return originalAudioPlay.apply(this, arguments);
  };

  // Intercept Web Audio API (if used for synthesis or buffer playback)
  const originalBufferStart = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function() {
    if (activeClickCategory && state.mute[activeClickCategory]) {
      return; // Suppress playback
    }
    return originalBufferStart.apply(this, arguments);
  };

  // Helper to click an element while silencing its audio
  function clickWithMute(el, category) {
    if (!el || el.offsetParent === null) return;
    if (state.mute[category]) activeClickCategory = category;
    try {
      el.click();
    } finally {
      activeClickCategory = null;
    }
  }

  // --- AUTOMATION LOOPS ---
  let clickTimer = null;
  let minigameTimer = null;
  let marketTimer = null;
  let mailTimer = null;

  function startLoops() {
    stopLoops();
    if (!state.master) return;

    // 1. Main Button Loop
    clickTimer = setInterval(() => {
      if (!state.mainBtn) return;
      const btn = document.querySelector('.main-btn');
      if (btn) clickWithMute(btn, 'mainBtn');
      const col = document.querySelector('.collect');
      if (col) clickWithMute(col, 'mainBtn');
    }, Math.max(5, state.clickDelay));

    // 2. Minigame Loop
    minigameTimer = setInterval(() => {
      // Hydraulic Press
      if (state.press) {
        const pCol = document.querySelector('.press-collect');
        if (pCol) clickWithMute(pCol, 'press');
        const pBtn = document.querySelector('.press-btn');
        if (pBtn) clickWithMute(pBtn, 'press');
      }

      // Loot Boxes
      if (state.lootBoxes) {
        document.querySelectorAll('.loot-box-target').forEach(el => clickWithMute(el, 'lootBoxes'));
      }

      // Chicken & Eggs
      if (state.chickenEggs) {
        const feed = document.querySelector('.action-btn');
        if (feed) clickWithMute(feed, 'chickenEggs');
        document.querySelectorAll('.egg').forEach(el => clickWithMute(el, 'chickenEggs'));
      }

      // Duolingo
      if (state.duolingo) {
        const choice = document.querySelector('.question-choice');
        if (choice) clickWithMute(choice, 'duolingo');
      }

      // Powerups
      if (state.powerups) {
        document.querySelectorAll('img.powerup').forEach(p => p.click());
      }

      // Upgrades
      if (state.upgrades) {
        const selector = state.allowOceanReset
          ? '.upgrade:not(.upgrade-disabled) .upgrade-icon'
          : '.upgrade:not(.upgrade-disabled) .upgrade-icon:not([src*="ocean"])';
        document.querySelectorAll(selector).forEach(u => u.click());
      }
    }, Math.max(10, state.minigameDelay));

    // 3. Trade Market Loop
    marketTimer = setInterval(() => {
      if (!state.tradeMarket) return;
      const select = document.querySelector('.stock-select');
      const priceEl = document.querySelector('.last-price');
      const countEl = document.querySelector('.stock-shares');
      const buyBtn = document.querySelector('.stock-buy');
      const sellBtn = document.querySelector('.stock-sell');

      if (!select || !priceEl || !buyBtn || !sellBtn) return;

      const currentStock = select.value || "Tesla";
      const limits = state.marketLimits[currentStock] || { buy: 350, sell: 500 };
      const price = parseFloat(priceEl.innerText.replace(/[^0-9.]/g, ''));
      const shares = countEl ? parseInt(countEl.innerText.replace(/[^0-9]/g, '') || "0", 10) : 0;

      if (isNaN(price)) return;

      if (price <= limits.buy && !buyBtn.disabled) {
        buyBtn.click();
      } else if (price >= limits.sell && shares > 0 && !sellBtn.disabled) {
        sellBtn.click();
      }
    }, Math.max(50, state.marketDelay));

    // 4. Mail Inbox Loop
    mailTimer = setInterval(() => {
      if (!state.mailInbox) return;
      const notif = document.querySelector('.notification');
      if (notif && notif.offsetParent !== null) notif.click();

      document.querySelectorAll('.question-container input').forEach(input => input.click());

      const actionBtn = document.querySelector('.mail-container .action, .modal .action');
      if (actionBtn && actionBtn.offsetParent !== null) {
        const text = (actionBtn.innerText || "").trim().toLowerCase();
        const isTrap = mailTraps.some(trap => text.includes(trap.toLowerCase()));
        if (!isTrap) actionBtn.click();
      }

      const closeBtn = document.querySelector('.mail-container .close, .modal .close');
      if (closeBtn && closeBtn.offsetParent !== null) closeBtn.click();
    }, Math.max(100, state.mailDelay));
  }

  function stopLoops() {
    clearInterval(clickTimer);
    clearInterval(minigameTimer);
    clearInterval(marketTimer);
    clearInterval(mailTimer);
  }

  // --- FLOATING UI PANEL ---
  const panel = document.createElement('div');
  panel.id = 'stim-control-suite';
  panel.style.cssText = `
    position: fixed;
    top: 10px;
    left: 10px;
    z-index: 9999999;
    width: 270px;
    max-height: 92vh;
    overflow-y: auto;
    background: rgba(16, 18, 27, 0.96);
    color: #e2e8f0;
    border: 1px solid #334155;
    border-radius: 12px;
    padding: 12px 14px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 11px;
    box-shadow: 0 10px 25px rgba(0,0,0,0.6);
    user-select: none;
  `;

  panel.innerHTML = `
    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
      <span style="font-weight:bold; font-size:13px; color:#38bdf8;">Stimulation Config</span>
      <button id="cfg-min" style="background:none; border:none; color:#94a3b8; cursor:pointer; font-size:14px; font-weight:bold;">—</button>
    </div>

    <!-- MASTER SWITCH -->
    <button id="cfg-master" style="width:100%; padding:7px; border:none; border-radius:6px; font-weight:bold; cursor:pointer; background:#ef4444; color:#fff; font-size:12px; margin-bottom:10px;">
      MASTER: PAUSED (\`)
    </button>

    <div id="cfg-body">
      <!-- SPEEDS -->
      <div style="font-weight:bold; color:#f59e0b; margin:6px 0 3px;">⚡ Speed Settings</div>
      <label style="display:block; margin-bottom:4px;">
        Click Delay: <b id="lbl-click">${state.clickDelay}ms</b>
        <input type="range" id="rng-click" min="5" max="100" step="5" value="${state.clickDelay}" style="width:100%;">
      </label>
      <label style="display:block; margin-bottom:4px;">
        Minigames Delay: <b id="lbl-mini">${state.minigameDelay}ms</b>
        <input type="range" id="rng-mini" min="15" max="300" step="15" value="${state.minigameDelay}" style="width:100%;">
      </label>
      <label style="display:block; margin-bottom:6px;">
        Market Tick: <b id="lbl-market">${state.marketDelay}ms</b>
        <input type="range" id="rng-market" min="100" max="1000" step="50" value="${state.marketDelay}" style="width:100%;">
      </label>

      <!-- MARKET TARGETS -->
      <div style="font-weight:bold; color:#f59e0b; margin:8px 0 4px;">📈 Market Thresholds</div>
      <div style="display:grid; grid-template-columns: 1fr 1fr; gap:4px; margin-bottom:4px;">
        <label>Tesla Buy ≤<input type="number" id="inp-tsla-buy" value="${state.marketLimits.Tesla.buy}" style="width:90%; background:#0f172a; border:1px solid #334155; color:#fff; padding:2px;"></label>
        <label>Tesla Sell ≥<input type="number" id="inp-tsla-sell" value="${state.marketLimits.Tesla.sell}" style="width:90%; background:#0f172a; border:1px solid #334155; color:#fff; padding:2px;"></label>
      </div>
      <div style="display:grid; grid-template-columns: 1fr 1fr; gap:4px; margin-bottom:6px;">
        <label>BTC Buy ≤<input type="number" id="inp-btc-buy" value="${state.marketLimits.Bitcoin.buy}" style="width:90%; background:#0f172a; border:1px solid #334155; color:#fff; padding:2px;"></label>
        <label>BTC Sell ≥<input type="number" id="inp-btc-sell" value="${state.marketLimits.Bitcoin.sell}" style="width:90%; background:#0f172a; border:1px solid #334155; color:#fff; padding:2px;"></label>
      </div>

      <!-- FEATURE TOGGLES & INDIVIDUAL MUTE BUTTONS -->
      <div style="display:flex; justify-content:space-between; align-items:center; margin:8px 0 4px;">
        <span style="font-weight:bold; color:#f59e0b;">🎛️ Clickers & Audio</span>
        <div>
          <button id="btn-select-all" style="background:#334155; color:#fff; border:none; border-radius:3px; padding:2px 5px; cursor:pointer; font-size:10px;">All</button>
          <button id="btn-select-none" style="background:#334155; color:#fff; border:none; border-radius:3px; padding:2px 5px; cursor:pointer; font-size:10px;">None</button>
        </div>
      </div>

      <div style="display:flex; flex-direction:column; gap:5px;">
        <!-- MAIN BUTTON -->
        <div style="display:flex; justify-content:space-between; align-items:center;">
          <label><input type="checkbox" id="chk-mainBtn"> Main Button</label>
          <button id="mute-mainBtn" class="mute-btn" title="Toggle Main Clicker Sound" style="background:#ef4444; color:#fff; border:none; border-radius:4px; padding:2px 7px; cursor:pointer; font-size:11px;">🔇 Mute</button>
        </div>

        <!-- HYDRAULIC PRESS -->
        <div style="display:flex; justify-content:space-between; align-items:center;">
          <label><input type="checkbox" id="chk-press"> Hydraulic Press</label>
          <button id="mute-press" class="mute-btn" title="Toggle Press Sound" style="background:#ef4444; color:#fff; border:none; border-radius:4px; padding:2px 7px; cursor:pointer; font-size:11px;">🔇 Mute</button>
        </div>

        <!-- LOOT BOXES -->
        <div style="display:flex; justify-content:space-between; align-items:center;">
          <label><input type="checkbox" id="chk-lootBoxes"> Loot Boxes</label>
          <button id="mute-lootBoxes" class="mute-btn" title="Toggle Loot Sound" style="background:#334155; color:#94a3b8; border:none; border-radius:4px; padding:2px 7px; cursor:pointer; font-size:11px;">🔊</button>
        </div>

        <!-- CHICKEN & EGGS -->
        <div style="display:flex; justify-content:space-between; align-items:center;">
          <label><input type="checkbox" id="chk-chickenEggs"> Chicken & Eggs</label>
          <button id="mute-chickenEggs" class="mute-btn" title="Toggle Egg Sound" style="background:#334155; color:#94a3b8; border:none; border-radius:4px; padding:2px 7px; cursor:pointer; font-size:11px;">🔊</button>
        </div>

        <!-- DUOLINGO -->
        <div style="display:flex; justify-content:space-between; align-items:center;">
          <label><input type="checkbox" id="chk-duolingo"> Duolingo Answers</label>
          <button id="mute-duolingo" class="mute-btn" title="Toggle Duolingo Sound" style="background:#334155; color:#94a3b8; border:none; border-radius:4px; padding:2px 7px; cursor:pointer; font-size:11px;">🔊</button>
        </div>

        <hr style="border:0; border-top:1px solid #334155; margin:3px 0;">

        <!-- BACKGROUND MEDIA (PODCASTS, ASMR, VIDEOS) -->
        <div style="display:flex; justify-content:space-between; align-items:center;">
          <span style="color:#cbd5e1;">Mute Background Media</span>
          <button id="mute-bgChaos" class="mute-btn" title="Mute Podcasts/Videos/ASMR" style="background:#334155; color:#94a3b8; border:none; border-radius:4px; padding:2px 7px; cursor:pointer; font-size:11px;">🔊</button>
        </div>

        <label><input type="checkbox" id="chk-upgrades"> Auto Upgrades</label>
        <label style="color:#ef4444;"><input type="checkbox" id="chk-allowOceanReset"> Allow Ocean Ending (Reset)</label>
        <label><input type="checkbox" id="chk-powerups"> Powerups</label>
        <label><input type="checkbox" id="chk-tradeMarket"> Trade Market Bot</label>
        <label><input type="checkbox" id="chk-mailInbox"> Mail Inbox Bot</label>
      </div>
    </div>
  `;
  document.body.appendChild(panel);

  // --- UI EVENT BINDINGS ---
  const masterBtn = panel.querySelector('#cfg-master');
  function toggleMaster() {
    state.master = !state.master;
    masterBtn.style.backgroundColor = state.master ? '#22c55e' : '#ef4444';
    masterBtn.textContent = state.master ? 'MASTER: ACTIVE (`)' : 'MASTER: PAUSED (`)';
    state.master ? startLoops() : stopLoops();
  }
  masterBtn.addEventListener('click', toggleMaster);

  // Mute Button Handler Helper
  function bindMuteButton(id, categoryKey) {
    const btn = panel.querySelector(`#mute-${id}`);
    if (!btn) return;

    function render() {
      const isMuted = state.mute[categoryKey];
      btn.textContent = isMuted ? '🔇 Muted' : '🔊 Snd';
      btn.style.backgroundColor = isMuted ? '#ef4444' : '#334155';
      btn.style.color = isMuted ? '#ffffff' : '#94a3b8';
    }

    btn.addEventListener('click', () => {
      state.mute[categoryKey] = !state.mute[categoryKey];
      render();
    });

    render();
  }

  // Bind all individual mute toggles
  bindMuteButton('mainBtn', 'mainBtn');
  bindMuteButton('press', 'press');
  bindMuteButton('lootBoxes', 'lootBoxes');
  bindMuteButton('chickenEggs', 'chickenEggs');
  bindMuteButton('duolingo', 'duolingo');
  bindMuteButton('bgChaos', 'bgChaos');

  // Sliders
  const rngClick = panel.querySelector('#rng-click');
  const lblClick = panel.querySelector('#lbl-click');
  rngClick.addEventListener('input', e => {
    state.clickDelay = parseInt(e.target.value, 10);
    lblClick.textContent = `${state.clickDelay}ms (~${Math.round(1000 / state.clickDelay)} CPS)`;
    if (state.master) startLoops();
  });

  const rngMini = panel.querySelector('#rng-mini');
  const lblMini = panel.querySelector('#lbl-mini');
  rngMini.addEventListener('input', e => {
    state.minigameDelay = parseInt(e.target.value, 10);
    lblMini.textContent = `${state.minigameDelay}ms`;
    if (state.master) startLoops();
  });

  const rngMarket = panel.querySelector('#rng-market');
  const lblMarket = panel.querySelector('#lbl-market');
  rngMarket.addEventListener('input', e => {
    state.marketDelay = parseInt(e.target.value, 10);
    lblMarket.textContent = `${state.marketDelay}ms`;
    if (state.master) startLoops();
  });

  // Inputs
  panel.querySelector('#inp-tsla-buy').addEventListener('input', e => state.marketLimits.Tesla.buy = parseFloat(e.target.value) || 0);
  panel.querySelector('#inp-tsla-sell').addEventListener('input', e => state.marketLimits.Tesla.sell = parseFloat(e.target.value) || 0);
  panel.querySelector('#inp-btc-buy').addEventListener('input', e => state.marketLimits.Bitcoin.buy = parseFloat(e.target.value) || 0);
  panel.querySelector('#inp-btc-sell').addEventListener('input', e => state.marketLimits.Bitcoin.sell = parseFloat(e.target.value) || 0);

  // Checkboxes
  const featureKeys = [
    'mainBtn', 'upgrades', 'allowOceanReset', 'press',
    'lootBoxes', 'chickenEggs', 'duolingo', 'powerups',
    'tradeMarket', 'mailInbox'
  ];

  featureKeys.forEach(key => {
    const el = panel.querySelector(`#chk-${key}`);
    if (el) {
      el.addEventListener('change', e => {
        state[key] = e.target.checked;
      });
    }
  });

  // Quick Select
  panel.querySelector('#btn-select-all').addEventListener('click', () => {
    featureKeys.forEach(key => {
      if (key === 'allowOceanReset') return;
      state[key] = true;
      const el = panel.querySelector(`#chk-${key}`);
      if (el) el.checked = true;
    });
  });

  panel.querySelector('#btn-select-none').addEventListener('click', () => {
    featureKeys.forEach(key => {
      state[key] = false;
      const el = panel.querySelector(`#chk-${key}`);
      if (el) el.checked = false;
    });
  });

  // Minimize
  let minimized = false;
  const cfgBody = panel.querySelector('#cfg-body');
  const minBtn = panel.querySelector('#cfg-min');
  minBtn.addEventListener('click', () => {
    minimized = !minimized;
    cfgBody.style.display = minimized ? 'none' : 'block';
    minBtn.textContent = minimized ? '+' : '—';
  });

  // Hotkey toggle: `
  function handleKeyDown(e) {
    if (e.code === 'Backquote' && !['INPUT', 'TEXTAREA'].includes(e.target.tagName)) {
      e.preventDefault();
      toggleMaster();
    }
  }
  window.addEventListener('keydown', handleKeyDown);

  // Cleanup helper
  window.__stimSuite = {
    state,
    toggleMaster,
    destroy: () => {
      stopLoops();
      HTMLMediaElement.prototype.play = originalAudioPlay;
      AudioBufferSourceNode.prototype.start = originalBufferStart;
      panel.remove();
      window.removeEventListener('keydown', handleKeyDown);
    }
  };

  console.log("%c Stimulation Suite with Audio Control Loaded!", "color: #38bdf8; font-weight: bold; font-size: 14px;");
})();

(() => {
  // Clean up any old instances or duplicate panels
  if (window.__stimSuite) window.__stimSuite.destroy();
  document.querySelectorAll('#stim-control-suite, #stim-panel, #stim-toggle-btn').forEach(el => el.remove());

  // --- COMPLETE STATE (ALL START DISABLED AT EXECUTION) ---
  const state = {
    master: false,
    activeTab: 'auto',

    // Delays in milliseconds
    clickDelay: 15,
    minigameDelay: 40,
    marketDelay: 250,
    mailDelay: 400,

    // Automation switches (all disabled initially)
    features: {
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
    },

    // Granular Mute Controls (all disabled initially)
    mute: {
      lofi: false,          // Lo-Fi hip hop track
      asmr: false,          // Soap, slime, kinetic sand, whispering
      podcast: false,       // True crime podcast
      videos: false,        // Subway Surfers, Mukbang (audio only; video keeps playing)
      ocean: false,         // Ambient ocean waves
      mainBtn: false,       // Main button rapid pops/clicks
      press: false,         // Hydraulic press crunch
      lootBoxes: false,     // Lootbox chime
      chickenEggs: false,   // Egg crack & chicken clucks
      duolingo: false,      // Duolingo dings
      upgrades: false,      // Upgrade purchase & level-up chimes
      tradeMarket: false,   // Stock market trade chimes
      mailInbox: false,     // Email alerts
      allOther: false       // Any other miscellaneous SFX
    },

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

  // --- AUDIO INTERCEPTION & CLASSIFICATION ---
  let activeClickCategory = null;

  function categorizeAudio(mediaEl, clickContext) {
    if (clickContext) return clickContext;
    const src = (mediaEl.src || mediaEl.currentSrc || '').toLowerCase();
    const tag = mediaEl.tagName.toLowerCase();

    if (src.includes('lofi') || src.includes('lo-fi') || src.includes('chill') || src.includes('music')) return 'lofi';
    if (src.includes('asmr') || src.includes('soap') || src.includes('sand') || src.includes('slime') || src.includes('whisper')) return 'asmr';
    if (src.includes('podcast') || src.includes('crime') || src.includes('talk') || src.includes('episode')) return 'podcast';
    if (tag === 'video' || src.includes('subway') || src.includes('mukbang') || src.includes('.mp4') || src.includes('.webm')) return 'videos';
    if (src.includes('ocean') || src.includes('wave') || src.includes('water')) return 'ocean';

    if (src.includes('click') || src.includes('button') || src.includes('pop') || src.includes('tap')) return 'mainBtn';
    if (src.includes('press') || src.includes('hydraulic') || src.includes('crush') || src.includes('squash')) return 'press';
    if (src.includes('loot') || src.includes('box') || src.includes('crate')) return 'lootBoxes';
    if (src.includes('egg') || src.includes('chicken') || src.includes('peck') || src.includes('cluck')) return 'chickenEggs';
    if (src.includes('duo') || src.includes('ding') || src.includes('correct')) return 'duolingo';
    if (src.includes('upgrade') || src.includes('level') || src.includes('collect') || src.includes('fanfare')) return 'upgrades';
    if (src.includes('trade') || src.includes('coin') || src.includes('cash') || src.includes('money')) return 'tradeMarket';
    if (src.includes('mail') || src.includes('notif') || src.includes('bell') || src.includes('inbox')) return 'mailInbox';

    return 'allOther';
  }

  const originalAudioPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function() {
    const category = categorizeAudio(this, activeClickCategory);
    if (state.mute[category]) {
      this.muted = true;
      this.volume = 0;
    }
    return originalAudioPlay.apply(this, arguments);
  };

  const originalBufferStart = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function() {
    if (activeClickCategory && state.mute[activeClickCategory]) return;
    return originalBufferStart.apply(this, arguments);
  };

  // Continuous background audio muter (preserves visual video playback)
  const audioEnforcerTimer = setInterval(() => {
    document.querySelectorAll('audio, video').forEach(media => {
      const category = categorizeAudio(media, null);
      if (state.mute[category]) {
        if (!media.muted || media.volume !== 0) {
          media.muted = true;
          media.volume = 0;
        }
      }
    });
  }, 150);

  function clickWithCategory(el, category) {
    if (!el || el.offsetParent === null) return;
    activeClickCategory = category;
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
      if (!state.features.mainBtn) return;
      const btn = document.querySelector('.main-btn');
      if (btn) clickWithCategory(btn, 'mainBtn');
      const col = document.querySelector('.collect');
      if (col) clickWithCategory(col, 'upgrades');
    }, Math.max(5, state.clickDelay));

    // 2. Minigame & Upgrade Loop
    minigameTimer = setInterval(() => {
      if (state.features.press) {
        const pCol = document.querySelector('.press-collect');
        if (pCol) clickWithCategory(pCol, 'press');
        const pBtn = document.querySelector('.press-btn');
        if (pBtn) clickWithCategory(pBtn, 'press');
      }

      if (state.features.lootBoxes) {
        document.querySelectorAll('.loot-box-target').forEach(el => clickWithCategory(el, 'lootBoxes'));
      }

      if (state.features.chickenEggs) {
        const feed = document.querySelector('.action-btn');
        if (feed) clickWithCategory(feed, 'chickenEggs');
        document.querySelectorAll('.egg').forEach(el => clickWithCategory(el, 'chickenEggs'));
      }

      if (state.features.duolingo) {
        const choice = document.querySelector('.question-choice');
        if (choice) clickWithCategory(choice, 'duolingo');
      }

      if (state.features.powerups) {
        document.querySelectorAll('img.powerup').forEach(p => p.click());
      }

      if (state.features.upgrades) {
        const selector = state.features.allowOceanReset
          ? '.upgrade:not(.upgrade-disabled) .upgrade-icon'
          : '.upgrade:not(.upgrade-disabled) .upgrade-icon:not([src*="ocean"])';
        document.querySelectorAll(selector).forEach(u => clickWithCategory(u, 'upgrades'));
      }
    }, Math.max(10, state.minigameDelay));

    // 3. Trade Market Loop
    marketTimer = setInterval(() => {
      if (!state.features.tradeMarket) return;
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
        clickWithCategory(buyBtn, 'tradeMarket');
      } else if (price >= limits.sell && shares > 0 && !sellBtn.disabled) {
        clickWithCategory(sellBtn, 'tradeMarket');
      }
    }, Math.max(50, state.marketDelay));

    // 4. Mail Inbox Loop
    mailTimer = setInterval(() => {
      if (!state.features.mailInbox) return;
      const notif = document.querySelector('.notification');
      if (notif && notif.offsetParent !== null) clickWithCategory(notif, 'mailInbox');

      document.querySelectorAll('.question-container input').forEach(input => input.click());

      const actionBtn = document.querySelector('.mail-container .action, .modal .action');
      if (actionBtn && actionBtn.offsetParent !== null) {
        const text = (actionBtn.innerText || "").trim().toLowerCase();
        const isTrap = mailTraps.some(trap => text.includes(trap.toLowerCase()));
        if (!isTrap) clickWithCategory(actionBtn, 'mailInbox');
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

  // --- FLOATING MOVABLE PANEL GUI ---
  const panel = document.createElement('div');
  panel.id = 'stim-control-suite';
  panel.style.cssText = `
    position: fixed !important;
    top: 60px !important;
    right: 20px !important;
    z-index: 2147483647 !important;
    width: 280px !important;
    max-height: 85vh !important;
    overflow-y: auto !important;
    background: #0f172a !important;
    color: #f8fafc !important;
    border: 2px solid #38bdf8 !important;
    border-radius: 12px !important;
    padding: 12px 14px !important;
    font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
    font-size: 11px !important;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.8), 0 0 15px rgba(56, 189, 248, 0.4) !important;
    user-select: none !important;
    box-sizing: border-box !important;
    display: block !important;
  `;

  panel.innerHTML = `
    <!-- DRAGGABLE TITLE BAR -->
    <div id="cfg-drag-handle" style="cursor: move; display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; padding: 4px 6px; background: #1e293b; border-radius: 6px; border: 1px dashed #475569;">
      <span style="font-weight: 800; font-size: 12px; color: #38bdf8;">✥ Drag to Move</span>
      <button id="cfg-min" style="background: none; border: none; color: #94a3b8; cursor: pointer; font-size: 14px; font-weight: bold;">—</button>
    </div>

    <!-- MASTER SWITCH (INITIALIZED OFF) -->
    <button id="cfg-master" style="width: 100%; padding: 8px; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; background: #ef4444; color: #ffffff; font-size: 12px; margin-bottom: 8px;">
      MASTER: PAUSED (\`)
    </button>

    <!-- TABS -->
    <div style="display: flex; gap: 6px; margin-bottom: 10px; border-bottom: 1px solid #334155; padding-bottom: 6px;">
      <button id="tab-btn-auto" style="flex: 1; padding: 6px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; background: #38bdf8; color: #0f172a; font-size: 11px;">
        ⚡ Automation
      </button>
      <button id="tab-btn-mute" style="flex: 1; padding: 6px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; background: #1e293b; color: #94a3b8; font-size: 11px;">
        🔇 Mute Hub
      </button>
    </div>

    <!-- CONTENT BODY -->
    <div id="cfg-body">
      <!-- TAB 1: AUTOMATION -->
      <div id="view-auto">
        <div style="font-weight: bold; color: #f59e0b; margin: 4px 0 3px;">⚡ Speed Settings</div>
        <label style="display: block; margin-bottom: 4px;">
          Click Delay: <b id="lbl-click">${state.clickDelay}ms</b>
          <input type="range" id="rng-click" min="5" max="100" step="5" value="${state.clickDelay}" style="width: 100%;">
        </label>
        <label style="display: block; margin-bottom: 4px;">
          Minigames Delay: <b id="lbl-mini">${state.minigameDelay}ms</b>
          <input type="range" id="rng-mini" min="15" max="300" step="15" value="${state.minigameDelay}" style="width: 100%;">
        </label>
        <label style="display: block; margin-bottom: 6px;">
          Market Tick: <b id="lbl-market">${state.marketDelay}ms</b>
          <input type="range" id="rng-market" min="100" max="1000" step="50" value="${state.marketDelay}" style="width: 100%;">
        </label>

        <div style="font-weight: bold; color: #f59e0b; margin: 8px 0 4px;">📈 Market Thresholds</div>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 4px; margin-bottom: 4px;">
          <label>TSLA Buy ≤<input type="number" id="inp-tsla-buy" value="${state.marketLimits.Tesla.buy}" style="width: 85%; background: #020617; border: 1px solid #334155; color: #fff; padding: 2px;"></label>
          <label>TSLA Sell ≥<input type="number" id="inp-tsla-sell" value="${state.marketLimits.Tesla.sell}" style="width: 85%; background: #020617; border: 1px solid #334155; color: #fff; padding: 2px;"></label>
        </div>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 4px; margin-bottom: 6px;">
          <label>BTC Buy ≤<input type="number" id="inp-btc-buy" value="${state.marketLimits.Bitcoin.buy}" style="width: 85%; background: #020617; border: 1px solid #334155; color: #fff; padding: 2px;"></label>
          <label>BTC Sell ≥<input type="number" id="inp-btc-sell" value="${state.marketLimits.Bitcoin.sell}" style="width: 85%; background: #020617; border: 1px solid #334155; color: #fff; padding: 2px;"></label>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center; margin: 8px 0 4px;">
          <span style="font-weight: bold; color: #f59e0b;">🎛️ Clicker Toggles</span>
          <div>
            <button id="btn-feat-all" style="background: #334155; color: #fff; border: none; border-radius: 3px; padding: 2px 5px; cursor: pointer; font-size: 10px;">All</button>
            <button id="btn-feat-none" style="background: #334155; color: #fff; border: none; border-radius: 3px; padding: 2px 5px; cursor: pointer; font-size: 10px;">None</button>
          </div>
        </div>

        <div style="display: flex; flex-direction: column; gap: 4px;">
          <label><input type="checkbox" id="chk-mainBtn"> Main Button</label>
          <label><input type="checkbox" id="chk-upgrades"> Auto Upgrades</label>
          <label style="color: #ef4444;"><input type="checkbox" id="chk-allowOceanReset"> Allow Ocean Ending (Reset)</label>
          <label><input type="checkbox" id="chk-press"> Hydraulic Press</label>
          <label><input type="checkbox" id="chk-lootBoxes"> Loot Boxes</label>
          <label><input type="checkbox" id="chk-chickenEggs"> Chicken & Eggs</label>
          <label><input type="checkbox" id="chk-duolingo"> Duolingo Answers</label>
          <label><input type="checkbox" id="chk-powerups"> Powerups</label>
          <label><input type="checkbox" id="chk-tradeMarket"> Trade Market Bot</label>
          <label><input type="checkbox" id="chk-mailInbox"> Mail Inbox Bot</label>
        </div>
      </div>

      <!-- TAB 2: MUTE HUB -->
      <div id="view-mute" style="display: none;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
          <span style="font-weight: bold; color: #ef4444;">🔇 Audio Silencers</span>
          <div>
            <button id="btn-mute-all" style="background: #ef4444; color: #fff; border: none; border-radius: 3px; padding: 2px 6px; cursor: pointer; font-size: 10px; font-weight: bold;">Mute All</button>
            <button id="btn-mute-none" style="background: #334155; color: #fff; border: none; border-radius: 3px; padding: 2px 6px; cursor: pointer; font-size: 10px;">Unmute All</button>
          </div>
        </div>

        <div style="font-weight: bold; color: #38bdf8; margin: 6px 0 3px;">🎧 Background Media</div>
        <div style="display: flex; flex-direction: column; gap: 5px; margin-bottom: 8px;">
          <label><input type="checkbox" id="mute-lofi"> 🎵 Lo-Fi Beats</label>
          <label><input type="checkbox" id="mute-asmr"> 🧼 ASMR (Soap, Sand, Slime)</label>
          <label><input type="checkbox" id="mute-podcast"> 🎙️ True Crime Podcast</label>
          <label><input type="checkbox" id="mute-videos"> 📱 Videos (Subway Surfers, Mukbang)</label>
          <label><input type="checkbox" id="mute-ocean"> 🌊 Ambient Ocean Waves</label>
        </div>

        <div style="font-weight: bold; color: #38bdf8; margin: 6px 0 3px;">🔊 Clickers & Game SFX</div>
        <div style="display: flex; flex-direction: column; gap: 5px;">
          <label><input type="checkbox" id="mute-mainBtn"> 🖱️ Main Button Rapid Clicks</label>
          <label><input type="checkbox" id="mute-press"> 🏗️ Hydraulic Press Squash</label>
          <label><input type="checkbox" id="mute-lootBoxes"> 📦 Loot Boxes Open Chimes</label>
          <label><input type="checkbox" id="mute-chickenEggs"> 🥚 Eggs Crack & Chicken Feed</label>
          <label><input type="checkbox" id="mute-duolingo"> 🦉 Duolingo Dings & Bells</label>
          <label><input type="checkbox" id="mute-upgrades"> 🛒 Upgrade & Level Up Chimes</label>
          <label><input type="checkbox" id="mute-tradeMarket"> 📈 Stock Buy/Sell Cash Sound</label>
          <label><input type="checkbox" id="mute-mailInbox"> ✉️ Email Notification Alert</label>
          <label><input type="checkbox" id="mute-allOther"> 🔔 All Other Uncategorized SFX</label>
        </div>
      </div>
    </div>
  `;

  // Attach directly to documentElement to avoid any Vue virtual-DOM clearing
  (document.body || document.documentElement).appendChild(panel);

  // --- DRAGGING LOGIC ---
  const handle = panel.querySelector('#cfg-drag-handle');
  let isDragging = false;
  let startX = 0, startY = 0;
  let initialLeft = 0, initialTop = 0;

  handle.addEventListener('mousedown', (e) => {
    isDragging = true;
    startX = e.clientX;
    startY = e.clientY;
    const rect = panel.getBoundingClientRect();
    initialLeft = rect.left;
    initialTop = rect.top;
    panel.style.right = 'auto'; // release fixed right anchor
    panel.style.left = `${initialLeft}px`;
    panel.style.top = `${initialTop}px`;
    handle.style.background = '#0284c7';
    document.body.style.userSelect = 'none';
  });

  window.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    const dx = e.clientX - startX;
    const dy = e.clientY - startY;
    const newLeft = Math.max(10, Math.min(window.innerWidth - panel.offsetWidth - 10, initialLeft + dx));
    const newTop = Math.max(10, Math.min(window.innerHeight - panel.offsetHeight - 10, initialTop + dy));
    panel.style.left = `${newLeft}px`;
    panel.style.top = `${newTop}px`;
  });

  window.addEventListener('mouseup', () => {
    if (isDragging) {
      isDragging = false;
      handle.style.background = '#1e293b';
      document.body.style.userSelect = '';
    }
  });

  // --- TAB TOGGLING ---
  const tabBtnAuto = panel.querySelector('#tab-btn-auto');
  const tabBtnMute = panel.querySelector('#tab-btn-mute');
  const viewAuto = panel.querySelector('#view-auto');
  const viewMute = panel.querySelector('#view-mute');

  function setTab(tab) {
    state.activeTab = tab;
    if (tab === 'auto') {
      viewAuto.style.display = 'block';
      viewMute.style.display = 'none';
      tabBtnAuto.style.background = '#38bdf8';
      tabBtnAuto.style.color = '#0f172a';
      tabBtnMute.style.background = '#1e293b';
      tabBtnMute.style.color = '#94a3b8';
    } else {
      viewAuto.style.display = 'none';
      viewMute.style.display = 'block';
      tabBtnMute.style.background = '#38bdf8';
      tabBtnMute.style.color = '#0f172a';
      tabBtnAuto.style.background = '#1e293b';
      tabBtnAuto.style.color = '#94a3b8';
    }
  }

  tabBtnAuto.addEventListener('click', () => setTab('auto'));
  tabBtnMute.addEventListener('click', () => setTab('mute'));

  // --- MASTER TOGGLE ---
  const masterBtn = panel.querySelector('#cfg-master');
  function toggleMaster() {
    state.master = !state.master;
    masterBtn.style.backgroundColor = state.master ? '#22c55e' : '#ef4444';
    masterBtn.textContent = state.master ? 'MASTER: ACTIVE (`)' : 'MASTER: PAUSED (`)';
    state.master ? startLoops() : stopLoops();
  }
  masterBtn.addEventListener('click', toggleMaster);

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

  panel.querySelector('#inp-tsla-buy').addEventListener('input', e => state.marketLimits.Tesla.buy = parseFloat(e.target.value) || 0);
  panel.querySelector('#inp-tsla-sell').addEventListener('input', e => state.marketLimits.Tesla.sell = parseFloat(e.target.value) || 0);
  panel.querySelector('#inp-btc-buy').addEventListener('input', e => state.marketLimits.Bitcoin.buy = parseFloat(e.target.value) || 0);
  panel.querySelector('#inp-btc-sell').addEventListener('input', e => state.marketLimits.Bitcoin.sell = parseFloat(e.target.value) || 0);

  // Automation Checkboxes
  const featureKeys = Object.keys(state.features);
  featureKeys.forEach(key => {
    const el = panel.querySelector(`#chk-${key}`);
    if (el) {
      el.addEventListener('change', e => state.features[key] = e.target.checked);
    }
  });

  panel.querySelector('#btn-feat-all').addEventListener('click', () => {
    featureKeys.forEach(key => {
      if (key === 'allowOceanReset') return;
      state.features[key] = true;
      const el = panel.querySelector(`#chk-${key}`);
      if (el) el.checked = true;
    });
  });

  panel.querySelector('#btn-feat-none').addEventListener('click', () => {
    featureKeys.forEach(key => {
      state.features[key] = false;
      const el = panel.querySelector(`#chk-${key}`);
      if (el) el.checked = false;
    });
  });

  // Mute Checkboxes
  const muteKeys = Object.keys(state.mute);
  muteKeys.forEach(key => {
    const el = panel.querySelector(`#mute-${key}`);
    if (el) {
      el.addEventListener('change', e => state.mute[key] = e.target.checked);
    }
  });

  panel.querySelector('#btn-mute-all').addEventListener('click', () => {
    muteKeys.forEach(key => {
      state.mute[key] = true;
      const el = panel.querySelector(`#mute-${key}`);
      if (el) el.checked = true;
    });
  });

  panel.querySelector('#btn-mute-none').addEventListener('click', () => {
    muteKeys.forEach(key => {
      state.mute[key] = false;
      const el = panel.querySelector(`#mute-${key}`);
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

  // Center on screen helper
  function recenterPanel() {
    panel.style.right = 'auto';
    panel.style.left = `${Math.max(10, (window.innerWidth - panel.offsetWidth) / 2)}px`;
    panel.style.top = `${Math.max(10, (window.innerHeight - panel.offsetHeight) / 2)}px`;
  }

  // Hotkeys: ` toggles Master; Shift + ` recenters panel
  function handleKeyDown(e) {
    if (e.code === 'Backquote' && !['INPUT', 'TEXTAREA'].includes(e.target.tagName)) {
      e.preventDefault();
      if (e.shiftKey) {
        recenterPanel();
      } else {
        toggleMaster();
      }
    }
  }
  window.addEventListener('keydown', handleKeyDown);

  // Global Export
  window.__stimSuite = {
    state,
    setTab,
    toggleMaster,
    recenter: recenterPanel,
    destroy: () => {
      stopLoops();
      clearInterval(audioEnforcerTimer);
      HTMLMediaElement.prototype.play = originalAudioPlay;
      AudioBufferSourceNode.prototype.start = originalBufferStart;
      panel.remove();
      window.removeEventListener('keydown', handleKeyDown);
    }
  };

  console.log("%c [Stimulation Suite] Injected successfully at top-right!", "color: #38bdf8; font-weight: bold; font-size: 14px;");
  console.log("Tip: Click & drag the top header bar to move the panel anywhere. Press Shift + ` to re-center it.");
})();

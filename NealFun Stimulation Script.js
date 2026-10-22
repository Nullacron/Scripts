(() => {
  if (window.__stimSuite) window.__stimSuite.destroy();

  // --- INITIAL STATE: EVERYTHING DISABLED ---
  const state = {
    master: false,          // Master loop starts PAUSED
    // Speeds (in ms)
    clickDelay: 15,
    minigameDelay: 40,
    marketDelay: 250,
    mailDelay: 400,
    // Feature Toggles (all disabled initially)
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
    // Market Price Targets
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

  // --- TIMERS ---
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
      if (btn) btn.click();
      const col = document.querySelector('.collect');
      if (col) col.click();
    }, Math.max(5, state.clickDelay));

    // 2. Minigame & Upgrade Loop
    minigameTimer = setInterval(() => {
      if (state.press) {
        const pCol = document.querySelector('.press-collect');
        if (pCol) pCol.click();
        const pBtn = document.querySelector('.press-btn');
        if (pBtn) pBtn.click();
      }

      if (state.lootBoxes) {
        document.querySelectorAll('.loot-box-target').forEach(el => el.click());
      }

      if (state.chickenEggs) {
        const feed = document.querySelector('.action-btn');
        if (feed && feed.offsetParent !== null) feed.click();
        document.querySelectorAll('.egg').forEach(el => el.click());
      }

      if (state.duolingo) {
        const choice = document.querySelector('.question-choice');
        if (choice && choice.offsetParent !== null) choice.click();
      }

      if (state.powerups) {
        document.querySelectorAll('img.powerup').forEach(p => p.click());
      }

      if (state.upgrades) {
        const selector = state.allowOceanReset
          ? '.upgrade:not(.upgrade-disabled) .upgrade-icon'
          : '.upgrade:not(.upgrade-disabled) .upgrade-icon:not([src*="ocean"])';
        document.querySelectorAll(selector).forEach(u => u.click());
      }
    }, Math.max(10, state.minigameDelay));

    // 3. Stock Trader Loop
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

    // 4. Mail Loop
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

  // --- FLOATING CONTROL PANEL GUI ---
  const panel = document.createElement('div');
  panel.id = 'stim-control-suite';
  panel.style.cssText = `
    position: fixed;
    top: 10px;
    left: 10px;
    z-index: 9999999;
    width: 250px;
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

    <!-- MASTER SWITCH (INITIALIZED AS PAUSED) -->
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

      <!-- FEATURE TOGGLES -->
      <div style="display:flex; justify-content:space-between; align-items:center; margin:8px 0 4px;">
        <span style="font-weight:bold; color:#f59e0b;">🎛️ Feature Toggles</span>
        <div>
          <button id="btn-select-all" style="background:#334155; color:#fff; border:none; border-radius:3px; padding:2px 5px; cursor:pointer; font-size:10px;">All</button>
          <button id="btn-select-none" style="background:#334155; color:#fff; border:none; border-radius:3px; padding:2px 5px; cursor:pointer; font-size:10px;">None</button>
        </div>
      </div>

      <div style="display:flex; flex-direction:column; gap:4px;">
        <label><input type="checkbox" id="chk-mainBtn"> Main Button</label>
        <label><input type="checkbox" id="chk-upgrades"> Auto Upgrades</label>
        <label style="color:#ef4444;"><input type="checkbox" id="chk-allowOceanReset"> Allow Ocean Ending (Reset)</label>
        <label><input type="checkbox" id="chk-press"> Hydraulic Press</label>
        <label><input type="checkbox" id="chk-lootBoxes"> Loot Boxes</label>
        <label><input type="checkbox" id="chk-chickenEggs"> Chicken & Eggs</label>
        <label><input type="checkbox" id="chk-duolingo"> Duolingo Answers</label>
        <label><input type="checkbox" id="chk-powerups"> Powerups</label>
        <label><input type="checkbox" id="chk-tradeMarket"> Trade Market Bot</label>
        <label><input type="checkbox" id="chk-mailInbox"> Mail Inbox Bot</label>
      </div>
    </div>
  `;
  document.body.appendChild(panel);

  // --- BIND UI EVENTS ---
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

  // Quick Select: All / None
  panel.querySelector('#btn-select-all').addEventListener('click', () => {
    featureKeys.forEach(key => {
      if (key === 'allowOceanReset') return; // keep dangerous reset off by default
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
      panel.remove();
      window.removeEventListener('keydown', handleKeyDown);
    }
  };

  console.log("%c Stimulation Suite Loaded (IDLE / PAUSED)", "color: #94a3b8; font-weight: bold; font-size: 14px;");
  console.log("Check the features you want in the top-left UI and press ` (backquote) or click the red Master button to activate.");
})();

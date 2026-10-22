(() => {
  // Clean up any previous instances
  if (window.__stimSuite) window.__stimSuite.destroy();
  document.querySelectorAll('#stim-control-suite, #stim-panel, #stim-toggle-btn').forEach(el => el.remove());

  // --- STATE (ALL DISABLED AT SCRIPT EXECUTION) ---
  const state = {
    master: false,
    activeTab: 'auto',

    // Global Speeds (ms)
    clickDelay: 15,
    minigameDelay: 40,
    marketDelay: 250,
    mailDelay: 400,

    clicker: {
      burstMultiplier: 1,
      useJitter: false,
      autoCollectLevel: false
    },
    upgrades: {
      reserveStim: 0,
      allowOceanReset: false
    },

    features: {
      mainBtn: false,
      upgrades: false,
      pressBtn: false,
      pressCollect: false,
      lootBoxes: false,
      chickenFeed: false,
      kinderEggs: false,
      duolingo: false,
      powerups: false,
      tradeMarket: false,
      mailInbox: false,
    },

    market: {
      cycleAll: true,
      smartRange: false,
      smartBuyPct: 25,
      smartSellPct: 25,
      batchBuyCount: 1,
      sellAllShares: true,
      selectedStockUI: 'Tesla',
      stocks: {
        'Tesla': { enabled: true, buy: 380, sell: 540, minSeen: Infinity, maxSeen: -Infinity, lastSeen: 0 },
        'Bitcoin': { enabled: true, buy: 18000, sell: 26000, minSeen: Infinity, maxSeen: -Infinity, lastSeen: 0 }
      }
    },

    mail: {
      autoSurvey: false,
      autoActions: false,
      trapsBlacklist: "Thank them, Donate, Send money, Wire, Transfer"
    },

    // --- EXPANDED SOUND ENGINE SILENCERS ---
    mute: {
      // 🗣️ Voices & Streamers
      narrator: false,      // Voice Narrator (Jeff Steitzer / Halo Announcer)
      streamer: false,      // Reaction Streamer (Ludwig)
      fitness: false,       // Fitness Instructor workout shoutouts
      podcast: false,       // 40-minute True Crime Podcast
      // 🔔 Popups & Milestones
      achievements: false,  // Achievements popup fanfare/chime
      levelup: false,       // Level Up popup sound
      duolingo: false,      // Duolingo popup notification & ding
      breakingNews: false,  // Breaking news intro broadcast jingle
      mailInbox: false,     // Email arrival ping / notification bell
      // ✨ Distractions & Ambient Audio
      dvd: false,           // DVD logo corner bounce / pop sound
      lofi: false,          // Lo-Fi chill beats music
      asmr: false,          // ASMR (Soap cutting, slime, kinetic sand, whispering)
      weather: false,       // Rain & Thunder atmospheric sounds
      popcorn: false,       // Popcorn popping sounds
      meditation: false,    // Meditation bells / Tibetan gong
      tamagotchi: false,    // Tamagotchi digital beeps
      videos: false,        // Subway Surfers & Mukbang (audio muted; video keeps running)
      ocean: false,         // Ambient ocean waves & end screen
      // 🖱️ Clickers & Actions
      mainBtn: false,       // Main button rapid clicks/pops
      press: false,         // Hydraulic press crunch/squash
      lootBoxes: false,     // Lootbox open chimes
      chickenEggs: false,   // Paul feeding & egg crack noises
      tradeMarket: false,   // Stock market trade chimes
      allOther: false       // Any other uncategorized sounds
    },

    panelOpacity: 96
  };

  function getStimulationBalance() {
    const el = document.querySelector('.amount, .counter, .points, .sps-counter');
    if (!el) return Infinity;
    const val = parseFloat(el.innerText.replace(/[^0-9.]/g, ''));
    return isNaN(val) ? Infinity : val;
  }

  // --- AUDIO CLASSIFICATION & INTERCEPTION ENGINE ---
  let activeClickCategory = null;

  function categorizeAudio(mediaEl, clickContext) {
    if (clickContext) return clickContext;
    const src = (mediaEl.src || mediaEl.currentSrc || '').toLowerCase();
    const tag = mediaEl.tagName.toLowerCase();

    // 1. Voices & Narrators
    if (src.includes('narrator') || src.includes('voice') || src.includes('steitzer') || src.includes('announcer') || src.includes('halo')) return 'narrator';
    if (src.includes('streamer') || src.includes('ludwig') || src.includes('react')) return 'streamer';
    if (src.includes('fitness') || src.includes('trainer') || src.includes('workout') || src.includes('coach')) return 'fitness';
    if (src.includes('podcast') || src.includes('crime') || src.includes('true-crime') || src.includes('episode')) return 'podcast';

    // 2. Popups & Milestones
    if (src.includes('achieve') || src.includes('badge') || src.includes('trophy') || src.includes('fanfare')) return 'achievements';
    if (src.includes('level') || src.includes('lvl') || src.includes('levelup') || src.includes('rank')) return 'levelup';
    if (src.includes('duo') || src.includes('lingo') || src.includes('owl') || src.includes('streak') || src.includes('correct') || src.includes('wrong')) return 'duolingo';
    if (src.includes('news') || src.includes('breaking') || src.includes('broadcast') || src.includes('jingle')) return 'breakingNews';
    if (src.includes('mail') || src.includes('notif') || src.includes('bell') || src.includes('inbox') || src.includes('email')) return 'mailInbox';

    // 3. Distractions & Ambient
    if (src.includes('dvd') || src.includes('bounce') || src.includes('corner')) return 'dvd';
    if (src.includes('lofi') || src.includes('lo-fi') || src.includes('chill') || src.includes('music')) return 'lofi';
    if (src.includes('asmr') || src.includes('soap') || src.includes('sand') || src.includes('slime') || src.includes('whisper')) return 'asmr';
    if (src.includes('rain') || src.includes('thunder') || src.includes('storm') || src.includes('weather')) return 'weather';
    if (src.includes('popcorn') || src.includes('kernel')) return 'popcorn';
    if (src.includes('meditat') || src.includes('gong') || src.includes('zen') || src.includes('bowl')) return 'meditation';
    if (src.includes('tamagotchi') || src.includes('pet') || src.includes('pixel') || src.includes('beep')) return 'tamagotchi';
    if (tag === 'video' || src.includes('subway') || src.includes('mukbang') || src.includes('.mp4') || src.includes('.webm')) return 'videos';
    if (src.includes('ocean') || src.includes('wave') || src.includes('water')) return 'ocean';

    // 4. Clickers & SFX
    if (src.includes('click') || src.includes('button') || src.includes('tap') || src.includes('pop')) return 'mainBtn';
    if (src.includes('press') || src.includes('hydraulic') || src.includes('crush') || src.includes('squash')) return 'press';
    if (src.includes('loot') || src.includes('box') || src.includes('crate')) return 'lootBoxes';
    if (src.includes('egg') || src.includes('chicken') || src.includes('peck') || src.includes('cluck')) return 'chickenEggs';
    if (src.includes('trade') || src.includes('coin') || src.includes('cash') || src.includes('money')) return 'tradeMarket';

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

    // 1. Main Click Loop
    const runMainClick = () => {
      if (state.master && state.features.mainBtn) {
        const btn = document.querySelector('.main-btn');
        if (btn) {
          for (let i = 0; i < state.clicker.burstMultiplier; i++) {
            clickWithCategory(btn, 'mainBtn');
          }
        }
        if (state.clicker.autoCollectLevel) {
          const col = document.querySelector('.collect');
          if (col) clickWithCategory(col, 'levelup');
        }
      }
      const jitter = state.clicker.useJitter ? (Math.random() * 0.4 + 0.8) : 1;
      const nextDelay = Math.max(5, Math.round(state.clickDelay * jitter));
      clickTimer = setTimeout(runMainClick, nextDelay);
    };
    runMainClick();

    // 2. Minigame & Upgrade Loop
    minigameTimer = setInterval(() => {
      if (state.features.pressBtn) {
        const pBtn = document.querySelector('.press-btn');
        if (pBtn) clickWithCategory(pBtn, 'press');
      }
      if (state.features.pressCollect) {
        const pCol = document.querySelector('.press-collect');
        if (pCol) clickWithCategory(pCol, 'press');
      }
      if (state.features.lootBoxes) {
        document.querySelectorAll('.loot-box-target').forEach(el => clickWithCategory(el, 'lootBoxes'));
      }
      if (state.features.chickenFeed) {
        const feed = document.querySelector('.action-btn');
        if (feed) clickWithCategory(feed, 'chickenEggs');
      }
      if (state.features.kinderEggs) {
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
        if (getStimulationBalance() >= state.upgrades.reserveStim) {
          const selector = state.upgrades.allowOceanReset
            ? '.upgrade:not(.upgrade-disabled) .upgrade-icon'
            : '.upgrade:not(.upgrade-disabled) .upgrade-icon:not([src*="ocean"])';
          document.querySelectorAll(selector).forEach(u => clickWithCategory(u, 'allOther'));
        }
      }
    }, Math.max(10, state.minigameDelay));

    // 3. Market Loop
    let stockCycleIndex = 0;
    marketTimer = setInterval(() => {
      if (!state.features.tradeMarket) return;
      const select = document.querySelector('.stock-select');
      const priceEl = document.querySelector('.last-price');
      const countEl = document.querySelector('.stock-shares');
      const buyBtn = document.querySelector('.stock-buy');
      const sellBtn = document.querySelector('.stock-sell');

      if (!select || !priceEl || !buyBtn || !sellBtn) return;

      const availableOptions = Array.from(select.options).map(o => o.value || o.text).filter(Boolean);
      availableOptions.forEach(stockName => {
        if (!state.market.stocks[stockName]) {
          state.market.stocks[stockName] = {
            enabled: true,
            buy: 0,
            sell: 0,
            minSeen: Infinity,
            maxSeen: -Infinity,
            lastSeen: 0
          };
          updateMarketStockPickerUI();
        }
      });

      if (state.market.cycleAll && availableOptions.length > 0) {
        stockCycleIndex = (stockCycleIndex + 1) % availableOptions.length;
        const nextStock = availableOptions[stockCycleIndex];
        if (select.value !== nextStock) {
          select.value = nextStock;
          select.dispatchEvent(new Event('change', { bubbles: true }));
          select.dispatchEvent(new Event('input', { bubbles: true }));
        }
      }

      const activeStock = select.value;
      const cfg = state.market.stocks[activeStock];
      if (!cfg || !cfg.enabled) return;

      const price = parseFloat(priceEl.innerText.replace(/[^0-9.]/g, ''));
      const shares = countEl ? parseInt(countEl.innerText.replace(/[^0-9]/g, '') || "0", 10) : 0;
      if (isNaN(price) || price <= 0) return;

      cfg.lastSeen = price;
      if (price < cfg.minSeen) cfg.minSeen = price;
      if (price > cfg.maxSeen) cfg.maxSeen = price;

      let targetBuy = cfg.buy;
      let targetSell = cfg.sell;

      if (state.market.smartRange && cfg.minSeen < cfg.maxSeen) {
        const spread = cfg.maxSeen - cfg.minSeen;
        targetBuy = cfg.minSeen + spread * (state.market.smartBuyPct / 100);
        targetSell = cfg.maxSeen - spread * (state.market.smartSellPct / 100);
      }

      if (targetBuy > 0 && price <= targetBuy && !buyBtn.disabled) {
        for (let i = 0; i < state.market.batchBuyCount; i++) {
          clickWithCategory(buyBtn, 'tradeMarket');
        }
      } else if (targetSell > 0 && price >= targetSell && shares > 0 && !sellBtn.disabled) {
        const toSell = state.market.sellAllShares ? shares : 1;
        for (let i = 0; i < toSell; i++) {
          clickWithCategory(sellBtn, 'tradeMarket');
        }
      }

      if (state.market.selectedStockUI === activeStock) {
        renderStockUIData();
      }
    }, Math.max(50, state.marketDelay));

    // 4. Mail Loop
    mailTimer = setInterval(() => {
      if (!state.features.mailInbox) return;
      const notif = document.querySelector('.notification');
      if (notif && notif.offsetParent !== null) clickWithCategory(notif, 'mailInbox');

      if (state.mail.autoSurvey) {
        document.querySelectorAll('.question-container input').forEach(input => input.click());
      }

      if (state.mail.autoActions) {
        const actionBtn = document.querySelector('.mail-container .action, .modal .action');
        if (actionBtn && actionBtn.offsetParent !== null) {
          const text = (actionBtn.innerText || "").trim().toLowerCase();
          const traps = state.mail.trapsBlacklist.split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
          const isTrap = traps.some(trap => text.includes(trap));
          if (!isTrap) clickWithCategory(actionBtn, 'mailInbox');
        }
      }

      const closeBtn = document.querySelector('.mail-container .close, .modal .close');
      if (closeBtn && closeBtn.offsetParent !== null) closeBtn.click();
    }, Math.max(100, state.mailDelay));
  }

  function stopLoops() {
    clearTimeout(clickTimer);
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
    width: 325px !important;
    max-height: 88vh !important;
    overflow-y: auto !important;
    background: rgba(15, 23, 42, 0.96) !important;
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
    <div id="cfg-drag-handle" style="cursor: move; display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; padding: 4px 8px; background: #1e293b; border-radius: 6px; border: 1px dashed #475569;">
      <span style="font-weight: 800; font-size: 12px; color: #38bdf8;">✥ Drag to Move Panel</span>
      <button id="cfg-min" style="background: none; border: none; color: #94a3b8; cursor: pointer; font-size: 14px; font-weight: bold;">—</button>
    </div>

    <button id="cfg-master" style="width: 100%; padding: 8px; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; background: #ef4444; color: #ffffff; font-size: 12px; margin-bottom: 8px;">
      MASTER: PAUSED (\`)
    </button>

    <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 4px; margin-bottom: 10px; border-bottom: 1px solid #334155; padding-bottom: 6px;">
      <button id="tab-btn-auto" style="padding: 5px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; background: #38bdf8; color: #0f172a; font-size: 10px;">⚡ Clicks</button>
      <button id="tab-btn-market" style="padding: 5px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; background: #1e293b; color: #94a3b8; font-size: 10px;">📈 Market</button>
      <button id="tab-btn-mail" style="padding: 5px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; background: #1e293b; color: #94a3b8; font-size: 10px;">✉️ Mail/Up</button>
      <button id="tab-btn-mute" style="padding: 5px; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; background: #1e293b; color: #94a3b8; font-size: 10px;">🔇 Audio</button>
    </div>

    <!-- TAB 1: CLICKS -->
    <div id="view-auto">
      <div style="font-weight: bold; color: #f59e0b; margin-bottom: 4px;">⚡ Main Clicker Settings</div>
      <label style="display: block; margin-bottom: 4px;">
        Click Interval: <b id="lbl-click">${state.clickDelay}ms</b>
        <input type="range" id="rng-click" min="5" max="100" step="5" value="${state.clickDelay}" style="width: 100%;">
      </label>
      <label style="display: block; margin-bottom: 4px;">
        Burst Clicks/Tick: <b id="lbl-burst">${state.clicker.burstMultiplier}x</b>
        <input type="range" id="rng-burst" min="1" max="25" step="1" value="${state.clicker.burstMultiplier}" style="width: 100%;">
      </label>
      <div style="display: flex; gap: 8px; margin-bottom: 6px;">
        <label><input type="checkbox" id="chk-jitter"> Timing Jitter</label>
        <label><input type="checkbox" id="chk-autoCollectLevel"> Auto Level Collect</label>
      </div>

      <div style="font-weight: bold; color: #f59e0b; margin: 8px 0 4px;">🎮 Minigame Toggles</div>
      <label style="display: block; margin-bottom: 4px;">
        Minigames Delay: <b id="lbl-mini">${state.minigameDelay}ms</b>
        <input type="range" id="rng-mini" min="15" max="300" step="15" value="${state.minigameDelay}" style="width: 100%;">
      </label>
      <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
        <span>Select Minigames:</span>
        <div>
          <button id="btn-feat-all" style="background: #334155; color: #fff; border: none; border-radius: 3px; padding: 2px 5px; cursor: pointer; font-size: 10px;">All</button>
          <button id="btn-feat-none" style="background: #334155; color: #fff; border: none; border-radius: 3px; padding: 2px 5px; cursor: pointer; font-size: 10px;">None</button>
        </div>
      </div>
      <div style="display: flex; flex-direction: column; gap: 4px;">
        <label><input type="checkbox" id="chk-mainBtn"> Main Button Auto-Clicker</label>
        <label><input type="checkbox" id="chk-pressBtn"> Hydraulic Press (Auto-Start)</label>
        <label><input type="checkbox" id="chk-pressCollect"> Hydraulic Press (Auto-Collect)</label>
        <label><input type="checkbox" id="chk-lootBoxes"> Floating Loot Boxes</label>
        <label><input type="checkbox" id="chk-chickenFeed"> Feed Paul the Chicken</label>
        <label><input type="checkbox" id="chk-kinderEggs"> Crack Kinder Eggs</label>
        <label><input type="checkbox" id="chk-duolingo"> Duolingo Answers</label>
        <label><input type="checkbox" id="chk-powerups"> Floating Powerups</label>
      </div>
    </div>

    <!-- TAB 2: MARKET -->
    <div id="view-market" style="display: none;">
      <div style="font-weight: bold; color: #f59e0b; margin-bottom: 4px;">📈 Multi-Stock Trading Engine</div>
      <label style="display: block; margin-bottom: 4px;">
        Market Eval Tick: <b id="lbl-market">${state.marketDelay}ms</b>
        <input type="range" id="rng-market" min="50" max="1000" step="25" value="${state.marketDelay}" style="width: 100%;">
      </label>
      <label style="display: block; margin-bottom: 4px;">
        Batch Buy Amount: <b id="lbl-batch">${state.market.batchBuyCount}x per tick</b>
        <input type="range" id="rng-batch" min="1" max="10" step="1" value="${state.market.batchBuyCount}" style="width: 100%;">
      </label>

      <div style="display: flex; flex-direction: column; gap: 4px; margin-bottom: 8px; background: #020617; padding: 6px; border-radius: 6px; border: 1px solid #1e293b;">
        <label><input type="checkbox" id="chk-market-cycle" checked> 🔄 <b>Cycle All Stocks</b> (Auto-rotates every asset)</label>
        <label><input type="checkbox" id="chk-market-sellall" checked> 💰 Sell Entire Position on Profit Target</label>
        <label><input type="checkbox" id="chk-market-smart"> 🧠 <b>Smart Range Mode</b> (Auto buy dip / sell peak %)</label>
      </div>

      <div id="smart-range-controls" style="display: none; margin-bottom: 8px; background: #1e293b; padding: 6px; border-radius: 6px;">
        <label style="display: block; margin-bottom: 4px;">
          Buy in Lowest: <b id="lbl-smart-buy">${state.market.smartBuyPct}%</b> of range
          <input type="range" id="rng-smart-buy" min="5" max="45" step="5" value="${state.market.smartBuyPct}" style="width: 100%;">
        </label>
        <label style="display: block;">
          Sell in Highest: <b id="lbl-smart-sell">${state.market.smartSellPct}%</b> of range
          <input type="range" id="rng-smart-sell" min="5" max="45" step="5" value="${state.market.smartSellPct}" style="width: 100%;">
        </label>
      </div>

      <div style="font-weight: bold; color: #38bdf8; margin: 6px 0 3px;">🎯 Configure Asset Target Prices</div>
      <div style="display: flex; gap: 6px; align-items: center; margin-bottom: 6px;">
        <span>Select Asset:</span>
        <select id="ui-stock-picker" style="flex: 1; background: #0f172a; border: 1px solid #38bdf8; color: #fff; padding: 3px; border-radius: 4px;"></select>
      </div>

      <div id="stock-data-box" style="background: #020617; padding: 8px; border-radius: 6px; border: 1px solid #334155;">
        <div style="display: flex; justify-content: space-between; margin-bottom: 4px;">
          <label><input type="checkbox" id="chk-stock-enable" checked> Trade this stock</label>
          <span id="txt-last-price" style="color: #38bdf8; font-weight: bold;">Last: $0</span>
        </div>
        <div style="color: #94a3b8; font-size: 10px; margin-bottom: 6px;">
          Observed Range: <span id="txt-range-low" style="color: #22c55e;">$0</span> - <span id="txt-range-high" style="color: #ef4444;">$0</span>
        </div>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 6px;">
          <label>Buy Below ≤<input type="number" id="inp-stock-buy" style="width: 90%; background: #0f172a; border: 1px solid #334155; color: #fff; padding: 2px; border-radius: 3px;"></label>
          <label>Sell Above ≥<input type="number" id="inp-stock-sell" style="width: 90%; background: #0f172a; border: 1px solid #334155; color: #fff; padding: 2px; border-radius: 3px;"></label>
        </div>
      </div>
      <label style="display: block; margin-top: 8px;"><input type="checkbox" id="chk-tradeMarket"> <b>Enable Market Bot Execution</b></label>
    </div>

    <!-- TAB 3: MAIL/UPGRADES -->
    <div id="view-mail" style="display: none;">
      <div style="font-weight: bold; color: #f59e0b; margin-bottom: 4px;">🛒 Upgrade Manager</div>
      <label style="display: block; margin-bottom: 4px;">
        Balance Reserve Buffer (Do not spend below):
        <input type="number" id="inp-reserve-stim" value="${state.upgrades.reserveStim}" style="width: 90%; background: #020617; border: 1px solid #334155; color: #fff; padding: 2px; border-radius: 3px;">
      </label>
      <label style="display: block; margin-bottom: 4px;"><input type="checkbox" id="chk-upgrades"> Auto-Buy Affordable Upgrades</label>
      <label style="display: block; color: #ef4444; margin-bottom: 8px;"><input type="checkbox" id="chk-allowOceanReset"> Allow "Go to the Ocean" Ending (Reset)</label>

      <div style="font-weight: bold; color: #f59e0b; margin: 8px 0 4px;">✉️ Mail Inbox Manager</div>
      <label style="display: block; margin-bottom: 4px;">
        Mail Scan Delay: <b id="lbl-mail">${state.mailDelay}ms</b>
        <input type="range" id="rng-mail" min="100" max="1000" step="50" value="${state.mailDelay}" style="width: 100%;">
      </label>
      <label style="display: block; margin-bottom: 4px;"><input type="checkbox" id="chk-mail-survey"> Auto-Check Survey Choices</label>
      <label style="display: block; margin-bottom: 4px;"><input type="checkbox" id="chk-mail-actions"> Auto-Click Safe Action Buttons (Grandma, etc.)</label>
      <label style="display: block; margin-bottom: 4px;">
        Trap Phrases Blacklist (comma-separated):
        <input type="text" id="inp-mail-traps" value="${state.mail.trapsBlacklist}" style="width: 95%; background: #020617; border: 1px solid #334155; color: #fff; padding: 3px; font-size: 10px; border-radius: 3px;">
      </label>
      <label style="display: block; margin-top: 6px;"><input type="checkbox" id="chk-mailInbox"> <b>Enable Mail Bot Execution</b></label>

      <hr style="border: 0; border-top: 1px solid #334155; margin: 8px 0;">
      <div style="font-weight: bold; color: #38bdf8; margin-bottom: 4px;">🎨 Interface Preferences</div>
      <label style="display: block;">
        Panel Opacity: <b id="lbl-opacity">${state.panelOpacity}%</b>
        <input type="range" id="rng-opacity" min="40" max="100" step="5" value="${state.panelOpacity}" style="width: 100%;">
      </label>
    </div>

    <!-- TAB 4: MUTE HUB (ALL GAME SOUNDS) -->
    <div id="view-mute" style="display: none;">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
        <span style="font-weight: bold; color: #ef4444;">🔇 Audio Silencers</span>
        <div>
          <button id="btn-mute-all" style="background: #ef4444; color: #fff; border: none; border-radius: 3px; padding: 2px 6px; cursor: pointer; font-size: 10px; font-weight: bold;">Mute All</button>
          <button id="btn-mute-none" style="background: #334155; color: #fff; border: none; border-radius: 3px; padding: 2px 6px; cursor: pointer; font-size: 10px;">Unmute All</button>
        </div>
      </div>

      <!-- VOICES & STREAMERS -->
      <div style="font-weight: bold; color: #38bdf8; margin: 4px 0 2px;">🗣️ Voices & Streamers</div>
      <div style="display: flex; flex-direction: column; gap: 4px; margin-bottom: 6px;">
        <label><input type="checkbox" id="mute-narrator"> 🎙️ <b>Voice Narrator</b> (Jeff Steitzer / Halo Announcer)</label>
        <label><input type="checkbox" id="mute-streamer"> 📢 <b>Reaction Streamer</b> (Ludwig)</label>
        <label><input type="checkbox" id="mute-fitness"> 🏋️ <b>Fitness Instructor</b> (Workout voice lines)</label>
        <label><input type="checkbox" id="mute-podcast"> 🔪 <b>True Crime Podcast</b></label>
      </div>

      <!-- POPUPS & MILESTONES -->
      <div style="font-weight: bold; color: #38bdf8; margin: 4px 0 2px;">🔔 Popups & Milestones</div>
      <div style="display: flex; flex-direction: column; gap: 4px; margin-bottom: 6px;">
        <label><input type="checkbox" id="mute-achievements"> 🏆 <b>Achievements</b> Popup Sound</label>
        <label><input type="checkbox" id="mute-levelup"> ⭐ <b>Level Up</b> Sound Effect</label>
        <label><input type="checkbox" id="mute-duolingo"> 🦉 <b>Duolingo</b> Popup Dings & Bells</label>
        <label><input type="checkbox" id="mute-breakingNews"> 📺 <b>Breaking News</b> Jingle</label>
        <label><input type="checkbox" id="mute-mailInbox"> ✉️ <b>Email Arrival</b> Notification Ping</label>
      </div>

      <!-- DISTRACTIONS & AMBIENCE -->
      <div style="font-weight: bold; color: #38bdf8; margin: 4px 0 2px;">✨ Distractions & Ambient Tracks</div>
      <div style="display: flex; flex-direction: column; gap: 4px; margin-bottom: 6px;">
        <label><input type="checkbox" id="mute-dvd"> 💿 <b>DVD Logo</b> Corner Pop / Bounce Sound</label>
        <label><input type="checkbox" id="mute-lofi"> 🎵 <b>Lo-Fi Beats</b> Music</label>
        <label><input type="checkbox" id="mute-asmr"> 🧼 <b>ASMR</b> (Soap, Sand, Slime, Whispering)</label>
        <label><input type="checkbox" id="mute-weather"> 🌧️ <b>Rain & Thunder</b> Weather Sounds</label>
        <label><input type="checkbox" id="mute-popcorn"> 🍿 <b>Popcorn</b> Popping SFX</label>
        <label><input type="checkbox" id="mute-meditation"> 🧘 <b>Meditation</b> Chimes & Bells</label>
        <label><input type="checkbox" id="mute-tamagotchi"> 👾 <b>Tamagotchi</b> Digital Beeps</label>
        <label><input type="checkbox" id="mute-videos"> 📱 <b>Subway Surfers & Mukbang</b> (Video stays running)</label>
        <label><input type="checkbox" id="mute-ocean"> 🌊 <b>Ambient Ocean Waves</b> (Ending)</label>
      </div>

      <!-- CLICKERS & MINIGAMES -->
      <div style="font-weight: bold; color: #38bdf8; margin: 4px 0 2px;">🖱️ Clickers & Actions</div>
      <div style="display: flex; flex-direction: column; gap: 4px;">
        <label><input type="checkbox" id="mute-mainBtn"> 🖱️ <b>Main Button</b> Rapid Clicks</label>
        <label><input type="checkbox" id="mute-press"> 🏗️ <b>Hydraulic Press</b> Squash</label>
        <label><input type="checkbox" id="mute-lootBoxes"> 📦 <b>Loot Boxes</b> Open Chimes</label>
        <label><input type="checkbox" id="mute-chickenEggs"> 🥚 <b>Eggs Crack & Chicken Feed</b></label>
        <label><input type="checkbox" id="mute-tradeMarket"> 📈 <b>Stock Buy/Sell</b> Cash Chime</label>
        <label><input type="checkbox" id="mute-allOther"> 🔔 <b>All Other</b> Miscellaneous SFX</label>
      </div>
    </div>
  `;

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
    panel.style.right = 'auto';
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

  // --- TAB NAVIGATION ---
  const tabs = ['auto', 'market', 'mail', 'mute'];
  function setTab(tabName) {
    state.activeTab = tabName;
    tabs.forEach(t => {
      const btn = panel.querySelector(`#tab-btn-${t}`);
      const view = panel.querySelector(`#view-${t}`);
      if (t === tabName) {
        btn.style.background = '#38bdf8';
        btn.style.color = '#0f172a';
        view.style.display = 'block';
      } else {
        btn.style.background = '#1e293b';
        btn.style.color = '#94a3b8';
        view.style.display = 'none';
      }
    });
  }
  tabs.forEach(t => panel.querySelector(`#tab-btn-${t}`).addEventListener('click', () => setTab(t)));

  // --- MASTER TOGGLE ---
  const masterBtn = panel.querySelector('#cfg-master');
  function toggleMaster() {
    state.master = !state.master;
    masterBtn.style.backgroundColor = state.master ? '#22c55e' : '#ef4444';
    masterBtn.textContent = state.master ? 'MASTER: ACTIVE (`)' : 'MASTER: PAUSED (`)';
    state.master ? startLoops() : stopLoops();
  }
  masterBtn.addEventListener('click', toggleMaster);

  // --- MARKET CONFIG UI HELPERS ---
  const stockPicker = panel.querySelector('#ui-stock-picker');
  const txtLast = panel.querySelector('#txt-last-price');
  const txtLow = panel.querySelector('#txt-range-low');
  const txtHigh = panel.querySelector('#txt-range-high');
  const inpBuy = panel.querySelector('#inp-stock-buy');
  const inpSell = panel.querySelector('#inp-stock-sell');
  const chkStockEnable = panel.querySelector('#chk-stock-enable');

  function updateMarketStockPickerUI() {
    const current = stockPicker.value;
    stockPicker.innerHTML = '';
    Object.keys(state.market.stocks).forEach(st => {
      const opt = document.createElement('option');
      opt.value = st;
      opt.textContent = st;
      if (st === current) opt.selected = true;
      stockPicker.appendChild(opt);
    });
    if (!stockPicker.value && Object.keys(state.market.stocks).length > 0) {
      stockPicker.value = Object.keys(state.market.stocks)[0];
    }
    state.market.selectedStockUI = stockPicker.value;
    renderStockUIData();
  }

  function renderStockUIData() {
    const cur = state.market.selectedStockUI;
    const cfg = state.market.stocks[cur];
    if (!cfg) return;
    txtLast.textContent = `Last: $${cfg.lastSeen.toLocaleString()}`;
    txtLow.textContent = `$${cfg.minSeen === Infinity ? 0 : cfg.minSeen.toLocaleString()}`;
    txtHigh.textContent = `$${cfg.maxSeen === -Infinity ? 0 : cfg.maxSeen.toLocaleString()}`;
    if (document.activeElement !== inpBuy) inpBuy.value = cfg.buy || '';
    if (document.activeElement !== inpSell) inpSell.value = cfg.sell || '';
    chkStockEnable.checked = cfg.enabled;
  }

  stockPicker.addEventListener('change', () => {
    state.market.selectedStockUI = stockPicker.value;
    renderStockUIData();
  });

  inpBuy.addEventListener('input', e => {
    const cfg = state.market.stocks[state.market.selectedStockUI];
    if (cfg) cfg.buy = parseFloat(e.target.value) || 0;
  });

  inpSell.addEventListener('input', e => {
    const cfg = state.market.stocks[state.market.selectedStockUI];
    if (cfg) cfg.sell = parseFloat(e.target.value) || 0;
  });

  chkStockEnable.addEventListener('change', e => {
    const cfg = state.market.stocks[state.market.selectedStockUI];
    if (cfg) cfg.enabled = e.target.checked;
  });

  const smartRangeControls = panel.querySelector('#smart-range-controls');
  panel.querySelector('#chk-market-smart').addEventListener('change', e => {
    state.market.smartRange = e.target.checked;
    smartRangeControls.style.display = e.target.checked ? 'block' : 'none';
  });

  panel.querySelector('#rng-smart-buy').addEventListener('input', e => {
    state.market.smartBuyPct = parseInt(e.target.value, 10);
    panel.querySelector('#lbl-smart-buy').textContent = `${state.market.smartBuyPct}%`;
  });

  panel.querySelector('#rng-smart-sell').addEventListener('input', e => {
    state.market.smartSellPct = parseInt(e.target.value, 10);
    panel.querySelector('#lbl-smart-sell').textContent = `${state.market.smartSellPct}%`;
  });

  panel.querySelector('#chk-market-cycle').addEventListener('change', e => state.market.cycleAll = e.target.checked);
  panel.querySelector('#chk-market-sellall').addEventListener('change', e => state.market.sellAllShares = e.target.checked);
  panel.querySelector('#rng-batch').addEventListener('input', e => {
    state.market.batchBuyCount = parseInt(e.target.value, 10);
    panel.querySelector('#lbl-batch').textContent = `${state.market.batchBuyCount}x per tick`;
  });

  // --- CLICKER & UPGRADES INPUT BINDINGS ---
  const rngClick = panel.querySelector('#rng-click');
  const lblClick = panel.querySelector('#lbl-click');
  rngClick.addEventListener('input', e => {
    state.clickDelay = parseInt(e.target.value, 10);
    lblClick.textContent = `${state.clickDelay}ms`;
  });

  const rngBurst = panel.querySelector('#rng-burst');
  const lblBurst = panel.querySelector('#lbl-burst');
  rngBurst.addEventListener('input', e => {
    state.clicker.burstMultiplier = parseInt(e.target.value, 10);
    lblBurst.textContent = `${state.clicker.burstMultiplier}x`;
  });

  panel.querySelector('#chk-jitter').addEventListener('change', e => state.clicker.useJitter = e.target.checked);
  panel.querySelector('#chk-autoCollectLevel').addEventListener('change', e => state.clicker.autoCollectLevel = e.target.checked);

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

  const rngMail = panel.querySelector('#rng-mail');
  const lblMail = panel.querySelector('#lbl-mail');
  rngMail.addEventListener('input', e => {
    state.mailDelay = parseInt(e.target.value, 10);
    lblMail.textContent = `${state.mailDelay}ms`;
    if (state.master) startLoops();
  });

  panel.querySelector('#inp-reserve-stim').addEventListener('input', e => state.upgrades.reserveStim = parseFloat(e.target.value) || 0);
  panel.querySelector('#chk-allowOceanReset').addEventListener('change', e => state.upgrades.allowOceanReset = e.target.checked);
  panel.querySelector('#chk-mail-survey').addEventListener('change', e => state.mail.autoSurvey = e.target.checked);
  panel.querySelector('#chk-mail-actions').addEventListener('change', e => state.mail.autoActions = e.target.checked);
  panel.querySelector('#inp-mail-traps').addEventListener('input', e => state.mail.trapsBlacklist = e.target.value);

  // Feature checkboxes
  const featureList = [
    'mainBtn', 'upgrades', 'pressBtn', 'pressCollect',
    'lootBoxes', 'chickenFeed', 'kinderEggs', 'duolingo',
    'powerups', 'tradeMarket', 'mailInbox'
  ];
  featureList.forEach(key => {
    const el = panel.querySelector(`#chk-${key}`);
    if (el) el.addEventListener('change', e => state.features[key] = e.target.checked);
  });

  panel.querySelector('#btn-feat-all').addEventListener('click', () => {
    featureList.forEach(k => {
      state.features[k] = true;
      const el = panel.querySelector(`#chk-${k}`);
      if (el) el.checked = true;
    });
  });

  panel.querySelector('#btn-feat-none').addEventListener('click', () => {
    featureList.forEach(k => {
      state.features[k] = false;
      const el = panel.querySelector(`#chk-${k}`);
      if (el) el.checked = false;
    });
  });

  // Mute checkboxes
  const muteKeys = Object.keys(state.mute);
  muteKeys.forEach(k => {
    const el = panel.querySelector(`#mute-${k}`);
    if (el) el.addEventListener('change', e => state.mute[k] = e.target.checked);
  });

  panel.querySelector('#btn-mute-all').addEventListener('click', () => {
    muteKeys.forEach(k => {
      state.mute[k] = true;
      const el = panel.querySelector(`#mute-${k}`);
      if (el) el.checked = true;
    });
  });

  panel.querySelector('#btn-mute-none').addEventListener('click', () => {
    muteKeys.forEach(k => {
      state.mute[k] = false;
      const el = panel.querySelector(`#mute-${k}`);
      if (el) el.checked = false;
    });
  });

  // Panel Opacity Slider
  const rngOpacity = panel.querySelector('#rng-opacity');
  const lblOpacity = panel.querySelector('#lbl-opacity');
  rngOpacity.addEventListener('input', e => {
    state.panelOpacity = parseInt(e.target.value, 10);
    lblOpacity.textContent = `${state.panelOpacity}%`;
    panel.style.background = `rgba(15, 23, 42, ${state.panelOpacity / 100})`;
  });

  // Minimize
  let minimized = false;
  const minBtn = panel.querySelector('#cfg-min');
  minBtn.addEventListener('click', () => {
    minimized = !minimized;
    tabs.forEach(t => panel.querySelector(`#view-${t}`).style.display = minimized ? 'none' : (t === state.activeTab ? 'block' : 'none'));
    minBtn.textContent = minimized ? '+' : '—';
  });

  updateMarketStockPickerUI();

  function recenterPanel() {
    panel.style.right = 'auto';
    panel.style.left = `${Math.max(10, (window.innerWidth - panel.offsetWidth) / 2)}px`;
    panel.style.top = `${Math.max(10, (window.innerHeight - panel.offsetHeight) / 2)}px`;
  }

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

  console.log("%c [Stimulation Suite] Audio Hub loaded with all voice, popup, and milestone silencers!", "color: #38bdf8; font-weight: bold; font-size: 14px;");
})();

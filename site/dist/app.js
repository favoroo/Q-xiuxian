/* 站点渲染层：只读 data.js（由 tools/export_site_data.py 从 scripts/data/*.gd 导出），
   页面里所有数量、档位、羁绊阶梯、升星规则都从这份数据现填，不在此手抄任何数字。
   交互口径与游戏内一致：筛选是「看哪一批」，不改写当前选中项（切板块不许替人选中第一件）。 */
(function () {
  "use strict";

  var D = window.GAME_DATA;
  if (!D) return;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function byId(id) { return document.getElementById(id); }

  /* —— 数量与版本：数字只从 meta 来 —— */
  var counts = D.meta.counts || {};
  counts.waves = (D.rules && D.rules.waves && D.rules.waves.victory) || 20;
  Array.prototype.forEach.call(document.querySelectorAll("[data-count]"), function (n) {
    var k = n.getAttribute("data-count");
    if (counts[k] != null) n.textContent = counts[k];
  });
  if (D.meta.version) {
    Array.prototype.forEach.call(document.querySelectorAll("[data-version]"), function (n) {
      n.textContent = "v" + D.meta.version;
    });
  }

  /* —— 角色：加成 / 代偿逐行列，开局自带与第二个技能做色签 —— */
  var roleGrid = byId("roleGrid");
  D.roles.forEach(function (r) {
    var card = el("article", "role plate");
    var top = el("div", "role-top");
    var img = el("img");
    img.src = r.i; img.alt = r.n + " 头像"; img.width = 42; img.height = 42;
    img.loading = "lazy";
    var meta = el("div");
    meta.appendChild(el("div", "role-name", r.n));
    meta.appendChild(el("div", "role-epi", r.e));
    top.appendChild(img); top.appendChild(meta);
    card.appendChild(top);

    (r.p || []).forEach(function (line) {
      var row = el("div", "role-line plus");
      row.appendChild(el("i", null, "＋"));
      row.appendChild(el("span", null, line));
      card.appendChild(row);
    });
    (r.c || []).forEach(function (line) {
      var row = el("div", "role-line minus");
      row.appendChild(el("i", null, "－"));
      row.appendChild(el("span", null, line));
      card.appendChild(row);
    });

    var tags = el("div", "role-tags");
    if (r.kit) tags.appendChild(el("em", "kit", "开局 " + r.kit));
    if (r.ex) tags.appendChild(el("em", "ex", "第二个技能 " + r.ex));
    if (tags.children.length) card.appendChild(tags);
    roleGrid.appendChild(card);
  });

  /* —— 通用「网格 + 筛选 + 详情条」工厂 —— */
  function buildCatalog(cfg) {
    var grid = byId(cfg.grid);
    var filters = byId(cfg.filters);
    var dIcon = byId(cfg.detailIcon), dName = byId(cfg.detailName), dDesc = byId(cfg.detailDesc);
    var shown = 0;

    var tiles = cfg.items.map(function (item, idx) {
      var b = el("button", "tile " + (cfg.cls || ""));
      b.type = "button";
      b.dataset.idx = idx;
      if (cfg.tileClass) b.className += " " + cfg.tileClass(item);
      var im = el("img");
      im.src = item.i; im.alt = ""; im.width = 34; im.height = 34; im.loading = "lazy";
      var t = el("span", "tile-txt");
      t.appendChild(el("b", null, item.n));
      t.appendChild(el("span", null, cfg.sub(item)));
      b.appendChild(im); b.appendChild(t);
      b.setAttribute("aria-label", item.n + "：" + cfg.plain(item));
      return b;
    });
    Array.prototype.forEach.call(tiles, function (b) { grid.appendChild(b); });

    function select(btn) {
      var item = cfg.items[+btn.dataset.idx];
      tiles.forEach(function (a) {
        a.classList.toggle("sel", a === btn);
        a.setAttribute("aria-pressed", a === btn ? "true" : "false");
      });
      dIcon.src = item.i;
      dName.textContent = item.n;
      dDesc.textContent = cfg.plain(item);
    }
    grid.addEventListener("click", function (e) {
      var btn = e.target.closest(".tile");
      if (btn && !btn.hidden) select(btn);
    });

    /* 筛选只改「看哪一批」：当前选中项被过滤掉也不动它，详情条继续说同一件东西 */
    function applyFilter(key) {
      shown = 0;
      tiles.forEach(function (b) {
        var ok = !key || cfg.match(cfg.items[+b.dataset.idx], key);
        b.hidden = !ok;
        if (ok) shown++;
      });
      count.textContent = shown + " 件";
    }

    var count = el("span", "fcount", "");
    var all = el("button", "fbtn on");
    all.type = "button"; all.textContent = cfg.allLabel; all.dataset.k = "";
    filters.appendChild(all);
    cfg.cats.forEach(function (c) {
      var b = el("button", "fbtn");
      b.type = "button"; b.dataset.k = c.k;
      if (c.dot) { var d = el("i"); d.style.background = c.dot; b.appendChild(d); }
      b.appendChild(document.createTextNode(c.n));
      filters.appendChild(b);
    });
    filters.appendChild(count);
    filters.addEventListener("click", function (e) {
      var b = e.target.closest(".fbtn");
      if (!b) return;
      Array.prototype.forEach.call(filters.querySelectorAll(".fbtn"), function (x) {
        x.classList.toggle("on", x === b);
      });
      applyFilter(b.dataset.k);
    });

    applyFilter("");
    select(tiles[0]);
    return { select: select, tiles: tiles };
  }

  /* —— 武器：器类 + 五行 11 个筛签，五行签带本家色 —— */
  var ELEMENT_DOT = { metal: "#c9a227", wood: "#59bf73", water: "#1e88e5", fire: "#ec4018", earth: "#a97544" };
  var classKeys = {};
  (D.cats || []).slice(0, 6).forEach(function (c) { classKeys[c.k] = true; });
  buildCatalog({
    grid: "armGrid", filters: "armFilters",
    detailIcon: "armDetailIcon", detailName: "armDetailName", detailDesc: "armDetailDesc",
    items: D.weapons, cls: "arm", allLabel: "全部 " + D.weapons.length + " 件",
    sub: function (w) { return w.t; },
    plain: function (w) { return w.d || w.t; },
    match: function (w, k) { return w.g.indexOf(k) >= 0; },
    cats: (D.cats || []).map(function (c) {
      return { k: c.k, n: c.n, dot: ELEMENT_DOT[c.k] || "" };
    }),
  });

  /* —— 升星与羁绊规则：数字从 rules / cats 现填，与游戏内同一条真话 —— */
  var st = (D.rules || {}).star || {};
  var starRule = byId("starRule");
  if (starRule && st.max) {
    starRule.textContent = "";
    starRule.appendChild(document.createTextNode(
      "集齐 " + (st.need || 3) + " 把同名同星，在商店合成升一星，伤害 ×" + st.dmg +
      "、攻击间隔 ×" + st.cd + "，最高 "));
    starRule.appendChild(el("b", "star", "★" + st.max));
    starRule.appendChild(document.createTextNode(
      "。武器栏 " + st.slots + " 格，背包 " + st.stash + " 格专门放着等合成。"));
  }
  var synBox = byId("synChips");
  if (synBox) {
    (D.cats || []).forEach(function (c) {
      var chip = el("em", null, c.n + " " + (c.th || []).join("/") + " 件 · " + (c.ef || []).join("+"));
      chip.style.background = ELEMENT_DOT[c.k] || "var(--panel)";
      synBox.appendChild(chip);
    });
  }

  /* —— 道具：档位四档筛签，顶边色即稀有度 —— */
  var tiers = [];
  var tierSeen = {};
  D.items.forEach(function (it) {
    if (!tierSeen[it.tier]) { tierSeen[it.tier] = true; tiers.push({ t: it.tier, n: it.tl }); }
  });
  tiers.sort(function (a, b) { return a.t - b.t; });
  var TIER_DOT = { 1: "#b8b3a6", 2: "#47adf9", 3: "#c773fa", 4: "#ffc740" };
  buildCatalog({
    grid: "itemGrid", filters: "itemFilters",
    detailIcon: "itemDetailIcon", detailName: "itemDetailName", detailDesc: "itemDetailDesc",
    items: D.items, allLabel: "全部 " + D.items.length + " 件",
    tileClass: function (it) { return "t" + it.tier; },
    sub: function (it) { return it.tl + " · " + it.price + " 金币"; },
    plain: function (it) {
      var rows = (it.r || []).join("、");
      return it.d ? (it.d + (rows ? "（" + rows + "）" : "")) : rows;
    },
    match: function (it, k) { return String(it.tier) === k; },
    cats: tiers.map(function (x) { return { k: String(x.t), n: x.n, dot: TIER_DOT[x.t] }; }),
  });

  /* —— 灵兽：有实拍切图就用切图，没有就用 PetData 的色值画灵球兜底 —— */
  var petGrid = byId("petGrid");
  D.pets.forEach(function (p) {
    var card = el("article", "pet");
    var top = el("div", "pet-orb");
    if (p.i) {
      var im = el("img", "orb-img");
      im.src = p.i; im.alt = p.n + " 形象"; im.width = 52; im.height = 52; im.loading = "lazy";
      top.appendChild(im);
    } else {
      var orb = el("div", "orb");
      orb.style.setProperty("--pet-core", p.color);
      orb.style.setProperty("--pet-halo", p.halo);
      orb.appendChild(el("b", null, p.n.charAt(0)));
      top.appendChild(orb);
    }
    var who = el("div");
    who.appendChild(el("div", "pet-n", p.n));
    who.appendChild(el("div", "pet-meta", "每 " + p.cd + " 秒出手 · " + p.price + " 金币起"));
    top.appendChild(who);
    top.appendChild(el("span", "pet-r", p.rn));
    card.appendChild(top);
    card.appendChild(el("p", null, p.d));
    petGrid.appendChild(card);
  });

  /* —— 技能：有图标用图标，没图标用游戏内占位符文上键 —— */
  var skillGrid = byId("skillGrid");
  D.skills.forEach(function (s) {
    var card = el("article", "skill plate");
    var top = el("div", "skill-top");
    if (s.i) {
      var im = el("img");
      im.src = s.i; im.alt = s.n + " 图标"; im.width = 40; im.height = 40;
      top.appendChild(im);
    } else {
      top.appendChild(el("div", "glyph", s.g || s.n.charAt(0)));
    }
    var meta = el("div");
    meta.appendChild(el("div", "skill-n", s.n));
    meta.appendChild(el("div", "skill-cd", s.cd > 0 ? "冷却 " + s.cd + " 秒" : "没有冷却"));
    top.appendChild(meta);
    card.appendChild(top);
    card.appendChild(el("p", null, s.d));
    card.appendChild(el("span", "skill-tag" + (s.offer ? "" : " bond"),
      s.offer ? "五选一" : "角色自带"));
    skillGrid.appendChild(card);
  });

  /* —— 导航高亮 + 标题带扫屏（游戏内 band_wipe 的品红/墨黑双矩带） —— */
  var links = Array.prototype.slice.call(document.querySelectorAll(".nav a"));
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (rows) {
      rows.forEach(function (r) {
        if (!r.isIntersecting) return;
        links.forEach(function (l) {
          l.classList.toggle("on", l.getAttribute("href") === "#" + r.target.id);
        });
        var title = r.target.querySelector(".sec-title");
        if (title && !title.dataset.wiped) {
          title.dataset.wiped = "1";
          title.classList.add("wiped");
        }
      });
    }, { rootMargin: "-70px 0px -65% 0px" });
    links.forEach(function (l) {
      var s = document.getElementById(l.getAttribute("href").slice(1));
      if (s) io.observe(s);
    });
  }
})();

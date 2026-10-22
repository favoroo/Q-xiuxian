/* 站点渲染层：只读 data.js 与 tokens.css（两者都由 tools/export_site_data.py 从游戏现读产出）。
   数量、档位、五行色、羁绊阶梯、升星规则、玩法秒数一律不在此手抄；
   主题色用 GameStyle 的 THEME_PRESETS 同一张表，切换只改 :root 上那三个变量。
   交互口径照游戏内：筛选只改「看哪一批」，不改写当前选中项（切板块不许替人选中第一件）。 */
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

  /* 低动效偏好一次判掉：JS 侧的揭示/数字滚动/上色扫屏全按它走，
     CSS 里另有一整块 prefers-reduced-motion 兜住补间（两边都必须停在「完整可见」这一态） */
  var RM = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  /* 动效时长一律从 tokens 现读，不在这里再抄一份毫秒数 */
  function tok(name) {
    var v = window.getComputedStyle(document.documentElement).getPropertyValue(name);
    var n = parseFloat(v);
    return /ms$/.test(v) ? n : n * 1000;
  }
  function stagger(node, i) {
    node.style.setProperty("--rv-delay", "calc(var(--rv-step) * " + Math.min(i, 6) + ")");
  }

  /* —— 数字与规则：一律从 data 现填，HTML 里写的那些只是无 JS 时的兜底 —— */
  var counts = D.meta.counts || {};
  var play = (D.rules || {}).play || {};
  counts.waves = play.victory || 20;
  Array.prototype.forEach.call(document.querySelectorAll("[data-count]"), function (n) {
    var k = n.getAttribute("data-count");
    if (counts[k] != null) n.textContent = counts[k];
  });
  Array.prototype.forEach.call(document.querySelectorAll("[data-rule]"), function (n) {
    var path = n.getAttribute("data-rule").split(".");
    var cur = D.rules;
    for (var i = 0; i < path.length && cur; i++) cur = cur[path[i]];
    if (cur != null) n.textContent = cur;
  });

  /* —— 主题色：与游戏内设置页同一张 THEME_PRESETS，选完记住 —— */
  var THEME_KEY = "***";
  (function buildThemes() {
    var box = byId("themeSwatches");
    var label = byId("themeName");
    var list = D.meta.themes || [];
    if (!box || !list.length) return;
    var saved = null;
    try { saved = window.localStorage.getItem(THEME_KEY); } catch (e) { /* 隐私模式就不记了 */ }
    function apply(t) {
      var s = document.documentElement.style;
      s.setProperty("--hot", t.main);
      s.setProperty("--hot-edge", t.edge);
      s.setProperty("--hot-dk", t.dk);
      // 字色跟着面色走（导出器按对比度算好的三档），否则深档面在品红下该配白字、
      // 换到荧绿就该配黑字，写死任何一边都会有一种主题糊字
      s.setProperty("--on-hot", t.t);
      s.setProperty("--on-hot-edge", t.te);
      s.setProperty("--on-hot-dk", t.td);
      Array.prototype.forEach.call(box.querySelectorAll(".theme-sw"), function (b) {
        b.setAttribute("aria-pressed", b.dataset.id === t.id ? "true" : "false");
      });
      if (label) label.textContent = t.n;
      try { window.localStorage.setItem(THEME_KEY, t.id); } catch (e) { /* 存不了也不影响这一屏 */ }
    }
    list.forEach(function (t) {
      var b = el("button", "theme-sw");
      b.type = "button";
      b.dataset.id = t.id;
      b.style.background = t.main;
      b.setAttribute("aria-label", "主题色改用" + t.n);
      b.addEventListener("click", function () { apply(t); });
      box.appendChild(b);
    });
    var want = saved || D.meta.theme_default || list[0].id;
    var pick = null;
    list.forEach(function (t) { if (t.id === want) pick = t; });
    apply(pick || list[0]);
  })();

  /* —— 角色：加成 / 代偿逐行列，开局自带与第二个技能做色签 —— */
  var roleGrid = byId("roleGrid");
  D.roles.forEach(function (r) {
    var card = el("article", "role plate");
    var top = el("div", "role-top");
    var img = el("img");
    img.src = r.i; img.alt = r.n + " 头像"; img.width = 42; img.height = 42; img.loading = "lazy";
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
  (function () {
    var cards = Array.prototype.slice.call(roleGrid.children);
    var fold = makeFold(roleGrid, 2, "名");
    function apply() {
      var cap = fold.cap(cards.length);
      cards.forEach(function (c, i) { c.hidden = i >= cap; });
      fold.sync(cards.length);
    }
    roleGrid._refilter = apply;
    apply();
    var rid = 0;
    window.addEventListener("resize", function () {
      window.clearTimeout(rid); rid = window.setTimeout(apply, 180);
    });
  })();

  /* —— 折叠：角色/武器/道具一次全铺太长，先给几整行，其余点按钮展开 ——
     阈值按「整行 × 当前列数」算：桌面 6 列与手机 2 列下折叠块高度差很多，
     按行取整不会出现切半行的断口，列数也直接读浏览器算好的 grid，不另写一份表。 */
  /* 折叠：角色/武器/道具一次全铺太长，先给几整行，其余点按钮展开 ——
     露出来的这几排靠 popFrom 逐颗顶上来，收起时不演（那是人要走的动作）。 */
  function visibleCount(grid) {
    return Array.prototype.filter.call(grid.children, function (n) { return !n.hidden; }).length;
  }
  function popFrom(grid, from) {
    var shown = Array.prototype.filter.call(grid.children, function (n) { return !n.hidden; });
    shown.slice(from).forEach(function (n, i) {
      if (!n.classList.contains("tile")) return;
      stagger(n, i);
      n.classList.remove("pop");
      void n.offsetWidth;
      n.classList.add("pop");
      n.addEventListener("animationend", function done() {
        n.classList.remove("pop");
        n.style.removeProperty("--rv-delay");
        n.removeEventListener("animationend", done);
      });
    });
  }

  function makeFold(grid, rows, unit) {
    var open = false;
    var btn = el("button", "more");
    btn.type = "button";
    btn.setAttribute("aria-controls", grid.id);
    grid.parentNode.insertBefore(btn, grid.nextSibling);
    function cols() {
      var v = window.getComputedStyle(grid).gridTemplateColumns;
      return Math.max(1, (v ? v.split(" ").filter(Boolean).length : 1));
    }
    function perView() { return rows * cols(); }
    btn.addEventListener("click", function () {
      var before = visibleCount(grid);
      open = !open;
      if (grid._refilter) grid._refilter();
      btn.scrollIntoView({ block: "nearest" });
      // 展开：新露出来的这几排逐颗顶上来（收起就不用演了，那是人要走的动作）
      if (!RM && open) popFrom(grid, before);
    });
    return {
      open: function () { return open; },
      cap: function (total) { return open || total <= perView() ? total : perView(); },
      sync: function (total) {
        var need = total > perView();
        btn.hidden = !need;
        if (need) {
          btn.textContent = open ? "收起" : ("展开其余 " + (total - perView()) + " " + unit);
          btn.appendChild(el("i", "chev", open ? "▲" : "▼"));
        }
        btn.setAttribute("aria-expanded", open ? "true" : "false");
      }
    };
  }

  /* —— 通用「网格 + 筛选 + 详情条」工厂 —— */
  function buildCatalog(cfg) {
    var grid = byId(cfg.grid);
    var filters = byId(cfg.filters);
    var dIcon = byId(cfg.detailIcon), dName = byId(cfg.detailName), dDesc = byId(cfg.detailDesc);
    var shown = 0;

    var tiles = cfg.items.map(function (item, idx) {
      var b = el("button", "tile" + (cfg.tileClass ? " " + cfg.tileClass(item) : ""));
      b.type = "button";
      b.dataset.idx = idx;
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
    var fold = cfg.rows ? makeFold(grid, cfg.rows, cfg.unit || "件") : null;

    function select(btn) {
      var item = cfg.items[+btn.dataset.idx];
      tiles.forEach(function (a) {
        a.classList.toggle("sel", a === btn);
        a.setAttribute("aria-pressed", a === btn ? "true" : "false");
      });
      dIcon.src = item.i;
      dName.textContent = item.n;
      dDesc.textContent = cfg.plain(item);
      // 详情条顶一下再归位：点完卡到读出来这一下，眼睛跟得上是同一件事
      var bar = dIcon.parentNode;
      if (!RM && bar) {
        bar.classList.remove("ping");
        void bar.offsetWidth;   // 摘类后必须强制一次重排，否则同一帧内再挂上去动画不会重播
        bar.classList.add("ping");
      }
    }
    grid.addEventListener("click", function (e) {
      var btn = e.target.closest(".tile");
      if (btn && !btn.hidden) select(btn);
    });

    /* 筛选只改「看哪一批」：当前选中项被过滤掉也不动它，详情条继续说同一件东西。
       折叠再在筛完的序列上截一刀，所以两家的结果一起算，不用 hidden 互相覆盖。 */
    var curKey = "";
    function applyFilter(key) {
      curKey = key || "";
      var matched = tiles.filter(function (b) {
        return !curKey || cfg.match(cfg.items[+b.dataset.idx], curKey);
      });
      tiles.forEach(function (b) { b.hidden = true; });
      var cap = fold ? fold.cap(matched.length) : matched.length;
      matched.slice(0, cap).forEach(function (b) { b.hidden = false; });
      shown = matched.length;
      count.textContent = (cap < matched.length ? "已显示 " + cap + " / " : "") + matched.length + " 件";
      if (fold) fold.sync(matched.length);
    }
    if (fold) {
      grid._refilter = function () { applyFilter(curKey); };
      var rid = 0;
      window.addEventListener("resize", function () {
        window.clearTimeout(rid);
        rid = window.setTimeout(function () { applyFilter(curKey); }, 180);
      });
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
    return { tiles: tiles };
  }

  /* —— 武器：卡框 accent 取五行属色（tokens 的 --m-*），器类签不带色点 —— */
  var ELEMENT_KEY = {};
  (D.cats || []).forEach(function (c) { if (c.kind === "element") ELEMENT_KEY[c.k] = true; });
  function elementOf(w) {
    for (var i = 0; i < w.g.length; i++) if (ELEMENT_KEY[w.g[i]]) return w.g[i];
    return "";
  }
  buildCatalog({
    grid: "armGrid", filters: "armFilters",
    detailIcon: "armDetailIcon", detailName: "armDetailName", detailDesc: "armDetailDesc",
    items: D.weapons, allLabel: "全部 " + D.weapons.length + " 件", rows: 3, unit: "件",
    tileClass: function (w) { var e = elementOf(w); return e ? "e-" + e : ""; },
    sub: function (w) { return w.t; },
    plain: function (w) { return w.d || w.t; },
    match: function (w, k) { return w.g.indexOf(k) >= 0; },
    cats: (D.cats || []).map(function (c) {
      return { k: c.k, n: c.n, dot: c.kind === "element" ? "var(--m-" + c.k + ")" : "" };
    }),
  });

  /* —— 升星与羁绊：数字从 rules / cats 现填，句子与游戏内商店提示同一口径 —— */
  var st = (D.rules || {}).star || {};
  var starRule = byId("starRule");
  if (starRule && st.max) {
    starRule.textContent = "";
    starRule.appendChild(document.createTextNode(
      "集齐 " + st.need + " 把同名同星，在商店合成升一星，伤害 ×" + st.dmg +
      "、攻击间隔 ×" + st.cd + "，最高 "));
    starRule.appendChild(el("b", "star", "★" + st.max));
    starRule.appendChild(document.createTextNode(
      "。武器栏 " + st.slots + " 格，背包 " + st.stash + " 格专门放着等合成。"));
  }
  var synBox = byId("synChips");
  if (synBox) {
    (D.cats || []).forEach(function (c) {
      var chip = el("em", null, c.n + " " + (c.th || []).join("/") + " 件 · " + (c.ef || []).join("+"));
      chip.style.background = c.kind === "element" ? "var(--m-" + c.k + ")" : "var(--chalk)";
      synBox.appendChild(chip);
    });
  }

  /* —— 道具：档位四档筛签，卡框色 = RARITY_* 四档 —— */
  var tiers = [];
  var tierSeen = {};
  D.items.forEach(function (it) {
    if (!tierSeen[it.tier]) { tierSeen[it.tier] = true; tiers.push({ t: it.tier, n: it.tl }); }
  });
  tiers.sort(function (a, b) { return a.t - b.t; });
  buildCatalog({
    grid: "itemGrid", filters: "itemFilters",
    detailIcon: "itemDetailIcon", detailName: "itemDetailName", detailDesc: "itemDetailDesc",
    items: D.items, allLabel: "全部 " + D.items.length + " 件", rows: 3, unit: "件",
    tileClass: function (it) { return "t" + it.tier; },
    sub: function (it) { return it.tl + " · " + it.price + " 金币"; },
    plain: function (it) {
      var rows = (it.r || []).join("、");
      return it.d ? (it.d + (rows ? "（" + rows + "）" : "")) : rows;
    },
    match: function (it, k) { return String(it.tier) === k; },
    cats: tiers.map(function (x) { return { k: String(x.t), n: x.n, dot: "var(--r-" + x.t + ")" }; }),
  });

  /* —— 灵兽：图取调形台实拍切图，描边用它自己那颗灵球的主色 —— */
  var petGrid = byId("petGrid");
  D.pets.forEach(function (p) {
    var card = el("article", "pet");
    card.style.setProperty("--pet-color", p.color);
    var top = el("div", "pet-orb");
    var im = el("img", "orb-img");
    im.src = p.i; im.alt = p.n + " 形象"; im.width = 52; im.height = 52; im.loading = "lazy";
    var who = el("div");
    who.appendChild(el("div", "pet-n", p.n));
    who.appendChild(el("div", "pet-meta", "每 " + p.cd + " 秒出手 · " + p.price + " 金币起"));
    top.appendChild(im); top.appendChild(who);
    top.appendChild(el("span", "pet-r", p.rn));
    card.appendChild(top);
    card.appendChild(el("p", null, p.d));
    petGrid.appendChild(card);
  });

  /* —— 技能：有图标用图标，没图标用游戏内占位符文上键 —— */
  var skillGrid = byId("skillGrid");
  /* 只放五选一那批：影爆 / 药爆跟着角色自带、不走选择界面，卡片混进来会让人以为能挑 */
  D.skills.filter(function (s) { return s.offer; }).forEach(function (s) {
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

  /* —— 首屏进入：同一帧里挂 .enter → 强制样式落地 → 立刻摘掉，让 CSS 补间把它顶上来。
     静态值不藏东西：JS 没跑或渲染器不推动画时，首屏文案照常完整可见（上一版用 keyframes +
     fill both，起始帧写在屏外，冻结渲染下整段首屏是空的）。 */
  (function enterHero() {
    if (RM) return;
    var kids = document.querySelectorAll(".hero-copy > *");
    var step = tok("--dur-press") / 2;
    for (var i = 0; i < kids.length; i++) {
      kids[i].classList.add("enter");
      kids[i].style.transitionDelay = Math.min(i, 6) * step + "ms";
    }
    void document.body.offsetWidth;   // 不强制落地的话，摘类后没有起始值可补间
    for (var j = 0; j < kids.length; j++) kids[j].classList.remove("enter");
  })();

  /* —— 导航指示条 + 分区高亮 + 滚动入场 + 数据带数字 —— */
  var links = Array.prototype.slice.call(document.querySelectorAll(".nav a"));
  var nav = links.length ? links[0].parentNode : null;
  var ind = null;
  if (nav) {
    ind = el("span", "nav-ind");
    ind.setAttribute("aria-hidden", "true");
    nav.appendChild(ind);
  }
  var active = null;   // 当前分区那一项；hover 只是借过去看一下，移开就还给它
  /* 手机上导航是横着划的：指示条滑到哪，就得把那一格也划进可视范围，
     否则会看到「带子在下面走，字却屏外了」这种断片。只滚 .nav 自己，不动整页。 */
  function ensureVisible(link) {
    if (!nav || !link) return;
    var l = link.offsetLeft, r = l + link.offsetWidth, w = nav.clientWidth;
    var to = nav.scrollLeft;
    if (l < to) to = l - 8;
    else if (r > to + w) to = r - w + 8;
    if (to === nav.scrollLeft) return;
    if (nav.scrollTo) nav.scrollTo({ left: to, behavior: RM ? "auto" : "smooth" });
    else nav.scrollLeft = to;
  }
  function place(link) {
    if (!ind || !link) return;
    ind.style.width = link.offsetWidth + "px";
    ind.style.transform = "translateX(" + link.offsetLeft + "px)";
    ind.setAttribute("data-show", "1");
    ensureVisible(link);
  }
  if (nav) {
    nav.addEventListener("mouseover", function (e) {
      var a = e.target.closest(".nav a");
      if (a) place(a);
    });
    nav.addEventListener("mouseleave", function () {
      // 手移开就还给当前分区；一个分区都还没进过时直接收起来，别留一根没人认领的带子
      if (active) place(active); else if (ind) ind.setAttribute("data-show", "0");
    });
    links.forEach(function (l) {
      l.addEventListener("click", function () { setActive(l); });
    });
    window.addEventListener("resize", function () { place(active); });
  }
  function setActive(href) {
    links.forEach(function (l) { l.classList.toggle("on", l === href); });
    active = href;
    place(href);
  }

  if ("IntersectionObserver" in window) {
    var spy = new IntersectionObserver(function (rows) {
      rows.forEach(function (r) {
        if (!r.isIntersecting) return;
        for (var i = 0; i < links.length; i++) {
          if (links[i].getAttribute("href") === "#" + r.target.id) setActive(links[i]);
        }
        // 分区标题不做扫屏/上色动效（用户 2026-10-21 拍板关掉），这里只负责把导航指到当前分区
      });
    }, { rootMargin: "-70px 0px -65% 0px" });
    links.forEach(function (l) {
      var s = document.getElementById(l.getAttribute("href").slice(1));
      if (s) spy.observe(s);
    });

    /* 滚动入场：只给「此刻还在首屏下方」的块挂 .rv —— 屏内正在读的东西绝不能被藏起来再演，
       那会变成「打开页面有一块空白自己慢慢冒出来」。JS 没跑或浏览器不认 IO 时页面照常全可见。 */
    var targets = [];
    Array.prototype.forEach.call(document.querySelectorAll(".section"), function (s) {
      var kids = [].slice.call(s.querySelectorAll(".sec-sub, .sec-body > *"));
      kids.forEach(function (n, i) {
        if (n.getBoundingClientRect().top > window.innerHeight * 0.92) {
          stagger(n, i);
          n.classList.add("rv");
          targets.push(n);
        }
      });
    });
    var revealer = null;
    if (targets.length && "IntersectionObserver" in window) {
      revealer = new IntersectionObserver(function (rows) {
        rows.forEach(function (r) {
          if (!r.isIntersecting) return;
          r.target.classList.add("on");
          revealer.unobserve(r.target);
        });
      }, { rootMargin: "0px 0px -8% 0px" });
      targets.forEach(function (n) { revealer.observe(n); });
    }
    /* 兜底闸：IO 没回调（老 WebView、冻结渲染、极快滚动丢帧）时，
       只要某块已经进视口就必须露出来 —— 看不见的内容一律按 bug 处理。 */
    function sweep() {
      for (var i = targets.length - 1; i >= 0; i--) {
        var n = targets[i], r = n.getBoundingClientRect();
        if (r.top < window.innerHeight && r.bottom > 0) {
          n.classList.add("on");
          if (revealer) revealer.unobserve(n);
          targets.splice(i, 1);
        }
      }
      if (!targets.length && ticking) {
        window.removeEventListener("scroll", onScroll);
        ticking = false;
      }
    }
    var ticking = false;
    function onScroll() {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(function () { ticking = false; sweep(); });
    }
    if (targets.length) {
      window.addEventListener("scroll", onScroll, { passive: true });
      window.setTimeout(sweep, 1200);
      window.setTimeout(sweep, 4000);
    }

    /* 数据带：六个数字滚上去，时长用扫屏那一拍（--dur-wipe + --wipe-fade）现读，不另定 */
    var band = document.querySelector(".band");
    if (band && !RM) {
      var nums = [].slice.call(band.querySelectorAll("[data-count]")).map(function (n) {
        return { node: n, to: parseInt(n.textContent, 10) || 0 };
      });
      var ms = tok("--dur-wipe") + tok("--wipe-fade");
      var roll = new IntersectionObserver(function (rows) {
        rows.forEach(function (r) {
          if (!r.isIntersecting) return;
          roll.disconnect();
          var t0 = 0;
          function frame(ts) {
            if (!t0) t0 = ts;
            var p = Math.min(1, (ts - t0) / ms);
            var e = 1 - Math.pow(1 - p, 3);
            nums.forEach(function (x) { x.node.textContent = Math.round(x.to * e); });
            if (p < 1) window.requestAnimationFrame(frame);
          }
          window.requestAnimationFrame(frame);
        });
      }, { threshold: 0.4 });
      roll.observe(band);
    }
  }
})();

/* 角色 / 武器网格与器类筛选。数据来自 data.js，由 scripts/data/*.gd 直接导出。 */
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

  /* —— 角色 —— */
  var roleGrid = document.getElementById("roleGrid");
  D.roles.forEach(function (r) {
    var card = el("article", "role plate");
    var top = el("div", "role-top");
    var img = el("img");
    img.src = r.i;
    img.alt = r.n + " 头像";
    img.width = 42;
    img.height = 42;
    var meta = el("div");
    meta.appendChild(el("div", "role-name", r.n));
    meta.appendChild(el("div", "role-epi", r.e));
    top.appendChild(img);
    top.appendChild(meta);
    card.appendChild(top);

    var plus = el("div", "role-line");
    plus.appendChild(el("i", "plus", "＋"));
    plus.appendChild(el("span", null, r.p));
    card.appendChild(plus);

    if (r.c) {
      var minus = el("div", "role-line");
      minus.appendChild(el("i", "minus", "－"));
      minus.appendChild(el("span", null, r.c));
      card.appendChild(minus);
    }
    roleGrid.appendChild(card);
  });

  /* —— 武器筛选 —— */
  var filters = document.getElementById("filters");
  var armGrid = document.getElementById("armGrid");
  var dIcon = document.getElementById("detailIcon");
  var dName = document.getElementById("detailName");
  var dDesc = document.getElementById("detailDesc");

  var arms = D.weapons.map(function (w, idx) {
    var b = el("button", "arm plate");
    b.type = "button";
    b.dataset.idx = idx;
    var im = el("img");
    im.src = w.i;
    im.alt = w.n + " 图标";
    im.width = 34;
    im.height = 34;
    var t = el("span", "arm-txt");
    t.appendChild(el("b", null, w.n));
    t.appendChild(el("span", null, w.t));
    b.appendChild(im);
    b.appendChild(t);
    b.setAttribute("aria-label", w.n + "：" + w.d);
    return b;
  });

  armGrid.append.apply(armGrid, arms);

  function select(btn) {
    var w = D.weapons[+btn.dataset.idx];
    arms.forEach(function (a) { a.classList.toggle("sel", a === btn); });
    a11ySelected(btn);
    dIcon.src = w.i;
    dIcon.alt = "";
    dName.textContent = w.n;
    dDesc.textContent = w.d || w.t;
  }

  function a11ySelected(btn) {
    arms.forEach(function (a) { a.setAttribute("aria-pressed", a === btn ? "true" : "false"); });
  }

  armGrid.addEventListener("click", function (e) {
    var btn = e.target.closest(".arm");
    if (btn) select(btn);
  });

  function applyFilter(key) {
    var shown = 0;
    arms.forEach(function (a) {
      var w = D.weapons[+a.dataset.idx];
      var ok = !key || w.g.indexOf(key) >= 0;
      a.hidden = !ok;
      if (ok) shown++;
    });
    var first = arms.find(function (a) { return !a.hidden; });
    if (first && first.hidden !== true) select(first);
    count.textContent = shown + " 件";
  }

  var count = el("span", "fcount", "");
  var all = el("button", "fbtn on");
  all.type = "button";
  all.textContent = "全部";
  all.dataset.k = "";
  filters.appendChild(all);
  D.cats.forEach(function (c) {
    var b = el("button", "fbtn");
    b.type = "button";
    b.textContent = c.n;
    b.dataset.k = c.k;
    filters.appendChild(b);
  });
  filters.appendChild(count);

  filters.addEventListener("click", function (e) {
    var b = e.target.closest(".fbtn");
    if (!b) return;
    filters.querySelectorAll(".fbtn").forEach(function (x) {
      x.classList.toggle("on", x === b);
    });
    applyFilter(b.dataset.k);
  });

  select(arms[0]);
  applyFilter("");

  /* —— 导航高亮 —— */
  var links = Array.prototype.slice.call(document.querySelectorAll(".nav a"));
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (rows) {
      rows.forEach(function (r) {
        if (!r.isIntersecting) return;
        links.forEach(function (l) {
          l.classList.toggle("on", l.getAttribute("href") === "#" + r.target.id);
        });
      });
    }, { rootMargin: "-70px 0px -65% 0px" });
    links.forEach(function (l) {
      var s = document.getElementById(l.getAttribute("href").slice(1));
      if (s) io.observe(s);
    });
  }
})();

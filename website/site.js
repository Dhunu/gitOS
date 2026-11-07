(function () {
  document.documentElement.classList.add("js");
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  // ---- Account demo. The accounts are made up.
  var accounts = {
    work: { login: "maya-northwind", title: "Work", email: "maya@northwind.example", folder: "~/Work" },
    personal: { login: "maya-makes", title: "Personal", email: "maya@pixel.example", folder: "~/Personal" }
  };
  var currentRepo = $(".repo[aria-pressed=true]");

  function showAccount(flash) {
    var account = accounts[currentRepo.dataset.account];
    $("[data-repo-name]").textContent = currentRepo.dataset.repo;
    $("[data-rule]").textContent = account.folder;
    $("[data-account-name]").textContent = account.login;
    $("[data-identity]").textContent = account.email;
    if (flash) $$(".identity-row").forEach(function (row) {
      row.classList.remove("flash");
      void row.offsetWidth;
      row.classList.add("flash");
    });
  }
  $$(".repo").forEach(function (button) {
    $("[data-avatar]", button).classList.toggle("alt", button.dataset.account === "personal");
    button.addEventListener("click", function () {
      currentRepo.setAttribute("aria-pressed", "false");
      currentRepo = button;
      button.setAttribute("aria-pressed", "true");
      showAccount(true);
    });
  });
  showAccount(false);

  var alertBox = $("#push-alert");
  var pushButton = $("[data-push-warning]");
  if (alertBox.showModal) {
    pushButton.addEventListener("click", function () {
      var key = currentRepo.dataset.account;
      var account = accounts[key];
      var other = accounts[key === "work" ? "personal" : "work"];
      $$("[data-alert-account]").forEach(function (el) { el.textContent = account.title + " · @" + account.login; });
      $("[data-alert-email]").textContent = other.email;
      alertBox.showModal();
    });
  } else {
    pushButton.hidden = true;
  }

  // ---- Feature list and detail.
  var rows = $$(".feature");
  var details = $$(".feature-detail");
  function selectFeature(id) {
    rows.forEach(function (row) {
      var on = row.dataset.feature === id;
      row.classList.toggle("on", on);
      if (on) row.setAttribute("aria-current", "true");
      else row.removeAttribute("aria-current");
    });
    details.forEach(function (detail) { detail.classList.toggle("on", detail.id === id); });
  }
  rows.forEach(function (row) {
    row.addEventListener("click", function () { selectFeature(row.dataset.feature); });
  });
  selectFeature(rows[0].dataset.feature);

  // ---- Picking lines in the staging example.
  $$("[data-stageable] .ln.add, [data-stageable] .ln.del").forEach(function (line) {
    var numbers = $$(".no", line);
    var button = document.createElement("button");
    button.type = "button";
    button.className = "gutter-btn";
    button.setAttribute("aria-pressed", "false");
    button.setAttribute("aria-label", "Pick line: " + $(".tx", line).textContent.replace(/^(added|removed): /, ""));
    line.insertBefore(button, numbers[0]);
    numbers.forEach(function (number) { button.appendChild(number); });
    button.addEventListener("click", function () {
      button.setAttribute("aria-pressed", String(line.classList.toggle("picked")));
    });
  });

  // ---- Toolbar tabs follow the section on screen.
  var navLinks = $$("[data-nav]");
  if ("IntersectionObserver" in window) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        navLinks.forEach(function (link) {
          if (link.dataset.nav === entry.target.id) link.setAttribute("aria-current", "true");
          else link.removeAttribute("aria-current");
        });
      });
    }, { rootMargin: "-40% 0px -55% 0px" });
    navLinks.forEach(function (link) {
      var section = document.getElementById(link.dataset.nav);
      if (section) observer.observe(section);
    });
  }

  // ---- Themes, repainted from the app's own palettes.
  var themes = (window.GITOS_THEMES || []).filter(function (t) { return t.id !== "gitos-light"; });
  if (!themes.length) return;
  var root = document.documentElement;
  var keys = ["accent", "head", "canvas", "panel", "field", "added", "modified", "removed", "renamed", "conflict"];
  var grid = $("[data-theme-grid]");
  var shots = $$("[data-theme-shot]");

  function channels(hex) {
    var n = parseInt(hex.slice(1), 16);
    return [n >> 16 & 255, n >> 8 & 255, n & 255];
  }
  function luminance(rgb) {
    var c = rgb.map(function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  }
  function contrast(a, b) {
    var x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }
  function blend(color, background, amount) {
    return background.map(function (v, i) { return Math.round(v * (1 - amount) + color[i] * amount); });
  }
  // Keeps a color's character, moving it just far enough from the background to read as text.
  function readable(hex, background, light) {
    var target = light ? [0, 0, 0] : [255, 255, 255];
    var from = channels(hex);
    for (var mix = 0; mix <= 1; mix += 0.04) {
      var color = blend(target, from, mix);
      if (contrast(color, background) >= 4.6) return "rgb(" + color.join(",") + ")";
    }
    return light ? "#000" : "#fff";
  }

  function applyTheme(theme) {
    var light = theme.scheme === "light";
    keys.forEach(function (key) { root.style.setProperty("--" + key, theme[key]); });
    var accent = channels(theme.accent);
    root.style.setProperty("--on-accent", contrast(accent, [255, 255, 255]) >= contrast(accent, [11, 14, 19]) ? "#FFFFFF" : "#0B0E13");
    var panel = channels(theme.panel);
    root.style.setProperty("--link", readable(theme.accent, contrast(accent, panel) < contrast(accent, channels(theme.canvas)) ? panel : channels(theme.canvas), light));
    root.style.setProperty("--t-added", readable(theme.added, blend(channels(theme.added), panel, 0.16), light));
    root.style.setProperty("--t-accent", readable(theme.accent, blend(accent, panel, 0.16), light));
    root.style.setProperty("--t-head", readable(theme.head, blend(channels(theme.head), panel, 0.16), light));
    root.dataset.scheme = theme.scheme;
    $("meta[name=theme-color]").content = theme.panel;
    shots.forEach(function (img) { img.src = "assets/themes/" + theme.id + ".png"; });
    $$(".theme-card").forEach(function (card) {
      card.setAttribute("aria-pressed", String(card.dataset.theme === theme.id));
    });
  }

  themes.forEach(function (theme) {
    var card = document.createElement("button");
    card.type = "button";
    card.className = "theme-card";
    card.dataset.theme = theme.id;
    card.setAttribute("aria-pressed", "false");
    var preview = document.createElement("span");
    preview.className = "theme-preview";
    preview.setAttribute("aria-hidden", "true");
    var side = document.createElement("span");
    side.className = "theme-side";
    side.style.background = theme.panel;
    var main = document.createElement("span");
    main.className = "theme-main";
    main.style.background = theme.canvas;
    [[theme.accent, 55], [theme.added, 75], [theme.removed, 42]].forEach(function (bar) {
      var line = document.createElement("i");
      line.style.background = bar[0];
      line.style.width = bar[1] + "%";
      main.appendChild(line);
    });
    preview.appendChild(side);
    preview.appendChild(main);
    card.appendChild(preview);
    card.appendChild(document.createTextNode(theme.name));
    card.addEventListener("click", function () {
      applyTheme(theme);
      try { localStorage.setItem("gitos-theme", theme.id); } catch (e) {}
    });
    grid.appendChild(card);
  });

  var saved = null;
  try { saved = localStorage.getItem("gitos-theme"); } catch (e) {}
  applyTheme(themes.filter(function (t) { return t.id === saved; })[0] || themes[0]);
})();

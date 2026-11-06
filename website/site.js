(function () {
  var themes = window.GITOS_THEMES;
  var root = document.documentElement;
  var chips = document.querySelectorAll(".chip");
  var shots = document.querySelectorAll("[data-theme-shot]");
  var keys = ["accent", "head", "canvas", "panel", "field", "added", "modified", "removed", "renamed", "conflict"];

  function find(id) {
    return themes.filter(function (t) { return t.id === id; })[0];
  }

  // Readable text on the accent button, whichever theme is active.
  function onAccent(hex) {
    var n = parseInt(hex.slice(1), 16);
    var luminance = (0.299 * (n >> 16 & 255) + 0.587 * (n >> 8 & 255) + 0.114 * (n & 255)) / 255;
    return luminance > 0.5 ? "#0B0E13" : "#FFFFFF";
  }

  function apply(theme) {
    keys.forEach(function (key) { root.style.setProperty("--" + key, theme[key]); });
    root.style.setProperty("--on-accent", onAccent(theme.accent));
    root.dataset.scheme = theme.light ? "light" : "dark";
    document.querySelector('meta[name="theme-color"]').content = theme.canvas;
    shots.forEach(function (img) { img.src = "assets/themes/" + theme.id + ".png"; });
    chips.forEach(function (chip) {
      chip.setAttribute("aria-pressed", String(chip.dataset.theme === theme.id));
    });
  }

  chips.forEach(function (chip) {
    chip.addEventListener("click", function () {
      var theme = find(chip.dataset.theme);
      if (!theme) return;
      apply(theme);
      try { localStorage.setItem("gitos-theme", theme.id); } catch (e) {}
    });
  });

  var saved = null;
  try { saved = find(localStorage.getItem("gitos-theme")); } catch (e) {}
  if (saved) apply(saved);
})();

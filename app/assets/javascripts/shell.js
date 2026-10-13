/* Application shell control: sidebar (full/mini/off-canvas + persisted),
 * light/dark theme (persisted). Attribute-driven, mirroring the Spike theme
 * protocol: <html data-bs-theme>, <body data-sidebartype>,
 * #main-wrapper.show-sidebar on mobile. No jQuery. */
(function () {
  "use strict";

  var DESKTOP = "(min-width: 1300px)";
  var MOBILE_OPEN_CLASS = "show-sidebar";

  function wrapper() { return document.getElementById("main-wrapper"); }

  function isDesktop() { return window.matchMedia(DESKTOP).matches; }

  function stored(key, fallback) {
    try { return localStorage.getItem(key) || fallback; } catch (e) { return fallback; }
  }

  function save(key, value) {
    try { value ? localStorage.setItem(key, value) : localStorage.removeItem(key); } catch (e) { /* noop */ }
  }

  function storedSession(key, fallback) {
    try { return sessionStorage.getItem(key) || fallback; } catch (e) { return fallback; }
  }

  function saveSession(key, value) {
    try { value ? sessionStorage.setItem(key, value) : sessionStorage.removeItem(key); } catch (e) { /* noop */ }
  }

  function closeMobileSidebar() {
    var w = wrapper();
    if (w) w.classList.remove(MOBILE_OPEN_CLASS);
    document.body.style.overflow = "";
  }

  function openMobileSidebar() {
    var w = wrapper();
    if (w) w.classList.add(MOBILE_OPEN_CLASS);
    document.body.style.overflow = "hidden";
  }

  function sidebarMini() {
    if (!isDesktop()) { return; }
    var mini = stored("etSidebarMini", "") === "1";
    document.body.setAttribute("data-sidebartype", mini ? "mini-sidebar" : "full");
  }

  function toggleSidebar() {
    if (isDesktop()) {
      var mini = stored("etSidebarMini", "") === "1";
      save("etSidebarMini", mini ? "" : "1");
      sidebarMini();
    } else {
      var w = wrapper();
      if (w && w.classList.contains(MOBILE_OPEN_CLASS)) { closeMobileSidebar(); } else { openMobileSidebar(); }
    }
  }

  function applyTheme(theme) {
    document.documentElement.setAttribute("data-bs-theme", theme);
    var toggles = document.querySelectorAll("[data-theme-toggle]");
    toggles.forEach(function (el) {
      var icon = el.querySelector("i");
      if (icon) {
        icon.classList.toggle("ti-moon", theme === "light");
        icon.classList.toggle("ti-sun", theme !== "light");
      }
      var label = el.querySelector("[data-theme-label]");
      if (label) label.textContent = theme === "light" ? "Modo oscuro" : "Modo claro";
    });
  }

  function initTheme() {
    applyTheme(stored("etTheme", "light"));
    document.querySelectorAll("[data-theme-toggle]").forEach(function (el) {
      if (el.dataset.themeWired) return;
      el.dataset.themeWired = "1";
      el.addEventListener("click", function (e) {
        e.preventDefault();
        var next = document.documentElement.getAttribute("data-bs-theme") === "dark" ? "light" : "dark";
        save("etTheme", next);
        applyTheme(next);
      });
    });
  }

  function initSidebar() {
    sidebarMini();
    document.querySelectorAll(".sidebartoggler").forEach(function (el) {
      if (el.dataset.shellWired) return;
      el.dataset.shellWired = "1";
      el.addEventListener("click", function (e) {
        e.preventDefault();
        toggleSidebar();
      });
    });
  }

  function activateSourceTab(container, slug) {
    var btn = container.querySelector('[data-tab-slug="' + slug + '"]');
    if (!btn || btn.classList.contains("active")) { return; }
    if (window.bootstrap && window.bootstrap.Tab) {
      window.bootstrap.Tab.getOrCreateInstance(btn).show();
    } else {
      btn.click();
    }
  }

  function initSourceTabs() {
    document.querySelectorAll("[data-source-tabs]").forEach(function (container) {
      var id = container.getAttribute("data-source-tabs");
      if (!id) { return; }
      var key = "etSourceTab:" + id;
      if (!container.dataset.sourceTabsWired) {
        container.dataset.sourceTabsWired = "1";
        container.addEventListener("shown.bs.tab", function (event) {
          var slug = event.target.getAttribute("data-tab-slug");
          if (slug) { saveSession(key, slug); }
        });
      }
      var saved = storedSession(key, "");
      if (saved) { activateSourceTab(container, saved); }
    });
  }

  function init() { initTheme(); initSidebar(); initSourceTabs(); }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
  window.matchMedia(DESKTOP).addEventListener("change", sidebarMini);
})();

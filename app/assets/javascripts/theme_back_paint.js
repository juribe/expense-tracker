(function () {
  // Back-paint the stored theme before CSS to avoid a light flash.
  try {
    var t = localStorage.getItem("etTheme");
    if (t) document.documentElement.setAttribute("data-bs-theme", t);
  } catch (e) { /* noop */ }
})();

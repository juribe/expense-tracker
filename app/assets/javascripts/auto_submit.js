(function () {
  // Delegated auto-submit: elements marked data-auto-submit re-send their
  // form on change (replaces inline onchange="this.form.submit()").
  document.addEventListener("change", function (e) {
    var el = e.target.closest("[data-auto-submit]");
    if (!el) return;
    if (el.form) el.form.requestSubmit();
  });
})();

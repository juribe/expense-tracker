(function () {
  // Delegated trigger: a buttón click proxies to the declared element.
  document.addEventListener("click", function (e) {
    var el = e.target.closest("[data-click-target-id]");
    if (!el) return;
    var target = document.getElementById(el.dataset.clickTargetId);
    if (target) target.click();
  });

  // Delegated confirmation for destructive links (replaces inline onclick).
  document.addEventListener("click", function (e) {
    var el = e.target.closest("[data-reset-confirm]");
    if (!el) return;
    if (!window.confirm(el.dataset.resetConfirm)) {
      e.preventDefault();
      e.stopPropagation();
    }
  });
})();

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
    if (el.dataset.resetConfirmBypass === "true") {
      delete el.dataset.resetConfirmBypass;
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    var msg = el.dataset.resetConfirm;
    Dialog.confirm(msg, { title: "Confirmar", confirmLabel: "Confirmar", variant: "warning" }).then(function (confirmed) {
      if (!confirmed) return;
      el.dataset.resetConfirmBypass = "true";
      el.click();
    });
  });
})();

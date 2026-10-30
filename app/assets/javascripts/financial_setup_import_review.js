(function () {
  // Delegated on document so it works no matter how the page was rendered
  // (full load or Turbo visit) — per-element DOMContentLoaded listeners were
  // missing the first click after Turbo restores/renders the page. The window
  // guard keeps the handler from being attached twice.
  if (window.__importRemoveBound) return;
  window.__importRemoveBound = true;

  document.addEventListener('click', function (e) {
    var btn = e.target.closest('.import-remove');
    if (!btn) return;

    var msg = btn.dataset.confirm || 'Remove this account?';
    e.preventDefault();
    Dialog.confirm(msg, { title: "Confirmar", confirmLabel: "Eliminar", variant: "danger" }).then(function (confirmed) {
      if (!confirmed) return;
      // Hide the account card and clear its keep field so it's dropped on confirm.
      var card = btn.closest('.card');
      if (!card) return;
      card.classList.add('d-none');
      var keepInput = card.querySelector('input[name^="keep["]');
      if (keepInput) keepInput.value = '';
    });
  });
})();

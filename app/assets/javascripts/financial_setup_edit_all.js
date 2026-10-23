(function () {
  if (window.__editRowsBound) return;
  window.__editRowsBound = true;

  // Delegated on document so the buttons keep working after Turbo renders.
  document.addEventListener('click', function (e) {
    var addBtn = e.target.closest('#addAnotherRow');
    if (addBtn) {
      var container = document.getElementById('manualRows');
      var template = document.getElementById('manualRowTemplate');
      if (!container || !template) return;
      var idx = container.querySelectorAll('.manual-row').length;
      var html = template.innerHTML.replaceAll('{IDX}', idx);
      container.insertAdjacentHTML('beforeend', html);
      if (window.MoneyInputs) MoneyInputs.init();
      return;
    }

    var removeBtn = e.target.closest('.remove-row');
    if (removeBtn) {
      var row = removeBtn.closest('.manual-row');
      if (row) row.remove();
    }
  });
})();

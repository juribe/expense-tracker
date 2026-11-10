(function () {
  if (window.__financialSetupGmfExemptionBound) return;
  window.__financialSetupGmfExemptionBound = true;

  function boxes() {
    return Array.from(document.querySelectorAll('[data-gmf-exempt]'));
  }

  // Only one account may be exempt. When one is checked, the rest are
  // disabled so the form can never submit two marks. If the server already
  // has an exempt account, every switch stays disabled.
  function sync() {
    var all = boxes();
    if (all.length === 0) return;

    var locked = all.some(function (box) {
      return box.dataset.gmfExemptLocked === 'true';
    });

    if (locked) {
      all.forEach(function (box) {
        box.checked = false;
        box.disabled = true;
      });
      return;
    }

    var checked = all.filter(function (box) { return box.checked; });

    // Legacy drafts could contain more than one mark; keep the first.
    if (checked.length > 1) {
      checked.slice(1).forEach(function (box) { box.checked = false; });
      checked = [ checked[0] ];
    }

    all.forEach(function (box) {
      box.disabled = checked.length > 0 && !box.checked;
    });
  }

  document.addEventListener('change', function (event) {
    if (!event.target.matches('[data-gmf-exempt]')) return;
    sync();
  });

  document.addEventListener('financial-setup:gmf-refresh', sync);

  function observeRows() {
    var container = document.getElementById('manualRows');
    if (!container || container.dataset.gmfExemptionObserved === 'true') return;

    container.dataset.gmfExemptionObserved = 'true';
    new MutationObserver(sync).observe(container, { childList: true });
  }

  function init() {
    sync();
    observeRows();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();

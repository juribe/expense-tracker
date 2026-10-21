(function () {
  // Import preview: rows whose category the user picks become "ready";
  // the header counters reflect what will actually be imported. Rows with
  // kind/amount problems never have a dropdown, so they stay excluded.
  function bind(root) {
    root.querySelectorAll("[data-imports-preview='true']").forEach(initPage);
  }

  function initPage(container) {
    if (container.dataset.importsPreviewBound === "true") return;
    container.dataset.importsPreviewBound = "true";

    update(container);
    container.addEventListener("change", function (event) {
      var select = event.target.closest("[data-testid='preview-category-select']");
      if (!select) return;

      var row = select.closest("[data-testid='preview-row']");
      setStatus(row, select.value !== "");
      update(container);
    });
  }

  function update(container) {
    var ready = 0;

    container.querySelectorAll("[data-testid='preview-row']").forEach(function (row) {
      var select = row.querySelector("[data-testid='preview-category-select']");
      var isReady = select ? select.value !== "" : false;

      if (isReady) ready++;
      setStatus(row, isReady);
    });

    var total = container.querySelectorAll("[data-testid='preview-row']").length;
    var readyCount = container.querySelector("[data-testid='preview-ready-count']");
    var errorCount = container.querySelector("[data-testid='preview-error-count']");
    if (readyCount) readyCount.textContent = String(ready);
    if (errorCount) errorCount.textContent = String(total - ready);
  }

  function setStatus(row, isReady) {
    if (!row) return;

    var badge = row.querySelector("[data-testid='preview-row-status']");

    if (badge) {
      badge.classList.toggle("bg-success", isReady);
      badge.classList.toggle("bg-secondary", !isReady);
      badge.textContent = isReady ? badge.dataset.labelReady : badge.dataset.labelError;
    }

    row.dataset.status = isReady ? "ok" : "error";
  }

  document.addEventListener("DOMContentLoaded", function () {
    bind(document);
  });

  document.addEventListener("turbo:load", function () {
    bind(document);
  });
})();

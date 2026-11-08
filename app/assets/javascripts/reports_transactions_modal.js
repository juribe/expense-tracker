// Reports: open the shared transactions modal from any drill-down trigger and
// sort its table client-side without a page reload.
(function () {
  var MODAL_ID = "reportTransactionsModal";
  var TRIGGER_SELECTOR = "[data-transactions-modal-url]";
  var SORT_SELECTOR = "[data-sortable-table] [data-sort-key]";

  function modalElement() {
    return document.getElementById(MODAL_ID);
  }

  function modalBody() {
    return document.querySelector("[data-report-transactions-body]");
  }

  function renderMessage(body, message) {
    body.innerHTML = '<p class="text-danger mb-0"></p>';
    body.querySelector("p").textContent = message || "";
  }

  function showLoading(modal, body) {
    body.innerHTML = '<div class="text-center text-muted py-4">' +
      '<div class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></div>' +
      '<p class="mt-2 mb-0"></p></div>';
    body.querySelector("p").textContent = modal.dataset.transactionsLoading || "";
  }

  function open(url) {
    var modal = modalElement();
    var body = modalBody();

    if (!modal || !body || !window.bootstrap) {
      window.location.href = url;
      return;
    }

    showLoading(modal, body);
    window.bootstrap.Modal.getOrCreateInstance(modal).show();

    var fetchUrl = new URL(url, window.location.href);
    fetchUrl.searchParams.set("modal", "1");

    fetch(fetchUrl.toString(), {
      headers: { "Accept": "text/html" },
      credentials: "same-origin"
    })
      .then(function (response) {
        if (!response.ok) throw new Error("request failed");
        return response.text();
      })
      .then(function (html) {
        body.innerHTML = html;
      })
      .catch(function () {
        renderMessage(body, modal.dataset.transactionsError);
      });
  }

  var collator;
  try {
    collator = new Intl.Collator("es", { numeric: true, sensitivity: "base" });
  } catch (error) {
    collator = null;
  }

  function compareValues(a, b, type) {
    if (type === "number") {
      var numberA = parseFloat(a);
      var numberB = parseFloat(b);
      return (isNaN(numberA) ? 0 : numberA) - (isNaN(numberB) ? 0 : numberB);
    }
    if (type === "date") {
      return a < b ? -1 : (a > b ? 1 : 0);
    }
    if (collator) return collator.compare(a, b);
    return a.localeCompare(b);
  }

  function sortTable(button) {
    var table = button.closest("[data-sortable-table]");
    var header = button.closest("th");
    var tbody = table && table.tBodies[0];
    if (!table || !header || !tbody) return;

    var ascending = header.getAttribute("aria-sort") !== "ascending";
    var direction = ascending ? 1 : -1;
    var column = header.cellIndex;
    var type = button.dataset.sortType || "text";

    table.querySelectorAll("thead th").forEach(function (cell) {
      cell.setAttribute("aria-sort", "none");
      var icon = cell.querySelector("[data-sort-icon]");
      if (icon) icon.className = "ti ti-arrows-sort";
    });

    header.setAttribute("aria-sort", ascending ? "ascending" : "descending");
    var activeIcon = header.querySelector("[data-sort-icon]");
    if (activeIcon) activeIcon.className = "ti " + (ascending ? "ti-sort-ascending" : "ti-sort-descending");

    Array.prototype.slice.call(tbody.rows)
      .sort(function (rowA, rowB) {
        var valueA = rowA.cells[column] ? rowA.cells[column].getAttribute("data-sort-value") || "" : "";
        var valueB = rowB.cells[column] ? rowB.cells[column].getAttribute("data-sort-value") || "" : "";
        return compareValues(valueA, valueB, type) * direction;
      })
      .forEach(function (row) {
        tbody.appendChild(row);
      });
  }

  function handleTrigger(event) {
    var trigger = event.target.closest(TRIGGER_SELECTOR);
    if (!trigger) return false;
    if (event.defaultPrevented || event.button !== 0 ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false;

    var url = trigger.getAttribute("data-transactions-modal-url");
    if (!url) return false;

    event.preventDefault();
    open(url);
    return true;
  }

  document.addEventListener("click", function (event) {
    if (handleTrigger(event)) return;

    var button = event.target.closest(SORT_SELECTOR);
    if (!button) return;

    event.preventDefault();
    sortTable(button);
  });

  window.ReportsTransactionsModal = { open: open };
})();

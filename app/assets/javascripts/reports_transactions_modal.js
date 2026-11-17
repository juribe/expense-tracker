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

  var lastTrigger = null;

  function focusableTrigger(target) {
    if (!target) return null;
    var selector = "a[href], button, input, select, textarea, [tabindex]:not([tabindex='-1'])";
    if (target.matches && target.matches(selector)) return target;
    return target.querySelector ? target.querySelector(selector) : null;
  }

  // Bootstrap 5.3 does not return focus to the opener when the modal closes,
  // so aria-hidden ends up on a container whose close button still has focus.
  // Move focus out before that happens; the opener is restored when it can
  // take focus, otherwise focus falls back to the document body.
  function restoreFocus(modal) {
    var target = focusableTrigger(lastTrigger);
    lastTrigger = null;

    // Leave the modal before aria-hidden is applied, then restore the opener.
    // The focus trap is still active during the hide event, so focusing the
    // opener immediately would be pulled back to the modal close button.
    if (modal.contains(document.activeElement)) document.activeElement.blur();

    window.setTimeout(function () {
      if (target && document.body.contains(target)) target.focus();
    }, 0);
  }

  function prepareFocusRestore(modal) {
    if (modal.dataset.focusRestoreBound === "true") return;

    modal.dataset.focusRestoreBound = "true";
    modal.addEventListener("hide.bs.modal", function () {
      restoreFocus(modal);
    });
  }

  function showLoading(modal, body) {
    body.innerHTML = '<div class="text-center text-muted py-4">' +
      '<div class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></div>' +
      '<p class="mt-2 mb-0"></p></div>';
    body.querySelector("p").textContent = modal.dataset.transactionsLoading || "";
  }

  function open(url, trigger) {
    var modal = modalElement();
    var body = modalBody();

    if (!modal || !body || !window.bootstrap) {
      window.location.href = url;
      return;
    }

    lastTrigger = trigger || document.activeElement;
    prepareFocusRestore(modal);

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

    syncCardOrder(table);
  }

  // The phone cards render the same transactions as the table. When the table
  // is sorted, mirror that order in the card list so both stay consistent.
  function syncCardOrder(table) {
    var list = table.closest("[data-report-transactions-list]");
    var cards = list && list.querySelector("[data-report-transactions-cards]");
    if (!cards) return;

    var cardsByKey = {};
    Array.prototype.slice.call(cards.children).forEach(function (card) {
      cardsByKey[card.getAttribute("data-transaction-key")] = card;
    });

    Array.prototype.slice.call(table.tBodies[0].rows).forEach(function (row) {
      var card = cardsByKey[row.getAttribute("data-transaction-key")];
      if (card) cards.appendChild(card);
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
    open(url, trigger);
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

// Statement imports
// Client-side helpers for the "Create statement expenses" form:
//   - submit guard: a movement marked for creation must have a category
//   - select all / deselect all and a live selection count
//   - bulk category: assign one category to every selected movement via a modal
//   - pay-only mode: collapse the movements so the user can register just the
//     statement payment without importing any expense
//
// Expected markup: form[data-movement-form="true"] with rows
// [data-movement-row] holding a [data-movement-select="true"] checkbox and a
// [data-movement-category="true"] select, an optional [data-movement-select-all],
// [data-movement-selection-count], [data-movement-body], [data-movement-submit],
// [data-movement-pay-only], a [data-movement-error] target and a
// #bulkCategoryModal with [data-movement-bulk-category] / [data-movement-bulk-apply].
(function () {
  var FORM_SELECTOR = '[data-movement-form="true"]';

  function form() {
    return document.querySelector(FORM_SELECTOR);
  }

  function rows(scope) {
    return Array.prototype.slice.call(scope.querySelectorAll("[data-movement-row]"));
  }

  function selectedRows(scope) {
    return rows(scope).filter(function (row) {
      var checkbox = row.querySelector("[data-movement-select='true']");
      return checkbox && checkbox.checked;
    });
  }

  function fillTemplate(element, count) {
    if (!element) return;
    element.textContent = count > 0 ? element.dataset.template.replace("__COUNT__", count) : "";
  }

  function updateSelection(scope) {
    var selected = selectedRows(scope).length;
    fillTemplate(scope.querySelector("[data-movement-selection-count]"), selected);

    var all = scope.querySelector("[data-movement-select-all]");
    if (all) {
      var total = rows(scope).length;
      all.checked = selected > 0 && selected === total;
      all.indeterminate = selected > 0 && selected < total;
    }

    var bulkOpen = scope.querySelector("[data-movement-bulk-open]");
    if (bulkOpen) bulkOpen.disabled = selected === 0;
  }

  function clearError(scope) {
    var error = scope.querySelector("[data-movement-error]");
    if (error) error.classList.add("d-none");
  }

  function uncategorizedSelected(scope) {
    return selectedRows(scope).filter(function (row) {
      var select = row.querySelector("[data-movement-category='true']");
      return select && select.value === "";
    });
  }

  function openBulk(scope) {
    var modal = document.getElementById("bulkCategoryModal");
    if (!modal) return;

    fillTemplate(modal.querySelector("[data-movement-bulk-count]"), selectedRows(scope).length);
    var category = modal.querySelector("[data-movement-bulk-category]");
    if (category) category.value = "";
    window.bootstrap.Modal.getOrCreateInstance(modal).show();
  }

  function applyBulk(scope) {
    var modal = document.getElementById("bulkCategoryModal");
    var category = modal && modal.querySelector("[data-movement-bulk-category]");
    if (!category || category.value === "") return;

    selectedRows(scope).forEach(function (row) {
      var select = row.querySelector("[data-movement-category='true']");
      if (!select) return;

      select.value = category.value;
      select.dispatchEvent(new Event("change", { bubbles: true }));
    });

    window.bootstrap.Modal.getOrCreateInstance(modal).hide();
    updateSelection(scope);
  }

  function togglePayOnly(scope) {
    var button = scope.querySelector("[data-movement-pay-only]");
    var active = scope.dataset.payOnly === "true";
    var next = !active;
    scope.dataset.payOnly = next ? "true" : "false";

    var body = scope.querySelector("[data-movement-body]");
    var submit = scope.querySelector("[data-movement-submit]");
    var hint = scope.querySelector("[data-movement-pay-only-hint]");
    var label = scope.querySelector("[data-movement-pay-only-label]");

    if (body) body.classList.toggle("d-none", next);
    if (submit) submit.classList.toggle("d-none", next);
    if (hint) hint.classList.toggle("d-none", !next);
    if (label && button) {
      label.textContent = next ? button.dataset.movementPayOnlyActive : button.dataset.movementPayOnlyInactive;
    }
  }

  function bind(scope) {
    if (scope.dataset.movementBound === "true") return;
    scope.dataset.movementBound = "true";

    var error = scope.querySelector("[data-movement-error]");

    scope.addEventListener("submit", function (event) {
      var invalid = uncategorizedSelected(scope);
      if (invalid.length === 0) return;

      event.preventDefault();
      invalid.forEach(function (row) { row.classList.add("table-danger"); });
      if (error) {
        error.textContent = error.getAttribute("data-movement-error-message") || "";
        error.classList.remove("d-none");
      }
    });

    scope.addEventListener("change", function (event) {
      if (error) error.classList.add("d-none");
      var row = event.target.closest && event.target.closest("[data-movement-row]");
      if (row) row.classList.remove("table-danger");

      if (event.target.matches("[data-movement-select-all]")) {
        var checked = event.target.checked;
        rows(scope).forEach(function (item) {
          var checkbox = item.querySelector("[data-movement-select='true']");
          if (checkbox) checkbox.checked = checked;
        });
      }
      if (event.target.matches("[data-movement-select-all], [data-movement-select]")) {
        updateSelection(scope);
      }
    });

    updateSelection(scope);
  }

  function bindControls() {
    if (document.dataset.movementControlsBound === "true") return;
    document.dataset.movementControlsBound = "true";

    document.addEventListener("click", function (event) {
      var scope = form();
      if (!scope) return;

      if (event.target.closest("[data-movement-bulk-open]")) {
        openBulk(scope);
      } else if (event.target.closest("[data-movement-bulk-apply]")) {
        applyBulk(scope);
      } else if (event.target.closest("[data-movement-pay-only]")) {
        togglePayOnly(scope);
      }
    });
  }

  function init() {
    document.querySelectorAll(FORM_SELECTOR).forEach(bind);
    bindControls();
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
})();

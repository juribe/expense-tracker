(function () {
  var payloadRoot = document.querySelector("[data-monthly-expenses-ui-payload]");
  var P = payloadRoot ? JSON.parse(payloadRoot.dataset.monthlyExpensesUiPayload) : {};
(function () {
  if (window.RecurringUI) return;

  var formModal, processModal;
  var currentRow = null;

  function $(sel) { return document.querySelector(sel); }

  function initModals() {
    formModal = bootstrap.Modal.getOrCreateInstance("#recurringFormModal");
    processModal = bootstrap.Modal.getOrCreateInstance("#processModal");
  }

  function setFormMode(mode, row) {
  var isEdit = mode === "edit";
  var form = $("#recurringForm");

  $("#recurringFormTitle").textContent =
    isEdit ? "Edit Monthly Expense" : "Add Monthly Expense";

  // Always refresh CSRF token
  var csrfMeta = document.querySelector('meta[name="csrf-token"]');
  var csrfInput = form.querySelector('input[name="authenticity_token"]');

  if (csrfMeta) {
    if (!csrfInput) {
      csrfInput = document.createElement("input");
      csrfInput.type = "hidden";
      csrfInput.name = "authenticity_token";
      form.appendChild(csrfInput);
    }

    csrfInput.value = csrfMeta.content;
  }

  var methodInput = form.querySelector('input[name="_method"]');

  if (isEdit) {
    if (!methodInput) {
      methodInput = document.createElement("input");
      methodInput.type = "hidden";
      methodInput.name = "_method";
      form.appendChild(methodInput);
    }

    methodInput.value = "patch";

    form.action = row.dataset.editUrl;

    CategoryPicker.setValue(
      $("#recurring_template_category_id"),
      row.dataset.categoryId
    );

    $("#recurring_template_description").value =
      row.dataset.description || "";

    $("#recurring_template_amount").value =
      String(row.dataset.amount).replace(".", ",");

    if (window.MoneyInputs) {
      window.MoneyInputs.formatField(
        $("#recurring_template_amount"),
        true
      );
    }

    $("#recurring_template_payment_day").value =
      row.dataset.paymentDay;

    $("#recurring_active_switch").checked =
      row.dataset.active === "true";

  } else {
    if (methodInput) {
      methodInput.remove();
    }

    form.action = P.create_url;
    form.reset();
    $("#recurring_active_switch").checked = true;
  }
}

  window.RecurringUI = {
    openFormModal: function (mode, row) {
      initModals();
      setFormMode(mode, row);
      formModal.show();
    },

    openProcessModal: function (row) {
      initModals();
      currentRow = row;

      $("#processCategory").textContent =
        row.querySelector("td .badge").textContent;
      $("#processDescription").textContent =
        row.dataset.description || row.cells[1].textContent.trim();
      $("#processConfiguredAmount").textContent = row.cells[2].textContent.trim();

      var configuredAmount = Number(row.dataset.amount) || 0;
      var paidSoFar = Number(row.dataset.paidAmount) || 0;
      var remaining = Math.max(configuredAmount - paidSoFar, 0);
      if (remaining <= 0) remaining = configuredAmount;
      $("#processPaidSoFar").textContent = "$" + paidSoFar.toFixed(2);
      var markCheckbox = $("#processMarkAsPaid");
      if (markCheckbox) markCheckbox.checked = false;

      var today = new Date();
      var pad = function (n) { return String(n).padStart(2, "0"); };
      $("#processDate").value = today.getFullYear() + "-" + pad(today.getMonth() + 1) + "-" + pad(today.getDate());
      $("#processAmount").value =
        remaining.toFixed(2).replace(".", ",");
      if (window.MoneyInputs) window.MoneyInputs.formatField($("#processAmount"), true);

      // Preselect the template's source, but only when it is one of the
      // payment sources offered (debt cuota sources — loans — stay blank so
      // the user must pick where the money comes from).
      var sourceSelect = $("#processMoneySource");
      var templateSource = row.dataset.moneySourceId || "";
      sourceSelect.value = Array.prototype.slice.call(sourceSelect.options)
                                           .some(function (o) { return o.value === templateSource; })
        ? templateSource
        : "";

      var form = $("#processForm");
      form.action = row.dataset.processUrl;

      if (!form.querySelector('input[name="authenticity_token"]')) {
        var token = document.querySelector('meta[name="csrf-token"]');
        var input = document.createElement("input");
        input.type = "hidden";
        input.name = "authenticity_token";
        input.value = token ? token.content : "";
        form.appendChild(input);
      }

      processModal.show();
    },

    confirmDelete: function (button) {
      initModals();
      currentRow = button.closest("tr");
      var title = (P.delete_title || "¿Eliminar gasto recurrente?");
      var message = (P.delete_body || "¿Estás seguro?");
      Dialog.confirm(message, { title: title, confirmLabel: "Eliminar", variant: "danger" }).then(function (confirmed) {
        if (!confirmed || !currentRow) return;
        var form = document.createElement("form");
        form.method = "post";
        form.action = currentRow.dataset.deleteUrl;
        form.innerHTML =
          '<input type="hidden" name="_method" value="delete">' +
          '<input type="hidden" name="authenticity_token" value="' +
          (document.querySelector('meta[name="csrf-token"]') || {}).content + '">';
        document.body.appendChild(form);
        form.submit();
      });
    },

    toggleActive: function (button) {
      var row = button.closest("tr");
      var form = document.createElement("form");
      form.method = "post";
      form.action = row.dataset.toggleUrl;
      form.innerHTML =
        '<input type="hidden" name="_method" value="patch">' +
        '<input type="hidden" name="authenticity_token" value="' +
        (document.querySelector('meta[name="csrf-token"]') || {}).content + '">';
      document.body.appendChild(form);
      form.submit();
    }
  };

  document.addEventListener("DOMContentLoaded", function () {
    var tooltips = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltips.forEach(function (el) { new bootstrap.Tooltip(el); });
  });
})();
  document.addEventListener("click", function (e) {
    var trigger = e.target.closest("[data-rt-action]");
    if (!trigger || !window.RecurringUI) return;
    var action = trigger.dataset.rtAction;
    if (action === "create") RecurringUI.openFormModal("create");
    else if (action === "edit") RecurringUI.openFormModal("edit", trigger.closest("tr"));
    else if (action === "toggle") RecurringUI.toggleActive(trigger);
    else if (action === "delete") RecurringUI.confirmDelete(trigger);
    else if (action === "process") RecurringUI.openProcessModal(trigger.closest("tr"));
  });

  // Auto-open the form after re-render on validation failure.
  var pageRoot = document.querySelector("[data-auto-open-form-modal]");
  if (pageRoot && window.RecurringUI && pageRoot.dataset.autoOpenFormModal) {
    RecurringUI.openFormModal(pageRoot.dataset.autoOpenFormModal);
  }
})();

// Client-side sorting for the recurring-expenses table. The sort headers
// keep their href as a no-JS fallback; the delegated capture listener stops
// Turbo before it can replace the page.
(function () {
  if (window.RecurringSort) return;
  window.RecurringSort = true;

  var STATUS_RANKS = { pending: 0, completed: 1, inactive: 2 };

  function compareRows(left, right, column) {
    var leftValue = valueFor(left, column);
    var rightValue = valueFor(right, column);

    if (typeof leftValue === "number" && typeof rightValue === "number") {
      return leftValue - rightValue;
    }

    return String(leftValue).localeCompare(String(rightValue), "es", {
      sensitivity: "base",
      numeric: true
    });
  }

  function valueFor(row, column) {
    if (column === "category") return row.dataset.categoryName || "";
    if (column === "description") return row.dataset.description || "";
    if (column === "amount") return parseFloat(row.dataset.amount) || 0;
    if (column === "payment_day") {
      return row.dataset.paymentDay ? parseInt(row.dataset.paymentDay, 10) : Number.MAX_SAFE_INTEGER;
    }
    if (column === "status") {
      var rank = STATUS_RANKS[row.dataset.status];
      return rank === undefined ? 3 : rank;
    }
    return "";
  }

  function sortTable(table, column, direction) {
    var tbody = table.tBodies[0];
    if (!tbody) return;

    var rows = [].slice.call(tbody.rows);
    rows.sort(function (left, right) {
      var result = compareRows(left, right, column);
      return direction === "desc" ? -result : result;
    });

    rows.forEach(function (row) { tbody.appendChild(row); });
  }

  function updateLinks(column, direction) {
    var links = [].slice.call(document.querySelectorAll("[data-recurring-sort-column]"));

    links.forEach(function (link) {
      var active = link.dataset.recurringSortColumn === column;
      link.classList.toggle("active", active);
      link.dataset.recurringSortDirection =
        active && direction === "asc" ? "desc" : "asc";

      var header = link.closest("th");
      if (header) {
        header.setAttribute("aria-sort", active ? (direction === "asc" ? "ascending" : "descending") : "none");
      }

      var icon = link.querySelector(".ti");
      if (!icon) return;

      icon.classList.remove("ti-arrow-up", "ti-arrow-down", "ti-arrows-sort", "text-secondary");
      if (active) {
        icon.classList.add(direction === "asc" ? "ti-arrow-up" : "ti-arrow-down");
      } else {
        icon.classList.add("ti-arrows-sort", "text-secondary");
      }
    });
  }

  function syncFilterFields(column, direction) {
    var sortField = document.querySelector("input[name='sort']");
    var directionField = document.querySelector("input[name='dir']");
    if (sortField) sortField.value = column;
    if (directionField) directionField.value = direction;
  }

  function updateUrl(column, direction) {
    if (!window.history || !window.history.pushState) return;

    var url = new URL(window.location.href);
    url.searchParams.set("sort", column);
    url.searchParams.set("dir", direction);
    window.history.pushState({}, "", url);
  }

  function applyFromUrl() {
    var params = new URLSearchParams(window.location.search);
    var column = params.get("sort");
    var table = document.querySelector("[data-testid='recurring-table']");
    if (!table || !column) return;

    var direction = params.get("dir") === "desc" ? "desc" : "asc";
    sortTable(table, column, direction);
    updateLinks(column, direction);
    syncFilterFields(column, direction);
  }

  document.addEventListener("click", function (event) {
    var link = event.target.closest("[data-recurring-sort-column]");
    if (!link) return;
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    var table = document.querySelector("[data-testid='recurring-table']");
    if (!table) return;

    event.preventDefault();
    event.stopPropagation();

    var column = link.dataset.recurringSortColumn;
    var direction = link.dataset.recurringSortDirection === "desc" ? "desc" : "asc";
    sortTable(table, column, direction);
    updateLinks(column, direction);
    syncFilterFields(column, direction);
    updateUrl(column, direction);
  }, true);

  window.addEventListener("popstate", applyFromUrl);
})();

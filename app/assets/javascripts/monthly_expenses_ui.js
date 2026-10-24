(function () {
  var payloadRoot = document.querySelector("[data-monthly-expenses-ui-payload]");
  var P = payloadRoot ? JSON.parse(payloadRoot.dataset.monthlyExpensesUiPayload) : {};
(function () {
  if (window.RecurringUI) return;

  var formModal, processModal, deleteModal;
  var currentRow = null;

  function $(sel) { return document.querySelector(sel); }

  function initModals() {
    formModal = bootstrap.Modal.getOrCreateInstance("#recurringFormModal");
    processModal = bootstrap.Modal.getOrCreateInstance("#processModal");
    deleteModal = bootstrap.Modal.getOrCreateInstance("#deleteRtModal");
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
      $("#processDescription").textContent = row.cells[1].textContent.trim();
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
      deleteModal.show();
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

  document.addEventListener("click", function (e) {
    if (e.target.id !== "confirmDeleteRt" || !currentRow) return;
    var form = document.createElement("form");
    form.method = "post";
    form.action = currentRow.dataset.deleteUrl;
    form.innerHTML =
      '<input type="hidden" name="_method" value="delete">' +
      '<input type="hidden" name="authenticity_token" value="' +
      (document.querySelector('meta[name="csrf-token"]') || {}).content + '">';
    document.body.appendChild(form);
    deleteModal.hide();
    form.submit();
  });

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

(function () {
  // Expense candidates queue: row selection, bulk action modals and the
  // discard confirmation. Bulk updates reuse the existing PATCH/POST endpoints
  // rendered by the view; this file only handles presentation and selection.

  var SELECTION_STORAGE_KEY = "expenseCandidatesSelection";

  function payload() {
    var el = document.querySelector("[data-candidates-table-payload]");
    return el ? JSON.parse(el.dataset.candidatesTablePayload) : {};
  }

  function rowElements() {
    return Array.prototype.slice.call(document.querySelectorAll("[data-candidate-row]"));
  }

  function selectedIds() {
    var ids = {};
    rowElements().forEach(function (el) {
      var checkbox = el.querySelector(".row-check");
      if (checkbox && checkbox.checked) ids[el.dataset.id] = true;
    });
    return Object.keys(ids);
  }

  function rowForId(id) {
    return rowElements().filter(function (el) { return el.dataset.id === id; })[0];
  }

  function syncDuplicateCheckboxes(id, checked) {
    Array.prototype.slice.call(document.querySelectorAll(".row-check")).forEach(function (checkbox) {
      if (checkbox.value === id) checkbox.checked = checked;
    });
  }

  function updateBulk() {
    var bar = document.getElementById("bulkBar");
    if (!bar) return;

    var ids = selectedIds();
    var count = ids.length;
    var hasSelection = count > 0;
    var data = payload();

    bar.classList.toggle("d-none", !hasSelection);
    var selectedLabel = count === 1
      ? (data.selected_label_singular || "seleccionado")
      : (data.selected_label || "seleccionados");
    document.getElementById("bulkCount").textContent = count + " " + selectedLabel;

    ["bulkCategory", "bulkSource", "bulkConfirm", "bulkDiscard"].forEach(function (id) {
      var button = document.getElementById(id);
      if (button) button.disabled = !hasSelection;
    });

    rowElements().forEach(function (el) {
      var selected = ids.indexOf(el.dataset.id) !== -1;
      el.classList.toggle("selected", selected);
    });

    var total = {};
    rowElements().forEach(function (el) { total[el.dataset.id] = true; });
    var totalCount = Object.keys(total).length;
    ["selectAll", "selectAllMobile"].forEach(function (id) {
      var selectAll = document.getElementById(id);
      if (!selectAll) return;
      selectAll.checked = totalCount > 0 && count === totalCount;
      selectAll.indeterminate = count > 0 && count < totalCount;
    });
  }

  function selectAllRows(checked) {
    Array.prototype.slice.call(document.querySelectorAll(".row-check")).forEach(function (checkbox) {
      checkbox.checked = checked;
    });
  }

  function clearSelection() {
    selectAllRows(false);
    updateBulk();
  }

  function persistSelection() {
    try {
      window.sessionStorage.setItem(SELECTION_STORAGE_KEY, JSON.stringify(selectedIds()));
    } catch (error) {
      // Private browsing can block storage; selection simply is not restored.
    }
  }

  function clearPersistedSelection() {
    try {
      window.sessionStorage.removeItem(SELECTION_STORAGE_KEY);
    } catch (error) {
      // Nothing to clear when storage is unavailable.
    }
  }

  // Category and source updates reload the page. Restoring the checked rows
  // after the redirect keeps the batch ready for the next bulk action.
  function restorePersistedSelection() {
    var raw;
    try {
      raw = window.sessionStorage.getItem(SELECTION_STORAGE_KEY);
    } catch (error) {
      return;
    }
    if (!raw) return;

    clearPersistedSelection();

    var ids;
    try {
      ids = JSON.parse(raw);
    } catch (error) {
      return;
    }
    if (!Array.isArray(ids)) return;

    ids.forEach(function (id) { syncDuplicateCheckboxes(id, true); });
  }

  function showModal(id) {
    var element = document.getElementById(id);
    if (!element || !window.bootstrap) return;
    window.bootstrap.Modal.getOrCreateInstance(element).show();
  }

  function resetCategoryPicker(selectId) {
    var select = document.getElementById(selectId);
    if (select && window.CategoryPicker) window.CategoryPicker.setValue(select, "");
  }

  function openCategoryModal() {
    var ids = selectedIds();
    if (!ids.length) return;

    document.getElementById("bulkCategoryCandidateIds").value = ids.join(",");
    resetCategoryPicker("bulkCategorySelect");
    showModal("bulkCategoryModal");
  }

  function openSourceModal() {
    var ids = selectedIds();
    if (!ids.length) return;

    document.getElementById("bulkSourceCandidateIds").value = ids.join(",");
    var select = document.getElementById("bulkSourceSelect");
    if (select) select.value = "";
    showModal("bulkSourceModal");
  }

  function missingFieldLabels() {
    return payload().missing_labels || {};
  }

  function unresolvableMissing(row) {
    var assignable = ["category_id", "money_source_id"];
    return (row.dataset.missingFields || "")
      .split(/\s+/)
      .filter(function (field) { return field && assignable.indexOf(field) === -1; });
  }

  function descriptionFor(row) {
    var description = row.querySelector(".candidate-description");
    return description ? description.textContent.trim() : row.dataset.id;
  }

  function blockedCandidates(ids) {
    var labels = missingFieldLabels();
    var blocked = [];

    ids.forEach(function (id) {
      var row = rowForId(id);
      if (!row) return;
      var fields = unresolvableMissing(row);
      if (!fields.length) return;

      var fieldNames = fields.map(function (field) { return labels[field] || field; }).join(", ");
      blocked.push(descriptionFor(row) + " (" + fieldNames + ")");
    });

    return blocked;
  }

  function openConfirmModal() {
    var ids = selectedIds();
    if (!ids.length) return;

    document.getElementById("bulkCandidateIds").value = ids.join(",");
    resetCategoryPicker("bulkConfirmCategorySelect");
    var sourceSelect = document.getElementById("bulkConfirmSourceSelect");
    if (sourceSelect) sourceSelect.value = "";

    var blocked = blockedCandidates(ids);
    var alert = document.getElementById("bulkConfirmBlocked");
    var list = document.getElementById("bulkConfirmBlockedList");
    var submit = document.getElementById("confirmBulkSubmit");

    if (alert) alert.classList.toggle("d-none", blocked.length === 0);
    if (list) list.textContent = blocked.join(" · ");
    if (submit) submit.disabled = blocked.length > 0;

    showModal("bulkConfirmModal");
  }

  function bulkDiscardSelected() {
    var ids = selectedIds();
    if (!ids.length) return;

    var data = payload();
    var single = ids.length === 1;
    var word = single ? "candidato" : "candidatos";
    var action = single
      ? (data.will_be_discarded_singular || "será descartado.")
      : (data.will_be_discarded || "serán descartados.");
    var hint = single
      ? (data.discard_undo_hint_singular || data.discard_undo_hint || "")
      : (data.discard_undo_hint || "");
    var message = ids.length + " " + word + " " + action + " " + hint;

    window.Dialog.confirm(message, {
      title: "Confirmar",
      confirmLabel: "Descartar",
      variant: "danger"
    }).then(function (confirmed) {
      if (!confirmed) return;

      clearPersistedSelection();

      var form = document.createElement("form");
      form.method = "post";
      form.action = data.bulk_discard_url;

      var csrf = document.querySelector('meta[name="csrf-token"]');
      if (csrf) {
        var token = document.createElement("input");
        token.type = "hidden";
        token.name = "authenticity_token";
        token.value = csrf.content;
        form.appendChild(token);
      }

      var idsInput = document.createElement("input");
      idsInput.type = "hidden";
      idsInput.name = "candidate_ids";
      idsInput.value = ids.join(",");
      form.appendChild(idsInput);

      var page = document.querySelector(".candidates-page");
      if (page && page.dataset.status === "discarded") {
        var statusInput = document.createElement("input");
        statusInput.type = "hidden";
        statusInput.name = "status";
        statusInput.value = "discarded";
        form.appendChild(statusInput);
      }

      document.body.appendChild(form);
      form.submit();
    });
  }

  function showSubmittingState(form, label) {
    var button = form.querySelector("button[type='submit']");
    if (!button) return;
    button.disabled = true;
    button.textContent = label;
  }

  document.addEventListener("change", function (event) {
    if (!document.querySelector(".candidates-page")) return;

    if (event.target.id === "selectAll" || event.target.id === "selectAllMobile") {
      selectAllRows(event.target.checked);
      updateBulk();
      return;
    }

    if (event.target.classList.contains("row-check")) {
      syncDuplicateCheckboxes(event.target.value, event.target.checked);
      updateBulk();
    }
  });

  document.addEventListener("click", function (event) {
    if (!document.querySelector(".candidates-page")) return;

    if (event.target.id === "bulkClearSelection" || event.target.closest("#bulkClearSelection")) {
      clearSelection();
    } else if (event.target.id === "bulkCategory" || event.target.closest("#bulkCategory")) {
      openCategoryModal();
    } else if (event.target.id === "bulkSource" || event.target.closest("#bulkSource")) {
      openSourceModal();
    } else if (event.target.id === "bulkConfirm" || event.target.closest("#bulkConfirm")) {
      openConfirmModal();
    } else if (event.target.id === "bulkDiscard" || event.target.closest("#bulkDiscard")) {
      bulkDiscardSelected();
    }
  });

  document.addEventListener("submit", function (event) {
    if (event.defaultPrevented) return;

    var data = payload();
    if (event.target.id === "bulkCategoryForm" || event.target.id === "bulkSourceForm") {
      persistSelection();
      showSubmittingState(event.target, data.applying_label || "Aplicando...");
    } else if (event.target.id === "bulkConfirmForm") {
      clearPersistedSelection();
      showSubmittingState(event.target, data.creating_label || "Creando...");
    }
  });

  function init() {
    if (!document.querySelector(".candidates-page")) return;

    restorePersistedSelection();
    updateBulk();
  }

  document.addEventListener("turbo:load", init);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

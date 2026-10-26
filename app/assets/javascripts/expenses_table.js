(function () {
  if (window.__expensesTableInit) return;
  window.__expensesTableInit = true;

  var payloadEl = document.querySelector("[data-expenses-table-payload]");
  var payload = payloadEl ? JSON.parse(payloadEl.dataset.expensesTablePayload) : {};

  var $ = function (sel) { return document.querySelector(sel); };
  var $$ = function (sel) { return Array.prototype.slice.call(document.querySelectorAll(sel)); };

  function stateQuery() {
    var q = new URLSearchParams(location.search);
    var keys = ["category_id", "money_source_id", "start_date", "end_date", "min_amount", "max_amount", "sort", "dir", "page"];
    var out = [];
    keys.forEach(function (k) {
      var v = q.get(k);
      if (v) out.push(encodeURIComponent(k) + "=" + encodeURIComponent(v));
    });
    return out.length ? "?" + out.join("&") : "";
  }

  function urlWithState(path) {
    var sep = path.indexOf("?") === -1 ? "?" : "&";
    return path + sep + stateQuery().replace(/^\?/, "");
  }

  function updateBulk() {
    var checks = $$(".row-check");
    var n = selectedIds().length;
    var has = n > 0;
    $("#bulkCount").textContent = n + " seleccionados";
    var all = $("#selectAll");
    if (all) all.checked = checks.length > 0 && $$(".row-check").filter(function (c) { return c.checked; }).length === checks.length;
    ["bulkCategory", "bulkSource", "clearSel", "bulkDelete"].forEach(function (id) {
      var el = $("#" + id);
      if (el) el.disabled = !has;
    });
  }

  function selectedIds() {
    var seen = {};
    $$("tr[data-id], .mobile-item[data-id]")
      .filter(function (el) { return el.querySelector(".row-check") && el.querySelector(".row-check").checked; })
      .forEach(function (el) { seen[el.dataset.id] = true; });
    return Object.keys(seen);
  }

  function updateBulkEdit() {
    var n = ($("#bulkExpenseIds").value || "").split(",").filter(Boolean).length;
    var hasValue = !!$("#bulkCategorySelect").value || !!$("#bulkSourceSelect").value;
    var btn = $("#confirmBulkEdit");
    btn.disabled = !hasValue;
    var word = n === 1 ? "gasto" : "gastos";
    btn.innerHTML = '<i class="ti ti-check me-1"></i>Actualizar ' + n + " " + word;
    if (hasValue) {
      CategoryPicker.setInvalid($("#bulkCategorySelect"), false);
      $("#bulkSourceSelect").classList.remove("is-invalid");
    }
  }

  var bulkEditFocus = "category";

  function openBulkEdit(field) {
    var ids = selectedIds();
    if (!ids.length) return;
    var n = ids.length;
    var word = n === 1 ? "gasto" : "gastos";
    bulkEditFocus = field;
    $("#bulkExpenseIds").value = ids.join(",");
    $("#bulkEditForm").action = urlWithState(payload.bulk_update_url);
    if (field === "category") {
      $("#bulkEditTitle").textContent = "Cambiar categoría de " + n + " " + word;
      $("#bulkEditSummary").innerHTML =
        "Estás a punto de cambiar la categoría de <strong>" + n + "</strong> " + word + " seleccionados.";
    } else {
      $("#bulkEditTitle").textContent = "Cambiar fuente de dinero de " + n + " " + word;
      $("#bulkEditSummary").innerHTML =
        "Estás a punto de cambiar la fuente de dinero de <strong>" + n + "</strong> " + word + " seleccionados.";
    }
    CategoryPicker.setValue($("#bulkCategorySelect"), "");
    $("#bulkSourceSelect").value = "";
    CategoryPicker.setInvalid($("#bulkCategorySelect"), false);
    $("#bulkSourceSelect").classList.remove("is-invalid");
    updateBulkEdit();
    bootstrap.Modal.getOrCreateInstance("#bulkEditModal").show();
  }

  function openBulkRecurring(row) {
    if (!row) return;

    // Same-category templates first: clone matching options into a top
    // optgroup so the likely selection is one tap away.
    var category = row.dataset.categoryId || "";
    var select = $("#bulkRecurringSelect");
    var oldGroup = $("#sameCategoryGroup");
    if (oldGroup) oldGroup.remove();
    var matching = Array.prototype.slice.call(select.options)
                                      .filter(function (o) {
                                        return o.value && o.dataset.categoryId === category;
                                      });
    if (matching.length) {
      var group = document.createElement("optgroup");
      group.label = payload.same_category_group_label;
      group.id = "sameCategoryGroup";
      matching.reverse().forEach(function (option) { group.appendChild(option.cloneNode(true)); });
      select.insertBefore(group, select.options[1]);
    }

    select.dataset.expenseAmount = row.dataset.amount || "0";
    select.value = "";
    $("#recurringExpenseId").value = row.dataset.id;
    $("#bulkRecurringForm").action = urlWithState(payload.assign_recurring_url);
    $("#confirmBulkRecurring").disabled = true;
    var details = $("#recurringTemplateDetails");
    if (details) details.classList.add("d-none");
    var checkbox = $("#recurringCompleted");
    if (checkbox) checkbox.checked = true;
    bootstrap.Modal.getOrCreateInstance("#bulkRecurringModal").show();
  }

  function renderRecurringDetails(select) {
    var panel = $("#recurringTemplateDetails");
    if (!panel) return;
    if (!select.value) {
      panel.classList.add("d-none");
      $("#confirmBulkRecurring").disabled = true;
      return;
    }
    var option = select.options[select.selectedIndex];
    var expectedEl = $("#recurringExpectedAmount");
    if (expectedEl) expectedEl.textContent = option.dataset.expectedLabel || "";
    var paidEl = $("#recurringPaidAmount");
    if (paidEl) paidEl.textContent = option.dataset.paidLabel || "";
    var remainingEl = $("#recurringRemainingAmount");
    if (remainingEl) remainingEl.textContent = option.dataset.remainingLabel || "";

    var expected = Number(option.dataset.amount || 0);
    var paid = Number(option.dataset.paid || 0);
    var expenseAmount = Number(select.dataset.expenseAmount || 0);
    var checkbox = $("#recurringCompleted");
    if (checkbox) checkbox.checked = (paid + expenseAmount >= expected);

    panel.classList.remove("d-none");
    $("#confirmBulkRecurring").disabled = false;
  }

  function openDrawer(url, editUrl, deleteUrl) {
    var body = $("#drawerBody");
    body.innerHTML = '<div class="text-center text-muted py-4"><div class="spinner-border spinner-border-sm" role="status"><span class="visually-hidden">Cargando&hellip;</span></div></div>';
    fetch(url, { headers: { "Accept": "text/html" } })
      .then(function (r) { return r.text(); })
      .then(function (html) {
        body.innerHTML = html;
        $("#drawerEdit").href = editUrl;
        $("#drawerDelete").setAttribute("data-delete-url", deleteUrl);
        var offcanvas = bootstrap.Offcanvas.getOrCreateInstance("#detailDrawer");
        offcanvas.show();
      });
  }

  function openDelete(url, count) {
    $("#deleteTitle").textContent = count > 1 ? "¿Eliminar " + count + " gastos?" : "¿Eliminar gasto?";
    $("#deleteBody").textContent = count > 1 ? "¿Eliminar " + count + " gastos? Esta acción no se puede deshacer." : "Esta acción no se puede deshacer.";
    $("#deleteForm").action = url;
    bootstrap.Modal.getOrCreateInstance("#deleteModal").show();
  }

  function openProcessModal(button) {
    var form = $("#expenseProcessForm");
    var amount = button.dataset.processAmount || "";
    form.action = button.dataset.processUrl;
    $("#expenseProcessTitle").textContent = button.dataset.processTitle || "Confirmar Pago";
    $("#expenseProcessCategory").textContent = button.dataset.processCategory || "";
    $("#expenseProcessDescription").textContent = button.dataset.processDescription || "Sin descripción";
     $("#expenseProcessConfiguredAmount").textContent = "$" + Number(amount).toFixed(2);
     var paidSoFar = Number(button.dataset.processPaidAmount || 0);
     var remaining = Math.max(Number(amount) - paidSoFar, 0);
     if (remaining <= 0) remaining = Number(amount);
     $("#processPaidSoFar").textContent = "$" + paidSoFar.toFixed(2);
     var markCheckbox = $("#processMarkAsPaid");
     if (markCheckbox) markCheckbox.checked = false;
     $("#expenseProcessDate").value = payload.today;
     $("#expenseProcessAmount").value = remaining.toFixed(2);
     if (window.MoneyInputs) window.MoneyInputs.formatField($("#expenseProcessAmount"), true);
    bootstrap.Modal.getOrCreateInstance("#expenseProcessModal").show();
  }

  document.addEventListener("change", function (e) {
    if (e.target.matches(".row-check, #selectAll")) {
      if (e.target.id === "selectAll") {
        $$(".row-check").forEach(function (c) { c.checked = e.target.checked; });
      }
      updateBulk();
    }
    if (e.target.matches("#bulkCategorySelect, #bulkSourceSelect")) {
      updateBulkEdit();
    }
    if (e.target.matches("#bulkRecurringSelect")) {
      renderRecurringDetails(e.target);
    }
  });

  document.addEventListener("click", function (e) {
    // The drawer opens ONLY from the eye button — a whole-row click no
    // longer opens it (rows host interactive buttons on every column).
    var viewBtn = e.target.closest("[data-open-drawer]");
    if (viewBtn) {
      var row = viewBtn.closest("tr[data-id], .mobile-item[data-id]");
      openDrawer(row.dataset.viewUrl, row.dataset.editUrl, row.dataset.deleteUrl);
      return;
    }
    var delBtn = e.target.closest("[data-delete]");
    if (delBtn) {
      openDelete(delBtn.dataset.deleteUrl || delBtn.closest("[data-delete-url]").dataset.deleteUrl, 1);
      return;
    }
    var processBtn = e.target.closest("[data-process-expense]");
    if (processBtn) {
      openProcessModal(processBtn);
      return;
    }
    var applyRecBtn = e.target.closest("[data-assign-recurring]");
    if (applyRecBtn) {
      openBulkRecurring(applyRecBtn.closest("tr[data-id], .mobile-item[data-id]"));
      return;
    }
    if (e.target.id === "clearSel") {
      $$(".row-check").forEach(function (c) { c.checked = false; });
      updateBulk();
    }
    if (e.target.id === "bulkCategory" || e.target.id === "bulkSource") {
      openBulkEdit(e.target.id === "bulkCategory" ? "category" : "source");
    }
    if (e.target.id === "bulkDelete") {
      var ids = selectedIds();
      if (ids.length) {
        $("#deleteIds").value = ids.join(",");
        openDelete(payload.bulk_destroy_url + stateQuery(), ids.length);
      }
    }
    if (e.target.id === "confirmDelete") {
      var form = $("#deleteForm");
      var action = form.action || "";
      if (action === "" || action === location.href.split("#")[0]) return;
      var methodInput = form.querySelector("input[name=_method]");
      if (!methodInput) {
        methodInput = document.createElement("input");
        methodInput.type = "hidden";
        methodInput.name = "_method";
        methodInput.value = "delete";
        form.appendChild(methodInput);
      }
      form.innerHTML =
      '<input type="hidden" name="_method" value="delete">' +
      '<input type="hidden" name="authenticity_token" value="' +
      (document.querySelector('meta[name="csrf-token"]') || {}).content + '">' +
      '<input type="hidden" name="ids" value="' + form.querySelector("#deleteIds").value + '">';
      bootstrap.Modal.getInstance("#deleteModal").hide();
      bootstrap.Offcanvas.getInstance("#detailDrawer") && bootstrap.Offcanvas.getInstance("#detailDrawer").hide();
      form.requestSubmit();
    }
  });

  $("#bulkEditForm").addEventListener("submit", function (e) {
    if (!$("#bulkCategorySelect").value && !$("#bulkSourceSelect").value) {
      e.preventDefault();
      CategoryPicker.setInvalid($("#bulkCategorySelect"), true);
      $("#bulkSourceSelect").classList.add("is-invalid");
      return;
    }
    var btn = $("#confirmBulkEdit");
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1" role="status" aria-hidden="true"></span>Actualizando&hellip;';
  });

  $("#bulkEditModal").addEventListener("shown.bs.modal", function () {
    if (bulkEditFocus === "source") {
      $("#bulkSourceSelect").focus();
    } else {
      CategoryPicker.focus($("#bulkCategorySelect"));
    }
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Enter") {
      var row = e.target.closest("tr[data-id], .mobile-item[data-id]");
      if (row && !e.target.closest("[data-stop], input, button, a")) {
        openDrawer(row.dataset.viewUrl, row.dataset.editUrl, row.dataset.deleteUrl);
      }
    }
  });

  document.addEventListener("turbo:before-fetch-request", function (e) {
    if (!e.target.url || e.target.url.indexOf("/expenses") === -1) return;
    if (e.target.url.indexOf(".csv") !== -1) return;
    if (e.target.fetchOptions && (e.target.fetchOptions.method || "get").toLowerCase() !== "get") return;
    var tableCard = $("#tableCard");
    if (tableCard) tableCard.classList.add("d-none");
    var loading = $("#loadingState");
    if (loading) loading.classList.remove("d-none");
  });

  document.addEventListener("turbo:render", function () {
    var loading = $("#loadingState");
    if (loading && location.pathname === "/expenses") loading.classList.add("d-none");
  });
})();

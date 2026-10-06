// Día de Cuadre — reconciliation dashboard interactions.
// Two Bootstrap modals driven by the data-* attributes of the buttons that
// open them:
//   .js-assign-payment  → "Asignar pago"   (search/assign an existing expense)
//   .js-reconcile       → "Conciliar"      (record real balance, adjust, defer)
// Server actions are posted with fetch + CSRF token; a full reload keeps the
// persisted reconciliation state consistent.
(function () {
  "use strict";

  var money = window.MoneyInputs;

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.getAttribute("content") : "";
  }

  function post(url, body) {
    // redirect: 'manual' — the controller redirects after every write; if the
    // fetch followed it, the followed GET would consume the flash message and
    // the reload below would render without a notice.
    return fetch(url, {
      method: "POST",
      redirect: "manual",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken()
      },
      body: JSON.stringify(body || {})
    }).then(function (response) {
      if (response.type === "opaqueredirect" || response.ok) return response;
      throw new Error("HTTP " + response.status);
    });
  }

  // Machine-format numbers coming from the server's data attributes
  // ("-5973508.42"). Never run them through MoneyInputs.sanitizeValue: that
  // helper is built for es-CO user text and would strip the sign and treat
  // the decimal dot as a thousands separator.
  function parseMoney(value) {
    var parsed = parseFloat(value);
    return isNaN(parsed) ? 0 : parsed;
  }

  // User-typed text in the "Saldo real" input, which MoneyInputs renders in
  // es-CO format ("8.450.000" / "-500.000,5"). sanitizeValue drops the sign,
  // so the negative is detected first and re-applied.
  function parseUserMoney(value) {
    var raw = String(value == null ? "" : value).trim();
    if (!raw) return 0;
    var negative = raw.charAt(0) === "-";
    var sanitized = money ? money.sanitizeValue(negative ? raw.slice(1) : raw) : raw;
    var parsed = parseFloat(sanitized);
    if (isNaN(parsed)) return 0;
    return negative ? -parsed : parsed;
  }

  function formatDate(iso) {
    if (!iso) return "—";
    var date = new Date(iso + (iso.length === 10 ? "T00:00:00" : ""));
    if (isNaN(date.getTime())) return "—";
    return date.toLocaleDateString(document.documentElement.lang || "es-CO", { month: "short", day: "numeric" });
  }

  function escapeHtml(text) {
    var div = document.createElement("div");
    div.textContent = text === null || text === undefined ? "" : String(text);
    return div.innerHTML;
  }

  function debounce(fn, delay) {
    var timer = null;
    return function () {
      var args = arguments;
      var self = this;
      clearTimeout(timer);
      timer = setTimeout(function () { fn.apply(self, args); }, delay);
    };
  }

  function getJSON(url) {
    return fetch(url, { headers: { "Accept": "application/json" } })
      .then(function (response) { return response.ok ? response.json() : { }; });
  }

  // ---------------------------------------------------------------- Assign

  var assignState = { templateId: null, expenseId: null };

  function assignModal() {
    return document.getElementById("assignPaymentModal");
  }

  function assignSearchUrl() {
    return assignModal().dataset.searchUrl;
  }

  function assignCreateUrl() {
    return assignModal().dataset.createExpenseUrl;
  }

  function openAssign(button) {
    assignState = { templateId: button.dataset.templateId, expenseId: null };

    var modal = assignModal();
    modal.querySelector(".js-payment-name").textContent = button.dataset.name;
    modal.querySelector(".js-payment-amount").textContent = button.dataset.amountFormatted ||
      button.dataset.amount;
    modal.querySelector(".js-payment-due").textContent = formatDate(button.dataset.due);

    var search = modal.querySelector("#assignExpenseSearch");
    search.value = "";
    resetAssignResults();

    var createLink = modal.querySelector("#assignCreateExpenseLink");
    if (createLink) {
      createLink.href = assignCreateUrl() + "?" + new URLSearchParams({
        amount: button.dataset.amount,
        description: button.dataset.name,
        date: button.dataset.due || ""
      }).toString();
    }

    modal.querySelector("#assignPaymentSubmit").disabled = true;

    bootstrap.Modal.getOrCreateInstance(modal).show();
    fetchAssignResults("");
  }

  // The placeholder row is rebuilt from the labels stashed on the list by
  // the DOMContentLoaded wiring: the first fetch wipes the original
  // .js-search-empty node, and openAssign must not crash on the second open.
  function resetAssignResults() {
    var list = document.getElementById("assignExpenseResults");
    list.innerHTML = emptyRow(list.dataset.hint);
  }

  function emptyRow(label) {
    return "<div class='list-group-item text-muted small'>" + escapeHtml(label || "—") + "</div>";
  }

  function fetchAssignResults(query) {
    // Scoped to the cuadre period shown on screen: only an expense dated in
    // that month can clear the pending row, so both the search and the
    // assign post carry the period.
    var period = assignModal().dataset.period || "";
    var params = new URLSearchParams({
      q: query || "",
      template_id: assignState.templateId || "",
      period: period
    });
    var amountField = document.querySelector(".js-assign-payment.active") || document.querySelector(".js-assign-payment");
    if (amountField) params.set("amount", amountField.dataset.amount);

    getJSON(assignSearchUrl() + "?" + params.toString()).then(function (data) {
      var list = document.getElementById("assignExpenseResults");
      list.innerHTML = "";
      var expenses = (data && data.expenses) || [];
      if (!expenses.length) {
        list.innerHTML = emptyRow(list.dataset.emptyLabel);
        return;
      }
      expenses.forEach(function (expense) {
        list.insertAdjacentHTML("beforeend", assignResultRow(expense));
      });
    });
  }

  function assignResultRow(expense) {
    var date = formatDate(expense.date);
    return "<button type='button' class='list-group-item list-group-item-action d-flex justify-content-between align-items-center flex-wrap gap-2 py-2 js-assign-result' data-expense-id='" +
      expense.id + "' data-description='" + escapeHtml(expense.description) + "'>" +
      "<span class='d-flex align-items-center gap-2'>" +
      "<i class='bi bi-circle text-secondary small'></i>" +
      "<span>" + escapeHtml(expense.description) + "</span>" +
      "</span>" +
      "<span class='text-muted small'>" + escapeHtml(expense.amount) + " · " + escapeHtml(date) + "</span>" +
      "</button>";
  }

  function selectAssignResult(button) {
    assignState.expenseId = button.dataset.expenseId;
    document.querySelectorAll("#assignExpenseResults .js-assign-result").forEach(function (row) {
      row.classList.remove("active");
      row.querySelector(".bi-circle") && row.querySelector(".bi-circle").classList.remove("text-primary");
    });
    button.classList.add("active");
    var dot = button.querySelector(".bi-circle");
    if (dot) dot.classList.replace("bi-circle", "bi-check-circle-fill");
    if (dot) dot.classList.add("text-primary");
    document.getElementById("assignPaymentSubmit").disabled = false;
  }

  function submitAssign() {
    if (!assignState.expenseId) return;
    var button = document.getElementById("assignPaymentSubmit");
    button.disabled = true;

    post(document.getElementById("assignPaymentModal").dataset.assignUrl
      .replace("TEMPLATE_ID", assignState.templateId),
      { expense_id: assignState.expenseId, period: assignModal().dataset.period || "" })
      .then(function () {
        bootstrap.Modal.getOrCreateInstance(assignModal()).hide();
        window.location.reload();
      })
      .catch(function () {
        button.disabled = false;
        window.alert(button.dataset.errorLabel || "No se pudo asignar el pago.");
      });
  }

  // -------------------------------------------------------------- Reconcile

  var reconcileState = { sourceId: null, kind: null, appBalance: 0 };

  function reconcileModal() {
    return document.getElementById("reconcileModal");
  }

  function openReconcile(button) {
    reconcileState = {
      sourceId: button.dataset.sourceId,
      kind: button.dataset.kind,
      appBalance: parseMoney(button.dataset.appBalance)
    };

    var modal = reconcileModal();
    modal.querySelector(".js-source-name").textContent = button.dataset.name;
    modal.querySelector(".js-app-balance").textContent = button.dataset.appBalanceFormatted ||
      button.dataset.appBalance;

    var actual = modal.querySelector("#reconcileActualBalance");
    actual.value = button.dataset.actualBalance || "";
    updateDifference();

    modal.querySelector("#reconcileSearchBlock").classList.add("d-none");
    modal.querySelector("#reconcileSearchInput").value = "";
    resetMovementResults();
    noteInput().value = "";

    // Populate the Crear expense / Crear ingreso links BEFORE the user types
    // anything — otherwise they keep href="#" and the first click is dead.
    updatePrefillLinks();

    bootstrap.Modal.getOrCreateInstance(modal).show();
  }

  function updateDifference() {
    var modal = reconcileModal();
    var actual = parseUserMoney(modal.querySelector("#reconcileActualBalance").value);
    var difference = actual - reconcileState.appBalance;
    var target = modal.querySelector(".js-difference");

    if (modal.querySelector("#reconcileActualBalance").value.trim() === "") {
      target.textContent = "—";
      target.classList.remove("text-success", "text-warning-emphasis");
      return;
    }

    var prefix = difference > 0 ? "+" : "";
    target.textContent = prefix + difference.toLocaleString(document.documentElement.lang || "es-CO", {
      minimumFractionDigits: 2, maximumFractionDigits: 2
    });
    target.classList.toggle("text-success", difference === 0);
    target.classList.toggle("text-warning-emphasis", difference !== 0);
  }

  // Raw text as typed — the server normalizes es-CO money with
  // MoneyFormat.normalize, which also preserves negative balances.
  function rawActualBalance() {
    return reconcileModal().querySelector("#reconcileActualBalance").value.trim();
  }

  function submitAdjust() {
    var value = rawActualBalance();
    if (value === "") return;

    var button = document.getElementById("reconcileAdjust");
    button.disabled = true;

    post(reconcileModal().dataset.balanceUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      actual_balance: value,
      adjust: true,
      note: noteInput().value.trim()
    }).then(function () {
      bootstrap.Modal.getOrCreateInstance(reconcileModal()).hide();
      window.location.reload();
    }).catch(function () {
      button.disabled = false;
    });
  }

  // "Todo está bien": no balance change, no note — the current balance is
  // confirmed as the real one and the row turns reconciled (Cuadrado).
  function submitAllGood() {
    var button = document.getElementById("reconcileAllGood");
    button.disabled = true;

    post(reconcileModal().dataset.balanceUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      mark_ok: true
    }).then(function () {
      bootstrap.Modal.getOrCreateInstance(reconcileModal()).hide();
      window.location.reload();
    }).catch(function () {
      button.disabled = false;
    });
  }

  function noteInput() {
    return reconcileModal().querySelector("#reconcileNote");
  }

  function submitLeavePending() {
    var button = document.getElementById("reconcileLeavePending");
    button.disabled = true;

    post(reconcileModal().dataset.leaveUrl.replace("SOURCE_ID", reconcileState.sourceId), {})
      .then(function () {
        bootstrap.Modal.getOrCreateInstance(reconcileModal()).hide();
        window.location.reload();
      })
      .catch(function () {
        button.disabled = false;
      });
  }

  function updatePrefillLinks() {
    var modal = reconcileModal();
    var actual = rawActualBalance();
    var difference = parseUserMoney(actual) - reconcileState.appBalance;
    var today = new Date().toISOString().slice(0, 10);

    var create = modal.dataset.createExpenseUrl;
    var income = modal.dataset.createIncomeUrl;
    // Without a typed "Saldo real" the difference is unknown: prefill only
    // the money source and the date, and let the user enter the amount.
    var params = {
      money_source_id: reconcileState.sourceId,
      date: today
    };
    if (actual !== "") {
      params.amount = Math.abs(difference).toFixed(2);
    }

    modal.querySelector("#reconcileCreateExpense").href =
      create + "?" + new URLSearchParams(params).toString();
    modal.querySelector("#reconcileCreateIncome").href =
      income + "?" + new URLSearchParams(params).toString();
  }

  function resetMovementResults() {
    var list = document.getElementById("reconcileSearchResults");
    list.innerHTML = emptyRow(list.dataset.hint);
  }

  function movementResultRow(movement) {
    var kindLabel = movement.kind === "income" ? "Ingreso" : "Gasto";
    var kindClass = movement.kind === "income" ? "text-success" : "text-danger";
    return "<div class='list-group-item d-flex justify-content-between align-items-center flex-wrap gap-2 py-2'>" +
      "<span class='d-flex align-items-center gap-2'>" +
      "<span class='badge rounded-pill " + kindClass + "'>" + escapeHtml(kindLabel) + "</span>" +
      "<span>" + escapeHtml(movement.description) + "</span>" +
      "</span>" +
      "<span class='text-muted small'>" + escapeHtml(movement.amount) + " · " +
      escapeHtml(formatDate(movement.date)) +
      " <a href='" + movement.edit_url + "' target='_blank' rel='noopener' class='ms-2'>" +
      escapeHtml(movement.editLabel || "Abrir") + "</a></span>" +
      "</div>";
  }

  function differenceMagnitude() {
    var actual = rawActualBalance();
    if (actual === "") return "0";
    return Math.abs(parseUserMoney(actual) - reconcileState.appBalance).toString();
  }

  function fetchMovements() {
    var query = reconcileModal().querySelector("#reconcileSearchInput").value;
    var params = new URLSearchParams({ q: query, amount: differenceMagnitude() });

    getJSON(reconcileModal().dataset.movementsUrl + "?" + params.toString()).then(function (data) {
      var list = document.getElementById("reconcileSearchResults");
      list.innerHTML = "";
      var movements = (data && data.movements) || [];
      if (!movements.length) {
        list.innerHTML = emptyRow(list.dataset.emptyLabel);
        return;
      }
      movements.forEach(function (movement) {
        list.insertAdjacentHTML("beforeend", movementResultRow(movement));
      });
    });
  }

  // ------------------------------------------------------------------ Wiring

  document.addEventListener("click", function (event) {
    var assignButton = event.target.closest(".js-assign-payment");
    if (assignButton) {
      document.querySelectorAll(".js-assign-payment").forEach(function (b) { b.classList.remove("active"); });
      assignButton.classList.add("active");
      openAssign(assignButton);
      return;
    }

    var result = event.target.closest("#assignExpenseResults .js-assign-result");
    if (result) {
      selectAssignResult(result);
      return;
    }

    if (event.target.closest("#assignPaymentSubmit")) {
      submitAssign();
      return;
    }

    var reconcileButton = event.target.closest(".js-reconcile");
    if (reconcileButton) {
      openReconcile(reconcileButton);
      return;
    }

    if (event.target.closest("#reconcileAdjust")) {
      submitAdjust();
      return;
    }

    if (event.target.closest("#reconcileAllGood")) {
      submitAllGood();
      return;
    }

    if (event.target.closest("#reconcileLeavePending")) {
      submitLeavePending();
      return;
    }

    if (event.target.closest("#reconcileSearchToggle")) {
      var block = document.getElementById("reconcileSearchBlock");
      block.classList.toggle("d-none");
      if (!block.classList.contains("d-none")) {
        reconcileModal().querySelector("#reconcileSearchInput").focus();
      }
    }
  });

  document.addEventListener("input", function (event) {
    if (event.target.id === "reconcileActualBalance") {
      updateDifference();
      updatePrefillLinks();
    }
    if (event.target.id === "assignExpenseSearch") {
      fetchAssignResults(event.target.value);
    }
    if (event.target.id === "reconcileSearchInput") {
      debounceFetchMovements();
    }
  });

  var debounceFetchMovements = debounce(fetchMovements, 300);

  document.addEventListener("DOMContentLoaded", function () {
    ["assignPaymentModal", "reconcileModal"].forEach(function (id) {
      var modal = document.getElementById(id);
      if (!modal) return;
      if (id === "assignPaymentModal") {
        stashListHint(modal, "assignExpenseResults", "resultsEmptyLabel");
      } else {
        stashListHint(modal, "reconcileSearchResults", "movementEmptyLabel");
      }
    });
  });

  // Keeps the initial hint text (the placeholder row rendered by the server)
  // on the list's dataset: the row is destroyed by the first fetch, and the
  // modals need it every time they are reopened.
  function stashListHint(modal, listId, emptyLabelKey) {
    var list = document.getElementById(listId);
    if (!list) return;
    var hintNode = list.querySelector(".js-search-empty");
    list.dataset.hint = hintNode ? hintNode.textContent : (modal.dataset[emptyLabelKey] || "");
    list.dataset.emptyLabel = modal.dataset[emptyLabelKey] || "";
  }
})();

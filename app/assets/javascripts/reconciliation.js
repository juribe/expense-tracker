// Día de Balance — reconciliation dashboard interactions.
// Two Bootstrap modals driven by the data-* attributes of the buttons that
// open them:
//   .js-assign-payment  → "Asignar pago"   (search/assign an existing expense)
//   .js-reconcile       → "Conciliar"      (record real balance, adjust, defer)
// Server actions are posted with fetch + CSRF token; a full reload keeps the
// persisted reconciliation state consistent.
(function () {
  "use strict";

  var money = window.MoneyInputs;
  var movementState = { page: 1, perPage: 8, hasMore: false, loading: false };

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

  function validUserMoney(value) {
    var raw = String(value == null ? "" : value).trim();
    if (!raw) return false;
    var negative = raw.charAt(0) === "-";
    var sanitized = money ? money.sanitizeValue(negative ? raw.slice(1) : raw) : raw;
    return sanitized !== "" && sanitized !== "-" && isFinite(parseFloat(sanitized));
  }

  function formatMoney(value) {
    var number = typeof value === "number" ? value : parseFloat(value);
    if (isNaN(number)) return String(value == null ? "" : value);
    return number.toLocaleString("es-CO", {
      style: "currency", currency: "COP", maximumFractionDigits: 0
    });
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
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.json();
      });
  }

  // ---------------------------------------------------------------- Assign

  var assignState = { templateId: null, expenseId: null, categoryName: "", description: "", amount: "" };

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
    assignState = {
      templateId: button.dataset.templateId,
      expenseId: null,
      categoryName: button.dataset.categoryName || "",
      description: "",
      amount: ""
    };

    var modal = assignModal();
    modal.querySelector(".js-payment-name").textContent = button.dataset.name;
    modal.querySelector(".js-payment-amount").textContent = button.dataset.amountFormatted ||
      formatMoney(button.dataset.amount);
    modal.querySelector(".js-payment-due").textContent = formatDate(button.dataset.due);
    modal.querySelector(".js-payment-category").textContent = assignState.categoryName || "—";

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

    resetAssignSelection();
    bootstrap.Modal.getOrCreateInstance(modal).show();
    fetchAssignResults("");
  }

  function resetAssignResults() {
    var list = document.getElementById("assignExpenseResults");
    list.innerHTML = emptyRow(list.dataset.hint);
  }

  function resetAssignSelection() {
    var modal = assignModal();
    var label = modal.querySelector("#assignSelectedLabel");
    label.textContent = modal.dataset.selectHint || label.dataset.selectHint || "";
    modal.querySelector("#assignPaymentSubmit").disabled = true;
    assignState.expenseId = null;
    assignState.description = "";
    assignState.amount = "";
  }

  function emptyRow(label) {
    return "<div class='rec-payment-empty'>" + escapeHtml(label || "—") + "</div>";
  }

  function assignEmptyMessage() {
    var list = document.getElementById("assignExpenseResults");
    if (assignState.categoryName && list.dataset.emptyLabel) {
      return list.dataset.emptyLabel.replace("%{category}", assignState.categoryName);
    }
    return list.dataset.emptyGeneric || list.dataset.emptyLabel || "";
  }

  function fetchAssignResults(query) {
    var modal = assignModal();
    var period = modal.dataset.period || "";
    var params = new URLSearchParams({
      q: query || "",
      template_id: assignState.templateId || "",
      period: period
    });
    var list = document.getElementById("assignExpenseResults");
    list.innerHTML = emptyRow(modal.dataset.loadingLabel || "…");

    getJSON(assignSearchUrl() + "?" + params.toString()).then(function (data) {
      list.innerHTML = "";
      var expenses = (data && data.expenses) || [];
      if (!expenses.length) {
        list.innerHTML = emptyRow(assignEmptyMessage());
        return;
      }
      expenses.forEach(function (expense) {
        list.insertAdjacentHTML("beforeend", assignResultRow(expense));
      });
    }).catch(function () {
      list.innerHTML = emptyRow(modal.dataset.errorLabel || "");
    });
  }

  function assignResultRow(expense) {
    var date = formatDate(expense.date);
    var amount = formatMoney(expense.amount);
    return "<div class='rec-payment-result js-assign-result' role='button' tabindex='0' aria-selected='false' data-expense-id='" +
      escapeHtml(expense.id) + "' data-description='" + escapeHtml(expense.description) +
      "' data-amount='" + escapeHtml(amount) + "'>" +
      "<span class='rec-payment-kind'>" + escapeHtml(expense.kind_label || "Gasto") + "</span>" +
      "<span class='rec-payment-name'>" + escapeHtml(expense.description) + "</span>" +
      "<span class='rec-payment-meta'>" + escapeHtml(amount) + " · " + escapeHtml(date) + "</span>" +
      "<a class='rec-payment-open' href='" + escapeHtml(expense.edit_url) +
      "' target='_blank' rel='noopener'>" + escapeHtml(assignModal().dataset.openLabel || "Abrir") + "</a>" +
      "</div>";
  }

  function selectAssignResult(row) {
    assignState.expenseId = row.dataset.expenseId;
    assignState.description = row.dataset.description;
    assignState.amount = row.dataset.amount;

    document.querySelectorAll("#assignExpenseResults .js-assign-result").forEach(function (item) {
      item.classList.remove("selected");
      item.setAttribute("aria-selected", "false");
    });
    row.classList.add("selected");
    row.setAttribute("aria-selected", "true");

    var modal = assignModal();
    var template = modal.dataset.selectedLabel || "Seleccionado: %{description} · %{amount}";
    modal.querySelector("#assignSelectedLabel").textContent = template
      .replace("%{description}", assignState.description)
      .replace("%{amount}", assignState.amount);
    modal.querySelector("#assignPaymentSubmit").disabled = false;
  }

  function submitAssign() {
    if (!assignState.expenseId) return;
    var button = document.getElementById("assignPaymentSubmit");
    button.disabled = true;

    post(assignModal().dataset.assignUrl
      .replace("TEMPLATE_ID", assignState.templateId),
      { expense_id: assignState.expenseId, period: assignModal().dataset.period || "" })
      .then(function () {
        bootstrap.Modal.getOrCreateInstance(assignModal()).hide();
        window.location.reload();
      })
      .catch(function () {
        button.disabled = false;
        Dialog.alert(button.dataset.errorLabel || assignModal().dataset.errorLabel || "No se pudo asignar el pago.", { title: "Error", variant: "danger" });
      });
  }

  // -------------------------------------------------------------- Reconcile

  var reconcileState = { sourceId: null, kind: null, appBalance: 0, isDebt: false };

  function reconcileModal() {
    return document.getElementById("reconcileModal");
  }

  function openReconcile(button) {
    var modal = reconcileModal();
    var kind = button.dataset.kind || "account";
    reconcileState = {
      sourceId: button.dataset.sourceId,
      kind: kind,
      appBalance: parseMoney(button.dataset.appBalance),
      isDebt: kind === "credit_card" || kind === "loan"
    };

    modal.querySelector(".js-modal-title").textContent = button.dataset.modalTitle ||
      modal.dataset.accountModalTitle || "Conciliar";
    modal.querySelector(".js-source-name").textContent = button.dataset.name;
    modal.querySelector(".js-source-meta").textContent = button.dataset.meta || "—";
    modal.querySelector(".js-balance-label").textContent = button.dataset.balanceLabel ||
      (reconcileState.isDebt ? modal.dataset.debtBalanceLabel : modal.dataset.accountBalanceLabel);
    modal.querySelector(".js-movements-title").textContent = button.dataset.movementsTitle ||
      (reconcileState.isDebt ? modal.dataset.debtMovementsTitle : modal.dataset.accountMovementsTitle);
    modal.querySelector(".js-app-balance").textContent = button.dataset.appBalanceFormatted ||
      formatMoney(reconcileState.appBalance);
    modal.querySelector(".js-movement-count").textContent = "";

    // The real balance is intentionally not remembered: every reconciliation
    // starts from the current app balance and an empty input.
    var actual = modal.querySelector("#reconcileActualBalance");
    actual.value = "";
    actual.classList.remove("is-invalid");
    modal.querySelector("#reconcileBalanceError").textContent = "";
    updateDifference();

    modal.querySelector("#reconcileSearchInput").value = "";
    resetMovementResults();
    noteInput().value = "";

    // Populate the Crear expense / Crear ingreso links BEFORE the user types
    // anything — otherwise they keep href="#" and the first click is dead.
    updatePrefillLinks();

    // A loan difference is resolved by registering the real Payment from the
    // loan page, so the expense/income shortcuts would be misleading there.
    var isLoan = kind === "loan";
    modal.querySelector("#reconcileCreateExpense").classList.toggle("d-none", isLoan);
    modal.querySelector("#reconcileCreateIncome").classList.toggle("d-none", isLoan);

    movementState = { page: 1, perPage: 8, hasMore: false, loading: false };
    bootstrap.Modal.getOrCreateInstance(modal).show();
    fetchMovements();

    var mode = button.dataset.mode || "balance";
    setTimeout(function () {
      if (mode === "movements") {
        modal.querySelector("#reconcileSearchInput").focus();
      } else {
        actual.focus();
      }
    }, 120);
  }

  function updateDifference() {
    var modal = reconcileModal();
    var input = modal.querySelector("#reconcileActualBalance");
    var target = modal.querySelector(".js-difference");
    var hint = modal.querySelector(".js-difference-hint");

    if (input.value.trim() === "") {
      target.textContent = "—";
      target.classList.remove("is-zero", "is-positive", "is-negative");
      hint.textContent = modal.dataset.differenceHint || "";
      return;
    }

    var difference = parseUserMoney(input.value) - reconcileState.appBalance;
    var prefix = difference > 0 ? "+ " : difference < 0 ? "− " : "";
    target.textContent = prefix + formatMoney(Math.abs(difference));
    target.classList.toggle("is-zero", difference === 0);
    target.classList.toggle("is-positive", difference !== 0);
    target.classList.remove("is-negative");
    if (difference === 0) {
      hint.textContent = modal.dataset.differenceZero || "";
    } else if (difference > 0) {
      hint.textContent = modal.dataset.differencePositive || "";
    } else {
      hint.textContent = modal.dataset.differenceNegative || "";
    }
  }

  // Raw text as typed — the server normalizes es-CO money with
  // MoneyFormat.normalize, which also preserves negative balances.
  function rawActualBalance() {
    return reconcileModal().querySelector("#reconcileActualBalance").value.trim();
  }

  function showBalanceError(message) {
    var modal = reconcileModal();
    var input = modal.querySelector("#reconcileActualBalance");
    input.classList.add("is-invalid");
    modal.querySelector("#reconcileBalanceError").textContent = message;
    input.focus();
  }

  function clearBalanceError() {
    var modal = reconcileModal();
    modal.querySelector("#reconcileActualBalance").classList.remove("is-invalid");
    modal.querySelector("#reconcileBalanceError").textContent = "";
  }

  function submitAdjust() {
    var value = rawActualBalance();
    if (!validUserMoney(value)) {
      showBalanceError(reconcileModal().dataset.invalidBalance || "Ingresa un saldo válido.");
      return;
    }
    clearBalanceError();

    var button = document.getElementById("reconcileAdjust");
    button.disabled = true;

    post(reconcileModal().dataset.balanceUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      actual_balance: value,
      adjust: true,
      note: noteInput().value.trim(),
      period: reconcileModal().dataset.period || ""
    }).then(function () {
      bootstrap.Modal.getOrCreateInstance(reconcileModal()).hide();
      window.location.reload();
    }).catch(function () {
      button.disabled = false;
    });
  }

  // "Todo está bien": no balance change, no note — the current balance is
  // confirmed as the real one and the row turns verified.
  function submitAllGood() {
    var button = document.getElementById("reconcileAllGood");
    button.disabled = true;

    post(reconcileModal().dataset.balanceUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      mark_ok: true,
      period: reconcileModal().dataset.period || ""
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

    post(reconcileModal().dataset.leaveUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      period: reconcileModal().dataset.period || ""
    }).then(function () {
      bootstrap.Modal.getOrCreateInstance(reconcileModal()).hide();
      window.location.reload();
    }).catch(function () {
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
    list.innerHTML = "<div class='rec-movement-empty js-search-empty'>" +
      escapeHtml(list.dataset.hint || "") + "</div>";
  }

  function movementResultRow(movement) {
    var kindLabel = movement.kind_label || (movement.kind === "income" ? "Ingreso" : "Gasto");
    var directionClass = movement.kind === "income" ? "is-in" : "is-out";
    var secondary = movement.secondary ? "<span class='rec-movement-secondary'>" + escapeHtml(movement.secondary) + "</span>" : "";
    return "<div class='rec-movement-item' role='listitem'>" +
      "<span class='rec-movement-kind " + directionClass + "'>" + escapeHtml(kindLabel) + "</span>" +
      "<span class='rec-movement-name'>" + escapeHtml(movement.description) + secondary + "</span>" +
      "<span class='rec-movement-meta'>" + escapeHtml(formatMoney(movement.amount)) + " · " +
      escapeHtml(formatDate(movement.date)) + "</span>" +
      "<a class='rec-movement-open' href='" + escapeHtml(movement.edit_url) +
      "' target='_blank' rel='noopener'>" + escapeHtml(reconcileModal().dataset.openLabel || "Abrir") + "</a>" +
      "</div>";
  }

  function fetchMovements(append) {
    if (movementState.loading) return;
    movementState.loading = true;

    var modal = reconcileModal();
    var list = document.getElementById("reconcileSearchResults");
    var loadMore = document.getElementById("reconcileLoadMore");
    var query = modal.querySelector("#reconcileSearchInput").value.trim();

    if (!append) {
      movementState.page = 1;
      list.innerHTML = "<div class='rec-movement-empty'>" + escapeHtml(modal.dataset.loading || "") + "</div>";
    } else {
      loadMore.disabled = true;
    }

    var params = new URLSearchParams({
      q: query,
      money_source_id: reconcileState.sourceId,
      period: modal.dataset.period || "",
      page: movementState.page,
      per_page: movementState.perPage
    });

    getJSON(modal.dataset.movementsUrl + "?" + params.toString()).then(function (data) {
      var movements = (data && data.movements) || [];
      if (!append) list.innerHTML = "";

      if (!movements.length && !append) {
        list.innerHTML = "<div class='rec-movement-empty'>" + escapeHtml(modal.dataset.noMovements || "") + "</div>";
      } else {
        movements.forEach(function (movement) {
          list.insertAdjacentHTML("beforeend", movementResultRow(movement));
        });
      }

      movementState.page = data.page || movementState.page;
      movementState.hasMore = !!data.has_more;
      var total = data.total_count || 0;
      var count = modal.querySelector(".js-movement-count");
      if (total > 0) {
        var template = total === 1 ? modal.dataset.countOne : modal.dataset.countOther;
        count.textContent = (template || "%{count}").replace("%{count}", total);
      } else {
        count.textContent = "";
      }

      if (movementState.hasMore) {
        loadMore.classList.remove("d-none");
        loadMore.disabled = false;
        loadMore.innerHTML = escapeHtml(modal.dataset.loadMore || "") + " <i class='ti ti-arrow-down' aria-hidden='true'></i>";
      } else if (list.querySelector(".rec-movement-item")) {
        loadMore.classList.remove("d-none");
        loadMore.disabled = true;
        loadMore.textContent = modal.dataset.noMore || "";
      } else {
        loadMore.classList.add("d-none");
      }
    }).catch(function () {
      if (append) movementState.page -= 1;
      if (!append) {
        list.innerHTML = "<div class='rec-movement-empty is-error'>" +
          escapeHtml(modal.dataset.movementError || "") + "</div>";
      }
      loadMore.classList.add("d-none");
    }).finally(function () {
      movementState.loading = false;
      loadMore.disabled = false;
    });
  }

  function loadMoreMovements() {
    if (!movementState.hasMore) return;
    movementState.page += 1;
    fetchMovements(true);
  }

  // ------------------------------------------------------------------ Wiring

  document.addEventListener("click", function (event) {
    if (event.target.closest(".rec-payment-open")) return;

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

    if (event.target.closest("#reconcileLoadMore")) {
      loadMoreMovements();
    }
  });

  document.addEventListener("keydown", function (event) {
    if (event.key !== "Enter" && event.key !== " ") return;
    var result = event.target.closest("#assignExpenseResults .js-assign-result");
    if (!result) return;
    event.preventDefault();
    selectAssignResult(result);
  });

  document.addEventListener("input", function (event) {
    if (event.target.id === "reconcileActualBalance") {
      clearBalanceError();
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

  var debounceFetchMovements = debounce(function () {
    movementState.page = 1;
    fetchMovements(false);
  }, 300);

  // CSP-safe: set the progress bar width from its data attribute instead of
  // an inline style="width: ...%" attribute in the markup.
  document.querySelectorAll(".rec-progress-fill[data-progress]").forEach(function (bar) {
    bar.style.width = (bar.getAttribute("data-progress") || 0) + "%";
  });
})();

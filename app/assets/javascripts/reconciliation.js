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

  // Loans use their own modal so the mockup layout does not constrain the
  // shared modal used by accounts, cards and wallets.
  var reconcileState = {
    modalId: null, sourceId: null, kind: null, appBalance: 0,
    isDebt: false, isLoan: false, loanInterest: null
  };

  function activeModal() {
    return document.getElementById(reconcileState.modalId);
  }

  function q(selector) {
    var modal = activeModal();
    return modal ? modal.querySelector(selector) : null;
  }

  function openReconcile(button) {
    var kind = button.dataset.kind || "account";
    var isLoan = kind === "loan";
    var modal = document.getElementById(isLoan ? "reconcileLoanModal" : "reconcileModal");
    if (!modal) return;

    var loanInterest = null;
    if (isLoan && button.dataset.loanInterestEnabled === "true") {
      loanInterest = {
        accruedFormatted: button.dataset.loanAccruedInterestFormatted || "",
        totalFormatted: button.dataset.loanEstimatedTotalFormatted || ""
      };
    }

    reconcileState = {
      modalId: modal.id,
      sourceId: button.dataset.sourceId,
      kind: kind,
      appBalance: parseMoney(button.dataset.appBalance),
      isDebt: kind === "credit_card" || isLoan,
      isLoan: isLoan,
      loanInterest: loanInterest
    };

    modal.querySelector(".js-modal-title").textContent = button.dataset.modalTitle ||
      (isLoan ? modal.dataset.debtModalTitle : modal.dataset.accountModalTitle) || "Conciliar";
    modal.querySelector(".js-source-name").textContent = button.dataset.name;
    modal.querySelector(".js-source-meta").textContent = button.dataset.meta || "—";

    var balanceLabel = modal.querySelector(".js-balance-label");
    if (balanceLabel) {
      balanceLabel.textContent = button.dataset.balanceLabel ||
        (reconcileState.isDebt ? modal.dataset.debtBalanceLabel : modal.dataset.accountBalanceLabel);
    }

    modal.querySelector(".js-movements-title").textContent = button.dataset.movementsTitle ||
      (reconcileState.isDebt ? modal.dataset.debtMovementsTitle : modal.dataset.accountMovementsTitle);
    var appBalance = modal.querySelector(".js-app-balance");
    if (appBalance) {
      appBalance.textContent = button.dataset.appBalanceFormatted || formatMoney(reconcileState.appBalance);
    }
    modal.querySelector(".js-movement-count").textContent = "";

    applyLoanPresentation(button);

    // The real balance is intentionally not remembered: every reconciliation
    // starts from the current app balance and an empty input.
    var actual = modal.querySelector(".js-actual-input");
    actual.value = "";
    actual.classList.remove("is-invalid");
    clearBalanceError();
    updateDifference();

    modal.querySelector(".js-movement-search").value = "";
    resetMovementResults();
    noteInput().value = "";

    // The expense/income shortcuts only exist in the shared modal.
    if (!isLoan) updatePrefillLinks();

    movementState = { page: 1, perPage: 8, hasMore: false, loading: false };
    bootstrap.Modal.getOrCreateInstance(modal).show();
    fetchMovements();

    var mode = button.dataset.mode || "balance";

    if (isLoan) {
      // The loan modal leads with the principal/interest breakdown. Focusing a
      // field would scroll the modal body past that information, so it always
      // opens at the top and never focuses the principal input.
      var loanBody = modal.querySelector(".rec-loan-body") || modal.querySelector(".modal-body");
      var resetLoanScroll = function () {
        if (loanBody) loanBody.scrollTop = 0;
      };
      modal.addEventListener("shown.bs.modal", resetLoanScroll, { once: true });
      resetLoanScroll();
      return;
    }

    var focusTarget = mode === "movements" ? modal.querySelector(".js-movement-search") : actual;
    modal.addEventListener("shown.bs.modal", function focusReconcileTarget() {
      focusTarget.focus();
    }, { once: true });
    setTimeout(function () {
      focusTarget.focus();
    }, 120);
  }

  // The loan modal always shows the principal card. The interest-card and its
  // values only appear when the server supplied a displayable estimate.
  function applyLoanPresentation(button) {
    if (!reconcileState.isLoan) return;

    var modal = activeModal();
    var interest = reconcileState.loanInterest;
    var summary = modal.querySelector(".js-loan-summary");
    var breakdown = modal.querySelector(".js-loan-breakdown");

    summary.classList.toggle("is-single", !interest);
    breakdown.classList.toggle("d-none", !interest);

    var principal = button.dataset.appBalanceFormatted || formatMoney(reconcileState.appBalance);
    modal.querySelector(".js-loan-principal").textContent = principal;
    modal.querySelector(".js-loan-principal-part").textContent = principal;

    if (!interest) return;

    modal.querySelector(".js-loan-accrued").textContent = interest.accruedFormatted;
    modal.querySelector(".js-loan-total").textContent = interest.totalFormatted;
  }

  function differenceCopy() {
    var modal = activeModal();
    return {
      hint: modal.dataset.differenceHint,
      zero: modal.dataset.differenceZero,
      positive: modal.dataset.differencePositive,
      negative: modal.dataset.differenceNegative
    };
  }

  function updateDifference() {
    var modal = activeModal();
    var input = modal.querySelector(".js-actual-input");
    var target = modal.querySelector(".js-difference");
    var hint = modal.querySelector(".js-difference-hint");
    var copy = differenceCopy();

    if (input.value.trim() === "") {
      target.textContent = "—";
      target.classList.remove("is-zero", "is-positive", "is-negative");
      hint.textContent = copy.hint || "";
      return;
    }

    var difference = parseUserMoney(input.value) - reconcileState.appBalance;
    var prefix = difference > 0 ? "+ " : difference < 0 ? "− " : "";
    target.textContent = prefix + formatMoney(Math.abs(difference));
    target.classList.toggle("is-zero", difference === 0);
    target.classList.toggle("is-positive", difference !== 0);
    target.classList.remove("is-negative");
    if (difference === 0) {
      hint.textContent = copy.zero || "";
    } else if (difference > 0) {
      hint.textContent = copy.positive || "";
    } else {
      hint.textContent = copy.negative || "";
    }
  }

  // Raw text as typed — the server normalizes es-CO money with
  // MoneyFormat.normalize, which also preserves negative balances.
  function rawActualBalance() {
    return q(".js-actual-input").value.trim();
  }

  function showBalanceError(message) {
    var input = q(".js-actual-input");
    var error = q(".js-balance-error");
    input.classList.add("is-invalid");
    var wrapper = input.closest(".rec-loan-input");
    if (wrapper) wrapper.classList.add("is-invalid");
    error.textContent = message;
    error.hidden = false;
    input.focus();
  }

  function clearBalanceError() {
    var input = q(".js-actual-input");
    var error = q(".js-balance-error");
    if (input) {
      input.classList.remove("is-invalid");
      var wrapper = input.closest(".rec-loan-input");
      if (wrapper) wrapper.classList.remove("is-invalid");
    }
    if (error) {
      error.textContent = "";
      error.hidden = true;
    }
  }

  function submitAdjust() {
    var value = rawActualBalance();
    var modal = activeModal();
    if (!validUserMoney(value)) {
      showBalanceError(modal.dataset.invalidBalance || "Ingresa un saldo válido.");
      return;
    }
    clearBalanceError();

    var button = q(".js-reconcile-adjust");
    button.disabled = true;

    post(modal.dataset.balanceUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      actual_balance: value,
      adjust: true,
      note: noteInput().value.trim(),
      period: modal.dataset.period || ""
    }).then(function () {
      bootstrap.Modal.getOrCreateInstance(modal).hide();
      window.location.reload();
    }).catch(function () {
      button.disabled = false;
    });
  }

  // "Todo está bien": no balance change, no note — the current balance is
  // confirmed as the real one and the row turns verified.
  function submitAllGood() {
    var modal = activeModal();
    var button = q(".js-reconcile-all-good");
    button.disabled = true;

    post(modal.dataset.balanceUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      mark_ok: true,
      period: modal.dataset.period || ""
    }).then(function () {
      bootstrap.Modal.getOrCreateInstance(modal).hide();
      window.location.reload();
    }).catch(function () {
      button.disabled = false;
    });
  }

  function noteInput() {
    return q(".js-note");
  }

  function submitLeavePending() {
    var modal = activeModal();
    var button = q(".js-reconcile-leave-pending");
    button.disabled = true;

    post(modal.dataset.leaveUrl.replace("SOURCE_ID", reconcileState.sourceId), {
      period: modal.dataset.period || ""
    }).then(function () {
      bootstrap.Modal.getOrCreateInstance(modal).hide();
      window.location.reload();
    }).catch(function () {
      button.disabled = false;
    });
  }

  function updatePrefillLinks() {
    var modal = activeModal();
    var createExpense = modal.querySelector(".js-create-expense");
    var createIncome = modal.querySelector(".js-create-income");
    if (!createExpense || !createIncome) return;

    var actual = rawActualBalance();
    var difference = parseUserMoney(actual) - reconcileState.appBalance;
    var today = new Date().toISOString().slice(0, 10);

    // Without a typed "Saldo real" the difference is unknown: prefill only
    // the money source and the date, and let the user enter the amount.
    var params = {
      money_source_id: reconcileState.sourceId,
      date: today
    };
    if (actual !== "") {
      params.amount = Math.abs(difference).toFixed(2);
    }

    createExpense.href = modal.dataset.createExpenseUrl + "?" + new URLSearchParams(params).toString();
    createIncome.href = modal.dataset.createIncomeUrl + "?" + new URLSearchParams(params).toString();
  }

  function isLoanMovementLayout() {
    return activeModal().dataset.movementLayout === "loan";
  }

  function movementEmptyMarkup(label, isError) {
    if (isLoanMovementLayout()) {
      return "<div class='rec-loan-empty" + (isError ? " is-error" : "") + "'>" +
        escapeHtml(label || "") + "</div>";
    }
    return "<div class='rec-movement-empty" + (isError ? " is-error" : "") + "'>" +
      escapeHtml(label || "") + "</div>";
  }

  function resetMovementResults() {
    var list = q(".js-movement-results");
    list.innerHTML = movementEmptyMarkup(list.dataset.hint || "");
  }

  function loanMovementResultRow(movement) {
    var kindLabel = movement.kind_label || (movement.kind === "income" ? "Ingreso" : "Gasto");
    var directionClass = movement.kind === "income" ? "is-in" : "is-out";
    var secondary = movement.secondary ? " · " + movement.secondary : "";
    return "<div class='rec-loan-movement' role='listitem'>" +
      "<span class='rec-loan-movement-dot " + directionClass + "'></span>" +
      "<div class='rec-loan-movement-copy'>" +
      "<span class='rec-loan-movement-name'>" + escapeHtml(movement.description) + "</span>" +
      "<span class='rec-loan-movement-type'>" + escapeHtml(kindLabel) + escapeHtml(secondary) + "</span>" +
      "</div>" +
      "<span class='rec-loan-movement-value'>" + escapeHtml(formatMoney(movement.amount)) + " · " +
      escapeHtml(formatDate(movement.date)) + "</span>" +
      "<a class='rec-loan-movement-open' href='" + escapeHtml(movement.edit_url) +
      "' target='_blank' rel='noopener'>" + escapeHtml(activeModal().dataset.openLabel || "Abrir") + "</a>" +
      "</div>";
  }

  function movementResultRow(movement) {
    if (isLoanMovementLayout()) return loanMovementResultRow(movement);

    var kindLabel = movement.kind_label || (movement.kind === "income" ? "Ingreso" : "Gasto");
    var directionClass = movement.kind === "income" ? "is-in" : "is-out";
    var secondary = movement.secondary ? "<span class='rec-movement-secondary'>" + escapeHtml(movement.secondary) + "</span>" : "";
    return "<div class='rec-movement-item' role='listitem'>" +
      "<span class='rec-movement-kind " + directionClass + "'>" + escapeHtml(kindLabel) + "</span>" +
      "<span class='rec-movement-name'>" + escapeHtml(movement.description) + secondary + "</span>" +
      "<span class='rec-movement-meta'>" + escapeHtml(formatMoney(movement.amount)) + " · " +
      escapeHtml(formatDate(movement.date)) + "</span>" +
      "<a class='rec-movement-open' href='" + escapeHtml(movement.edit_url) +
      "' target='_blank' rel='noopener'>" + escapeHtml(activeModal().dataset.openLabel || "Abrir") + "</a>" +
      "</div>";
  }

  function fetchMovements(append) {
    if (movementState.loading) return;
    movementState.loading = true;

    var modal = activeModal();
    var list = q(".js-movement-results");
    var loadMore = q(".js-load-more");
    var query = q(".js-movement-search").value.trim();

    if (!append) {
      movementState.page = 1;
      list.innerHTML = movementEmptyMarkup(modal.dataset.loading || "");
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
        list.innerHTML = movementEmptyMarkup(modal.dataset.noMovements || "");
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
      } else if (list.querySelector(".rec-movement-item, .rec-loan-movement")) {
        loadMore.classList.remove("d-none");
        loadMore.disabled = true;
        loadMore.textContent = modal.dataset.noMore || "";
      } else {
        loadMore.classList.add("d-none");
      }
    }).catch(function () {
      if (append) movementState.page -= 1;
      if (!append) {
        list.innerHTML = movementEmptyMarkup(modal.dataset.movementError || "", true);
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

    if (event.target.closest(".js-reconcile-adjust")) {
      submitAdjust();
      return;
    }

    if (event.target.closest(".js-reconcile-all-good")) {
      submitAllGood();
      return;
    }

    if (event.target.closest(".js-reconcile-leave-pending")) {
      submitLeavePending();
      return;
    }

    if (event.target.closest(".js-load-more")) {
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
    if (event.target.classList.contains("js-actual-input")) {
      clearBalanceError();
      updateDifference();
      updatePrefillLinks();
    }
    if (event.target.id === "assignExpenseSearch") {
      fetchAssignResults(event.target.value);
    }
    if (event.target.classList.contains("js-movement-search")) {
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

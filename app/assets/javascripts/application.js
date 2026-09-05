(function () {
  // Colombian number rule: "." is the thousands separator and "," is the
  // decimal separator. A number never has more than one comma — only the
  // first comma typed starts the decimals; extra commas are ignored.

  function sanitizeValue(value) {
    // Machine format for form submission: drop the thousands dots, turn the
    // single decimal comma into a dot so server-side decimal casting parses.
    var raw = String(value == null ? "" : value).replace(/\./g, "").trim();
    var commaIndex = raw.indexOf(",");
    if (commaIndex === -1) return raw;

    var integerPart = raw.slice(0, commaIndex);
    var decimalPart = raw.slice(commaIndex + 1).replace(/,/g, "");
    return integerPart + "." + decimalPart;
  }

  function formatValue(value, finalize) {
    var raw = String(value == null ? "" : value).replace(/\./g, "").trim();
    if (!raw) return "";

    var commaIndex = raw.indexOf(",");
    var hasComma = commaIndex !== -1;
    var integerPart = (hasComma ? raw.slice(0, commaIndex) : raw).replace(/[^\d]/g, "");
    var decimalPart = hasComma
      ? raw.slice(commaIndex + 1).replace(/,/g, "").replace(/[^\d]/g, "").slice(0, 2)
      : "";

    if (!integerPart) integerPart = "0";
    integerPart = String(parseInt(integerPart, 10)).replace(/\B(?=(\d{3})+(?!\d))/g, ".");

    if (!hasComma) return integerPart;
    // Keep the comma while typing so decimals can be entered; on blur drop a
    // trailing comma with no digits after it.
    if (finalize) {
      decimalPart = decimalPart.replace(/0+$/, "");
      if (!decimalPart) return integerPart;
    }
    return integerPart + "," + decimalPart;
  }

  function formatInput(input, finalize) {
    if (!input || input.readOnly || input.disabled) return;
    var next = formatValue(input.value, finalize);
    if (input.value !== next) input.value = next;
  }

  function bindInput(input) {
    if (input.dataset.moneyBound === "true") return;
    input.dataset.moneyBound = "true";

    input.addEventListener("input", function () {
      formatInput(input, false);
    });

    input.addEventListener("blur", function () {
      formatInput(input, true);
    });

    formatInput(input, true);
  }

  function bindForm(form) {
    if (!form || form.dataset.moneySubmitBound === "true") return;
    form.dataset.moneySubmitBound = "true";

    form.addEventListener("submit", function () {
      form.querySelectorAll("[data-money-input='true']").forEach(function (input) {
        input.value = sanitizeValue(input.value);
      });
    });
  }

  function init(root) {
    var scope = root || document;
    scope.querySelectorAll("[data-money-input='true']").forEach(bindInput);
    scope.querySelectorAll("form").forEach(bindForm);
    bindAvailableCredit(scope);
  }

  window.MoneyInputs = {
    init: init,
    formatField: function (input, finalize) {
      formatInput(input, finalize !== false);
    },
    formatValue: formatValue,
    sanitizeValue: sanitizeValue
  };

  document.addEventListener("DOMContentLoaded", function () {
    init(document);
    bindChoiceCards();
  });

  document.addEventListener("turbo:load", function () {
    init(document);
    bindChoiceCards();
  });

  function bindChoiceCards() {
    document.querySelectorAll('[role="radiogroup"] .choice-card').forEach(function (card) {
      if (card.dataset.choiceBound === "true") return;
      card.dataset.choiceBound = "true";

      card.addEventListener("click", function () {
        var group = card.closest('[role="radiogroup"]');
        group.querySelectorAll('.choice-card').forEach(function (c) {
          c.classList.remove('selected');
          c.setAttribute('aria-checked', 'false');
        });
        card.classList.add('selected');
        card.setAttribute('aria-checked', 'true');

        var radio = card.querySelector('input[type="radio"]');
        if (radio) radio.checked = true;

        var form = card.closest('form');
        if (form) form.submit();
      });
    });
  }

  function toNumber(str) {
    var n = parseFloat(String(str == null ? "" : str).replace(/[^\d.]/g, ""));
    return isNaN(n) ? 0 : n;
  }

  function formatCurrencyNumber(value) {
    // es-CO: "." thousands, "," decimals.
    return "$" + Math.max(0, value).toLocaleString("es-CO", { maximumFractionDigits: 2 });
  }

  function updateAvailableCredit(row) {
    var balanceInput = row.querySelector("[data-ca-balance='true']");
    var limitInput = row.querySelector("[data-ca-limit='true']");
    var readout = row.querySelector("[data-ca-available='true']");
    if (!limitInput || !readout) return;

    var limit = toNumber(limitInput.value);
    var debt = balanceInput ? toNumber(balanceInput.value) : 0;
    readout.textContent = formatCurrencyNumber(limit - debt);
  }

  function bindAvailableCredit(scope) {
    scope.querySelectorAll(".manual-row").forEach(function (row) {
      var limitInput = row.querySelector("[data-ca-limit='true']");
      if (!limitInput || limitInput.dataset.caBound === "true") return;
      limitInput.dataset.caBound = "true";

      limitInput.addEventListener("input", function () { updateAvailableCredit(row); });
      limitInput.addEventListener("blur", function () { updateAvailableCredit(row); });

      var balanceInput = row.querySelector("[data-ca-balance='true']");
      if (balanceInput) {
        balanceInput.addEventListener("input", function () { updateAvailableCredit(row); });
        balanceInput.addEventListener("blur", function () { updateAvailableCredit(row); });
      }
    });
  }

  // ---------------------------------------------------------------- Source recognition chips
  function recognitionChipsContainer(chipsEl) { return chipsEl; }
  function recognitionCountEl(chipsEl) {
    var section = chipsEl.closest(".recognition-section");
    return section && section.querySelector("[data-recognition-count]");
  }
  function recognitionKind(chipsEl) { return chipsEl.getAttribute("data-recognition-chips"); }
  function recognitionFieldName(kind) { return kind + "[]"; }
  function recognitionRefreshCount(chipsEl) {
    var countEl = recognitionCountEl(chipsEl);
    if (!countEl) return;
    var chips = chipsEl.querySelectorAll(".recognition-chip").length;
    countEl.textContent = countEl.textContent.replace(/\d+/, String(chips));
  }

  function recognitionMakeChip(value, kind) {
    var chip = document.createElement("span");
    chip.className = "recognition-chip";
    chip.setAttribute("data-testid", "recognition-chip");

    var hidden = document.createElement("input");
    hidden.type = "hidden";
    hidden.name = recognitionFieldName(kind);
    hidden.value = value;

    var remove = document.createElement("button");
    remove.type = "button";
    remove.className = "recognition-chip-remove";
    remove.setAttribute("data-recognition-remove", "");
    remove.setAttribute("aria-label", "Remover");
    remove.innerHTML = '<i class="bi bi-x"></i>';

    chip.appendChild(document.createTextNode(value));
    chip.appendChild(hidden);
    chip.appendChild(remove);
    return chip;
  }

  function recognitionSetupAddInput(chipAddBtn) {
    var chipsEl = chipAddBtn.closest("[data-recognition-chips]");
    if (!chipsEl || chipAddBtn.dataset.recognitionBound === "true") return;
    chipAddBtn.dataset.recognitionBound = "true";
    var kind = recognitionKind(chipsEl);

    chipAddBtn.addEventListener("click", function () {
      if (chipsEl.querySelector(".recognition-inline-add")) return;
      var input = document.createElement("input");
      input.type = "text";
      input.className = "form-control form-control-sm recognition-inline-add";
      input.setAttribute("data-recognition-inline-add", kind);
      input.placeholder = "...";
      chipAddBtn.parentNode.insertBefore(input, chipAddBtn);
      input.focus();

      function commit() {
        var value = input.value.trim();
        if (value) {
          chipsEl.insertBefore(recognitionMakeChip(value, kind), chipAddBtn);
          recognitionRefreshCount(chipsEl);
          recognitionMarkDirty();
        }
        input.remove();
      }
      input.addEventListener("keydown", function (e) { if (e.key === "Enter") { e.preventDefault(); commit(); } });
      input.addEventListener("blur", commit);
    });
  }

  function recognitionAcceptChip(suggestedChip, panel) {
    var chipsEl = panel.querySelector("[data-recognition-chips='" + suggestedChip.dataset.suggestedFor + "']");
    if (!chipsEl) return;
    var value = suggestedChip.dataset.suggestedValue || "";
    var kind = suggestedChip.dataset.suggestedFor;
    var existing = chipsEl.querySelectorAll('input[name="' + recognitionFieldName(kind) + '"]');
    for (var i = 0; i < existing.length; i++) {
      if (existing[i].value === value) return;
    }
    chipsEl.insertBefore(recognitionMakeChip(value, kind), chipsEl.querySelector(".recognition-chip-add"));
    recognitionRefreshCount(chipsEl);
  }

  function recognitionDismissChip(suggestedChip, form) {
    if (!form) return;
    var hidden = document.createElement("input");
    hidden.type = "hidden";
    hidden.name = "dismissed[" + suggestedChip.dataset.suggestedFor + "][]";
    hidden.value = suggestedChip.dataset.suggestedValue || "";
    form.appendChild(hidden);
  }

  // --- drawer dirty tracking -------------------------------------------------
  function recognitionForm() { return document.querySelector("form.recognition-form"); }
  function recognitionMarkDirty() {
    var form = recognitionForm();
    if (form) form.dataset.recognitionDirty = "true";
  }
  function recognitionIsDirty() {
    var form = recognitionForm();
    return !!form && form.dataset.recognitionDirty === "true";
  }
  function recognitionLeaveUrl() {
    var overlay = document.querySelector(".recognition-drawer-overlay");
    if (overlay && overlay.dataset.closeUrl) return overlay.dataset.closeUrl;
    var cancel = document.querySelector(".recognition-drawer-foot [data-recognition-close]");
    return cancel ? cancel.getAttribute("href") : window.location.pathname;
  }
  function recognitionConfirmLeave() {
    var form = recognitionForm();
    var message = (form && form.dataset.unsavedMessage) || "Are you sure?";
    return !recognitionIsDirty() || window.confirm(message);
  }

  // ---------------------------------------------------------------- Confirm dialogs
  // Turbo / Rails UJS are not loaded in this app, so [data-turbo-confirm] and
  // [data-confirm] are inert by default. Implement confirm-before-submit here:
  // the message may live on the form (button_to form: { data: ... }) or on the
  // submit button itself.
  document.addEventListener("submit", function (e) {
    var form = e.target;
    if (!form || form.nodeType !== 1) return;
    var message = form.dataset.turboConfirm || form.dataset.confirm;
    if (!message && e.submitter) {
      message = e.submitter.dataset.turboConfirm || e.submitter.dataset.confirm;
    }
    if (!message) return;

    e.preventDefault();
    delete form.dataset.turboConfirm;
    delete form.dataset.confirm;
    if (e.submitter) {
      delete e.submitter.dataset.turboConfirm;
      delete e.submitter.dataset.confirm;
    }
    if (window.confirm(message)) {
      // Deferring avoids a Chrome quirk: requestSubmit() called reentrantly
      // from a submit handler that called preventDefault() re-dispatches a
      // submit event whose defaultPrevented flag is already true, so the
      // form never actually submits.
      setTimeout(function () {
        form.requestSubmit(e.submitter || undefined);
      }, 0);
    }
  }, true);

  // Delegate: pick up any chips rendered on the page (also after form edits).
  document.addEventListener("click", function (e) {
    var closer = e.target.closest("[data-recognition-close]");
    if (closer) {
      if (!recognitionConfirmLeave()) { e.preventDefault(); return; }
      if (closer.tagName !== "A") {
        e.preventDefault();
        var url = closer.dataset.closeUrl || recognitionLeaveUrl();
        if (window.Turbo) { window.Turbo.visit(url); } else { window.location.href = url; }
      }
      return;
    }
    var remove = e.target.closest("[data-recognition-remove]");
    if (remove) {
      var chipsEl = remove.closest("[data-recognition-chips]");
      remove.closest(".recognition-chip").remove();
      if (chipsEl) recognitionRefreshCount(chipsEl);
      recognitionMarkDirty();
      return;
    }
    var focusBtn = e.target.closest("[data-recognition-accept-suggestion]");
    if (focusBtn) {
      var chip = focusBtn.closest(".recognition-chip-suggested");
      var panel = focusBtn.closest(".recognition-drawer");
      if (chip && panel) recognitionAcceptChip(chip, panel);
      if (chip) chip.remove();
      recognitionMarkDirty();
      return;
    }
    var dismissBtn = e.target.closest("[data-recognition-dismiss-suggestion]");
    if (dismissBtn) {
      var suggested = dismissBtn.closest(".recognition-chip-suggested");
      if (suggested) recognitionDismissChip(suggested, recognitionForm());
      if (suggested) suggested.remove();
      recognitionMarkDirty();
      return;
    }
  });

  document.addEventListener("submit", function (e) {
    var form = e.target.closest("form.recognition-form");
    if (form && !e.defaultPrevented) delete form.dataset.recognitionDirty;
  });

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape" || !document.querySelector(".recognition-drawer")) return;
    if (!recognitionConfirmLeave()) return;
    var url = recognitionLeaveUrl();
    if (window.Turbo) { window.Turbo.visit(url); } else { window.location.href = url; }
  });

  window.addEventListener("beforeunload", function (e) {
    if (!recognitionIsDirty()) return;
    e.preventDefault();
    e.returnValue = "";
  });

  function bindRecognition(scope) {
    scope.querySelectorAll("[data-recognition-chips] .recognition-chip-add").forEach(recognitionSetupAddInput);
  }

  document.addEventListener("DOMContentLoaded", function () {
    bindRecognition(document);
  });

  // --- Async Gmail sync auto-refresh --------------------------------------
  // A sync runs as a background job; the settings page offers no inline
  // result until it finishes. When the user clicks "Sincronizar", we remember
  // that a sync is pending (in sessionStorage) and, on the page that loads
  // after the redirect, poll the sync_status endpoint. Once the connection is
  // no longer "syncing" and a summary is available, we stop and refresh so
  // the fresh imports / last_synced / suggestions appear without a manual reload.
  var SYNC_POLL_KEY = "gmailSyncPending";
  var SYNC_POLL_INTERVAL = 2000;
  var SYNC_POLL_TIMEOUT = 5 * 60 * 1000; // give up after 5 minutes

  function gmailSyncStatusPath() {
    var btn = document.querySelector("[data-sync-status-path]");
    return btn ? btn.getAttribute("data-sync-status-path") : null;
  }

  function startSyncPoller() {
    var statusPath = gmailSyncStatusPath();
    if (!statusPath) return;

    var startedAt = Date.now();
    var timer = setInterval(function () {
      fetch(statusPath, { headers: { "Accept": "application/json" } })
        .then(function (res) { return res.ok ? res.json() : null; })
        .then(function (state) {
          if (!state) return; // transient error: keep polling

          var done = !state.syncing && state.summary;
          var timedOut = Date.now() - startedAt > SYNC_POLL_TIMEOUT;
          if (!done && !timedOut) return;

          clearInterval(timer);
          try { sessionStorage.removeItem(SYNC_POLL_KEY); } catch (_) {}
          if (window.Turbo) { window.Turbo.visit(window.location.href); }
          else { window.location.reload(); }
        })
        .catch(function () { /* network blip: keep polling until timeout */ });
    }, SYNC_POLL_INTERVAL);
  }

  document.addEventListener("submit", function (e) {
    var btn = e.target.querySelector && e.target.querySelector("[data-sync-status-path]");
    if (!btn) return;
    try { sessionStorage.setItem(SYNC_POLL_KEY, "1"); } catch (_) {}
    startSyncPoller();
  });

  // If we land here with a pending sync (e.g. a hard navigation that dropped
  // the in-flight poller), resume polling.
  var hasPendingSync = false;
  try { hasPendingSync = sessionStorage.getItem(SYNC_POLL_KEY) === "1"; } catch (_) {}
  if (hasPendingSync && gmailSyncStatusPath()) {
    startSyncPoller();
    try { sessionStorage.removeItem(SYNC_POLL_KEY); } catch (_) {}
  }
})();

(function () {
  // Colombian number rule: "." is the thousands separator and "," is the
  // decimal separator. A number never has more than one comma — only the
  // first comma typed starts the decimals; extra commas are ignored.

  // Splits a money string into integer and decimal parts regardless of the
  // separator used. es-CO types "1.234,56" (comma decimal, dotted thousands);
  // many users type "1234.56" or "5.50" with a dot decimal. A comma always
  // wins as the decimal separator; without a comma a trailing dot group of
  // 1-2 digits is treated as a decimal separator, otherwise dots group
  // thousands ("1.234" stays one thousand two hundred thirty-four).
  function decimalParts(value) {
    var raw = String(value == null ? "" : value).trim();
    // A leading minus is meaningful (negative balances); keep it through the
    // split and re-attach it to the integer part. `-` elsewhere is ignored
    // along with the other non-digit noise.
    var negative = raw.charAt(0) === "-";
    if (negative) raw = raw.slice(1);
    var sign = negative ? "-" : "";

    var commaIndex = raw.indexOf(",");
    if (commaIndex !== -1) {
      var integer = raw.slice(0, commaIndex).replace(/[^\d]/g, "");
      var decimal = raw.slice(commaIndex + 1).replace(/[^\d]/g, "");
      return { integer: sign + integer, decimal: decimal };
    }

    var lastDot = raw.lastIndexOf(".");
    if (lastDot !== -1) {
      var tail = raw.slice(lastDot + 1);
      var integer = raw.slice(0, lastDot).replace(/[^\d]/g, "");
      if (/^\d{1,2}$/.test(tail) && raw.slice(0, lastDot).match(/^\d+$/)) {
        return { integer: sign + integer, decimal: tail };
      }
    }

    return { integer: sign + raw.replace(/\./g, "").replace(/[^\d]/g, ""), decimal: "" };
  }

  function sanitizeValue(value) {
    // Machine format for form submission: drop the thousands dots, turn the
    // decimal separator (comma or dot) into a dot so server-side decimal
    // casting parses.
    var parts = decimalParts(value);
    if (!parts.decimal) return parts.integer || "";
    return (parts.integer || "0") + "." + parts.decimal;
  }

  function formatValue(value, finalize, keepTrailingComma) {
    var raw = String(value == null ? "" : value).trim();
    // Only show a decimal comma when the user has actually typed one. A dot in
    // the input is a thousands separator (or a not-yet-decimal), never an
    // implicit decimal comma.
    var hasComma = raw.indexOf(",") !== -1;
    var trailingComma = !!keepTrailingComma && raw.slice(-1) === ",";

    if (!hasComma && !trailingComma) {
      // Integer-only display: strip any dots, group thousands with dots.
      var intOnly = raw.replace(/[^\d-]/g, "");
      if (!intOnly || intOnly === "-" ) return "";
      var neg = intOnly.charAt(0) === "-";
      var digits = neg ? intOnly.slice(1) : intOnly;
      if (!digits) return "";
      var grouped = String(parseInt(digits, 10) || 0).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
      return neg ? "-" + grouped : grouped;
    }

    var parts = decimalParts(value);
    var integerPart = parts.integer || "";
    var decimalPart = parts.decimal || "";
    if (!integerPart && !decimalPart && !trailingComma) return "";

    integerPart = integerPart ? String(parseInt(integerPart, 10) || 0).replace(/\B(?=(\d{3})+(?!\d))/g, ".") : "";
    if (!decimalPart && !trailingComma) return integerPart;
    decimalPart = (decimalPart || "").replace(/[^\d]/g, "").slice(0, 2);

    // Keep the comma while typing so decimals can be entered; on blur drop a
    // trailing comma with no digits after it.
    if (finalize) {
      decimalPart = decimalPart.replace(/0+$/, "");
      if (!decimalPart && !trailingComma) return integerPart;
    }
    if (!decimalPart && trailingComma) return (integerPart || "") + ",";
    return integerPart + "," + decimalPart;
  }

  function formatInput(input, finalize, keepTrailingComma) {
    if (!input || input.readOnly || input.disabled) return;
    var next = formatValue(input.value, finalize, keepTrailingComma);
    if (input.value !== next) input.value = next;
  }

  function bindInput(input) {
    if (input.dataset.moneyBound === "true") return;
    input.dataset.moneyBound = "true";

    input.addEventListener("input", function () {
      var keep = String(input.value).trim().slice(-1) === ",";
      formatInput(input, false, keep);
    });

    input.addEventListener("blur", function () {
      formatInput(input, true, false);
    });

    formatInput(input, true, false);
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
    remove.innerHTML = '<i class="ti ti-x"></i>';

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

      // Enter commit and the blur that removing the input triggers must
      // never both add the chip: one value, one chip.
      var committed = false;
      function commit() {
        if (committed) return;
        committed = true;
        var value = input.value.trim();
        if (value) {
          chipsEl.insertBefore(recognitionMakeChip(value, kind), chipAddBtn);
          recognitionRefreshCount(chipsEl);
          recognitionMarkDirty();
        }
        input.value = "";
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
      showRecognitionVeil(closer);
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
    if (form && !e.defaultPrevented) {
      delete form.dataset.recognitionDirty;
      showRecognitionSaveLoading(e.submitter || form.querySelector("[data-testid='recognition-save']"));
    }
  });

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape" || !document.querySelector(".recognition-drawer")) return;
    if (!recognitionConfirmLeave()) return;
    showRecognitionVeil();
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

  // --- drawer navigation feedback ---------------------------------------------
  // Opening (edit/bank-edit links) and closing (data-recognition-close) the
  // drawer are full Turbo re-renders: while the request is in flight nothing
  // moved on screen and it read as lag. A full-screen veil with a spinner
  // shows instantly on click and hides when the next render lands.
  function showRecognitionVeil(link) {
    var veil = document.createElement("div");
    veil.className = "turbo-veil";
    veil.innerHTML = '<div class="turbo-veil-card"><span class="spinner-border" aria-hidden="true"></span></div>';
    if (link) veil.dataset.fromLink = link.getAttribute("data-testid") || "";
    document.body.classList.add("turbo-loading");
    document.body.appendChild(veil);
  }

  function hideRecognitionVeil() {
    document.body.classList.remove("turbo-loading");
    document.querySelectorAll(".turbo-veil").forEach(function (veil) { veil.remove(); });
    document.querySelectorAll("[data-testid='edit-recognition'].is-loading, [data-testid='recognition-bank-edit'].is-loading")
            .forEach(function (link) { link.classList.remove("is-loading"); });
    document.querySelectorAll("form.recognition-form [data-testid='recognition-save']")
            .forEach(resetRecognitionSave);
  }

  function resetRecognitionSave(button) {
    if (!button) return;
    button.disabled = false;
    button.removeAttribute("aria-busy");
    button.classList.remove("is-loading");
  }

  function showRecognitionSaveLoading(button) {
    if (!button || button.disabled) return;
    button.disabled = true;
    button.setAttribute("aria-busy", "true");
    button.classList.add("is-loading");
    showRecognitionVeil();
  }

  // Clicked drawer-open links: flag it and lift the veil BEFORE Turbo navigates.
  document.addEventListener("click", function (e) {
    var link = e.target.closest("a[data-testid='edit-recognition'], a[data-testid='recognition-bank-edit']");
    if (!link) return;
    if (link.classList.contains("is-loading")) { e.preventDefault(); return; }
    link.classList.add("is-loading");
    showRecognitionVeil(link);
  }, true);

  // Render landed (or someone left a stale veil behind): clean slate.
  document.addEventListener("turbo:load", hideRecognitionVeil);
  document.addEventListener("turbo:before-cache", hideRecognitionVeil);
  document.addEventListener("turbo:fetch-request-error", hideRecognitionVeil);
  document.addEventListener("DOMContentLoaded", hideRecognitionVeil);
  window.addEventListener("pageshow", hideRecognitionVeil);

  // --- collapsible recognition cards ------------------------------------------
  // Bank group cards and the Gmail criteria card are collapsed accordions:
  // any [data-recognition-toggle] inside a [data-recognition-collapsible]
  // flips the card's `expanded` class (bodies are server-rendered and only
  // hidden with CSS, so the content stays crawler/test friendly).
  function recognitionToggleCard(card) {
    var expanded = card.classList.toggle("expanded");
    card.querySelectorAll("[data-recognition-toggle]").forEach(function (btn) {
      btn.setAttribute("aria-expanded", expanded ? "true" : "false");
    });
  }

  document.addEventListener("click", function (e) {
    var toggle = e.target.closest("[data-recognition-toggle]");
    if (!toggle) return;
    var card = toggle.closest("[data-recognition-collapsible]");
    if (!card) return;
    e.preventDefault();
    recognitionToggleCard(card);
  });

  document.addEventListener("DOMContentLoaded", function () {
    bindRecognition(document);
  });

  // --- guided recognition tutorial -------------------------------------------
  // The "¿Cómo funciona?" modal holds five server-rendered step panels: the
  // active one is switched with local state (`.is-active`), the progress rail
  // is clickable and the last step swaps "Next" for "Back to start".
  function recognitionHelpShow(modal, targetStep) {
    var steps = Array.prototype.slice.call(modal.querySelectorAll("[data-testid='recognition-help-step']"));
    var current = steps.findIndex(function (step) { return step.classList.contains("is-active"); });
    var index = Math.max(0, Math.min(targetStep - 1, steps.length - 1));
    if (index === current) return;

    var last = index === steps.length - 1;
    steps.forEach(function (step, i) {
      var active = i === index;
      step.classList.toggle("is-active", active);
      step.setAttribute("data-help-active", active ? "true" : "false");
    });
    modal.querySelectorAll("[data-testid='help-progress-step']").forEach(function (dot, i) {
      dot.classList.toggle("is-active", i === index);
      dot.classList.toggle("is-done", i < index);
    });
    var readoutTitle = modal.querySelector("[data-help-title]");
    var readoutMeta = modal.querySelector("[data-help-meta]");
    var stepTitle = steps[index].getAttribute("data-help-title-text");
    if (readoutTitle && stepTitle) readoutTitle.textContent = stepTitle;
    if (readoutMeta) {
      var template = readoutMeta.dataset.progressTemplate || "";
      readoutMeta.textContent = template.replace("%{count}", index + 1).replace("%{total}", steps.length);
    }
    var prev = modal.querySelector("[data-testid='help-prev']");
    var next = modal.querySelector("[data-testid='help-next']");
    var restart = modal.querySelector("[data-testid='help-restart']");
    if (prev) prev.disabled = index === 0;
    if (restart) restart.classList.toggle("d-none", !last);
    if (next) next.classList.toggle("d-none", last);
    var body = modal.querySelector(".modal-body");
    if (body) body.scrollTop = 0;
  }

  function bindRecognitionHelp(modal) {
    if (modal.dataset.helpBound === "true") return;
    modal.dataset.helpBound = "true";
    var readoutMeta = modal.querySelector("[data-help-meta]");
    if (readoutMeta) readoutMeta.dataset.progressTemplate = readoutMeta.textContent;
    var restart = modal.querySelector("[data-testid='help-restart']");
    if (restart) restart.classList.add("d-none");

    modal.addEventListener("click", function (e) {
      var steps = modal.querySelectorAll("[data-testid='recognition-help-step']");
      var current = -1;
      for (var i = 0; i < steps.length; i++) {
        if (steps[i].classList.contains("is-active")) { current = i; break; }
      }

      var jump = e.target.closest("[data-help-jump]");
      if (jump) { recognitionHelpShow(modal, parseInt(jump.dataset.helpJump, 10)); return; }

      var nav = e.target.closest("[data-help-nav]");
      if (!nav) return;
      if (nav.dataset.helpNav === "prev") recognitionHelpShow(modal, current);
      if (nav.dataset.helpNav === "next") recognitionHelpShow(modal, current + 2);
      if (nav.dataset.helpNav === "restart") recognitionHelpShow(modal, 1);
    });
  }

  // Re-run the assistant every time the modal opens (Bootstrap event).
  document.addEventListener("shown.bs.modal", function (e) {
    var el = document.getElementById("recognition-help-modal");
    if (el && el === e.target) {
      recognitionHelpShow(el, 1);
      bindRecognitionHelp(el);
    }
  });

  document.addEventListener("DOMContentLoaded", function () {
    var el = document.getElementById("recognition-help-modal");
    if (el) bindRecognitionHelp(el);
  });

  document.addEventListener("turbo:load", function () {
    var el = document.getElementById("recognition-help-modal");
    if (el) bindRecognitionHelp(el);
  });

  // --- institution autocomplete ---------------------------------------------
  // Searchable combobox for the money-source institution selector
  // ([data-institution-combobox] in money_sources/_institution_select).
  // The option list travels inline as JSON in data-options (catalog +
  // user's custom entities); the chosen polymorphic ref lives in the hidden
  // money_source[institution_ref] input and is parsed server-side by
  // MoneySource#assign_institution_ref. Vanilla, no frameworks.
  var INSTITUTION_MAX_SUGGESTIONS = 12;

  function institutionFold(text) {
    return String(text == null ? "" : text)
      .normalize("NFKD")
      .replace(/\p{Mn}/gu, "")
      .toLowerCase();
  }

  function institutionHiddenInput(combobox) {
    var cell = combobox.closest(".mb-3") || combobox.parentElement;
    return cell ? cell.querySelector("input[type=hidden][name*='institution_ref']") : null;
  }

  function institutionExhaustiveData(combobox) {
    if (!combobox.dataset.optionsParsed) {
      combobox.dataset.optionsParsed = "true";
      try {
        combobox._data = JSON.parse(combobox.dataset.options || "{}");
      } catch (e) {
        combobox._data = {};
      }
    }
    return combobox._data || {};
  }

  function institutionOptions(combobox) {
    var data = institutionExhaustiveData(combobox);
    return data.options || [];
  }

  function institutionMatchesSearch(option, query) {
    if (String(query || "").trim() === "") return true;

    var needle = institutionFold(query);
    return institutionFold(option.label).indexOf(needle) !== -1 ||
           institutionFold(option.type).indexOf(needle) !== -1;
  }

  function institutionLabelFor(combobox, ref) {
    var options = institutionOptions(combobox);
    for (var i = 0; i < options.length; i++) {
      if (options[i].value === ref) return options[i].label;
    }
    return null;
  }

  function institutionItemHtml(data, option, highlighted) {
    var group = data.groups && data.groups[option.group];
    var badge = "";
    if (option.type && data.types && data.types[option.type]) {
      badge = '<span class="badge bg-light text-dark border ms-1">' +
        escapeInstitutionHtml(data.types[option.type]) + "</span>";
    }
    if (option.inactive) {
      badge += ' <span class="badge bg-secondary-subtle text-secondary-emphasis">' +
        escapeInstitutionHtml(data.inactive_marker || "") + "</span>";
    }
    var prefix = group ? '<span class="text-secondary small">' +
      escapeInstitutionHtml(group) + " · </span>" : "";

    var classes = "dropdown-item" + (highlighted ? " active" : "") +
      (option.inactive ? " text-secondary" : "");
    return '<button type="button" class="' + classes + '" data-institution-option value="' +
      escapeInstitutionHtml(option.value) + '">' + prefix +
      escapeInstitutionHtml(option.label) + badge + "</button>";
  }

  // Minimal escaper: labels originate from user-given names, so never trust
  // them inside innerHTML.
  function escapeInstitutionHtml(text) {
    return String(text == null ? "" : text).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // Recreates the dropdown body from the JSON data: the "no entity" entry
  // first, then group headers (catalog / custom entities) and highlighted
  // option navigation state.
  function institutionRenderList(combobox, query) {
    var data = institutionExhaustiveData(combobox);
    var list = combobox.querySelector("[data-institution-list]");
    var options = institutionOptions(combobox);
    var chosen = combobox.dataset.selectedRef || "";

    var html = '<button type="button" class="dropdown-item text-secondary' +
      (chosen === "" ? " active" : "") + '" data-institution-option value="">';
    html += escapeInstitutionHtml(data.none_label || "—") + "</button>";

    var lastGroup = null;
    var allowed = options.filter(function (option) { return institutionMatchesSearch(option, query); })
                         .slice(0, INSTITUTION_MAX_SUGGESTIONS);
    allowed.forEach(function (option) {
      if (option.group !== lastGroup) {
        lastGroup = option.group;
        var heading = data.groups && data.groups[lastGroup];
        html += '<h6 class="dropdown-header">' + escapeInstitutionHtml(heading || "") + "</h6>";
      }
      html += institutionItemHtml(data, option, option.value === chosen);
    });
    if (allowed.length === 0) {
      html += '<span class="dropdown-item text-secondary disabled">' +
        escapeInstitutionHtml(data.no_match || "—") + "</span>";
    }

    list.innerHTML = html;
    list.hidden = false;
    list.classList.add("show");
    combobox.querySelector("[data-institution-search]").setAttribute("aria-expanded", "true");
    combobox.dataset.highlightIndex = -1;
  }

  function institutionCloseList(combobox) {
    var list = combobox.querySelector("[data-institution-list]");
    list.hidden = true;
    list.classList.remove("show");
    combobox.querySelector("[data-institution-search]").setAttribute("aria-expanded", "false");
    combobox.dataset.highlightIndex = -1;
  }

  // Read-only snapshot: shows the stored selection in the text input and the
  // clear button. Kept consistent by this module only.
  function institutionSyncDisplay(combobox) {
    var hidden = institutionHiddenInput(combobox);
    var search = combobox.querySelector("[data-institution-search]");
    var clear = combobox.querySelector("[data-institution-clear]");
    var ref = hidden ? hidden.value : "";
    var data = institutionExhaustiveData(combobox);

    combobox.dataset.selectedRef = ref;
    search.value = ref ? (institutionLabelFor(combobox, ref) || "") : "";
    clear.hidden = ref === "";
    combobox.dataset.highlightIndex = -1;
    void data; // parsed lazily on first interaction
  }

  function institutionPick(combobox, value) {
    var hidden = institutionHiddenInput(combobox);
    var search = combobox.querySelector("[data-institution-search]");
    var clear = combobox.querySelector("[data-institution-clear]");

    if (hidden) hidden.value = value;
    combobox.dataset.selectedRef = value;
    search.value = value === "" ? "" : (institutionLabelFor(combobox, value) || "");
    clear.hidden = value === "";
    institutionCloseList(combobox);
    search.focus();
  }

  function institutionHighlightedItem(combobox) {
    var items = combobox.querySelectorAll("[data-institution-option]");
    var index = parseInt(combobox.dataset.highlightIndex || "-1", 10);
    return items[index] || null;
  }

  function institutionMoveHighlight(combobox, delta) {
    var items = combobox.querySelectorAll("[data-institution-option]");
    var index = Math.max(parseInt(combobox.dataset.highlightIndex || "-1", 10) + delta, -1);
    if (index > items.length - 1) index = items.length - 1;
    if (index < 0) index = 0;
    combobox.dataset.highlightIndex = String(index);
    items.forEach(function (item, i) { item.classList.toggle("active", i === index); });
    return items[index];
  }

  function institutionBind(scope) {
    scope.querySelectorAll("[data-institution-combobox]").forEach(function (combobox) {
      institutionSyncDisplay(combobox);
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    institutionBind(document);
  });

  // Delegated interactions (the comboboxes may be re-rendered inside panels).
  document.addEventListener("focusin", function (e) {
    var combobox = e.target.closest("[data-institution-combobox]");
    if (combobox && e.target.matches("[data-institution-search]")) {
      institutionRenderList(combobox, "");
    }
  });

  document.addEventListener("input", function (e) {
    var combobox = e.target.closest("[data-institution-combobox]");
    if (combobox && e.target.matches("[data-institution-search]")) {
      institutionRenderList(combobox, e.target.value);
    }
  });

  document.addEventListener("keydown", function (e) {
    var combobox = e.target.closest("[data-institution-combobox]");
    if (!combobox || !e.target.matches("[data-institution-search]")) return;
    var list = combobox.querySelector("[data-institution-list]");
    if (list.hidden) return;

    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      institutionMoveHighlight(combobox, e.key === "ArrowDown" ? 1 : -1);
    } else if (e.key === "Enter") {
      var highlighted = institutionHighlightedItem(combobox);
      if (highlighted) {
        e.preventDefault();
        institutionPick(combobox, highlighted.getAttribute("value"));
      }
    } else if (e.key === "Escape") {
      institutionCloseList(combobox);
    }
  });

  document.addEventListener("mousedown", function (e) {
    var item = e.target.closest("[data-institution-option]");
    if (!item) return;
    e.preventDefault();
    var combobox = item.closest("[data-institution-combobox]");
    institutionPick(combobox, item.getAttribute("value"));
  });

  document.addEventListener("click", function (e) {
    var clearButton = e.target.closest("[data-institution-clear]");
    if (clearButton) {
      var combobox = clearButton.closest("[data-institution-combobox]");
      institutionPick(combobox, "");
      return;
    }
    // Clicking anywhere outside the combobox closes its open list.
    document.querySelectorAll("[data-institution-combobox]").forEach(function (combobox) {
      if (!combobox.contains(e.target) &&
          !combobox.querySelector("[data-institution-list]").hidden) {
        // A pending typed query is discarded: the hidden input already holds
        // the committed selection (or none).
        institutionCloseList(combobox);
      }
    });
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
  var syncPollerRunning = false;

  function gmailSyncStatusPath() {
    var btn = document.querySelector("[data-sync-status-path]");
    return btn ? btn.getAttribute("data-sync-status-path") : null;
  }

  function startSyncPoller() {
    // One poller at a time: the submit listener and the turbo:load resume
    // both may try to start one on the same navigation.
    if (syncPollerRunning) return;

    var statusPath = gmailSyncStatusPath();
    if (!statusPath) return;
    syncPollerRunning = true;

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
          syncPollerRunning = false;
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

  // If we arrive with a pending sync, start polling right away — no manual
  // reload. Turbo Drive renders redirects WITHOUT a full page load, so this
  // must re-run on every Turbo visit (turbo:load), not just at script eval.
  function resumePendingSyncPolling() {
    var hasPendingSync = false;
    try { hasPendingSync = sessionStorage.getItem(SYNC_POLL_KEY) === "1"; } catch (_) {}
    if (hasPendingSync && gmailSyncStatusPath()) {
      startSyncPoller();
    }

    // Page rendered while a sync is running (arrived mid-scan): poll until it
    // finishes and refresh so the results show up without a manual reload.
    if (document.querySelector("[data-sync-in-progress]")) {
      startSyncPoller();
    }
  }

  resumePendingSyncPolling();
  document.addEventListener("DOMContentLoaded", resumePendingSyncPolling);
  document.addEventListener("turbo:load", resumePendingSyncPolling);
  document.addEventListener("turbo:render", resumePendingSyncPolling);
})();

// Settings → WhatsApp connection flow. Clicking the primary CONNECT token
// button opens WhatsApp and switches the section to a "Connecting…" state.
// The status endpoint is polled every 30 seconds for up to 3 minutes (6
// attempts, never more frequently); a single timer is guaranteed and cleaned
// up on cancel, on navigation and as soon as the backend reports connected.
(function () {
  var POLL_INTERVAL_MS = 30000;
  var MAX_ATTEMPTS = 6;
  var MAX_DURATION_MS = 3 * 60 * 1000;
  var timer = null;
  var attemptsLeft = 0;

  // Rails rejects state-changing fetches without the CSRF token header.
  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.content : "";
  }

  function fetchWithCsrf(url, options) {
    return fetch(url, Object.assign({}, options, {
      credentials: "same-origin",
      headers: Object.assign({ "X-CSRF-Token": csrfToken() }, options.headers)
    }));
  }

  function connectCard() {
    return document.getElementById("whatsapp-connect-card");
  }

  function stopTimer() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
    attemptsLeft = 0;
  }

  function setState(name) {
    var root = connectCard();
    if (!root) return;
    root.querySelectorAll("[data-connect-state]").forEach(function (el) {
      el.hidden = el.getAttribute("data-connect-state") !== name;
    });
  }

  function reloadSection(url) {
    if (window.Turbo) {
      Turbo.visit(url);
    } else {
      window.location.replace(url);
    }
  }

  function finishExpired() {
    stopTimer();
    var root = connectCard();
    if (!root) return;
    fetchWithCsrf(root.dataset.cancelUrl, { method: "DELETE" })
      .then(function () { reloadSection(root.dataset.expiredUrl); })
      .catch(function () { reloadSection(root.dataset.expiredUrl); });
  }

  function pollStatus() {
    var root = connectCard();
    if (!root) return;
    fetch(root.dataset.statusUrl, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        if (data.status === "connected") {
          stopTimer();
          reloadSection(window.location.href);
        } else if (data.status !== "pending") {
          finishExpired();
        }
      })
      .catch(function () { /* transient network error: keep waiting */ });
  }

  function startPolling() {
    var root = connectCard();
    if (!root) return;
    stopTimer();
    attemptsLeft = MAX_ATTEMPTS;
    var deadline = Date.now() + MAX_DURATION_MS;
    timer = setInterval(function () {
      attemptsLeft -= 1;
      if (attemptsLeft <= 0 || Date.now() >= deadline) {
        finishExpired();
        return;
      }
      pollStatus();
    }, POLL_INTERVAL_MS);
  }

  function bindCard() {
    var root = connectCard();
    if (!root || root.dataset.bound) return;
    root.dataset.bound = "1";

    var tokenButton = root.querySelector("[data-connect-action]");
    if (tokenButton) {
      tokenButton.addEventListener("click", function () {
        // Expose the same deep link in the connecting state before switching.
        var reopen = root.querySelector("[data-reopen-link]");
        if (reopen) {
          reopen.href = tokenButton.href;
          reopen.classList.remove("d-none");
        }
        setState("connecting");
        startPolling();
      });
    }

    var cancelButton = root.querySelector("[data-cancel-action]");
    if (cancelButton) {
      cancelButton.addEventListener("click", function () {
        stopTimer();
        fetchWithCsrf(root.dataset.cancelUrl, { method: "DELETE" })
          .then(function () { reloadSection(root.dataset.cleanUrl); })
          .catch(function () { reloadSection(root.dataset.cleanUrl); });
      });
    }
  }

  stopTimer();
  document.addEventListener("turbo:load", bindCard);
  document.addEventListener("turbo:before-render", stopTimer);
  document.addEventListener("turbo:visit", stopTimer);
  if (document.readyState !== "loading") {
    bindCard();
  } else {
    document.addEventListener("DOMContentLoaded", bindCard);
  }
})();

(function () {
  // Searchable category dropdown. The server renders a native <select> (kept
  // hidden so forms still submit it) next to a combobox that filters the
  // same options as you type.
  //
  // Public API on window.CategoryPicker:
  //   bind(container)   enhance a picker built at runtime; returns the picker
  //   value(select)     current value of a picker's select
  //   setValue(select, value)  pick a category from script, keeping the
  //                     visible label in sync

  var CONTAINER_SELECTOR = "[data-category-picker]";
  var OPTION_SELECTOR = "[role=option][data-value]";

  // Mirrors ActivityClassification.normalize_name so "publicos" matches
  // "Servicios públicos" and punctuation never blocks a match. The `u` flag
  // is what makes \p{L}/\p{N} read as "any letter/number"; without it the
  // class matches those literal characters instead and every query normalizes
  // to "" — the list would never filter.
  function normalize(text) {
    return String(text == null ? "" : text)
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s]+/gu, " ")
      .trim()
      .replace(/\s+/g, " ");
  }

  function CategoryPicker(container) {
    this.container = container;
    this.input = container.querySelector("[role=combobox]");
    this.listbox = container.querySelector("[role=listbox]");
    this.select = container.querySelector("select");
    this.toggle = container.querySelector("[data-category-picker-toggle]");
    this.emptyMessage = container.querySelector("[data-no-results]");
    this.feedback = container.querySelector("[data-required-message]");
    this.visibleOptions = [];
    this.activeIndex = -1;
  }

  CategoryPicker.prototype.options = function () {
    return Array.prototype.slice.call(this.listbox.querySelectorAll(OPTION_SELECTOR));
  };

  CategoryPicker.prototype.bind = function () {
    var self = this;

    this.input.addEventListener("input", function () {
      self.filter(self.input.value);
      self.open();
    });

    this.input.addEventListener("focus", function () {
      self.open();
    });

    this.input.addEventListener("keydown", function (event) {
      self.onKeydown(event);
    });

    this.input.addEventListener("blur", function () {
      // Clicking an option blurs the input first; defer so the click lands.
      window.setTimeout(function () { self.close(); }, 120);
    });

    if (this.toggle) {
      this.toggle.addEventListener("click", function () {
        if (self.isOpen()) {
          self.close();
        } else {
          self.open();
          self.input.focus();
        }
      });
    }

    this.listbox.addEventListener("mousedown", function (event) {
      var option = event.target.closest(OPTION_SELECTOR);
      if (option) {
        event.preventDefault();
        self.choose(option);
      }
    });

    // Keeps the visible label correct when a script (or a bulk update) sets
    // the select's value directly.
    this.select.addEventListener("change", function () {
      self.syncFromSelect();
    });

    var form = this.container.closest("form");
    if (form) {
      form.addEventListener("submit", function (event) {
        if (!self.validate()) event.preventDefault();
      });
    }

    this.syncFromSelect();
    this.filter("");
    return this;
  };

  CategoryPicker.prototype.isOpen = function () {
    return !this.listbox.hidden;
  };

  CategoryPicker.prototype.open = function () {
    if (this.input.disabled) return;

    this.listbox.hidden = false;
    this.input.setAttribute("aria-expanded", "true");
    this.renderActive();
  };

  CategoryPicker.prototype.close = function () {
    this.listbox.hidden = true;
    this.input.setAttribute("aria-expanded", "false");
    this.input.removeAttribute("aria-activedescendant");
    this.setActive(-1);
  };

  // Filters every option by its server-rendered search text. The list keeps
  // its alphabetical DOM order; non-matching rows are simply hidden.
  CategoryPicker.prototype.filter = function (query) {
    var needle = normalize(query);
    var matches = 0;

    this.options().forEach(function (option) {
      var hit = needle === "" || normalize(option.dataset.search).indexOf(needle) !== -1;
      option.hidden = !hit;
      if (hit) matches += 1;
    });

    if (this.emptyMessage) {
      this.emptyMessage.hidden = matches > 0 || this.options().length === 0;
    }

    this.visibleOptions = this.options().filter(function (option) { return !option.hidden; });
    this.setActive(needle === "" ? -1 : 0);
  };

  CategoryPicker.prototype.onKeydown = function (event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!this.isOpen()) { this.open(); return; }
      var step = event.key === "ArrowDown" ? 1 : -1;
      var next = this.activeIndex + step;
      if (next < 0) next = this.visibleOptions.length - 1;
      this.setActive(next);
      return;
    }

    if (event.key === "Enter") {
      if (this.isOpen() && this.activeIndex >= 0) {
        event.preventDefault();
        this.choose(this.visibleOptions[this.activeIndex]);
      }
      return;
    }

    if (event.key === "Escape") {
      if (this.isOpen()) { event.preventDefault(); this.close(); }
      return;
    }

    if (event.key === "Backspace" && this.input.value === "") {
      this.clear();
    }
  };

  CategoryPicker.prototype.setActive = function (index) {
    if (this.activeIndex >= 0 && this.visibleOptions[this.activeIndex]) {
      var previous = this.visibleOptions[this.activeIndex];
      previous.classList.remove("category-picker__option--active");
      previous.removeAttribute("data-active");
    }

    if (index >= this.visibleOptions.length) index = this.visibleOptions.length - 1;
    if (index < 0) {
      this.activeIndex = -1;
      this.input.removeAttribute("aria-activedescendant");
      return;
    }

    this.activeIndex = index;
    var option = this.visibleOptions[index];
    option.classList.add("category-picker__option--active");
    option.setAttribute("data-active", "true");
    this.input.setAttribute("aria-activedescendant", option.id);
    if (option.scrollIntoView) option.scrollIntoView({ block: "nearest" });
  };

  CategoryPicker.prototype.renderActive = function () {
    if (this.activeIndex >= 0) this.setActive(this.activeIndex);
  };

  // The blank option ("Todas las Categorías" in filters) is a value, not a
  // selection: it clears the box so the placeholder reads through instead of
  // leaving copyable text in the input.
  CategoryPicker.prototype.choose = function (option) {
    this.select.value = option.dataset.value;
    this.input.value = option.dataset.value === "" ? "" : option.textContent.trim();
    this.hideFeedback();
    this.close();
    this.filter("");
    this.select.dispatchEvent(new Event("change", { bubbles: true }));
  };

  CategoryPicker.prototype.clear = function () {
    this.select.value = "";
    this.input.value = "";
    this.hideFeedback();
    this.close();
    this.select.dispatchEvent(new Event("change", { bubbles: true }));
  };

  CategoryPicker.prototype.optionFor = function (value) {
    var wanted = String(value == null ? "" : value);
    return this.options().filter(function (option) {
      return option.dataset.value === wanted;
    })[0];
  };

  // Reads the select and repaints the visible label, so external writes to
  // the select never leave a stale category name in the box. A blank value
  // leaves the input empty: the placeholder is text, never copyable content.
  CategoryPicker.prototype.syncFromSelect = function () {
    var option = this.optionFor(this.select.value);
    this.input.value = option && option.dataset.value !== "" ? option.textContent.trim() : "";
    this.clearActive();
    if (option) {
      option.setAttribute("aria-selected", "true");
    }
    this.options().forEach(function (each) {
      if (each !== option) each.setAttribute("aria-selected", "false");
    });
  };

  CategoryPicker.prototype.clearActive = function () {
    this.options().forEach(function (option) {
      option.classList.remove("category-picker__option--active");
      option.removeAttribute("data-active");
    });
    this.activeIndex = -1;
  };

  CategoryPicker.prototype.hideFeedback = function () {
    this.input.classList.remove("is-invalid");
    if (this.feedback) this.feedback.hidden = true;
  };

  CategoryPicker.prototype.validate = function () {
    if (this.container.dataset.required !== "true" || this.select.value) return true;

    this.input.classList.add("is-invalid");
    if (this.feedback) this.feedback.hidden = false;
    this.open();
    this.input.focus();
    return false;
  };

  var instances = new WeakMap();

  function forNode(node) {
    if (!node) return null;
    var container = node.matches && node.matches(CONTAINER_SELECTOR)
      ? node
      : node.closest(CONTAINER_SELECTOR);
    if (!container) return null;

    if (!instances.has(container)) instances.set(container, new CategoryPicker(container));
    return instances.get(container);
  }

  function bindAll(root) {
    var scope = root || document;
    var containers = scope.querySelectorAll(CONTAINER_SELECTOR);
    Array.prototype.forEach.call(containers, function (container) {
      if (container.dataset.categoryPickerBound === "true") return;
      container.dataset.categoryPickerBound = "true";
      forNode(container).bind();
    });
  }

  document.addEventListener("turbo:load", function () { bindAll(); });
  document.addEventListener("DOMContentLoaded", function () { bindAll(); });
  if (document.readyState !== "loading") bindAll();

  window.CategoryPicker = {
    bind: function (container) {
      return forNode(container);
    },
    value: function (select) {
      var picker = forNode(select);
      return picker ? picker.select.value : (select ? select.value : "");
    },
    setValue: function (select, value) {
      var picker = forNode(select);
      if (!picker) return;
      if (value === "" || value == null) {
        picker.clear();
        return;
      }
      var option = picker.optionFor(value);
      if (option) picker.choose(option);
    },
    // The visible control, for scripts that focus or flag the field. The
    // select itself is hidden, so styling or focusing it would be invisible.
    input: function (select) {
      var picker = forNode(select);
      return picker ? picker.input : null;
    },
    setInvalid: function (select, invalid) {
      var input = window.CategoryPicker.input(select);
      if (input) input.classList.toggle("is-invalid", !!invalid);
    },
    focus: function (select) {
      var input = window.CategoryPicker.input(select);
      if (input) input.focus();
    }
  };
})();

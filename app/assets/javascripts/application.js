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
    // the input is a thousands separator — except a final dot group of 1-2
    // digits, which is the dot-decimal typing style ("5.50", "1234.56"); the
    // live format must mirror the same rule decimalParts applies to the
    // submitted value or the decimal is swallowed mid-typing ("5.50" → "550").
    var hasComma = raw.indexOf(",") !== -1;
    var trailingComma = !!keepTrailingComma && raw.slice(-1) === ",";

    if (!hasComma && !trailingComma) {
      var parts = decimalParts(value);
      if (parts.decimal) {
        // parseInt keeps the sign ("-5,50"), no extra "-" needed.
        var grouped = String(parseInt(parts.integer, 10) || 0)
                        .replace(/\B(?=(\d{3})+(?!\d))/g, ".");
        return grouped + "," + parts.decimal;
      }

      // Integer-only display: strip any dots, group thousands with dots.
      var intOnly = raw.replace(/[^\d-]/g, "");
      var neg = intOnly.charAt(0) === "-";
      var digits = neg ? intOnly.slice(1) : intOnly;
      var grouped = digits ? String(parseInt(digits, 10) || 0).replace(/\B(?=(\d{3})+(?!\d))/g, ".") : "";
      if (!grouped) return "";
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

})();

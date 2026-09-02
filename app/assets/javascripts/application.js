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
})();

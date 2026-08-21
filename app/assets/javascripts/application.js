(function () {
  function sanitizeValue(value) {
    return String(value == null ? "" : value).replace(/,/g, "").trim();
  }

  function formatValue(value, finalize) {
    var raw = sanitizeValue(value);
    if (!raw) return "";

    var hasDot = raw.indexOf(".") !== -1;
    var parts = raw.split(".");
    var integerPart = parts.shift().replace(/[^\d]/g, "");
    var decimalPart = parts.join("").replace(/[^\d]/g, "").slice(0, 2);

    if (!integerPart) integerPart = "0";
    integerPart = String(parseInt(integerPart, 10)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");

    if (!hasDot) return integerPart;
    if (finalize) decimalPart = decimalPart.replace(/0+$/, "");
    if (!decimalPart) return integerPart;

    return integerPart + "." + decimalPart;
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
  });

  document.addEventListener("turbo:load", function () {
    init(document);
  });
})();

(function () {
  // Abono extraordinario preview for revolving credit (credit cards /
  // crédito rotativo): as the amount is typed, the read-only summary shows
  // the current balance, the abono, the new balance and — when the product
  // has a credit limit — the new available credit. Pure presentation: the
  // server recomputes everything through the same balances on submit.
  function parseMoney(value) {
    var clean = window.MoneyInputs
      ? window.MoneyInputs.sanitizeValue(value)
      : String(value == null ? "" : value).replace(/[^\d.-]/g, "");
    var n = parseFloat(clean);
    return isNaN(n) ? 0 : n;
  }

  function formatMoney(value) {
    return "$" + value.toLocaleString("es-CO", { maximumFractionDigits: 2 });
  }

  function setText(box, selector, text) {
    var el = box.querySelector(selector);
    if (el) el.textContent = text;
  }

  function update(box) {
    var amountInput = box.querySelector("[data-extra-amount='true']");
    var result = box.querySelector("[data-extra-result]");
    if (!amountInput || !result) return;

    var amount = parseMoney(amountInput.value);
    var balance = parseFloat(box.getAttribute("data-balance")) || 0;
    var limit = parseFloat(box.getAttribute("data-limit")) || 0;

    result.hidden = amount <= 0;
    if (result.hidden) return;

    var newBalance = Math.max(balance - amount, 0);
    var availableRow = box.querySelector("[data-extra-available-row]");
    var availableCell = box.querySelector("[data-extra-available]");
    var hasLimit = limit > 0;

    setText(box, "[data-extra-balance]", formatMoney(balance));
    setText(box, "[data-extra-payment]", "-" + formatMoney(amount));
    setText(box, "[data-extra-new-balance]", formatMoney(newBalance));

    if (availableRow) availableRow.hidden = !hasLimit;
    if (availableCell) {
      availableCell.hidden = !hasLimit;
      if (hasLimit) availableCell.textContent = formatMoney(Math.max(limit - newBalance, 0));
    }
  }

  function bind() {
    document.querySelectorAll("[data-extra-preview]").forEach(function (box) {
      if (box.dataset.extraBound === "true") return;
      box.dataset.extraBound = "true";
      var input = box.querySelector("[data-extra-amount='true']");
      if (!input) return;
      input.addEventListener("input", function () { update(box); });
      input.addEventListener("blur", function () { update(box); });
      update(box);
    });
  }

  document.addEventListener("DOMContentLoaded", bind);
  document.addEventListener("turbo:load", bind);
  if (document.readyState !== "loading") bind();
})();

// Debt capacity interactions: client-side table sorting only.
(function () {
  function sortTable(table, index, direction) {
    var body = table.tBodies[0];
    if (!body) return;

    Array.from(body.rows)
      .sort(function (left, right) {
        var a = left.cells[index].dataset.sortValue || left.cells[index].textContent.trim();
        var b = right.cells[index].dataset.sortValue || right.cells[index].textContent.trim();
        var aNumber = parseFloat(a.replace(/[^0-9.-]/g, ""));
        var bNumber = parseFloat(b.replace(/[^0-9.-]/g, ""));
        var comparison = !isNaN(aNumber) && !isNaN(bNumber) ? aNumber - bNumber : a.localeCompare(b);
        return direction === "desc" ? -comparison : comparison;
      })
      .forEach(function (row) { body.appendChild(row); });
  }

  document.addEventListener("click", function (event) {
    var button = event.target.closest("[data-debt-sort]");
    if (!button) return;

    var table = button.closest("table");
    var direction = button.dataset.direction === "asc" ? "desc" : "asc";
    button.dataset.direction = direction;
    sortTable(table, Number(button.dataset.debtSort), direction);
  });

  document.addEventListener("change", function (event) {
    var select = event.target.closest("[data-debt-comparison-select]");
    if (select) {
      syncRevolvingFields(select.closest("[data-debt-comparison-form]"));
      return;
    }

    var radio = event.target.closest("[data-debt-comparison-form] input[name='mode']");
    if (!radio) return;

    var form = radio.closest("[data-debt-comparison-form]");
    form.querySelectorAll(".debt-capacity-mode-option").forEach(function (option) {
      option.classList.toggle("is-selected", option.querySelector("input").checked);
    });
  });

  function syncRevolvingFields(form) {
    if (!form) return;

    var select = form.querySelector("[data-debt-comparison-select]");
    var option = select && select.options[select.selectedIndex];
    var revolving = option && option.dataset.debtType === "revolving";
    var balanceBased = revolving || option && option.dataset.debtKind === "credit_card";
    var noAmortization = balanceBased;
    var installments = form.querySelector("[data-debt-comparison-installments-field]");
    var termOption = form.querySelector("[data-debt-comparison-term-option]");

    form.classList.toggle("is-revolving", balanceBased);
    form.classList.toggle("is-no-amortization", noAmortization);

    if (installments) installments.classList.toggle("d-none", !balanceBased);
    if (termOption) {
      termOption.classList.toggle("d-none", balanceBased);
      termOption.querySelector("input").disabled = balanceBased;
      if (balanceBased) {
        var reduceInstallment = form.querySelector("input[name='mode'][value='reduce_installment']");
        reduceInstallment.checked = true;
        reduceInstallment.dispatchEvent(new Event("change", { bubbles: true }));
      }
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-debt-comparison-form]").forEach(syncRevolvingFields);
  });

  document.addEventListener("submit", function (event) {
    var form = event.target.closest("[data-debt-comparison-form]");
    if (!form) return;

    event.preventDefault();
    var submit = form.querySelector("[data-debt-comparison-submit]");
    var container = form.closest("[data-testid='debt-capacity-comparison']");
    var amount = form.querySelector("[data-debt-comparison-amount]");
    var params = new URLSearchParams(new FormData(form));
    if (amount && window.MoneyInputs) {
      amount.value = window.MoneyInputs.sanitizeValue(amount.value);
      params.set("amount", amount.value);
    }
    submit.disabled = true;
    submit.textContent = "Calculando...";

    fetch(form.action + "?" + params.toString(), { headers: { Accept: "text/html" } })
      .then(function (response) {
        if (!response.ok) throw new Error("No se pudo actualizar la simulación");
        return response.text();
      })
      .then(function (html) {
        container.outerHTML = html;
        var updated = document.querySelector("[data-testid='debt-capacity-comparison']");
        if (updated && window.MoneyInputs) window.MoneyInputs.init(updated);
      })
      .catch(function () {
        submit.disabled = false;
        submit.textContent = "Calcular";
      });
  });
})();

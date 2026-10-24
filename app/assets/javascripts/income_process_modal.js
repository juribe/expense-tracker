(function () {
  if (window.__incomeProcessModalInit) return;
  window.__incomeProcessModalInit = true;

  var payloadEl = document.querySelector("[data-income-process-payload]");
  var payload = payloadEl ? JSON.parse(payloadEl.dataset.incomeProcessPayload) : {};

  var modal = null;

  function openModal(button) {
    var form = document.getElementById("incomeProcessForm");
    var category = button.dataset.processCategory || "";
    var description = button.dataset.processDescription || payload.no_description;
    var amount = button.dataset.processAmount || "";
    var title = button.dataset.processTitle || payload.confirm_title;

    form.action = button.dataset.processUrl;

    document.getElementById("incomeProcessTitle").textContent = title;
    document.getElementById("incomeProcessCategory").textContent = category;
    document.getElementById("incomeProcessDescription").textContent = description;
     document.getElementById("incomeProcessConfiguredAmount").textContent = "$" + Number(amount).toFixed(2);
     var paidSoFar = Number(button.dataset.processPaidAmount || 0);
     var remaining = Math.max(Number(amount) - paidSoFar, 0);
     if (remaining <= 0) remaining = Number(amount);
     document.getElementById("processPaidSoFar").textContent = "$" + paidSoFar.toFixed(2);
     var markCheckbox = document.getElementById("processMarkAsPaid");
     if (markCheckbox) markCheckbox.checked = false;
     document.getElementById("incomeProcessDate").value = payload.today;
     document.getElementById("incomeProcessAmount").value = remaining.toFixed(2);
     if (window.MoneyInputs) window.MoneyInputs.formatField(document.getElementById("incomeProcessAmount"), true);

    (modal || (modal = bootstrap.Modal.getOrCreateInstance("#incomeProcessModal"))).show();
  }

  document.addEventListener("click", function (e) {
    var button = e.target.closest("[data-process-income]");
    if (button) openModal(button);
  });
})();

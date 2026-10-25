(function () {
  function init() {
    var modalEl = document.getElementById("movementDetailModal");
    if (!modalEl) return;

    function getModal() {
      if (window.bootstrap && window.bootstrap.Modal) {
        return window.bootstrap.Modal.getOrCreateInstance(modalEl);
      }
      return null;
    }

    document.querySelectorAll(".statement-row").forEach(function (row) {
      if (row.dataset.statementBound === "true") return;
      row.dataset.statementBound = "true";
      row.addEventListener("click", function (e) {
        if (e.target.closest("button,a")) return;
        document.getElementById("detailDescription").textContent = row.dataset.description || "";
        document.getElementById("detailDate").textContent = row.dataset.date || "";
        var amount = Number(row.dataset.amount);
        var amountEl = document.getElementById("detailAmount");
        amountEl.textContent = (row.dataset.direction === "in" ? "+" : "−") + "$" + Math.abs(amount).toLocaleString("es-CO");
        amountEl.className = "col-sm-8 " + (row.dataset.direction === "in" ? "text-success fw-bold" : "text-danger fw-bold");
        document.getElementById("detailType").textContent = row.dataset.type || "";
        document.getElementById("detailCategory").textContent = row.dataset.category || "—";
        document.getElementById("detailRelated").textContent = row.dataset.related || "—";
        var modal = getModal();
        if (modal) modal.show();
      });
    });
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
})();
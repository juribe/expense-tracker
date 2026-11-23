(function () {
  var modal = document.getElementById("goal-contribution-modal");
  if (!modal) return;

  function newKey() {
    if (window.crypto && typeof window.crypto.randomUUID === "function") {
      return window.crypto.randomUUID();
    }
    return "goal-" + Date.now() + "-" + Math.random().toString(16).slice(2);
  }

  modal.addEventListener("show.bs.modal", function (event) {
    var button = event.relatedTarget;
    if (!button) return;

    document.getElementById("goal_contribution_goal_id").value =
      button.getAttribute("data-contribution-goal-id");
    document.getElementById("goal-contribution-name").textContent =
      button.getAttribute("data-contribution-goal-name");
    document.getElementById("goal-contribution-saved").textContent =
      button.getAttribute("data-contribution-goal-saved");
    var action = button.getAttribute("data-contribution-action") || "deposit";
    var depositButton = document.getElementById("goal-contribution-deposit-button");
    var withdrawButton = document.getElementById("goal-contribution-withdraw-button");

    depositButton.classList.toggle("d-none", action !== "deposit");
    withdrawButton.classList.toggle("d-none", action !== "withdraw");

    document.getElementById("goal-contribution-title-text").textContent =
      button.getAttribute("data-contribution-title") || "";
    document.getElementById("goal-contribution-amount-label").textContent =
      button.getAttribute("data-contribution-label") || "";
    document.getElementById("goal_contribution_amount").value = "";
    document.getElementById("goal_contribution_note").value = "";
    document.getElementById("goal_contribution_date").value = modal.dataset.today;
    document.getElementById("goal_contribution_idempotency_key").value = newKey();
  });
})();

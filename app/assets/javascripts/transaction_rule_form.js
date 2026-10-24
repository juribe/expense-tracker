(function () {
  var conditionField = document.getElementById("condition_field");
  var actionField = document.getElementById("action_field");
  var conditionInputs = document.querySelectorAll("[data-condition-input]");
  var actionInputs = document.querySelectorAll("[data-action-input]");

  function syncCondition() {
    if (!conditionField) return;
    var active = conditionField.value;
    conditionInputs.forEach(function (el) {
      var on = el.getAttribute("data-condition-input") === active;
      el.classList.toggle("d-none", !on);
    });
  }

  function syncAction() {
    if (!actionField) return;
    var active = actionField.value;
    actionInputs.forEach(function (el) {
      var on = el.getAttribute("data-action-input") === active;
      el.classList.toggle("d-none", !on);
    });
  }

  if (conditionField) conditionField.addEventListener("change", syncCondition);
  if (actionField) actionField.addEventListener("change", syncAction);
  syncCondition();
  syncAction();
})();

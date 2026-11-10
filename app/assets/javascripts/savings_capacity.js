// Savings-capacity report: the server precomputes every percentage/option
// combination, so this module only selects the matching scenario and updates
// the visible breakdown. It never performs financial calculations.
(function () {
  function money(value) {
    var amount = Math.round(Math.abs(Number(value) || 0));
    return "$" + amount.toLocaleString("es-CO");
  }

  function signedMoney(value) {
    var amount = Number(value) || 0;
    return (amount < 0 ? "-" : "") + money(amount);
  }

  function deduction(value) {
    var amount = Number(value) || 0;
    return amount > 0 ? "−" + money(amount) : money(0);
  }

  function rootFor(element) {
    return element && element.closest("[data-savings-capacity]");
  }

  function scenariosFor(root) {
    if (!root._savingsCapacityScenarios) {
      try {
        root._savingsCapacityScenarios = JSON.parse(root.dataset.savingsCapacityScenarios || "[]");
      } catch (error) {
        root._savingsCapacityScenarios = [];
      }
    }

    return root._savingsCapacityScenarios;
  }

  function findScenario(root, percentage, basicEnabled, historyEnabled) {
    return scenariosFor(root).find(function (scenario) {
      return Number(scenario.percentage) === Number(percentage) &&
        Boolean(scenario.basic_reserve_enabled) === basicEnabled &&
        Boolean(scenario.include_previous) === historyEnabled;
    });
  }

  function setAllText(root, selector, text) {
    root.querySelectorAll(selector).forEach(function (element) {
      element.textContent = text;
    });
  }

  function setDisabledRow(row, disabled) {
    if (!row) return;

    row.classList.toggle("is-disabled", disabled);
    row.setAttribute("aria-disabled", disabled ? "true" : "false");
  }

  function updateSubtitle(element, active, activeText, inactiveText) {
    if (!element) return;

    element.textContent = active ? activeText : inactiveText;
  }

  function update(root) {
    var basicToggle = root.querySelector("[data-savings-capacity-basic-toggle]");
    var historyToggle = root.querySelector("[data-savings-capacity-history-toggle]");
    var range = root.querySelector("[data-savings-capacity-percentage]");
    if (!basicToggle || !historyToggle || !range) return;

    var percentage = Number(range.value);
    var basicEnabled = basicToggle.checked;
    var historyEnabled = historyToggle.checked;
    var scenario = findScenario(root, percentage, basicEnabled, historyEnabled);
    if (!scenario) return;

    var result = Number(scenario.result);
    var basicReserve = Number(scenario.basic_reserve);
    var previousVariable = Number(scenario.previous_variable);

    setAllText(root, "[data-savings-capacity-result]", signedMoney(result));
    root.querySelectorAll("[data-savings-capacity-result]").forEach(function (element) {
      element.classList.toggle("is-negative", result < 0);
    });

    setAllText(root, "[data-savings-capacity-additional]", money(scenario.additional_total));
    setAllText(root, "[data-savings-capacity-basic-value]", deduction(basicReserve));
    setAllText(root, "[data-savings-capacity-history-value]", deduction(previousVariable));
    setAllText(root, "[data-savings-capacity-percentage-label]", percentage + "%");

    var basicSubtitle = root.querySelector("[data-savings-capacity-basic-subtitle]");
    if (basicSubtitle) {
      var basicTemplate = basicSubtitle.dataset.activeTemplate || "";
      updateSubtitle(
        basicSubtitle,
        basicEnabled,
        basicTemplate.replace("__PERCENTAGE__", percentage),
        basicSubtitle.dataset.inactiveText || ""
      );
    }

    var historySubtitle = root.querySelector("[data-savings-capacity-history-subtitle]");
    if (historySubtitle) {
      updateSubtitle(
        historySubtitle,
        historyEnabled,
        historySubtitle.dataset.activeText || "",
        historySubtitle.dataset.inactiveText || ""
      );
    }

    setDisabledRow(root.querySelector("[data-savings-capacity-basic-row]"), !basicEnabled);
    setDisabledRow(root.querySelector("[data-savings-capacity-history-row]"), !historyEnabled);
    range.disabled = !basicEnabled;

    var basicHidden = root.querySelector("[data-savings-capacity-basic-hidden]");
    if (basicHidden) basicHidden.value = basicEnabled ? "1" : "0";

    var historyHidden = root.querySelector("[data-savings-capacity-history-hidden]");
    if (historyHidden) historyHidden.value = historyEnabled ? "1" : "0";

    var percentageHidden = root.querySelector("[data-savings-capacity-percentage-hidden]");
    if (percentageHidden) percentageHidden.value = percentage;

    var negativeNote = root.querySelector("[data-savings-capacity-negative-note]");
    if (negativeNote) negativeNote.hidden = result >= 0;

    var goalLink = root.querySelector("[data-savings-capacity-goal-link]");
    if (goalLink) {
      var goalUrl = goalLink.dataset.savingsCapacityGoalUrl || goalLink.href;

      if (result > 0) {
        var url = new URL(goalUrl, window.location.origin);
        url.searchParams.set("target_amount", Math.round(result));
        goalLink.href = url.toString();
        goalLink.classList.remove("disabled");
        goalLink.removeAttribute("aria-disabled");
        goalLink.removeAttribute("tabindex");
      } else {
        goalLink.href = "#";
        goalLink.classList.add("disabled");
        goalLink.setAttribute("aria-disabled", "true");
        goalLink.setAttribute("tabindex", "-1");
      }
    }

    var goalNote = root.querySelector("[data-savings-capacity-goal-note]");
    if (goalNote) {
      goalNote.textContent = result > 0 ? goalNote.dataset.positiveText : goalNote.dataset.negativeText;
    }
  }

  function updateAll() {
    document.querySelectorAll("[data-savings-capacity]").forEach(update);
  }

  document.addEventListener("input", function (event) {
    var root = rootFor(event.target);
    if (!root) return;
    if (event.target.matches("[data-savings-capacity-percentage]")) update(root);
  });

  document.addEventListener("change", function (event) {
    var root = rootFor(event.target);
    if (!root) return;
    if (event.target.matches("[data-savings-capacity-basic-toggle], [data-savings-capacity-history-toggle]")) {
      update(root);
    }
  });

  document.addEventListener("click", function (event) {
    var link = event.target.closest("[data-savings-capacity-goal-link]");
    if (link && link.getAttribute("aria-disabled") === "true") event.preventDefault();
  });

  document.addEventListener("turbo:load", updateAll);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", updateAll);
  } else {
    updateAll();
  }
})();

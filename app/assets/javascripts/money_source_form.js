(function () {
  // Money source form: shows only the panel for the selected kind and keeps
  // the name placeholder aligned with that kind. Inactive panels disable
  // their inputs so duplicate field names (e.g. credit_account fields shared
  // by the card and loan panels) do not overwrite the active panel on submit.
  function applyPanels(form, kind) {
    form.querySelectorAll("[data-kind-panel]").forEach(function (panel) {
      var panelKinds = panel.getAttribute("data-kind-panel").split(" ");
      var active = panelKinds.indexOf(kind) !== -1;
      panel.hidden = !active;
      panel.querySelectorAll("input, select, textarea").forEach(function (input) {
        input.disabled = !active;
      });
    });
  }

  function updateNamePlaceholder(form) {
    var nameInput = form.querySelector("#money_source_name");
    var kindSelect = form.querySelector("select#money_source_kind");
    var option = kindSelect && kindSelect.selectedOptions[0];
    var placeholder = option && option.getAttribute("data-name-placeholder");
    if (nameInput && placeholder) nameInput.setAttribute("placeholder", placeholder);
  }

  function bind(form) {
    if (form.dataset.moneySourceBound) return;
    form.dataset.moneySourceBound = "true";

    var kindInput = form.querySelector("#money_source_kind");
    if (!kindInput) return;

    // The initial placeholder comes from the server (it already matches the
    // preselected kind); it only changes when the user picks another kind.
    applyPanels(form, kindInput.value);
    kindInput.addEventListener("change", function () {
      applyPanels(form, kindInput.value);
      updateNamePlaceholder(form);
    });
  }

  function init() {
    document.querySelectorAll("form[data-money-source-form]").forEach(bind);
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
})();

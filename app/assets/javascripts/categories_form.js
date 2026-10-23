(function () {
  function bind(root) {
    var scope = root || document;
    scope.querySelectorAll(".category-form").forEach(function (container) {
      if (container.dataset.categoryFormBound === "true") return;
      container.dataset.categoryFormBound = "true";

      var form = container.querySelector("form");
      var saveBtn = container.querySelector("#save-category-btn");
      var nameInput = container.querySelector("#category_name");
      var typeSelect = container.querySelector("#category_category_type");
      var parentPicker = container.querySelector("[data-testid=category-parent-picker]");
      var newRecord = container.dataset.newRecord === "true";

      function refreshSaveState() {
        if (!saveBtn) return;
        var hasName = nameInput && nameInput.value.trim().length > 0;
        saveBtn.disabled = newRecord ? !hasName : false;
      }

      function filterParents() {
        if (!typeSelect || !parentPicker) return;
        var selectedType = typeSelect.value;
        var options = parentPicker.querySelectorAll("[role=option][data-category-type]");
        options.forEach(function (opt) {
          var matches = !selectedType || opt.dataset.categoryType === selectedType;
          opt.hidden = !matches;
          if (!matches) opt.setAttribute("aria-hidden", "true");
          else opt.removeAttribute("aria-hidden");
        });
        // Clear the hidden select if the chosen parent no longer matches.
        var hiddenSelect = parentPicker.querySelector("select");
        if (hiddenSelect && hiddenSelect.value) {
          var chosen = parentPicker.querySelector("[role=option][data-value='" + hiddenSelect.value + "']");
          if (chosen && chosen.dataset.categoryType !== selectedType) {
            hiddenSelect.value = "";
            var search = parentPicker.querySelector(".category-picker__input");
            if (search) search.value = "";
          }
        }
      }

      if (form) {
        form.addEventListener("input", function () {
          form.dataset.dirty = "true";
          refreshSaveState();
        });
        form.addEventListener("submit", function () {
          var summary = document.getElementById("error-summary");
          var invalid = form.querySelectorAll(".is-invalid").length > 0;
          if (summary && invalid) {
            summary.classList.remove("d-none");
          }
        });
      }

      if (typeSelect) {
        typeSelect.addEventListener("change", filterParents);
        filterParents();
      }

      refreshSaveState();
    });
  }

  document.addEventListener("DOMContentLoaded", function () { bind(document); });
  document.addEventListener("turbo:load", function () { bind(document); });
})();

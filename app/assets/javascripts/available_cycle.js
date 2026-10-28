// Available-cycle report: client-side search, due-date sorting and the
// values/percentage switch. Delegated listeners keep this safe across Turbo
// navigations and avoid duplicate handlers.
(function () {
  function rootFor(element) {
    return element && element.closest("[data-available-cycle]");
  }

  function rowsFor(root) {
    return Array.prototype.slice.call(root.querySelectorAll("[data-available-cycle-row]"));
  }

  function updateCount(root, count) {
    var label = root.querySelector("[data-available-cycle-count]");
    if (!label) return;

    var singular = label.dataset.singular || "gasto pendiente";
    var plural = label.dataset.plural || "gastos pendientes";

    label.textContent = count + " " + (count === 1 ? singular : plural);
  }

  function sortRows(root, rows) {
    var direction = root.dataset.availableCycleSortDirection || "asc";
    var tbody = root.querySelector("[data-available-cycle-rows]");
    if (!tbody) return;

    rows.sort(function (left, right) {
      var leftDate = left.dataset.dueDate || "";
      var rightDate = right.dataset.dueDate || "";

      if (!leftDate && !rightDate) return 0;
      if (!leftDate) return 1;
      if (!rightDate) return -1;

      return direction === "desc" ? rightDate.localeCompare(leftDate) : leftDate.localeCompare(rightDate);
    });

    rows.forEach(function (row) {
      tbody.appendChild(row);
    });
  }

  function applyFilter(root) {
    var input = root.querySelector("[data-available-cycle-search]");
    var query = input ? input.value.trim().toLocaleLowerCase("es") : "";
    var rows = rowsFor(root);

    rows.forEach(function (row) {
      var haystack = (row.dataset.search || "").toLocaleLowerCase("es");
      row.hidden = query.length > 0 && haystack.indexOf(query) === -1;
    });

    sortRows(root, rows);

    var visibleCount = rows.filter(function (row) {
      return !row.hidden;
    }).length;
    updateCount(root, visibleCount);
  }

  document.addEventListener("input", function (event) {
    if (!event.target.matches("[data-available-cycle-search]")) return;

    var root = rootFor(event.target);
    if (root) applyFilter(root);
  });

  document.addEventListener("click", function (event) {
    var sortButton = event.target.closest("[data-available-cycle-sort]");
    if (sortButton) {
      var sortRoot = rootFor(sortButton);
      if (!sortRoot) return;

      var nextDirection = sortRoot.dataset.availableCycleSortDirection === "desc" ? "asc" : "desc";
      sortRoot.dataset.availableCycleSortDirection = nextDirection;
      sortButton.setAttribute("aria-pressed", nextDirection === "desc" ? "true" : "false");

      var label = sortButton.querySelector("[data-available-cycle-sort-label]");
      if (label) {
        label.textContent = nextDirection === "desc" ? sortButton.dataset.labelDesc : sortButton.dataset.labelAsc;
      }

      applyFilter(sortRoot);
      return;
    }

    var modeButton = event.target.closest("[data-available-cycle-mode]");
    if (!modeButton) return;

    var modeRoot = rootFor(modeButton);
    if (!modeRoot) return;

    var mode = modeButton.dataset.availableCycleMode;

    modeRoot.querySelectorAll("[data-available-cycle-mode]").forEach(function (button) {
      var active = button === modeButton;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", active ? "true" : "false");
    });

    modeRoot.querySelectorAll("[data-available-cycle-values]").forEach(function (element) {
      element.hidden = mode !== "values";
    });
    modeRoot.querySelectorAll("[data-available-cycle-percent]").forEach(function (element) {
      element.hidden = mode !== "percent";
    });
  });
})();

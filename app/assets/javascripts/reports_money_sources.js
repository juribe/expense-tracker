// Reports: "Origen del gasto" source detail. Expands/collapses groups,
// searches individual sources, sorts rows locally and opens a source's
// transactions list without changing any financial calculation.
(function () {
  "use strict";

  var collator;
  try {
    collator = new Intl.Collator("es", { numeric: true, sensitivity: "base" });
  } catch (error) {
    collator = null;
  }

  function compareNames(a, b) {
    if (collator) return collator.compare(a, b);
    return a.localeCompare(b);
  }

  function originalOrder(row, index) {
    if (!row.hasAttribute("data-money-source-original-order")) {
      row.setAttribute("data-money-source-original-order", String(index));
    }
    return Number(row.getAttribute("data-money-source-original-order"));
  }

  function setup(root) {
    if (root.getAttribute("data-money-sources-bound") === "true") return;
    root.setAttribute("data-money-sources-bound", "true");

    var tbody = root.querySelector(".money-sources-table tbody");
    if (!tbody) return;

    var search = root.querySelector("[data-money-source-search]");
    var sort = root.querySelector("[data-money-source-sort]");
    var noResults = root.querySelector("[data-money-source-no-results]");
    var groups = Array.prototype.slice.call(tbody.querySelectorAll("[data-money-source-group]"));
    var rows = Array.prototype.slice.call(tbody.querySelectorAll("[data-money-source-row]"));
    var collapsed = {};

    groups.forEach(function (group, index) {
      originalOrder(group, index);
    });
    rows.forEach(function (row, index) {
      originalOrder(row, index);
    });

    function groupKey(group) {
      return group.getAttribute("data-money-source-group-key");
    }

    function rowsFor(key) {
      return rows.filter(function (row) {
        return row.getAttribute("data-money-source-group-key") === key;
      });
    }

    function matchesSearch(row, query) {
      if (!query) return true;
      var name = (row.getAttribute("data-money-source-name") || "").toLowerCase();
      return name.indexOf(query) !== -1;
    }

    function setExpanded(group, expanded) {
      var key = groupKey(group);
      var toggle = group.querySelector("[data-money-source-toggle]");

      group.classList.toggle("is-collapsed", !expanded);
      if (expanded) {
        delete collapsed[key];
      } else {
        collapsed[key] = true;
      }

      if (!toggle) return;
      toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
      var label = group.getAttribute(
        expanded ? "data-money-source-collapse-label" : "data-money-source-expand-label"
      );
      if (label) toggle.setAttribute("aria-label", label);
    }

    function applyVisibility() {
      var query = search ? search.value.trim().toLowerCase() : "";
      var anyMatch = false;

      groups.forEach(function (group) {
        var key = groupKey(group);
        var groupRows = rowsFor(key);
        var matchingRows = groupRows.filter(function (row) {
          return matchesSearch(row, query);
        });
        var groupHasMatches = !query || matchingRows.length > 0;
        var isCollapsed = collapsed[key] === true;

        group.hidden = !groupHasMatches;
        if (groupHasMatches) anyMatch = true;

        groupRows.forEach(function (row) {
          row.hidden = !groupHasMatches || isCollapsed || !matchesSearch(row, query);
        });

        setExpanded(group, !isCollapsed);
      });

      if (noResults) noResults.hidden = !query || anyMatch;
    }

    function sortRows(mode) {
      var orderedGroups = groups.slice();

      if (mode === "amount") {
        orderedGroups.sort(function (a, b) {
          return Number(b.getAttribute("data-money-source-amount")) -
            Number(a.getAttribute("data-money-source-amount"));
        });
      } else if (mode === "name") {
        orderedGroups.sort(function (a, b) {
          return compareNames(a.getAttribute("data-money-source-name") || "",
            b.getAttribute("data-money-source-name") || "");
        });
      } else {
        orderedGroups.sort(function (a, b) {
          return Number(a.getAttribute("data-money-source-original-order")) -
            Number(b.getAttribute("data-money-source-original-order"));
        });
      }

      orderedGroups.forEach(function (group) {
        var groupRows = rowsFor(groupKey(group));

        if (mode === "amount") {
          groupRows.sort(function (a, b) {
            return Number(b.getAttribute("data-money-source-amount")) -
              Number(a.getAttribute("data-money-source-amount"));
          });
        } else if (mode === "name") {
          groupRows.sort(function (a, b) {
            return compareNames(a.getAttribute("data-money-source-name") || "",
              b.getAttribute("data-money-source-name") || "");
          });
        } else {
          groupRows.sort(function (a, b) {
            return Number(a.getAttribute("data-money-source-original-order")) -
              Number(b.getAttribute("data-money-source-original-order"));
          });
        }

        tbody.appendChild(group);
        groupRows.forEach(function (row) {
          tbody.appendChild(row);
        });
      });

      if (noResults) tbody.appendChild(noResults);
      applyVisibility();
    }

    groups.forEach(function (group) {
      group.addEventListener("click", function (event) {
        if (event.target.closest("a")) return;
        setExpanded(group, group.classList.contains("is-collapsed"));
        applyVisibility();
      });
    });

    rows.forEach(function (row) {
      row.addEventListener("click", function (event) {
        if (event.target.closest("a, button, input, select, label")) return;
        var href = row.getAttribute("data-money-source-href");
        if (href) window.location.href = href;
      });
    });

    if (search) {
      search.addEventListener("input", function () {
        if (search.value.trim()) {
          collapsed = {};
        }
        applyVisibility();
      });

      search.addEventListener("keydown", function (event) {
        if (event.key !== "Escape") return;
        search.value = "";
        applyVisibility();
      });
    }

    if (sort) {
      sort.addEventListener("change", function () {
        sortRows(sort.value);
      });
    }

    applyVisibility();
  }

  function init() {
    Array.prototype.slice.call(document.querySelectorAll("[data-money-sources-report]")).forEach(setup);
  }

  document.addEventListener("DOMContentLoaded", init);
  document.addEventListener("turbo:load", init);
  if (document.readyState !== "loading") init();
})();

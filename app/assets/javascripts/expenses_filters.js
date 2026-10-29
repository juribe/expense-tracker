// Collapsible filters on the expenses index.
//
// The panel is rendered collapsed (hidden) and this module only toggles its
// visibility: it never touches the form values, so the selected filters stay
// intact while collapsing, and no request is made until the user submits.
function initializeExpenseFilters() {
  var toggle = document.getElementById("filterToggle");
  var panel = document.getElementById("filterPanel");
  if (!toggle || !panel || toggle.dataset.filtersInitialized === "true") return;
  toggle.dataset.filtersInitialized = "true";

  function setExpanded(expanded) {
    toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
    panel.hidden = !expanded;
    toggle.classList.toggle("is-open", expanded);
  }

  setExpanded(toggle.getAttribute("aria-expanded") === "true");

  toggle.addEventListener("click", function () {
    setExpanded(panel.hidden);
  });
}

document.addEventListener("turbo:load", initializeExpenseFilters);
document.addEventListener("DOMContentLoaded", initializeExpenseFilters);
if (document.readyState !== "loading") initializeExpenseFilters();

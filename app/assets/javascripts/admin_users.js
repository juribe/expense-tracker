// Admin users page: select-all and bulk delete state.
//
// Keeps the header checkbox, the row checkboxes, the selection counter and
// the bulk delete button in sync. The admin's own checkbox is disabled by the
// server and is never included in the selection count.
(function () {
  var SELECT_ALL = "[data-admin-users-select-all]";
  var CHECKBOX = "[data-admin-users-checkbox]";
  var SUBMIT = "[data-admin-users-bulk-submit]";
  var COUNT = "[data-admin-users-selected-count]";

  function checkboxes() {
    return Array.prototype.slice.call(document.querySelectorAll(CHECKBOX)).filter(function (box) {
      return !box.disabled;
    });
  }

  function update() {
    var boxes = checkboxes();
    var selected = boxes.filter(function (box) { return box.checked; });
    var allSelected = boxes.length > 0 && selected.length === boxes.length;

    document.querySelectorAll(COUNT).forEach(function (element) {
      element.textContent = selected.length;
    });

    document.querySelectorAll(SUBMIT).forEach(function (element) {
      element.disabled = selected.length === 0;
    });

    document.querySelectorAll(SELECT_ALL).forEach(function (element) {
      element.checked = allSelected;
      element.indeterminate = selected.length > 0 && !allSelected;
    });
  }

  document.addEventListener("change", function (event) {
    if (event.target.matches(SELECT_ALL)) {
      checkboxes().forEach(function (box) {
        box.checked = event.target.checked;
      });
      update();
    } else if (event.target.matches(CHECKBOX)) {
      update();
    }
  });

  document.addEventListener("turbo:load", update);
  document.addEventListener("DOMContentLoaded", update);
  update();
})();

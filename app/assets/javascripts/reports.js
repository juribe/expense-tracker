// Reports: make the whole filter chip open its select's dropdown, not just
// the select's own box. Clicks anywhere on the chip are forwarded to the
// select via showPicker() (Chromium/Edge/Safari 18+); elsewhere we focus it,
// which still lets the native dropdown open on click-through.
(function () {
  document.addEventListener("click", function (event) {
    var chip = event.target.closest(".filter-chip");
    if (!chip || event.target.tagName === "SELECT") return;

    var select = chip.querySelector("select");
    if (!select) return;

    if (typeof select.showPicker === "function") {
      try {
        select.showPicker();
        return;
      } catch (error) {
        // Some browsers require the select to be visible/focused first.
      }
    }

    select.focus();
  });
})();

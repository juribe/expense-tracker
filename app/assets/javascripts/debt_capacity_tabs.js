// Debt capacity: the four desktop tabs collapse into a dropdown on phones.
// The dropdown only drives the real tab buttons, so the tab panes and their
// Bootstrap state stay single-instance.
(function () {
  "use strict";

  function trigger() {
    return document.getElementById("debtCapacityTabToggle");
  }

  function activeDesktopTab() {
    return document.querySelector("#debt-capacity-tabs .nav-link.active");
  }

  function dropdownItemFor(button) {
    if (!button) return null;
    return document.querySelector('[data-debt-tab-target="' + button.id + '"]');
  }

  function syncTrigger(button) {
    var toggle = trigger();
    var item = dropdownItemFor(button);
    if (!toggle || !item) return;

    var label = toggle.querySelector("[data-debt-tab-trigger-label]");
    var icon = toggle.querySelector("[data-debt-tab-trigger-icon]");
    if (label) label.textContent = item.dataset.debtTabLabel;
    if (icon) icon.className = "ti " + item.dataset.debtTabIcon;

    document.querySelectorAll("[data-debt-tab-target]").forEach(function (option) {
      var active = option === item;
      option.classList.toggle("active", active);
      if (active) {
        option.setAttribute("aria-current", "true");
      } else {
        option.removeAttribute("aria-current");
      }
    });
  }

  document.addEventListener("click", function (event) {
    var item = event.target.closest("[data-debt-tab-target]");
    if (!item || !window.bootstrap) return;

    var target = document.getElementById(item.dataset.debtTabTarget);
    if (!target) return;
    window.bootstrap.Tab.getOrCreateInstance(target).show();
  });

  document.addEventListener("shown.bs.tab", function (event) {
    if (event.target && event.target.closest("#debt-capacity-tabs")) {
      syncTrigger(event.target);
    }
  });

  function init() {
    syncTrigger(activeDesktopTab());
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
  document.addEventListener("turbo:load", init);
})();

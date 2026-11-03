// Profile page: fill the membership progress bar from its data-progress
// attribute so we stay CSP-compliant (no inline styles in markup).
(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var bars = document.querySelectorAll(".progress span[data-progress]");
    bars.forEach(function (bar) {
      var value = parseFloat(bar.dataset.progress);
      if (isNaN(value)) return;
      bar.style.width = Math.max(0, Math.min(100, value)) + "%";
    });
  });
})();
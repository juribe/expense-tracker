(function () {
  function toggle() {
    var sel = document.getElementById("pe-mode-select");
    if (!sel) return;
    var rec = document.getElementById("pe-recurring-fields");
    if (!rec) return;
    rec.style.display = sel.value === "recurring" ? "" : "none";
  }
  document.addEventListener("DOMContentLoaded", function () {
    var sel = document.getElementById("pe-mode-select");
    if (sel) { sel.addEventListener("change", toggle); toggle(); }
  });
})();

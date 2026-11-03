(function () {
  document.addEventListener("DOMContentLoaded", function () {
    var btn = document.querySelector("[data-dismiss-flash]");
    if (btn) {
      btn.addEventListener("click", function () {
        var f = btn.closest(".plans-flash");
        if (f) f.remove();
      });
    }
  });
})();
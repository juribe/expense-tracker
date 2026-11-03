(function () {
  function dismissFlash() {
    var flash = document.getElementById("flash");
    if (!flash) return;
    flash.classList.add("leaving");
    setTimeout(function () { flash.style.visibility = "hidden"; }, 220);
  }
  window.dismissFlash = dismissFlash;

  document.addEventListener("DOMContentLoaded", function () {
    var flash = document.getElementById("flash");
    if (!flash) return;
    var closeBtn = document.getElementById("flashClose");
    if (closeBtn) closeBtn.addEventListener("click", dismissFlash);
    setTimeout(dismissFlash, 8000);
  });
})();
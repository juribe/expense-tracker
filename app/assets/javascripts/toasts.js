(function () {
  var toastEl = document.getElementById("success-toast");
  if (toastEl && window.bootstrap) {
    var toast = new bootstrap.Toast(toastEl, { delay: 3000, autohide: true });
    toast.show();
  }
})();

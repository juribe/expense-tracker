(function () {
  var modal = document.getElementById("assign-to-goal-modal");
  if (!modal) return;
  modal.addEventListener("show.bs.modal", function (event) {
    var button = event.relatedTarget;
    if (!button) return;
    document.getElementById("assign-to-goal-id").value = button.getAttribute("data-assign-goal");
    document.getElementById("assign-to-goal-pocket-name").textContent = button.getAttribute("data-assign-pocket-name");
    document.getElementById("assign-to-goal-unallocated").textContent =
      modal.dataset.unallocatedLabel + ": " + button.getAttribute("data-assign-unallocated");
    document.getElementById("assign-to-goal-modal-title").innerHTML =
      '<i class="ti ti-pig-money me-2"></i>' + button.getAttribute("data-assign-goal-name");
  });
})();

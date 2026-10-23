document.addEventListener('DOMContentLoaded', function() {
  var modal = document.getElementById('reallocate-modal');
  if (!modal) return;
  modal.addEventListener('show.bs.modal', function(event) {
    var button = event.relatedTarget;
    if (!button) return;
    document.getElementById('reallocate-from-id').value = button.getAttribute('data-reallocate-from');
    document.getElementById('reallocate-from-name').textContent = button.getAttribute('data-reallocate-from-name');
  });
});

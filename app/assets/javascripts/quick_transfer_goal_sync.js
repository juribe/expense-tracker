(function() {
  var pocketSelect = document.getElementById('transfer_to_source_id');
  var goalField = document.getElementById('quick-assign-goal-field');
  var goalSelect = document.getElementById('quick_transfer_assign_goal_id');
  if (!pocketSelect || !goalField || !goalSelect) return;

  function sync() {
    // Origin-anchored pocket mode reads the select; the assign variant reads
    // the hidden field — both carry the pocket id as their value.
    var pocketId = pocketSelect.value;
    var hasVisibleGoal = false;
    Array.prototype.forEach.call(goalSelect.options, function(option) {
      if (!option.value) return; // the blank "pocket only" choice always stays
      var visible = option.getAttribute('data-pocket-id') === pocketId;
      option.hidden = !visible;
      if (visible) hasVisibleGoal = true;
    });
    // Drop a stale selection when its goal is no longer visible.
    if (!hasVisibleGoal || goalSelect.selectedOptions[0]?.hidden) {
      goalSelect.value = "";
    }
    goalField.hidden = !hasVisibleGoal;
  }

  pocketSelect.addEventListener('change', sync);
  sync();
})();

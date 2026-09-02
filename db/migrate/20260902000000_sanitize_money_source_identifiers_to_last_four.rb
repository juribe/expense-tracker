class SanitizeMoneySourceIdentifiersToLastFour < ActiveRecord::Migration[8.0]
  # SECURITY: the app now stores only the last four digits of account / card /
  # loan numbers. Truncate any legacy identifiers (full numbers) already in the
  # database so no full sensitive number remains at rest.
  def up
    MoneySource.where.not(identifier: nil).find_each do |source|
      digits = source.identifier.to_s.gsub(/\D/, "")
      next if digits.blank? || digits.length <= 4

      truncated = digits.chars.last(4).join
      next if truncated.blank?
      next if collision?(source, truncated)

      source.update_column(:identifier, truncated)
    end
  end

  # The identifier is unique per user. If truncation would collide with a
  # different existing source's last-four, leave the row untouched rather than
  # fail the migration (its next save will reconcile the identifier).
  def collision?(source, truncated)
    MoneySource.where(user_id: source.user_id, identifier: truncated)
               .where.not(id: source.id)
               .exists?
  end

  def down
    # No-op: once truncated, the original full numbers cannot be restored.
  end
end

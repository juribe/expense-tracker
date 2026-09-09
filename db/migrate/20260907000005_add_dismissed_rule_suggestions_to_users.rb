class AddDismissedRuleSuggestionsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :dismissed_rule_suggestions, :jsonb, default: [], null: false
  end
end
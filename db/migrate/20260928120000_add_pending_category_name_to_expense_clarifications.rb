class AddPendingCategoryNameToExpenseClarifications < ActiveRecord::Migration[8.0]
  def change
    add_column :expense_clarifications, :pending_category_name, :string
  end
end

# frozen_string_literal: true

# Counter cache for Category#expenses. Bullet flags the per-category
# `category.expenses.count` COUNT queries rendered on the categories index
# (the app root); maintaining expenses_count removes them.
class AddExpensesCounterCacheToCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :expenses_count, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE categories SET expenses_count = (
            SELECT COUNT(*) FROM transactions
            WHERE transactions.category_id = categories.id
              AND transactions.kind = 'expense'
          )
        SQL
      end
    end
  end
end

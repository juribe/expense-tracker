# frozen_string_literal: true

class AllowNullCategoryOnTransactions < ActiveRecord::Migration[8.0]
  def change
    change_column_null :transactions, :category_id, true
  end
end

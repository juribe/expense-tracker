# frozen_string_literal: true

class AddCategorySuggestionToExpenseCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :expense_candidates, :category_suggestion, :string
  end
end

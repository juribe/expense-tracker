# frozen_string_literal: true

class AddSuggestedSavingsPercentageToCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :suggested_savings_percentage, :decimal, precision: 5, scale: 2
  end
end

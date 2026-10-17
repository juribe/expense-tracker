# frozen_string_literal: true

class AddSavingsPotentialToCategories < ActiveRecord::Migration[8.0]
  def change
    add_column :categories, :savings_potential, :string
  end
end

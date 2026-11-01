# frozen_string_literal: true

class CreateGmfUvtYears < ActiveRecord::Migration[8.1]
  def change
    create_table :gmf_uvt_years, id: false do |t|
      t.integer :year, null: false, primary_key: true
      t.decimal :value, precision: 12, scale: 2, null: false
      t.timestamps
    end
  end
end

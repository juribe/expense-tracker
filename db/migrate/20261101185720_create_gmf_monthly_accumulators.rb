# frozen_string_literal: true

class CreateGmfMonthlyAccumulators < ActiveRecord::Migration[8.1]
  def change
    create_table :gmf_monthly_accumulators, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :user_id, null: false
      t.uuid :money_source_id, null: false
      t.integer :year, null: false
      t.integer :month, null: false
      t.decimal :total_debits, precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :covered_by_exemption, precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :taxable, precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :gmf_generated, precision: 14, scale: 2, default: "0.0", null: false
      t.timestamps
    end

    add_index :gmf_monthly_accumulators, [:user_id, :money_source_id, :year, :month],
              unique: true, name: "index_gmf_accumulators_unique_period"
    add_foreign_key :gmf_monthly_accumulators, :users
    add_foreign_key :gmf_monthly_accumulators, :money_sources
  end
end

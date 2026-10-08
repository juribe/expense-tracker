class CreateCreditScenarios < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_scenarios do |t|
      t.references :money_source, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.jsonb :params, null: false, default: {}
      t.jsonb :results, null: false, default: {}
      t.datetime :computed_at, null: false

      t.timestamps
    end

    add_index :credit_scenarios, [:money_source_id, :kind]
  end
end

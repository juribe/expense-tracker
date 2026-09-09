class CreateExpensePlaygroundRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :expense_playground_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :input_type, null: false, limit: 20
      t.string :input_label, limit: 200
      t.string :engine, limit: 30
      t.integer :duration_ms
      t.string :status, null: false, default: "ok", limit: 20
      t.jsonb :candidate, default: {}, null: false
      t.jsonb :steps, default: {}, null: false
      t.jsonb :error_messages, default: [], null: false, array: true
      t.jsonb :warnings, default: [], null: false, array: true
      t.integer :expense_id
      t.timestamps
    end

    add_index :expense_playground_runs, :created_at
    add_index :expense_playground_runs, :expense_id
  end
end

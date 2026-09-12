# frozen_string_literal: true

class CreateEvaluationCases < ActiveRecord::Migration[8.0]
  def change
    create_table :evaluation_cases do |t|
      t.references :evaluation_run, null: false, foreign_key: true
      t.integer :row_number, null: false
      t.text :message, null: false
      t.jsonb :expected_json, null: false, default: {}
      t.jsonb :actual_json
      t.jsonb :field_results, null: false, default: []
      t.string :status, null: false, default: "pending"
      t.boolean :json_valid, null: false, default: false
      t.integer :latency_ms
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :cost, precision: 12, scale: 6
      t.text :error

      t.timestamps
    end

    add_index :evaluation_cases, [ :evaluation_run_id, :row_number ], unique: true
    add_index :evaluation_cases, [ :evaluation_run_id, :status ]
  end
end
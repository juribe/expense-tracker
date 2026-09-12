# frozen_string_literal: true

class CreateEvaluationRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :evaluation_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :dataset_name
      t.string :dataset_version
      t.string :provider
      t.string :model
      t.string :prompt_version
      t.string :status, null: false, default: "pending"
      t.integer :total_cases, null: false, default: 0
      t.jsonb :metrics, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :evaluation_runs, [ :user_id, :created_at ]
  end
end
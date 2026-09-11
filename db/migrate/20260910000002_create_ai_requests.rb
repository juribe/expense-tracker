# frozen_string_literal: true

# Observability for the AI routing architecture: one row per routed
# resolution step (deterministic / cache / cheap / strong) so token spend,
# fallback rate and cache-hit rate are measurable from plain SQL.
class CreateAiRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_requests do |t|
      t.references :user, null: true, foreign_key: true
      t.string :task, null: false
      t.string :strategy, null: false
      t.string :provider
      t.string :model
      t.string :status, null: false, default: "ok"
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :latency_ms
      t.decimal :confidence, precision: 4, scale: 3
      t.boolean :escalated, null: false, default: false
      t.string :error
      t.timestamps
    end

    add_index :ai_requests, :task
    add_index :ai_requests, :strategy
    add_index :ai_requests, :created_at
  end
end

# frozen_string_literal: true

class CreateFinancialSetups < ActiveRecord::Migration[8.0]
  def change
    create_table :financial_setups do |t|
      t.references :user, null: false, foreign_key: true

      # 0-based index into FinancialSetupWizard.steps; -1 when finished.
      t.integer :current_step, null: false, default: 0

      # in_progress | completed | dismissed
      t.string :status, null: false, default: "in_progress"

      # Per-step state: choice (manual/import/skip) and draft source rows.
      t.jsonb :data, null: false, default: {}

      t.timestamps
    end

    add_index :financial_setups, [ :user_id, :status ]
  end
end

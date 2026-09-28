# Multi-expense clarification: a session groups every incomplete candidate
# from the same inbound message through a join table. Candidates stay
# independent (their own missing fields and status); the session only knows
# which ones belong to it.
class ClarificationSessionsGroupManyCandidates < ActiveRecord::Migration[8.0]
  def change
    create_table :expense_clarification_candidates do |t|
      t.references :expense_clarification, null: false, foreign_key: true
      t.references :expense_candidate, null: false, foreign_key: true
      t.jsonb :missing_fields, null: false, default: []

      t.timestamps
    end

    add_index :expense_clarification_candidates, %i[expense_clarification_id expense_candidate_id],
              unique: true, name: "index_clarification_candidates_unique"

    remove_index :expense_clarifications, name: "index_expense_clarifications_on_candidate_pending"
    remove_index :expense_clarifications, name: "index_expense_clarifications_on_user_pending"
    remove_column :expense_clarifications, :expense_candidate_id, :bigint
    remove_column :expense_clarifications, :pending_field, :string
    remove_column :expense_clarifications, :missing_fields_snapshot, :jsonb
    add_column :expense_clarifications, :original_message, :text
    add_index :expense_clarifications, :user_id,
              unique: true,
              where: "status = 'pending'",
              name: "index_expense_clarifications_on_user_pending"
  end
end

# Conversational clarification sessions for incomplete expense candidates
# received through WhatsApp. One pending session per user (partial unique
# index) keeps reply association unambiguous.
class CreateExpenseClarifications < ActiveRecord::Migration[8.0]
  def change
    create_table :expense_clarifications do |t|
      t.references :user, null: false, foreign_key: true
      t.references :expense_candidate, null: false, foreign_key: true
      t.string :phone_number, null: false
      t.string :status, null: false, default: "pending"
      t.text :question
      t.string :pending_field
      t.integer :questions_count, null: false, default: 0
      t.jsonb :missing_fields_snapshot, null: false, default: []

      t.timestamps
    end

    add_index :expense_clarifications, :status
    add_index :expense_clarifications, :user_id,
              unique: true,
              where: "status = 'pending'",
              name: "index_expense_clarifications_on_user_pending"
    add_index :expense_clarifications, :expense_candidate_id,
              unique: true,
              where: "status = 'pending'",
              name: "index_expense_clarifications_on_candidate_pending"
  end
end

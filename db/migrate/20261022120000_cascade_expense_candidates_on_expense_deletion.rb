# frozen_string_literal: true

# Deleting an expense must not be blocked by the ExpenseCandidate that
# produced it. Candidates are derived from the expense, so they are deleted
# with it (including their clarification links), never left dangling.
class CascadeExpenseCandidatesOnExpenseDeletion < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :expense_candidates, column: :expense_id
    add_foreign_key :expense_candidates, :transactions, column: :expense_id, on_delete: :cascade

    remove_foreign_key :expense_clarification_candidates, :expense_candidates
    add_foreign_key :expense_clarification_candidates, :expense_candidates, on_delete: :cascade
  end

  def down
    remove_foreign_key :expense_candidates, column: :expense_id
    add_foreign_key :expense_candidates, :transactions, column: :expense_id

    remove_foreign_key :expense_clarification_candidates, :expense_candidates
    add_foreign_key :expense_clarification_candidates, :expense_candidates
  end
end

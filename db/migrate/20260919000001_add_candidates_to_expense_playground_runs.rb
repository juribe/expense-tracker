# frozen_string_literal: true

# A playground run can detect several expenses at once (e.g. "gasté 50 mil en
# almuerzos y 20 mil en gasolina"). The single `candidate` column keeps the
# first one for backward compatibility; `candidates` stores every detected
# expense so history and future evaluation features can replay the full set.
class AddCandidatesToExpensePlaygroundRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :expense_playground_runs, :candidates, :jsonb, default: [], null: false
  end
end

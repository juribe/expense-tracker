# frozen_string_literal: true

class AddAttemptsToEvaluationCases < ActiveRecord::Migration[8.0]
  def change
    add_column :evaluation_cases, :attempts, :integer, null: false, default: 0
  end
end
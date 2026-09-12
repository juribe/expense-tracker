# frozen_string_literal: true

class AddInputOutputCostToEvaluationCases < ActiveRecord::Migration[8.0]
  def change
    add_column :evaluation_cases, :input_cost, :decimal, precision: 12, scale: 6
    add_column :evaluation_cases, :output_cost, :decimal, precision: 12, scale: 6
  end
end

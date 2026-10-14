# frozen_string_literal: true

# Adds the statement-summary part of a learned layout plus a recipe version so
# recipes produced by an older prompt can be ignored and re-learned. The
# summary_spec stores the declarative label/format selectors the AI describes
# for total_due, min_payment, interest_charged, due_date and statement_date;
# DynamicAdapter replays them without another AI call.
class AddSummarySpecToStatementFormatMappings < ActiveRecord::Migration[8.0]
  def change
    add_column :statement_format_mappings, :summary_spec, :jsonb, default: {}, null: false
    add_column :statement_format_mappings, :recipe_version, :integer, default: 0, null: false
  end
end

# frozen_string_literal: true

class AddMoneySourceIdToRecurringTemplates < ActiveRecord::Migration[8.0]
  def change
    add_reference :recurring_templates, :money_source, foreign_key: true
  end
end

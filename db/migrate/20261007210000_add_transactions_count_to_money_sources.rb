# frozen_string_literal: true

class AddTransactionsCountToMoneySources < ActiveRecord::Migration[8.0]
  def change
    add_column :money_sources, :transactions_count, :integer, default: 0, null: false

    # Backfill: reload the counter from the actual rows, the cached attribute
    # is read per-render by the money-source cards.
    MoneySource.find_each do |source|
      MoneySource.reset_counters(source.id, :transactions)
    end
  end
end

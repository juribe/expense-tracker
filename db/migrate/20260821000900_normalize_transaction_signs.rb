# frozen_string_literal: true

class NormalizeTransactionSigns < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE transactions
      SET amount = CASE
        WHEN kind = 'expense' THEN -ABS(amount)
        WHEN kind = 'income' THEN ABS(amount)
        ELSE amount
      END
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE transactions
      SET amount = ABS(amount)
    SQL
  end
end

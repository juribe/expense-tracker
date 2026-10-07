# frozen_string_literal: true

# Financial Cycles rework: a cycle is the user's financial month, defined by
# a single configurable start day (1..28) stored on users. Replaces the
# pay_schedules table (monthly paydays / semi-monthly pairs): the new model
# never creates a cycle per payment — multiple incomes share one monthly
# cycle — and start days are capped at 28 so every month length fits.
#
# Backfill maps an existing schedule to its first (smallest) payday, the
# closest notion of "when my financial month starts".
class MovePaySchedulesToUserCycleStartDay < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :financial_cycle_start_day, :integer, default: 1, null: false

    execute <<~SQL
      UPDATE users
      SET financial_cycle_start_day = (
        SELECT MIN(d::int)
        FROM pay_schedules ps, jsonb_array_elements_text(ps.paydays) AS d
        WHERE ps.user_id = users.id
      )
      WHERE id IN (SELECT user_id FROM pay_schedules)
    SQL

    drop_table :pay_schedules
  end

  def down
    create_table :pay_schedules do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :frequency, null: false, default: "monthly"
      t.jsonb :paydays, null: false, default: [ 1 ]

      t.timestamps
    end

    execute <<~SQL
      INSERT INTO pay_schedules (user_id, frequency, paydays, created_at, updated_at)
      SELECT id, 'monthly', jsonb_build_array(financial_cycle_start_day), NOW(), NOW()
      FROM users
      WHERE financial_cycle_start_day > 1
    SQL

    remove_column :users, :financial_cycle_start_day
  end
end

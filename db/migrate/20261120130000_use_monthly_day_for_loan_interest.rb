# frozen_string_literal: true

class UseMonthlyDayForLoanInterest < ActiveRecord::Migration[8.1]
  MAX_REFERENCE_DAY = 30

  def up
    add_column :credit_accounts, :interest_calculation_day, :integer

    execute <<~SQL
      UPDATE credit_accounts
      SET interest_calculation_day = LEAST(
        EXTRACT(DAY FROM interest_calculation_date)::integer,
        #{MAX_REFERENCE_DAY}
      )
      WHERE interest_calculation_date IS NOT NULL
    SQL

    remove_column :credit_accounts, :interest_calculation_date
  end

  def down
    add_column :credit_accounts, :interest_calculation_date, :date

    execute <<~SQL
      UPDATE credit_accounts
      SET interest_calculation_date = date_trunc('month', CURRENT_DATE)::date
        + (
          LEAST(
            interest_calculation_day,
            EXTRACT(DAY FROM date_trunc('month', CURRENT_DATE) + interval '1 month - 1 day')::integer
          ) - 1
        )
      WHERE interest_calculation_day IS NOT NULL
    SQL

    remove_column :credit_accounts, :interest_calculation_day
  end
end

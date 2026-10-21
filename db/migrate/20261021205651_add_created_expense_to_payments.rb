class AddCreatedExpenseToPayments < ActiveRecord::Migration[8.1]
  def up
    # Payments applied over a pre-existing expense (pick lists / awaiting
    # expenses) keep the flag false: reverting them must keep the expense.
    add_column :payments, :created_expense, :boolean, default: false, null: false
  end

  def down
    remove_column :payments, :created_expense
  end
end

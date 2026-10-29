# frozen_string_literal: true

# A CreditExtraPayment is the history row of a real extraordinary payment and
# points at the movement that funded it: a Transfer for revolving credit
# (reduce_balance) or an Expense + Payment for amortizing credit. Those
# movements keep their own delete actions (the transfers and expenses pages),
# so deleting one must remove its abono history row instead of failing with a
# foreign key violation. The movement's own callbacks still revert the real
# balances.
class CascadeCreditExtraPaymentsOnSourceDeletion < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :credit_extra_payments, column: :transfer_id
    add_foreign_key :credit_extra_payments, :transfers, column: :transfer_id, on_delete: :cascade

    remove_foreign_key :credit_extra_payments, column: :payment_id
    add_foreign_key :credit_extra_payments, :payments, column: :payment_id, on_delete: :cascade

    remove_foreign_key :credit_extra_payments, column: :expense_id
    add_foreign_key :credit_extra_payments, :transactions, column: :expense_id, on_delete: :cascade
  end

  def down
    remove_foreign_key :credit_extra_payments, column: :transfer_id
    add_foreign_key :credit_extra_payments, :transfers, column: :transfer_id

    remove_foreign_key :credit_extra_payments, column: :payment_id
    add_foreign_key :credit_extra_payments, :payments, column: :payment_id

    remove_foreign_key :credit_extra_payments, column: :expense_id
    add_foreign_key :credit_extra_payments, :transactions, column: :expense_id
  end
end

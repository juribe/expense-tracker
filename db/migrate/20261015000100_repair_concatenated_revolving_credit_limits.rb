class RepairConcatenatedRevolvingCreditLimits < ActiveRecord::Migration[8.0]
  # Revolving-line statements imported from images (no extractable text to
  # cross-check against) can carry a credit_limit whose decimals were glued to
  # the integer part: the printed "53.049.762,00" becomes 5_304_976_200, i.e.
  # exactly 100x the real cupo. The assigned cupo of a revolving line equals
  # its disbursed principal, so we undo the 100x only when it matches exactly;
  # every other credit_limit is left untouched.
  def up
    CreditAccount
      .joins(:money_source)
      .where(money_sources: { kind: "loan", sub_kind: "revolving" })
      .where("credit_accounts.principal_amount > 0")
      .where("credit_accounts.credit_limit = credit_accounts.principal_amount * 100")
      .find_each do |account|
        account.update_columns(credit_limit: account.principal_amount)
      end
  end

  def down
    # No-op: the concatenated value was never correct.
  end
end

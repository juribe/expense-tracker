# frozen_string_literal: true

# Source recognition only makes sense for PAYMENT sources (cash, accounts,
# cards, wallets): loans have no available money, and a revolving line's
# usage must be moved to a savings account — the account is the source that
# gets recognized. This drops any legacy recognition (and its identifiers,
# through the dependent destroy) configured on loans or pockets.
class DestroyRecognitionOfNonPaymentSources < ActiveRecord::Migration[8.0]
  def up
    MoneySourceRecognition.destroy_for_non_payment_sources!
  end

  def down
    # Irreversible: destroyed identifiers cannot be restored.
  end
end

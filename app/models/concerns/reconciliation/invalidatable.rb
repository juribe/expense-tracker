# frozen_string_literal: true

module Reconciliation
  # Marks the user's persisted reconciliation state stale after any relevant
  # financial write: expenses/incomes created, updated, deleted, assigned to
  # recurring templates, payments registered, transfers, recurring templates
  # created/updated, balances adjusted, and any Gmail/statement import that
  # ends up writing Transactions. Include in models owned by a user.
  module Invalidatable
    extend ActiveSupport::Concern

    included do
      after_commit on: [ :create, :update, :destroy ], if: :invalidate_reconciliation? do
        Reconciliation::Invalidate.call(user_id: reconciliation_user_id)
      end
    end

    private

    def reconciliation_user_id
      user_id
    end

    def invalidate_reconciliation?
      reconciliation_user_id.present?
    end
  end
end

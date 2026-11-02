module PaymentEngine
  # Financial transaction attempt for a Purchase. Approved payments are the only
  # source of membership activation or extension. Rows are never deleted.
  class Payment < ApplicationRecord
    STATUSES = %w[pending processing approved rejected canceled refunded partially_refunded].freeze

    belongs_to :purchase
    belongs_to :membership, optional: true

    validates :provider, presence: true
    validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
    validates :status, inclusion: { in: STATUSES }
    validates :provider_transaction_id, uniqueness: { scope: :provider }, allow_nil: true

    before_destroy :prevent_destroy

    scope :approved, -> { where(status: "approved") }
    scope :for_provider, ->(provider) { where(provider: provider.to_s) }

    def approved?
      status == "approved"
    end

    def refunded?
      %w[refunded partially_refunded].include?(status)
    end

    def final?
      %w[approved rejected canceled refunded partially_refunded].include?(status)
    end

    private

    def prevent_destroy
      errors.add(:base, "financial records cannot be deleted")
      throw :abort
    end
  end
end

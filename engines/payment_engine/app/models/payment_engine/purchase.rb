module PaymentEngine
  # Commercial intent to acquire a PaymentOption. A purchase can have several
  # payment attempts. On creation it captures a snapshot of the commercial
  # conditions so later PaymentOption changes never rewrite history.
  class Purchase < ApplicationRecord
    STATUSES = %w[pending processing completed failed canceled refunded].freeze

    belongs_to :owner, polymorphic: true
    belongs_to :payment_option
    belongs_to :membership, optional: true
    has_many :payments, dependent: :restrict_with_error

    validates :status, inclusion: { in: STATUSES }
    validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }
    validates :billing_type, inclusion: { in: PaymentOption::BILLING_TYPES }, allow_nil: true

    before_validation :capture_commercial_snapshot, on: :create
    before_destroy :prevent_destroy

    scope :for_owner, ->(owner) {
      where(owner_type: owner.class.polymorphic_name, owner_id: owner.id)
    }
    scope :completed, -> { where(status: "completed") }

    def duration_object
      Duration.from(duration)
    end

    def completed?
      status == "completed"
    end

    private

    def capture_commercial_snapshot
      return if payment_option.blank?

      option = payment_option
      self.option_name = option.name if option_name.blank?
      self.membership_type_name = option.membership_type.name if membership_type_name.blank?
      self.price = option.price if price.blank? || price.zero?
      self.amount = option.price if amount.blank? || amount.zero?
      self.currency ||= option.currency
      self.billing_type ||= option.billing_type
      self.duration = option.duration.to_h if duration.blank? || duration == {}
    end

    def prevent_destroy
      errors.add(:base, "financial records cannot be deleted")
      throw :abort
    end
  end
end

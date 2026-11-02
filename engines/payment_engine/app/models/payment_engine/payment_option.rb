module PaymentEngine
  # Commercial alternative to acquire a MembershipType. Holds price, currency
  # and billing period. Historical purchases keep a snapshot, so later price or
  # period changes never rewrite history.
  class PaymentOption < ApplicationRecord
    BILLING_TYPES = %w[one_time recurring].freeze
    INTERVALS = Duration::INTERVALS

    belongs_to :membership_type
    has_many :purchases, dependent: :restrict_with_error
    has_many :subscriptions, dependent: :restrict_with_error

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/, message: "must be lowercase alphanumeric with dashes" }
    validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/, message: "must be an ISO 4217 code" }
    validates :billing_type, inclusion: { in: BILLING_TYPES }
    validates :interval, inclusion: { in: INTERVALS }
    validates :interval_count, numericality: { only_integer: true, greater_than: 0 }
    validates :trial_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :recurring_requires_interval

    scope :active, -> { where(active: true) }
    scope :for_membership_type, ->(slug) {
      joins(:membership_type).merge(MembershipType.where(slug: slug.to_s))
    }
    scope :ordered, -> { order(:sort_order, :price, :id) }

    def self.for(slug)
      active.for_membership_type(slug).ordered
    end

    def self.find_by_slug(slug, active_only: true)
      scope = active_only ? active : all
      scope.find_by(slug: slug.to_s)
    end

    def one_time?
      billing_type == "one_time"
    end

    def recurring?
      billing_type == "recurring"
    end

    def duration
      Duration.new(interval: interval, count: interval_count)
    end

    def price_decimal
      BigDecimal(price.to_s)
    end

    private

    def recurring_requires_interval
      return unless recurring?
      return if interval.present? && interval_count.to_i.positive?

      errors.add(:interval, "is required for recurring options")
    end
  end
end

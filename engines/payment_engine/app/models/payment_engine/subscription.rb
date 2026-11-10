module PaymentEngine
  # Recurring billing agreement with a provider. A membership can exist without
  # a subscription; a subscription is only used for automatic renewals.
  class Subscription < ApplicationRecord
    STATUSES = %w[trialing active past_due paused canceled expired].freeze

    belongs_to :membership
    belongs_to :payment_option

    validates :provider, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :provider_subscription_id, uniqueness: { scope: :provider }, allow_nil: true
    validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, presence: true, format: { with: /\A[A-Z]{3}\z/ }

    before_validation :capture_commercial_conditions, on: :create

    scope :renewable, -> { where(status: %w[trialing active past_due]) }
    scope :due_for_renewal, -> {
      renewable.where("next_billing_at IS NOT NULL AND next_billing_at <= ?", Time.current)
    }

    # Existing subscriptions keep the conditions they were created with. Later
    # PaymentOption changes only affect new subscriptions.
    def effective_price
      price.to_i.positive? ? price.to_i : payment_option.price.to_i
    end

    def effective_currency
      currency.presence || payment_option.currency
    end

    def effective_billing_type
      billing_type.presence || payment_option.billing_type
    end

    def duration_object
      if duration.present? && duration != {}
        Duration.from(duration)
      else
        payment_option.duration
      end
    end

    def active?
      %w[trialing active past_due].include?(status) &&
        (current_period_ends_at.nil? || current_period_ends_at > Time.current)
    end

    def cancel_at_period_end?
      cancel_at_period_end == true
    end

    def canceling?
      canceled_at.present? && !cancel_at_period_end?
    end

    def renewal_due?
      active? && next_billing_at.present? && next_billing_at <= Time.current
    end

    private

    def capture_commercial_conditions
      return if payment_option.blank?

      self.price = payment_option.price if price.blank? || price.zero?
      self.currency ||= payment_option.currency
      self.billing_type ||= payment_option.billing_type
      self.duration = payment_option.duration.to_h if duration.blank? || duration == {}
    end
  end
end

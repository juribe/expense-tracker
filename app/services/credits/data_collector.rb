# frozen_string_literal: true

module Credits
  # DataCollector
  # Gathers the projection inputs from what already exists — the credit
  # account and the recorded credit payments — and merges user overrides on
  # top ("reconstruct credit"). Read-only: nothing is written back to the
  # credit tables. Every user-supplied value is listed under :user_supplied
  # so the projection can mark itself as estimated.
  #
  # Methods: call
  #
  # Example: DataCollector.call(money_source: loan, overrides: {:interest_rate => "21.27"})
  class DataCollector
    NUMERIC_OVERRIDES = %w[
      outstanding_balance interest_rate installment_amount
      current_installment_number installment_count
      principal_amount interest_amount insurance_amount other_amount
    ].freeze
    DATE_OVERRIDES = %w[latest_payment_date].freeze
    STRING_OVERRIDES = %w[interest_rate_type payment_frequency insurance_assumption interest_calculation extra_payment_default].freeze

    def self.call(money_source:, overrides: {})
      new(money_source, overrides).call
    end

    def initialize(money_source, overrides)
      @money_source = money_source
      @overrides = overrides || {}
      @credit_account = money_source.credit_account
    end

    def call
      inputs = base_inputs
      apply_overrides(inputs)
      apply_latest_payment(inputs)
      normalize(inputs)
      inputs
    end

    private

    def base_inputs
      {
        balance: @credit_account&.outstanding_balance.presence || @credit_account&.principal_amount,
        interest_rate: @credit_account&.interest_rate,
        interest_rate_type: @credit_account&.interest_rate_type || "effective_annual",
        payment_frequency: @credit_account&.payment_frequency.presence || "monthly",
        installment_amount: @credit_account&.installment_amount,
        installment_count: @credit_account&.installment_count,
        installments_paid: @credit_account&.installments_paid,
        start_date: @credit_account&.start_date,
        current_installment_number: nil,
        latest_payment_date: nil,
        latest_principal: nil,
        latest_interest: nil,
        latest_insurance: nil,
        latest_other: nil,
        actual_payments_count: payments.count,
        user_supplied: []
      }
    end

    def apply_overrides(inputs)
      NUMERIC_OVERRIDES.each do |key|
        next unless numeric_override?(key)

        inputs[input_key_for(key)] = parse_decimal(@overrides[key])
        mark_supplied(inputs, input_key_for(key))
      end
      DATE_OVERRIDES.each do |key|
        next unless @overrides[key].present?

        inputs[key.to_sym] = parse_date(@overrides[key])
        mark_supplied(inputs, key)
      end
      STRING_OVERRIDES.each do |key|
        next unless @overrides[key].present?

        inputs[key.to_sym] = @overrides[key]
        mark_supplied(inputs, key)
      end
    end

    def apply_latest_payment(inputs)
      latest = payments.order(:date, :id).last
      return if latest.nil?

      inputs[:latest_payment_date] ||= latest.date
      inputs[:latest_principal] ||= latest.principal_amount
      inputs[:latest_interest] ||= latest.interest_amount
      inputs[:latest_insurance] ||= latest.insurance_amount
      inputs[:latest_other] ||= latest.other_amount
    end

    def normalize(inputs)
      inputs[:current_installment_number] ||= inputs[:installments_paid].presence || inputs[:actual_payments_count]
      inputs[:user_supplied] = inputs[:user_supplied].map(&:to_s).uniq.sort
    end

    def input_key_for(override_key)
      { "outstanding_balance" => :balance,
        "principal_amount" => :latest_principal,
        "interest_amount" => :latest_interest,
        "insurance_amount" => :latest_insurance,
        "other_amount" => :latest_other }.fetch(override_key, override_key.to_sym)
    end

    def numeric_override?(key)
      @overrides[key].present?
    end

    def parse_decimal(value)
      BigDecimal(MoneyFormat.normalize(value).to_s)
    rescue ArgumentError, TypeError
      value.to_d
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    def mark_supplied(inputs, key)
      inputs[:user_supplied] << key
    end

    def payments
      @payments ||= @money_source.payments
    end
  end
end

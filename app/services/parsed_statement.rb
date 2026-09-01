# frozen_string_literal: true

# ParsedStatement
# Value object representing a single financial source extracted from an uploaded
# statement. Carries the fields the wizard reviews before any record is created.
# Never writes ActiveRecord records.
#
# Example: ParsedStatement.new(kind: "account", name: "Savings", bank: "Bancolombia", balance: 5420000)
class ParsedStatement
  ATTRIBUTES = %i[
    kind name bank sub_kind card_last_four
    balance credit_limit outstanding_balance monthly_payment principal_amount
    interest_rate interest_rate_type identifier transaction_count
  ].freeze

  attr_accessor(*ATTRIBUTES)

  def initialize(attributes = {})
    attrs = symbolize_keys(attributes)
    ATTRIBUTES.each { |attribute| public_send("#{attribute}=", attrs[attribute]) }
    self.balance = to_decimal(balance)
    self.credit_limit = to_decimal(credit_limit)
    self.outstanding_balance = to_decimal(outstanding_balance)
    self.monthly_payment = to_decimal(monthly_payment)
    self.principal_amount = to_decimal(principal_amount)
    self.interest_rate = to_decimal(interest_rate)
  end

  # String keys so the hash matches the stored import-state format (the
  # controller's dedup and editors all use string keys).
  def to_h
    ATTRIBUTES.each_with_object({}) { |attribute, hash| hash[attribute.to_s] = public_send(attribute) }
  end

  def display_name
    parts = [ name.to_s.presence || bank ]
    parts << "••••#{card_last_four}" if card_last_four.present?
    parts.compact.join(" ")
  end

  private

  def symbolize_keys(hash)
    (hash || {}).to_h.transform_keys { |key| key.to_sym }
  end

  def to_decimal(value)
    return if value.blank?

    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end

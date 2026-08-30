# frozen_string_literal: true

# Value object representing a single expense extracted from natural language.
# Performs validation so invalid entries never reach persistence.
class ParsedExpense
  MAX_AMOUNT = BigDecimal("99999999.99")

  ATTRIBUTES = %i[
    amount description transaction_date category_id category_name
    create_category confidence warnings source_hint
    money_source_id money_source_name
  ].freeze

  attr_accessor(*ATTRIBUTES)
  attr_reader :errors

  def initialize(attributes = {})
    @errors = []
    @warnings = []
    ATTRIBUTES.each do |attribute|
      public_send("#{attribute}=", attributes[attribute])
    end
    self.confidence = confidence.present? ? confidence.to_f : 1.0
    self.warnings = Array(warnings)
    self.create_category = ActiveModel::Type::Boolean.new.cast(create_category)
  end

  def valid?
    errors.clear
    validate_amount
    validate_date
    errors.empty?
  end

  def invalid?
    !valid?
  end

  def low_confidence?
    confidence.to_f < ExpenseParser::LOW_CONFIDENCE_THRESHOLD
  end

  def future_date?
    transaction_date.present? && transaction_date > Date.current
  end

  def to_h
    ATTRIBUTES.each_with_object({}) do |attribute, hash|
      hash[attribute] = public_send(attribute)
    end
  end

  private

  def validate_amount
    if amount.nil?
      errors << "Amount is missing or could not be read."
      return
    end
    unless amount.is_a?(Numeric) && amount.positive?
      errors << "Amount must be greater than zero."
      return
    end
    if amount > MAX_AMOUNT
      errors << "Amount exceeds the maximum allowed value."
    end
  end

  def validate_date
    if transaction_date.nil?
      errors << "Date is missing or invalid."
      return
    end
    unless transaction_date.is_a?(Date)
      errors << "Date is invalid."
    end
  end
end
